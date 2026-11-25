// ignore_for_file: deprecated_member_use — 与 music/contract_test.dart 同款说明。
/// 小说契约/模型守卫测试（验收 4/5/6/7 的模型侧）。
///
/// 只测形状与纯函数，不碰任何抓取/解析/IO：模块可空构造、元信息、占位页
/// 在 widget 测试下不 throw、进度文案确定、领域模型 JSON 往返无损。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_entry.dart';

void main() {
  test('4 NovelModule() 无参可构造，所有注入字段可空且不抛', () {
    final module = NovelModule();
    expect(module.engine, isNull);
    expect(module.dataSource, isNull);
    expect(module.collect, isNull);
    expect(module.history, isNull);
    expect(module.searchHistory, isNull);
    expect(module.stats, isNull);
    expect(module.prefs, isNull);
    expect(module.sourceStore, isNull);
    // 显式给全部字段注入值也不抛。
    expect(NovelModule(sourceStore: Object()), isA<NovelModule>());
  });

  test('5 NovelModule 元信息 type/label/icon 与 MediaType.novel 对齐', () {
    final module = NovelModule();
    expect(module.type, MediaType.novel);
    expect(module.label, '小说');
    expect(module.icon, MediaType.novel.icon);
  });

  testWidgets('5 buildHome/buildSettings 渲染骨架页不 throw（buildHome 自带 Scaffold）', (
    tester,
  ) async {
    final module = NovelModule();
    // buildHome 返回自带 Scaffold 的导航骨架，直接作为 MaterialApp.home。
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) => module.buildHome(context)),
      ),
    );
    await tester.pumpAndSettle();
    // 默认「首页」；窄窗仍用五入口 NavigationBar。
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('首页'), findsWidgets);
    expect(find.text('最近阅读'), findsOneWidget);

    // buildSettings 自带 Scaffold（设置页），直接作为 home 渲染。
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) => module.buildSettings(context)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('小说设置'), findsOneWidget);
  });

  test('7 novelProgressText 三种输入：无进度/读到/超 100% 夹取', () {
    // 无可计算进度（chapterIndex=0）→ novelReadText。
    expect(novelProgressText(chapterIndex: 0, chapterCount: 10), novelReadText);
    // 有 index 但总章数为 0（无进度可算）→ novelReadText。
    expect(novelProgressText(chapterIndex: 3, chapterCount: 0), novelReadText);
    // 30%。
    expect(
      novelProgressText(chapterIndex: 3, chapterCount: 10),
      '看到第 3 章 · 30%',
    );
    // 超 100% clamp 到 100%。
    expect(
      novelProgressText(chapterIndex: 11, chapterCount: 10),
      '看到第 11 章 · 100%',
    );
  });

  test('7 NovelRef 默认 sourceName=legado，JSON 往返与 ==/hashCode 一致', () {
    const ref = NovelRef(id: 'b1');
    expect(ref.sourceName, novelSourceName);
    expect(ref.sourceName, 'legado');

    final json = ref.toJson();
    expect(json, <String, Object?>{'id': 'b1', 'sourceName': 'legado'});
    final restored = NovelRef.fromJson(json);
    expect(restored, ref);
    expect(restored.hashCode, ref.hashCode);

    // 缺省sourceName 的 JSON（旧数据）回退到 legado。
    expect(
      NovelRef.fromJson(<String, Object?>{'id': 'x'}).sourceName,
      'legado',
    );
    // 相等性同时考虑 sourceName。
    expect(const NovelRef(id: 'b1', sourceName: 'other') == ref, isFalse);
  });

  test('6 四个领域模型 toJson/fromJson 往返无损（含 list 的 Detail/Content）', () {
    const summary = NovelSummary(
      id: 'b1',
      title: '书名',
      coverUrl: 'https://example.com/c.jpg',
      author: '作者',
      sourceName: 'legado',
      sourceKey: 'src-9',
      bookUrl: 'https://example.com/book/1',
      intro: '简介',
      kind: '玄幻,都市',
      latestChapter: '第100章',
      wordCount: '30万字',
      type: 0,
    );
    final restoredSummary = NovelSummary.fromJson(summary.toJson());
    // 这些字段决定"从书架恢复在线抓取"能否成功，缺一个都会让续读断链。
    expect(restoredSummary.id, summary.id);
    expect(restoredSummary.title, summary.title);
    expect(restoredSummary.coverUrl, summary.coverUrl);
    expect(restoredSummary.author, summary.author);
    expect(restoredSummary.sourceName, summary.sourceName);
    expect(restoredSummary.sourceKey, 'src-9');
    expect(restoredSummary.bookUrl, 'https://example.com/book/1');
    expect(restoredSummary.intro, '简介');
    expect(restoredSummary.kind, '玄幻,都市');
    expect(restoredSummary.latestChapter, '第100章');
    expect(restoredSummary.wordCount, '30万字');
    expect(restoredSummary.type, 0);

    const chapters = <NovelChapter>[
      NovelChapter(id: 'c1', title: '第一章', index: 1, url: 'https://x/1'),
      NovelChapter(id: 'c2', title: '第二章', index: 2, url: 'https://x/2'),
    ];
    const detail = NovelDetail(
      ref: NovelRef(id: 'b1'),
      title: '书名',
      coverUrl: 'https://example.com/c.jpg',
      chapters: chapters,
    );
    final restoredDetail = NovelDetail.fromJson(detail.toJson());
    expect(restoredDetail.ref, detail.ref);
    expect(restoredDetail.title, detail.title);
    expect(restoredDetail.coverUrl, detail.coverUrl);
    expect(restoredDetail.chapters, hasLength(2));
    expect(restoredDetail.chapters.map((c) => c.id), <String>['c1', 'c2']);
    expect(restoredDetail.chapters.last.index, 2);

    const content = NovelContent(
      chapterId: 'c1',
      title: '第一章',
      paragraphs: <String>['段落一', '段落二', '段落三'],
    );
    final restoredContent = NovelContent.fromJson(content.toJson());
    expect(restoredContent.chapterId, content.chapterId);
    expect(restoredContent.title, content.title);
    expect(restoredContent.paragraphs, <String>['段落一', '段落二', '段落三']);
  });
}
