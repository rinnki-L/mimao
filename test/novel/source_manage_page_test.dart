// ignore_for_file: deprecated_member_use — 与其他 novel 测试同款说明。
/// 书源管理页 widget 测试：用注入的假 WebView（不碰 native 插件）+ 内存存储，
/// 验证用户点网页「一键导入」→ 回调 → 导入服务 → 列表刷新 的闭环。
/// 全程无 dart:io / path_provider，避免真实文件 I/O 卡在 fake-async 测试区。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/pages/novel_source_manage_page.dart';
import 'package:mimao/novel/source/novel_source_importer.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

void main() {
  late _MemoryStorage store;
  late NovelSourceImporter importer;
  late _FakeFetcher fetcher;

  setUp(() {
    store = _MemoryStorage();
    fetcher = _FakeFetcher();
    importer = NovelSourceImporter(store, fetcher);
  });

  testWidgets('打开网站按钮渲染；点假网页「一键导入」后书源落库并出现在列表', (tester) async {
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

    expect(find.byKey(const Key('novel-source-open-site')), findsOneWidget);
    expect(find.text('还没有书源'), findsOneWidget);

    // 打开内嵌网页 → 点「一键导入」。
    await tester.tap(find.byKey(const Key('novel-source-open-site')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fake-web-import')));
    // 导入中 LinearProgressIndicator 是无限动画，pumpAndSettle 会挂死（LESSON.md
    // 已记）；这里都是内存异步，几帧即可推进完成。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('网页导入源'), findsOneWidget);
    expect(find.textContaining('已导入 1 个书源'), findsOneWidget);
    expect(store.sources, hasLength(1));
  });

  testWidgets('未点打开网站时不构造 WebView（列表/按钮可离线渲染）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NovelSourceManagePage(store: store, importer: importer),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('novel-source-open-site')), findsOneWidget);
    expect(find.byKey(const Key('novel-source-paste-import')), findsOneWidget);
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
