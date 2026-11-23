// ignore_for_file: deprecated_member_use — 与其他 novel 测试同款说明。
/// 书源管理页 widget 测试：用注入的假 WebView（不碰 native 插件）+ 内存存储，
/// 验证用户点网页「一键导入」→ 回调 → 导入服务 → 列表刷新 的闭环。
/// 全程无 dart:io / path_provider，避免真实文件 I/O 卡在 fake-async 测试区。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/pages/novel_source_manage_page.dart';
import 'package:mimao/novel/source/novel_rule_model.dart';
import 'package:mimao/novel/source/novel_rule_store.dart';
import 'package:mimao/novel/source/novel_source_importer.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

void main() {
  late _MemoryStorage store;
  late _MemoryRssStore rssStore;
  late _MemoryReplaceStore replaceStore;
  late NovelSourceImporter importer;
  late _FakeFetcher fetcher;

  setUp(() {
    store = _MemoryStorage();
    rssStore = _MemoryRssStore();
    replaceStore = _MemoryReplaceStore();
    fetcher = _FakeFetcher();
    importer = NovelSourceImporter(
      store,
      fetcher,
      rssStore: rssStore,
      replaceStore: replaceStore,
    );
  });

  testWidgets('点订阅站点卡片打开网站；点假网页「一键导入」后书源落库并出现在列表', (tester) async {
    fetcher.text = jsonEncode(<Object?>[
      <String, Object?>{
        'bookSourceName': '网页导入源',
        'bookSourceUrl': 'https://web/1',
      },
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: NovelSourceManagePage(
          store: store,
          importer: importer,
          webViewBuilder: (context, onImportLink) => ElevatedButton(
            key: const Key('fake-web-import'),
            onPressed: () => onImportLink(
              'yuedu://booksource/importonline?src=https://web/sy.json',
            ),
            child: const Text('网页一键导入'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 书源 tab 只有一个「导入书源」，不再有「打开书源网站」按钮。
    expect(find.byKey(const Key('novel-source-open-site')), findsNothing);
    expect(find.byKey(const Key('novel-source-paste-import')), findsOneWidget);
    expect(find.text('还没有书源'), findsOneWidget);

    // 打开网站 = 点「订阅源」里的订阅站点卡片（喵公子），满窗口进站点页。
    await tester.tap(find.text('订阅源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('喵公子书源管理'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回'), findsOneWidget);
    await tester.tap(find.byKey(const Key('fake-web-import')));
    // 导入中 LinearProgressIndicator 是无限动画，pumpAndSettle 会挂死（LESSON.md
    // 已记）；这里都是内存异步，几帧即可推进完成。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('已导入 1 个书源'), findsOneWidget);
    expect(store.sources, hasLength(1));

    // 返回规则管理页后仍停在订阅源分类；切回书源分类看新导入的源。
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('订阅站点'), findsOneWidget);
    await tester.tap(find.text('书源'));
    await tester.pumpAndSettle();
    expect(find.text('网页导入源'), findsOneWidget);
  });

  testWidgets('不点订阅卡片不构造 WebView（列表/按钮可离线渲染）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NovelSourceManagePage(store: store, importer: importer),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('novel-source-open-site')), findsNothing);
    expect(find.byKey(const Key('novel-source-paste-import')), findsOneWidget);
  });

  testWidgets('规则管理：三个分类 tab，订阅源与替换规则可导入并出现在列表', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NovelSourceManagePage(store: store, importer: importer),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('规则管理'), findsOneWidget);
    for (final label in <String>['书源', '订阅源', '替换规则']) {
      expect(find.text(label), findsOneWidget);
    }

    // 订阅源：默认订阅站点「喵公子」本来就算订阅源，应该直接出现在这里。
    await tester.tap(find.text('订阅源'));
    await tester.pumpAndSettle();
    expect(find.text('订阅站点'), findsOneWidget);
    expect(find.text('喵公子书源管理'), findsOneWidget);
    expect(find.text('还没有订阅源'), findsNothing);
    fetcher.text = jsonEncode(<Object?>[
      <String, Object?>{
        'sourceName': '某 RSS',
        'sourceUrl': 'https://rss.example/feed',
      },
    ]);
    await tester.tap(find.byKey(const Key('novel-rss-paste-import')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('novel-rule-import-link')),
      'https://rss.example/rules.json',
    );
    await tester.tap(find.byKey(const Key('novel-rule-import-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('某 RSS'), findsOneWidget);
    expect(find.text('RSS 订阅规则'), findsOneWidget);
    // 订阅站点与导入的 RSS 规则同屏展示，互不覆盖。
    expect(find.text('喵公子书源管理'), findsOneWidget);
    expect(find.textContaining('已导入 1 个订阅源'), findsOneWidget);
    expect(rssStore.sources, hasLength(1));
    expect(store.sources, isEmpty);

    // 等导入弹窗完全退场，再切下一个 tab（否则弹窗里的 chip 文案会混进查找）。
    await tester.pumpAndSettle();

    // 替换规则：同样从弹窗导入，落到替换规则仓库。
    await tester.tap(find.text('替换规则'));
    await tester.pumpAndSettle();
    expect(find.text('还没有替换规则'), findsOneWidget);
    fetcher.text = jsonEncode(<Object?>[
      <String, Object?>{
        'name': '去广告',
        'pattern': 'www.ad.com',
        'replacement': '',
      },
    ]);
    await tester.tap(find.byKey(const Key('novel-replace-import-empty')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('novel-rule-import-link')),
      'https://rules.example/replace.json',
    );
    await tester.tap(find.byKey(const Key('novel-rule-import-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('去广告'), findsOneWidget);
    expect(find.textContaining('已导入 1 条替换规则'), findsOneWidget);
    expect(replaceStore.rules, hasLength(1));
    expect(replaceStore.rules.single.pattern, 'www.ad.com');
  });
}

class _MemoryStorage implements NovelSourceStorage {
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
  Future<void> setEnabled(String key, bool enabled) async {
    final i = sources.indexWhere((s) => s.key == key);
    if (i >= 0) sources[i] = sources[i].copyWith(enabled: enabled);
  }

  @override
  Future<bool> delete(String key) async {
    final before = sources.length;
    sources.removeWhere((s) => s.key == key);
    return sources.length != before;
  }
}

class _FakeFetcher implements NovelSourceFetcher {
  String text = '[]';

  @override
  Future<NovelSourceFetchResult> fetch(String url) async =>
      NovelSourceFetchResult(text: text, finalUrl: url);
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
