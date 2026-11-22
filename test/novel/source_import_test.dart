// ignore_for_file: deprecated_member_use — 与其他 novel 测试同款说明。
/// 书源导入数据层测试：深链解析 / Legado JSON 解析 / 文件仓库 / 导入服务。
///
/// 全程离线（临时目录 + 假抓取器），不碰 path_provider / 网络 / WebView。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/source/novel_source_importer.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

void main() {
  group('深链与链接解析', () {
    test('解析网站「一键导入」的 yuedu:// 深链，提取 src', () {
      const link =
          'yuedu://booksource/importonline?src=https://shuyuan.nyasama.cc/cdn/abc.json';
      expect(
        parseImportSourceUrl(link),
        'https://shuyuan.nyasama.cc/cdn/abc.json',
      );
    });

    test('src 带 URL 编码/多个参数/fragment 时正确截取', () {
      const link =
          'yuedu://booksource/importonline?foo=1&src=https%3A%2F%2Fx.com%2Fa.json&bar=2';
      expect(parseImportSourceUrl(link), 'https://x.com/a.json');
      expect(
        parseImportSourceUrl(
          'yuedu://booksource/importonline?src=https://x.com/a.json#frag',
        ),
        'https://x.com/a.json',
      );
    });

    test('非 yuedu 协议 / 非 importonline 路径 / 无 src 返回 null', () {
      expect(parseImportSourceUrl('https://x.com/a.json'), isNull);
      expect(parseImportSourceUrl('yuedu://booksource/other?src=x'), isNull);
      expect(parseImportSourceUrl('yuedu://booksource/importonline'), isNull);
    });

    test('http(s) 链接可抓取判定', () {
      expect(isFetchableSourceUrl('https://x.com/a.json'), isTrue);
      expect(isFetchableSourceUrl('http://x.com/a.txt'), isTrue);
      expect(
        isFetchableSourceUrl('yuedu://booksource/importonline?src=x'),
        isFalse,
      );
      expect(isFetchableSourceUrl('not a url'), isFalse);
    });
  });

  group('Legado 书源文件解析', () {
    test('JSON 数组解析为书源列表，键名沿用 bookSourceUrl', () {
      final text = jsonEncode(<Object?>[
        <String, Object?>{
          'bookSourceName': '测试源A',
          'bookSourceUrl': 'https://a.example',
          'bookSourceType': 0,
          'enabled': true,
        },
        <String, Object?>{
          'bookSourceName': '测试源B',
          'bookSourceUrl': 'https://b.example',
        },
      ]);
      final parsed = parseLegadoSources(text);
      expect(parsed, hasLength(2));
      final a = NovelBookSource.fromLegado(parsed.first);
      expect(a.name, '测试源A');
      expect(a.url, 'https://a.example');
      expect(a.type, 0);
      expect(a.enabled, isTrue);
      expect(a.key, NovelBookSource.keyFor('https://a.example'));
      expect(a.raw['bookSourceName'], '测试源A');
    });

    test('单条对象（非数组）也能解析；非法 JSON 抛 FormatException', () {
      final single = parseLegadoSources(
        jsonEncode(<String, Object?>{'bookSourceUrl': 'https://c.example'}),
      );
      expect(single, hasLength(1));
      expect(() => parseLegadoSources('not json'), throwsFormatException);
    });

    test('带 BOM 的正文也能解析', () {
      final bom =
          '\uFEFF${jsonEncode(<Object?>[
            <String, Object?>{'bookSourceUrl': 'https://bom.example'},
          ])}';
      expect(parseLegadoSources(bom), hasLength(1));
    });
  });

  group('文件仓库', () {
    late Directory dir;
    late NovelSourceStore store;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('novel-source-test-');
      store = NovelSourceStore(dir);
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    NovelBookSource source(String name, String url) =>
        NovelBookSource.fromLegado(<String, Object?>{
          'bookSourceName': name,
          'bookSourceUrl': url,
        });

    test('保存/读取/去重/启停/删除全链路', () async {
      final a = source('A', 'https://a.example');
      final b = source('B', 'https://b.example');
      expect(await store.saveAll(<NovelBookSource>[a, b, a]), 2);

      var loaded = await store.loadAll();
      expect(loaded, hasLength(2));
      expect(loaded.map((s) => s.name), containsAll(<String>['A', 'B']));

      await store.setEnabled(a.key, false);
      loaded = await store.loadAll();
      expect(loaded.firstWhere((s) => s.key == a.key).enabled, isFalse);

      expect(await store.delete(a.key), isTrue);
      loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.single.name, 'B');
    });

    test('清单损坏时降级按目录源文件补录', () async {
      final c = source('C', 'https://c.example');
      await store.saveAll(<NovelBookSource>[c]);
      // 破坏 manifest。
      await File('${dir.path}/manifest.json').writeAsString('garbage');
      final loaded = await store.loadAll();
      expect(loaded, hasLength(1));
      expect(loaded.single.name, 'C');
    });
  });

  group('导入服务', () {
    late Directory dir;
    late NovelSourceStore store;
    late NovelSourceImporter importer;
    late _FakeFetcher fetcher;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('novel-import-test-');
      store = NovelSourceStore(dir);
      fetcher = _FakeFetcher();
      importer = NovelSourceImporter(store, fetcher);
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('从深链导入：下载 → 解析 → 落库，结果带条数', () async {
      fetcher.text = jsonEncode(<Object?>[
        <String, Object?>{
          'bookSourceName': '神话',
          'bookSourceUrl': 'https://x/1',
        },
        <String, Object?>{
          'bookSourceName': '仙侠',
          'bookSourceUrl': 'https://x/2',
        },
      ]);
      final result = await importer.importFromLink(
        'yuedu://booksource/importonline?src=https://x/sy.json',
      );
      expect(result.saved, 2);
      expect(result.total, 2);
      expect(await store.loadAll(), hasLength(2));
      expect(fetcher.lastUrl, 'https://x/sy.json');
    });

    test('空源 / 非法链接 / 下载失败都收敛为可读异常', () async {
      fetcher.text = '[]';
      expect(
        () => importer.importFromLink('https://x/empty.json'),
        throwsA(
          isA<NovelSourceImportException>().having(
            (e) => e.message,
            'message',
            contains('没有可用的书源'),
          ),
        ),
      );
      expect(
        () => importer.importFromLink('not a link'),
        throwsA(isA<NovelSourceImportException>()),
      );
      fetcher.error = 'boom';
      fetcher.text = '[]';
      expect(
        () => importer.importFromLink('https://x/a.json'),
        throwsA(
          isA<NovelSourceImportException>().having(
            (e) => e.message,
            'message',
            contains('下载书源失败'),
          ),
        ),
      );
    });
  });
}

class _FakeFetcher implements NovelSourceFetcher {
  String text = '[]';
  String? error;
  String? lastUrl;

  @override
  Future<NovelSourceFetchResult> fetch(String url) async {
    lastUrl = url;
    if (error != null) throw StateError(error!);
    return NovelSourceFetchResult(text: text, finalUrl: url);
  }
}
