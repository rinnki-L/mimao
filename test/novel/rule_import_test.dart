// ignore_for_file: deprecated_member_use — 与 source_import_test 同款说明。
/// 三类规则（书源 / 订阅源 / 替换规则）的导入、识别、落库与替换执行测试。
///
/// 全程离线：内存仓库 / 临时目录 + 假抓取器，不碰 path_provider / 网络。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/source/novel_rule_model.dart';
import 'package:mimao/novel/source/novel_rule_store.dart';
import 'package:mimao/novel/source/novel_source_importer.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

void main() {
  group('规则深链解析', () {
    test('三种 host 都给出类型与 src', () {
      expect(
        parseNovelRuleLink(
          'yuedu://booksource/importonline?src=https://x/book.json',
        )?.kind,
        NovelRuleKind.bookSource,
      );
      expect(
        parseNovelRuleLink(
          'yuedu://rsssource/importonline?src=https://x/rss.json',
        )?.kind,
        NovelRuleKind.rssSource,
      );
      final replace = parseNovelRuleLink(
        'yuedu://replacerule/importonline?src=https://x/replace.json',
      );
      expect(replace?.kind, NovelRuleKind.replaceRule);
      expect(replace?.url, 'https://x/replace.json');
    });

    test('yuedu://import/<kind>/importonline 形式也能解析', () {
      final link = parseNovelRuleLink(
        'yuedu://import/rsssource/importonline?src=https://x/rss.json',
      );
      expect(link?.kind, NovelRuleKind.rssSource);
      expect(link?.url, 'https://x/rss.json');
    });

    test('未知 host / 非 importonline / 缺 src 返回 null', () {
      expect(
        parseNovelRuleLink('yuedu://unknown/importonline?src=https://x/a'),
        isNull,
      );
      expect(
        parseNovelRuleLink('yuedu://rsssource/other?src=https://x/a'),
        isNull,
      );
      expect(parseNovelRuleLink('yuedu://rsssource/importonline'), isNull);
    });

    test('旧入口 parseImportSourceUrl 仍只认书源', () {
      expect(
        parseImportSourceUrl(
          'yuedu://rsssource/importonline?src=https://x/rss.json',
        ),
        isNull,
      );
      expect(
        parseImportSourceUrl(
          'yuedu://booksource/importonline?src=https://x/book.json',
        ),
        'https://x/book.json',
      );
    });
  });

  group('自动识别', () {
    test('按字段识别书源 / 订阅源 / 替换规则', () {
      expect(
        detectNovelRuleKind(<String, dynamic>{'bookSourceUrl': 'https://a'}),
        NovelRuleKind.bookSource,
      );
      expect(
        detectNovelRuleKind(<String, dynamic>{
          'sourceName': 'RSS',
          'sourceUrl': 'https://feed',
        }),
        NovelRuleKind.rssSource,
      );
      expect(
        detectNovelRuleKind(<String, dynamic>{
          'pattern': '广告',
          'replacement': '',
        }),
        NovelRuleKind.replaceRule,
      );
      expect(detectNovelRuleKind(<String, dynamic>{'foo': 1}), isNull);
    });
  });

  group('导入分流', () {
    late _MemoryBookStore bookStore;
    late _MemoryRssStore rssStore;
    late _MemoryReplaceStore replaceStore;
    late _FakeFetcher fetcher;
    late NovelSourceImporter importer;

    setUp(() {
      bookStore = _MemoryBookStore();
      rssStore = _MemoryRssStore();
      replaceStore = _MemoryReplaceStore();
      fetcher = _FakeFetcher();
      importer = NovelSourceImporter(
        bookStore,
        fetcher,
        rssStore: rssStore,
        replaceStore: replaceStore,
      );
    });

    test('深链类型优先：rsssource 落到订阅源仓库', () async {
      fetcher.text = jsonEncode(<Object?>[
        <String, Object?>{
          'sourceName': '某 RSS',
          'sourceUrl': 'https://feed.example/rss',
        },
      ]);
      final result = await importer.importFromLink(
        'yuedu://rsssource/importonline?src=https://x/rss.json',
      );
      expect(result.kind, NovelRuleKind.rssSource);
      expect(result.message, contains('1 个订阅源'));
      expect(rssStore.sources, hasLength(1));
      expect(bookStore.sources, isEmpty);
    });

    test('手选类型：普通 https 链接按替换规则导入', () async {
      fetcher.text = jsonEncode(<Object?>[
        <String, Object?>{
          'name': '去广告',
          'pattern': 'www\\.ad\\.com',
          'replacement': '',
          'isRegex': true,
        },
      ]);
      final result = await importer.importFromLink(
        'https://x/replace.json',
        kind: NovelRuleKind.replaceRule,
      );
      expect(result.kind, NovelRuleKind.replaceRule);
      expect(replaceStore.rules, hasLength(1));
      expect(replaceStore.rules.single.isRegex, isTrue);
    });

    test('自动识别：书源文件仍落书源仓库', () async {
      fetcher.text = jsonEncode(<Object?>[
        <String, Object?>{
          'bookSourceName': '神话',
          'bookSourceUrl': 'https://x/1',
        },
      ]);
      final result = await importer.importFromLink('https://x/book.json');
      expect(result.kind, NovelRuleKind.bookSource);
      expect(bookStore.sources, hasLength(1));
    });

    test('认不出类型时给可读错误', () async {
      fetcher.text = jsonEncode(<Object?>[
        <String, Object?>{'foo': 'bar'},
      ]);
      expect(
        () => importer.importFromLink('https://x/unknown.json'),
        throwsA(
          isA<NovelSourceImportException>().having(
            (e) => e.message,
            'message',
            contains('无法识别规则类型'),
          ),
        ),
      );
    });

    test('空文件 / 缺失的仓库都收敛为可读异常', () async {
      fetcher.text = '[]';
      expect(
        () => importer.importFromLink('https://x/empty.json'),
        throwsA(
          isA<NovelSourceImportException>().having(
            (e) => e.message,
            'message',
            contains('没有可用的规则'),
          ),
        ),
      );

      final bare = NovelSourceImporter(bookStore, fetcher);
      fetcher.text = jsonEncode(<Object?>[
        <String, Object?>{'sourceName': 'RSS', 'sourceUrl': 'https://feed'},
      ]);
      expect(
        () => bare.importFromLink(
          'yuedu://rsssource/importonline?src=https://x/rss.json',
        ),
        throwsA(
          isA<NovelSourceImportException>().having(
            (e) => e.message,
            'message',
            contains('没有可用的订阅源仓库'),
          ),
        ),
      );
    });
  });

  group('替换规则执行', () {
    NovelReplaceRule rule(
      String pattern,
      String replacement, {
      bool isRegex = false,
      bool enabled = true,
      String scope = '',
      bool scopeContent = true,
    }) => NovelReplaceRule(
      key: 'k',
      name: 'r',
      pattern: pattern,
      replacement: replacement,
      isRegex: isRegex,
      enabled: enabled,
      scope: scope,
      scopeTitle: false,
      scopeContent: scopeContent,
      raw: const <String, dynamic>{},
    );

    test('普通替换与正则分组替换', () {
      expect(
        applyReplaceRules('正文里的广告', <NovelReplaceRule>[rule('广告', '')]),
        '正文里的',
      );
      expect(
        applyReplaceRules('12章', <NovelReplaceRule>[
          rule(r'(\d+)章', '第\$1章', isRegex: true),
        ]),
        '第12章',
      );
    });

    test('坏正则跳过；替换成空时保留原文', () {
      expect(
        applyReplaceRules('原文', <NovelReplaceRule>[
          rule('(', 'x', isRegex: true),
        ]),
        '原文',
      );
      expect(applyReplaceRules('原文', <NovelReplaceRule>[rule('.*', '')]), '原文');
      expect(
        applyReplaceRules('原文', <NovelReplaceRule>[
          rule('原文', '', enabled: false),
        ]),
        '原文',
      );
    });

    test('作用范围：空全局，命中书名 / 书源地址才生效', () {
      final scoped = rule('广告', '');
      expect(
        scoped.appliesToBook(
          bookTitle: '任意书',
          sourceKey: 'src1',
          bookUrl: 'https://x/1',
        ),
        isTrue,
      );
      final limited = rule('广告', '', scope: '某书源');
      expect(
        limited.appliesToBook(
          bookTitle: '任意书',
          sourceKey: 'https://other/book',
          bookUrl: '',
        ),
        isFalse,
      );
      expect(
        limited.appliesToBook(
          bookTitle: '任意书',
          sourceKey: 'https://other/book',
          bookUrl: 'https://某书源/1',
        ),
        isTrue,
      );
    });
  });

  group('规则仓库', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('novel-rule-store-test-');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('订阅源：保存 / 启停 / 删除', () async {
      final store = NovelRssSourceStore(dir);
      final source = NovelRssSource.fromLegado(<String, dynamic>{
        'sourceName': 'RSS',
        'sourceUrl': 'https://feed/rss',
      });
      expect(await store.saveAll(<NovelRssSource>[source, source]), 1);
      var loaded = await store.loadAll();
      expect(loaded.single.name, 'RSS');

      await store.setEnabled(source.key, false);
      loaded = await store.loadAll();
      expect(loaded.single.enabled, isFalse);

      expect(await store.delete(source.key), isTrue);
      expect(await store.loadAll(), isEmpty);
    });

    test('替换规则：保存 / 启停 / 删除', () async {
      final store = NovelReplaceRuleStore(dir);
      final source = NovelReplaceRule.fromLegado(<String, dynamic>{
        'name': '去广告',
        'pattern': '广告',
        'replacement': '',
      });
      expect(await store.saveAll(<NovelReplaceRule>[source]), 1);
      var loaded = await store.loadAll();
      expect(loaded.single.pattern, '广告');
      expect(loaded.single.scopeContent, isTrue);

      await store.setEnabled(source.key, false);
      expect((await store.loadAll()).single.enabled, isFalse);

      expect(await store.delete(source.key), isTrue);
      expect(await store.loadAll(), isEmpty);
    });
  });
}

class _FakeFetcher implements NovelSourceFetcher {
  String text = '[]';
  String? error;

  @override
  Future<NovelSourceFetchResult> fetch(String url) async {
    if (error != null) throw StateError(error!);
    return NovelSourceFetchResult(text: text, finalUrl: url);
  }
}

class _MemoryBookStore implements NovelSourceStorage {
  final List<NovelBookSource> sources = <NovelBookSource>[];

  @override
  Future<List<NovelBookSource>> loadAll() async => List.unmodifiable(sources);

  @override
  Future<int> saveAll(Iterable<NovelBookSource> input) async {
    final unique = <String, NovelBookSource>{for (final s in input) s.key: s};
    sources
      ..removeWhere((s) => unique.containsKey(s.key))
      ..addAll(unique.values);
    return unique.length;
  }

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async => false;
}

class _MemoryRssStore implements NovelRssSourceStorage {
  final List<NovelRssSource> sources = <NovelRssSource>[];

  @override
  Future<List<NovelRssSource>> loadAll() async => List.unmodifiable(sources);

  @override
  Future<int> saveAll(Iterable<NovelRssSource> input) async {
    final unique = <String, NovelRssSource>{for (final s in input) s.key: s};
    sources
      ..removeWhere((s) => unique.containsKey(s.key))
      ..addAll(unique.values);
    return unique.length;
  }

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async => false;
}

class _MemoryReplaceStore implements NovelReplaceRuleStorage {
  final List<NovelReplaceRule> rules = <NovelReplaceRule>[];

  @override
  Future<List<NovelReplaceRule>> loadAll() async => List.unmodifiable(rules);

  @override
  Future<int> saveAll(Iterable<NovelReplaceRule> input) async {
    final unique = <String, NovelReplaceRule>{for (final r in input) r.key: r};
    rules
      ..removeWhere((r) => unique.containsKey(r.key))
      ..addAll(unique.values);
    return unique.length;
  }

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async => false;
}
