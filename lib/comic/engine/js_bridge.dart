/// Venera 源脚本 API 桥（js_bridge）。
///
/// 社区源脚本只认 `init.js` 暴露的那套全局 API（`Network.*`、`HtmlDocument`、
/// `fetch`、`console`、`Cookie`、`Convert.*` 等），它们底层都汇聚成一个
/// `sendMessage({method, ...})`。本类就是那个 `sendMessage` 的 Dart 侧实现：
/// 把每条消息映射到我们的 [ComicHttpClient] / [HtmlDomBridge] / 工具函数。
///
/// API 签名逐条对齐 Venera `assets/init.js`（见 README 的 API 清单），
/// 因此社区源脚本可以不改一行直接跑。桥本身不依赖 flutter_qjs/UI，可在
/// 纯 Dart 单测里直接喂 message map 验证对齐性。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;

import '../request/web_client.dart';
import 'html_dom_bridge.dart';

/// 已记录的日志条目（供测试/诊断，源脚本的 console.log 落到这里）。
class ComicJsLog {
  const ComicJsLog({
    required this.level,
    required this.title,
    required this.content,
  });

  final String level;
  final String title;
  final String content;

  @override
  String toString() => '[$level] $title: $content';
}

/// js_bridge 的消息分派器。
class ComicJsBridge {
  ComicJsBridge({ComicHttpClient? client, HtmlDomBridge? dom})
    : _client = client ?? ComicWebClient(),
      _dom = dom ?? HtmlDomBridge();

  final ComicHttpClient _client;
  final HtmlDomBridge _dom;
  final List<ComicJsLog> _logs = <ComicJsLog>[];

  /// 源脚本 `loadData` / `saveData` / `loadSetting` / `isLogged` 的存储回调。
  /// 未设置时返回 null / false；集成方（C′ 存储线）注入真实实现。
  Object? Function(String key, String dataKey)? loadData;
  void Function(String key, String dataKey, Object? data)? saveData;
  void Function(String key, String dataKey)? deleteData;
  Object? Function(String key, String settingKey)? loadSetting;
  bool Function(String key)? isLogged;

  /// 最近日志（只读快照）。
  List<ComicJsLog> get logs => List<ComicJsLog>.unmodifiable(_logs);

  /// 同步分派（Venera 的 `sendMessage` 对 html/convert/cookie(uuid/random/log) 同步返回）。
  ///
  /// 返回 [_needsAsync] 表示这是 http/delay —— 宿主应走 [dispatch] 的 Future 路径。
  (Object? value, bool needsAsync) dispatchSync(Map<dynamic, dynamic> message) {
    final method = message['method'] as String? ?? '';
    if (method == 'http' || method == 'delay') {
      return (null, true);
    }
    // cookie 的 get/set/delete 涉及磁盘 jar，Venera 侧 get 同步、set/delete 异步；
    // 这里为简单都走同步接口（ComicHttpClient 暴露同步 getCookies）。
    return (_dispatchImmediate(message), false);
  }

  /// 异步分派（仅 http / delay）。
  Future<Object?> dispatch(Map<dynamic, dynamic> message) async {
    final method = message['method'] as String? ?? '';
    if (method == 'http') return _http(message);
    if (method == 'delay') {
      final ms = _asInt(message['time']);
      await Future<void>.delayed(Duration(milliseconds: ms < 0 ? 0 : ms));
      return null;
    }
    return _dispatchImmediate(message);
  }

  /// 所有同步方法的实现。
  Object? _dispatchImmediate(Map<dynamic, dynamic> message) {
    final method = message['method'] as String? ?? '';
    switch (method) {
      case 'log':
        _logs.add(
          ComicJsLog(
            level: message['level']?.toString() ?? 'info',
            title: message['title']?.toString() ?? '',
            content: message['content']?.toString() ?? '',
          ),
        );
        return null;

      case 'cookie':
        return _cookieSync(message);

      case 'html':
        return _dom.dispatch(message);

      case 'convert':
        return _convert(message);

      case 'uuid':
        return _uuid();

      case 'random':
        return _random(message);

      case 'load_data':
        return loadData?.call(
          message['key']?.toString() ?? '',
          message['data_key']?.toString() ?? '',
        );

      case 'save_data':
        saveData?.call(
          message['key']?.toString() ?? '',
          message['data_key']?.toString() ?? '',
          message['data'],
        );
        return null;

      case 'delete_data':
        deleteData?.call(
          message['key']?.toString() ?? '',
          message['data_key']?.toString() ?? '',
        );
        return null;

      case 'load_setting':
        return loadSetting?.call(
          message['key']?.toString() ?? '',
          message['setting_key']?.toString() ?? '',
        );

      case 'isLogged':
        return isLogged?.call(message['key']?.toString() ?? '') ?? false;

      case 'getLocale':
        return 'zh_CN';

      case 'getPlatform':
        return 'windows';

      default:
        return null;
    }
  }

  /// `Network.sendRequest` / `fetch` 的底层：`method: 'http'`。
  ///
  /// 返回 `{status, headers, body}`；`bytes: true` 时 body 是字节列表，
  /// 否则是字符串（对齐 Venera 的 `result.body`）。
  Future<Map<String, Object?>> _http(Map<dynamic, dynamic> message) async {
    final url = message['url']?.toString() ?? '';
    final method = (message['http_method'] as String? ?? 'GET').toUpperCase();
    final headers = _stringMap(message['headers']);
    final bytesMode = message['bytes'] == true;

    final data = message['data'];
    final options = ComicFetchOptions(
      method: method,
      headers: headers,
      data: data is String ? data : (data == null ? null : jsonEncode(data)),
    );

    try {
      final response = await _client.fetch(url, options: options);
      final body = bytesMode ? response.bodyBytes : response.body;
      return <String, Object?>{
        'status': response.statusCode,
        'headers': response.headers.map(
          (key, values) => MapEntry(key, values.join(', ')),
        ),
        'body': body,
        'url': response.url,
      };
    } catch (error) {
      // Venera init.js 检查 `result.error` 并 throw —— 对齐这个字段。
      return <String, Object?>{'error': error.toString()};
    }
  }

  /// 同步 Cookie 分派（对齐 Venera：`getCookies` 同步返回，set/delete 触发异步写）。
  Object? _cookieSync(Map<dynamic, dynamic> message) {
    final function = message['function']?.toString() ?? '';
    final url = message['url']?.toString() ?? '';
    switch (function) {
      case 'set':
        final raw = message['cookies'];
        final cookies = <String, String>{};
        if (raw is List) {
          for (final item in raw) {
            if (item is Map) {
              final name = item['name']?.toString() ?? '';
              if (name.isNotEmpty) {
                cookies[name] = item['value']?.toString() ?? '';
              }
            }
          }
        }
        // 与 Venera 一致：set 不等待落盘完成。
        unawaited(_client.setCookies(url, cookies));
        return null;
      case 'get':
        return _client
            .getCookies(url)
            .map(
              (c) => <String, String>{
                'name': c['name'] ?? '',
                'value': c['value'] ?? '',
                'domain': c['domain'] ?? '',
              },
            )
            .toList();
      case 'delete':
        unawaited(_client.deleteCookies(url));
        return null;
      default:
        return null;
    }
  }

  /// `Convert.*` 编码/解码/哈希（对齐 init.js 的 type 列表）。
  Object? _convert(Map<dynamic, dynamic> message) {
    final type = message['type']?.toString() ?? '';
    final isEncode = message['isEncode'] != false;
    final rawValue = message['value'];

    try {
      switch (type) {
        case 'utf8':
          if (isEncode) return utf8.encode(rawValue?.toString() ?? '');
          return utf8.decode(_toBytes(rawValue), allowMalformed: true);
        case 'gbk':
          // GBK 码表不在 Dart 核心库；UTF-8 兜底并如实说明（ccc.js 等站
          // 只是偶尔用 gbk 解码，真实乱码由源脚本后续 JSON.parse 决定）。
          if (isEncode) return utf8.encode(rawValue?.toString() ?? '');
          return utf8.decode(_toBytes(rawValue), allowMalformed: true);
        case 'base64':
          if (isEncode) {
            // 对齐 Venera：encodeBase64 返回 base64 字符串（源脚本常与之拼接），
            // 只有 decodeBase64 返回字节数组。
            return base64.encode(_toBytes(rawValue));
          }
          return base64.decode(_asText(rawValue));
        case 'md5':
          return crypto.md5.convert(_toBytes(rawValue)).bytes;
        case 'sha1':
          return crypto.sha1.convert(_toBytes(rawValue)).bytes;
        case 'sha256':
          return crypto.sha256.convert(_toBytes(rawValue)).bytes;
        case 'sha512':
          return crypto.sha512.convert(_toBytes(rawValue)).bytes;
        case 'hmac':
          return _hmac(message);
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  Object _hmac(Map<dynamic, dynamic> message) {
    final hash = message['hash']?.toString() ?? 'md5';
    final key = _toBytes(message['key']);
    final value = _toBytes(message['value']);
    final crypto.Hmac hmac = switch (hash) {
      'sha1' => crypto.Hmac(crypto.sha1, key),
      'sha256' => crypto.Hmac(crypto.sha256, key),
      'sha512' => crypto.Hmac(crypto.sha512, key),
      _ => crypto.Hmac(crypto.md5, key),
    };
    final digest = hmac.convert(value).bytes;
    return message['isString'] == true ? _bytesToAsciiHex(digest) : digest;
  }

  String _uuid() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = _bytesToAsciiHex(bytes);
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Object _random(Map<dynamic, dynamic> message) {
    final min = (message['min'] as num?)?.toDouble() ?? 0;
    final max = (message['max'] as num?)?.toDouble() ?? 1;
    final random = math.Random.secure();
    if (message['type']?.toString() == 'double') {
      return min + random.nextDouble() * (max - min);
    }
    if (max <= min) return min.toInt();
    return min.toInt() + random.nextInt(max.toInt() - min.toInt());
  }

  List<int> _toBytes(dynamic value) {
    if (value is List) return value.cast<int>();
    if (value is String) return utf8.encode(value);
    if (value is List<int>) return value;
    return <int>[];
  }

  String _asText(dynamic value) => value?.toString() ?? '';

  Map<String, String> _stringMap(dynamic value) {
    if (value is! Map) return <String, String>{};
    return <String, String>{
      for (final entry in value.entries)
        '${entry.key}': entry.value?.toString() ?? '',
    };
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _bytesToAsciiHex(List<int> bytes) {
    const digits = '0123456789abcdef';
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(digits[(b >> 4) & 0xf]);
      buffer.write(digits[b & 0xf]);
    }
    return buffer.toString();
  }
}
