// 源仓库目录单测：解析 Venera index.json、非法输入容错、脚本 URL 拼接与
// 防逃逸校验。全部走假客户端，不访问网络。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/engine/engine.dart';

/// 按 URL 返回预置正文、记录抓取地址的假客户端。
class _FakeClient implements ComicHttpClient {
  _FakeClient({this.body = '', this.statusCode = 200, this.fail = false});

  final String body;
  final int statusCode;
  final bool fail;
  String? lastUrl;

  @override
  Future<ComicHttpResponse> fetch(
    String url, {
    ComicFetchOptions options = const ComicFetchOptions(),
  }) async {
    lastUrl = url;
    if (fail) throw StateError('offline');
    return ComicHttpResponse(statusCode: statusCode, body: body, url: url);
  }

  @override
  Future<void> setCookies(String url, Map<String, String> cookies) async {}

  @override
  List<Map<String, String>> getCookies(String url) =>
      const <Map<String, String>>[];

  @override
  Future<void> deleteCookies(String url) async {}
}

const String _indexUrl =
    'https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/index.json';

String _index(List<Object?> entries) => jsonEncode(entries);

Map<String, dynamic> _entry(
  String name, {
  String fileName = '',
  String key = '',
  String version = '1.0',
}) => <String, dynamic>{
  'name': name,
  'fileName': fileName.isEmpty ? '$key.js' : fileName,
  'key': key,
  'version': version,
};

ComicSourceIndexEntry _entryObj(
  String name, {
  String fileName = '',
  String key = '',
  String version = '1.0',
}) => ComicSourceIndexEntry.fromJson(
  _entry(name, fileName: fileName, key: key, version: version),
);

void main() {
  group('normalizeIndexUrl', () {
    test('接受 http(s) 绝对地址', () {
      expect(
        normalizeIndexUrl('https://rules.test/index.json')?.toString(),
        'https://rules.test/index.json',
      );
      expect(
        normalizeIndexUrl('http://rules.test/index.json')?.toString(),
        'http://rules.test/index.json',
      );
    });

    test('拒绝非 http(s)、空 host、user-info、query、fragment', () {
      for (final input in <String>[
        'ftp://rules.test/index.json',
        'rules.test/index.json',
        'https://user:pw@rules.test/index.json',
        'https://rules.test/index.json?x=1',
        'https://rules.test/index.json#frag',
        '',
      ]) {
        expect(normalizeIndexUrl(input), isNull, reason: input);
      }
    });
  });

  group('isSafeSourcePath', () {
    test('相对路径与子目录可用', () {
      for (final path in <String>[
        'copy_manga.js',
        'translated/nnhanman.js',
        '中文源.js',
      ]) {
        expect(isSafeSourcePath(path), isTrue, reason: path);
      }
    });

    test('拒绝绝对路径、协议、穿越、查询、反斜杠', () {
      for (final path in <String>[
        '',
        '/a.js',
        'https://evil.test/a.js',
        '../a.js',
        'a/../../b.js',
        'a?x=1',
        'a#f',
        r'a\b.js',
        'a/%2E%2E/b.js',
        'a//b.js',
      ]) {
        expect(isSafeSourcePath(path), isFalse, reason: path);
      }
    });

    test('拒绝带 scheme 的单斜杠/伪协议路径（resolve 会误判为 URI scheme）', () {
      for (final path in <String>['foo:bar.js', 'https:/evil.com/x.js']) {
        expect(isSafeSourcePath(path), isFalse, reason: path);
        // 不再触发 StateError，而是提前收敛为 ArgumentError。
        expect(
          () => ComicSourceCatalog().sourceUrl(
            _indexUrl,
            _entryObj('x', fileName: path, key: 'x'),
          ),
          throwsArgumentError,
          reason: path,
        );
      }
    });
  });

  group('ComicSourceCatalog.fetchIndex', () {
    test('解析官方形态清单，容错文档笔误 filename 与可选字段', () async {
      final body = _index(<Object?>[
        _entry('拷贝漫画', key: 'copy_manga', version: '1.4.3'),
        <String, dynamic>{
          'name': '翻译源',
          'filename': 'translated/nnhanman.js',
          'key': 'nnhanman',
          'version': '2.0',
          'description': '汉化',
        },
        <String, dynamic>{'name': '无 key'}, // 缺 fileName/url → 跳过
        <String, dynamic>{
          'name': '坏路径',
          'fileName': '../evil.js',
          'key': 'evil',
        }, // 路径穿越 → 跳过
        42, // 非 object → 跳过
      ]);
      final client = _FakeClient(body: body);
      final result = await ComicSourceCatalog(
        client: client,
      ).fetchIndex(_indexUrl);

      expect(client.lastUrl, _indexUrl);
      expect(result.entries, hasLength(2));
      expect(result.entries.first.name, '拷贝漫画');
      expect(result.entries.first.fileName, 'copy_manga.js');
      expect(result.entries.first.subtitle, 'v1.4.3');
      expect(result.entries.last.fileName, 'translated/nnhanman.js');
      expect(result.entries.last.subtitle, contains('汉化'));
      expect(result.failures, hasLength(3));
    });

    test('key 字符集校验与重复 key 去重', () async {
      final noName = _entry('', key: 'nokey')..remove('name');
      final body = _index(<Object?>[
        _entry('正常', key: 'ok_1'),
        _entry('怪 key', key: '../evil'),
        _entry('带点 key', key: 'a.b'),
        _entry('重复', key: 'ok_1', version: '9.9'),
        noName,
      ]);
      final result = await ComicSourceCatalog(
        client: _FakeClient(body: body),
      ).fetchIndex(_indexUrl);

      expect(result.entries.map((e) => e.key), <String>['ok_1', 'nokey']);
      expect(result.entries.first.version, '1.0'); // 重复的 9.9 未覆盖首条
      expect(result.failures, hasLength(3));
      expect(result.failures[0], contains('key 不合法')); // ../evil
      expect(result.failures[1], contains('key 不合法')); // a.b
      expect(result.failures[2], contains('key 重复')); // ok_1 重复
    });

    test('非数组 / 坏 JSON / 非 2xx / 网络异常收敛为 failures', () async {
      expect(
        (await ComicSourceCatalog(
          client: _FakeClient(body: '{"name":"x"}'),
        ).fetchIndex(_indexUrl)).failures.single,
        contains('格式错误'),
      );
      expect(
        (await ComicSourceCatalog(
          client: _FakeClient(body: 'not json'),
        ).fetchIndex(_indexUrl)).failures.single,
        contains('不是合法 JSON'),
      );
      expect(
        (await ComicSourceCatalog(
          client: _FakeClient(statusCode: 404, body: 'x'),
        ).fetchIndex(_indexUrl)).failures.single,
        contains('HTTP 404'),
      );
      expect(
        (await ComicSourceCatalog(
          client: _FakeClient(fail: true),
        ).fetchIndex(_indexUrl)).failures.single,
        contains('读取源清单失败'),
      );
    });

    test('非法仓库地址不发请求', () async {
      final client = _FakeClient(body: _index(<Object?>[]));
      final result = await ComicSourceCatalog(
        client: client,
      ).fetchIndex('https://user:pw@rules.test/');
      expect(client.lastUrl, isNull);
      expect(result.failures.single, contains('仓库地址不合法'));
    });
  });

  group('ComicSourceCatalog.sourceUrl', () {
    final catalog = ComicSourceCatalog();

    test('fileName 相对 index 目录拼接（含子目录）', () {
      expect(
        catalog.sourceUrl(_indexUrl, _entryObj('x', key: 'copy_manga')),
        'https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/copy_manga.js',
      );
      expect(
        catalog.sourceUrl(
          _indexUrl,
          _entryObj('x', fileName: 'translated/nnhanman.js', key: 'nnhanman'),
        ),
        'https://cdn.jsdelivr.net/gh/venera-app/venera-configs@main/translated/nnhanman.js',
      );
    });

    test('entry.url 为合法绝对地址时直接用', () {
      final entry = ComicSourceIndexEntry(
        name: 'x',
        fileName: 'x.js',
        key: 'x',
        url: 'https://raw.githubusercontent.com/u/r/main/x.js',
      );
      expect(
        catalog.sourceUrl(_indexUrl, entry),
        'https://raw.githubusercontent.com/u/r/main/x.js',
      );
    });

    test('entry.url 非法时抛 ArgumentError', () {
      final entry = ComicSourceIndexEntry(
        name: 'x',
        fileName: 'x.js',
        key: 'x',
        url: 'ftp://evil.test/x.js',
      );
      expect(() => catalog.sourceUrl(_indexUrl, entry), throwsArgumentError);
    });

    test('fileName 路径逃逸抛 ArgumentError', () {
      for (final path in <String>['../x.js', '/x.js', 'a/../../x.js']) {
        expect(
          () => catalog.sourceUrl(
            _indexUrl,
            _entryObj('x', fileName: path, key: 'x'),
          ),
          throwsArgumentError,
          reason: path,
        );
      }
    });

    test('非法 index 地址抛 ArgumentError', () {
      expect(
        () => catalog.sourceUrl(
          'https://user:pw@rules.test/',
          _entryObj('x', key: 'x'),
        ),
        throwsArgumentError,
      );
    });
  });
}
