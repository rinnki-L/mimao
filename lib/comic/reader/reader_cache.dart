// 图片缓存：内存 LRU + 磁盘缓存，两侧都限量；瞬时失败自动重试。
//
// 设计取舍：
// - 图片字节的"取字节"动作抽象成 [ImageByteLoader]，入参是 [ReaderImage]
//   （地址 + per-image 请求头）；默认实现支持本地文件与 http(s) URL。测试
//   注入假 loader 即可，不碰网络也不碰 A′ 源引擎。
// - 磁盘侧抽象成 [ByteStore]；生产用 [DiskByteStore]（dart:io 文件），测试用
//   [MemoryByteStore]，从而让"命中/淘汰"变成确定性的纯内存断言。
// - 缓存键用稳定的 FNV-1a 十六进制串，不用 String.hashCode（跨进程不稳定，
//   磁盘文件名换次运行就对不上）。键只由 URL 决定——同一图换 headers 不换键。
// - 网络瞬时错误（5xx / 连接失败）指数退避重试；403/404/410 这类确定性失败
//   直接放弃，避免给被拒的请求加倍流量。

import 'dart:collection';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show consolidateHttpClientResponseBytes;

import 'reader_models.dart';

/// 取一张图原始字节。可以是本地文件路径或 http(s) 地址；headers 非空时
/// 直通为请求头（源 `comic.onImageLoad` 钩子产物，常为 Referer/Cookie）。
typedef ImageByteLoader = Future<Uint8List> Function(ReaderImage image);

/// 稳定的 FNV-1a（63 位，避免负数），输出 16 位十六进制串，用作磁盘文件名。
String cacheKey(String url) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  const mask = 0x7fffffffffffffff;
  for (final b in utf8.encode(url)) {
    hash = ((hash ^ b) * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// 默认字节加载器：本地路径/`file://` 走 [File]，http(s) 走 [HttpClient]。
/// 只在真正需要取图时调用，命中缓存时不会触达它。
///
/// 不少站点对空 UA / 非同源 Referer 的图片请求直接 403：这里补桌面 Chrome
/// UA + 图片 URL 同源 Referer 兜底；源钩子给的 [ReaderImage.headers] 在
/// 兜底之上覆盖（同名字段以源为准）。
const String _imageDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

Future<Uint8List> defaultImageByteLoader(ReaderImage image) async {
  final url = image.url;
  final uri = Uri.tryParse(url);
  if (uri != null &&
      uri.isAbsolute &&
      (uri.scheme == 'http' || uri.scheme == 'https')) {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', _imageDefaultUserAgent);
      request.headers.set('Referer', '${uri.scheme}://${uri.authority}/');
      image.headers.forEach(request.headers.set);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      return await consolidateHttpClientResponseBytes(response);
    } finally {
      client.close();
    }
  }
  final path = uri != null && uri.scheme == 'file' ? uri.toFilePath() : url;
  return File(path).readAsBytes();
}

/// 确定性失败（4xx 客户端错）：重试也不会变好，直接放弃。
/// 判 [HttpException] 的消息文本（`HTTP <code>`），其他异常一律视为瞬时。
bool _isPermanentFailure(Object error) {
  final message = error.toString();
  return RegExp(r'HTTP 4\d\d').hasMatch(message);
}

/// 磁盘（或测试用的内存替身）字节仓库。
abstract interface class ByteStore {
  Future<Uint8List?> read(String key);
  Future<void> write(String key, Uint8List bytes);
  Future<void> remove(String key);
  int get length;
}

/// 生产磁盘缓存：一个目录放所有图片字节，超过 [maxEntries] 时按修改时间淘汰最旧的。
class DiskByteStore implements ByteStore {
  DiskByteStore(this.directory, {this.maxEntries = 200});

  final Directory directory;
  final int maxEntries;

  File _file(String key) =>
      File('${directory.path}${Platform.pathSeparator}$key');

  @override
  Future<Uint8List?> read(String key) async {
    final file = _file(key);
    if (!file.existsSync()) return null;
    try {
      return await file.readAsBytes();
    } on Object {
      // 文件损坏/被占用：当作未命中，让上层重新拉图覆盖。
      return null;
    }
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    await _file(key).writeAsBytes(bytes, flush: true);
    await _evict();
  }

  @override
  Future<void> remove(String key) async {
    final file = _file(key);
    if (file.existsSync()) await file.delete();
  }

  @override
  int get length => directory.existsSync()
      ? directory.listSync().whereType<File>().length
      : 0;

  Future<void> _evict() async {
    final files = directory.listSync().whereType<File>().toList()
      ..sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    final overflow = files.length - maxEntries;
    if (overflow <= 0) return;
    for (final file in files.take(overflow)) {
      await file.delete();
    }
  }
}

/// 测试用的有界内存仓库（同时模拟磁盘的容量限制），按 LRU 淘汰。
class MemoryByteStore implements ByteStore {
  MemoryByteStore({this.maxEntries = 1000});

  final int maxEntries;
  final LinkedHashMap<String, Uint8List> _map =
      LinkedHashMap<String, Uint8List>();

  @override
  Future<Uint8List?> read(String key) async {
    final bytes = _map.remove(key);
    if (bytes == null) return null;
    _map[key] = bytes; // 移到末尾 = 最近使用
    return bytes;
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    _map.remove(key);
    _map[key] = bytes;
    while (_map.length > maxEntries) {
      _map.remove(_map.keys.first);
    }
  }

  @override
  Future<void> remove(String key) async => _map.remove(key);

  @override
  int get length => _map.length;

  /// 清空仓库（测试与"清除缓存"入口用）。
  Future<void> clear() async => _map.clear();
}

/// 图片缓存管理器：先查内存 LRU，再查磁盘，最后才走 loader（瞬时失败重试）。
///
/// 命中/未命中/淘汰都记数，便于单测与手动排查容量行为。
class ReaderImageCache {
  ReaderImageCache({
    required this.loader,
    ByteStore? disk,
    this.maxMemoryBytes = 48 * 1024 * 1024,
    this.maxMemoryEntries = 24,
    this.maxRetries = 2,
    this.retryDelay = const Duration(milliseconds: 300),
  }) : disk = disk ?? MemoryByteStore();

  final ImageByteLoader loader;
  final ByteStore disk;
  final int maxMemoryBytes;
  final int maxMemoryEntries;

  /// 瞬时失败的重试次数（0 = 不重试）与首次退避时长（逐次翻倍）。
  final int maxRetries;
  final Duration retryDelay;

  /// key → 字节；LinkedHashMap 的插入顺序即 LRU 顺序。
  final LinkedHashMap<String, Uint8List> _memory =
      LinkedHashMap<String, Uint8List>();
  final Map<String, Future<Uint8List>> _inflight =
      <String, Future<Uint8List>>{};

  int hits = 0;
  int misses = 0;
  int evictions = 0;

  int get memoryLength => _memory.length;
  int get currentBytes => _memory.values.fold(0, (sum, e) => sum + e.length);
  bool isInMemory(String url) => _memory.containsKey(cacheKey(url));

  /// 取图：内存命中 → 磁盘命中 → loader 拉取并回填两级缓存。
  /// 同图并发请求合并成一个 Future（in-flight 去重）。
  Future<Uint8List> load(ReaderImage image) {
    final key = cacheKey(image.url);
    final cached = _memory.remove(key);
    if (cached != null) {
      _memory[key] = cached;
      hits++;
      return Future.value(cached);
    }
    final pending = _inflight[key];
    if (pending != null) return pending;

    final future = _fetch(image, key);
    _inflight[key] = future;
    return future.whenComplete(() => _inflight.remove(key));
  }

  Future<Uint8List> _fetch(ReaderImage image, String key) async {
    final fromDisk = await disk.read(key);
    if (fromDisk != null) {
      hits++;
      _putMemory(key, fromDisk);
      return fromDisk;
    }

    misses++;
    final bytes = await _loadWithRetry(image);
    if (bytes.isEmpty) {
      throw StateError('图片字节为空：${image.url}');
    }
    try {
      await disk.write(key, bytes);
    } on Object {
      // 磁盘写失败不影响本次展示（内存里还有一份）。
    }
    _putMemory(key, bytes);
    return bytes;
  }

  /// loader 拉取 + 瞬时失败指数退避重试；4xx 与空字节不重试。
  Future<Uint8List> _loadWithRetry(ReaderImage image) async {
    var delay = retryDelay;
    var attempt = 0;
    while (true) {
      try {
        return await loader(image);
      } on Object catch (error) {
        if (attempt >= maxRetries || _isPermanentFailure(error)) rethrow;
        attempt++;
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
  }

  void _putMemory(String key, Uint8List bytes) {
    _memory.remove(key);
    _memory[key] = bytes;
    while (_memory.length > maxMemoryEntries || currentBytes > maxMemoryBytes) {
      final oldest = _memory.keys.first;
      _memory.remove(oldest);
      evictions++;
    }
  }

  void clearStats() {
    hits = 0;
    misses = 0;
    evictions = 0;
  }
}
