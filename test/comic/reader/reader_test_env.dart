// 阅读器内核单测的共享夹具：内存 core 投影库 + 确定性假图片字节 + 章节列表。
//
// 不碰真实网络、不解码真实 PNG（用 Dart 可以 decode 的最小 PNG 字节），
// 也不依赖 A′ 源引擎——所有图片地址都是假 URL，由假 loader 直接返回字节。

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/reader/reader_cache.dart';
import 'package:mimao/comic/reader/reader_models.dart';
import 'package:mimao/comic/reader/reader_progress.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';

/// 1x1 PNG，可被 Flutter 的 MemoryImage 正常解码（widget 测试用）。
final Uint8List kBadgePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8AAAwAB/AF+kLQIAAAAAElFTkSuQmCC',
);

const ComicRef kRef = ComicRef(id: 'local:sample', sourceName: 'local');

/// 假 loader：按 URL 返回字节；带 errorUrls 时对这些地址抛异常（失败占位测试）。
ImageByteLoader fakeLoader({
  Uint8List? bytes,
  Set<String> errorUrls = const <String>{},
  Set<String> pendingUrls = const <String>{},
  void Function(String)? onLoad,
}) {
  final effectiveBytes = bytes ?? kBadgePng;
  return (url) async {
    onLoad?.call(url);
    if (errorUrls.contains(url)) {
      throw StateError('加载失败：$url');
    }
    if (pendingUrls.contains(url)) {
      // 永不完成：让 widget 测试能稳定观察加载态。
      return Completer<Uint8List>().future;
    }
    return effectiveBytes;
  };
}

/// 两章、每章三页的测试数据。
List<ComicChapter> sampleChapters() => const <ComicChapter>[
  ComicChapter(
    title: '第 1 章',
    imageUrls: <String>['p1-1.png', 'p1-2.png', 'p1-3.png'],
  ),
  ComicChapter(
    title: '第 2 章',
    imageUrls: <String>['p2-1.png', 'p2-2.png', 'p2-3.png'],
  ),
];

class ReaderTestEnv {
  final AppDb appDb;
  final LibraryRepository library;
  final ReaderImageCache cache;
  final List<String> loaded;

  ReaderTestEnv._(this.appDb, this.library, this.cache, this.loaded);

  factory ReaderTestEnv.create({
    Uint8List? bytes,
    Set<String> errorUrls = const <String>{},
    Set<String> pendingUrls = const <String>{},
    int maxMemoryEntries = 24,
    int maxDiskEntries = 1000,
  }) {
    final loaded = <String>[];
    final cache = ReaderImageCache(
      loader: fakeLoader(
        bytes: bytes,
        errorUrls: errorUrls,
        pendingUrls: pendingUrls,
        onLoad: loaded.add,
      ),
      disk: MemoryByteStore(maxEntries: maxDiskEntries),
      maxMemoryEntries: maxMemoryEntries,
    );
    final db = AppDb.forTesting(NativeDatabase.memory());
    return ReaderTestEnv._(db, LibraryRepository(db), cache, loaded);
  }

  Future<void> close() => appDb.close();
}

/// 构造一个记录调用的假 recorder（控制器逻辑测试用，不碰数据库）。
class RecordingRecorder implements ProgressRecorder {
  final List<ReadingProgress> events = <ReadingProgress>[];

  @override
  Future<void> persist(ReadingProgress progress) async {
    events.add(progress);
  }
}
