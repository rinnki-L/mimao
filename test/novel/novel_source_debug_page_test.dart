// ignore_for_file: deprecated_member_use — 与其他 novel 测试同款说明。
/// 书源调试页 widget 测试：页签渲染、动作分发、校验结果展示、取消。
///
/// 注入 fake 引擎（不碰网络/QuickJS）；真实引擎链路由 legado_engine_test 覆盖。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_source_debug_page.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

final NovelBookSource _source = NovelBookSource(
  key: 'k1',
  name: '测试源',
  url: 'https://s.example',
  type: 0,
  enabled: true,
  raw: const <String, dynamic>{
    'bookSourceName': '测试源',
    'bookSourceUrl': 'https://s.example',
    'searchUrl': '/s?q={{key}}',
  },
);

final NovelSummary _book = NovelSummary(
  id: 'k1::https://s.example/1',
  title: '测试书',
  author: '作者',
  sourceKey: 'k1',
  bookUrl: 'https://s.example/1',
);

class _FakeStore implements NovelSourceStorage {
  @override
  Future<List<NovelBookSource>> loadAll() async => <NovelBookSource>[_source];

  @override
  Future<int> saveAll(Iterable<NovelBookSource> sources) async => 0;

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async => false;
}

class _FakeEngine implements NovelOnlineEngine {
  _FakeEngine({this.failSearch = false});

  final bool failSearch;
  final List<String> calls = <String>[];

  @override
  Future<List<NovelSummary>> searchSource(
    NovelBookSource source,
    String keyword, {
    int page = 1,
  }) async {
    calls.add('search:$keyword');
    if (failSearch) throw Exception('搜索挂了');
    return <NovelSummary>[_book];
  }

  @override
  Future<NovelDetail> bookDetail(
    NovelBookSource source,
    NovelRef ref, {
    String? titleHint,
    String? authorHint,
  }) async {
    calls.add('detail');
    return NovelDetail(
      ref: _book.ref,
      title: '测试书',
      author: '作者',
      chapters: const <NovelChapter>[
        NovelChapter(id: 'c1', title: '第一章', index: 0, url: 'https://s/1'),
      ],
    );
  }

  @override
  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) async {
    calls.add('content');
    return NovelContent(
      chapterId: chapter.id,
      title: chapter.title,
      paragraphs: const <String>['第一段正文'],
    );
  }

  @override
  Future<List<NovelExploreKind>> exploreKinds(NovelBookSource source) async =>
      const <NovelExploreKind>[];

  @override
  Future<List<NovelSummary>> exploreSource(
    NovelBookSource source,
    NovelExploreKind kind, {
    int page = 1,
  }) async => const <NovelSummary>[];

  @override
  void close() {}
}

Future<void> _pump(WidgetTester tester, _FakeEngine engine) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: NovelSourceDebugPage(engine: engine, store: _FakeStore()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('页面渲染：书源下拉、动作分段、四个页签都在', (tester) async {
    await _pump(tester, _FakeEngine());

    expect(find.byKey(const Key('novel-debug-source')), findsOneWidget);
    expect(find.byKey(const Key('novel-debug-action')), findsOneWidget);
    expect(find.byKey(const Key('novel-debug-run')), findsOneWidget);
    expect(find.byKey(const Key('novel-debug-verify')), findsOneWidget);
    // 四个页签渲染（TabBar 必须有 controller，否则这里会红屏断言）。
    expect(find.text('执行链路'), findsOneWidget);
    expect(find.text('原始 HTML'), findsOneWidget);
    expect(find.text('JS 控制台'), findsOneWidget);
    expect(find.text('错误堆栈'), findsOneWidget);
    expect(find.textContaining('选一个动作后点「跑」'), findsOneWidget);
  });

  testWidgets('跑「搜索」：展示链路、摘要与原始 HTML 页签', (tester) async {
    final engine = _FakeEngine();
    await _pump(tester, engine);

    await tester.tap(find.byKey(const Key('novel-debug-run')));
    await tester.pumpAndSettle();

    expect(engine.calls, contains('search:测试源'));
    expect(find.textContaining('1 本'), findsWidgets);
    // 执行链路页签有阶段/结果事件。
    expect(find.textContaining('解析结果'), findsWidgets);
  });

  testWidgets('完整校验：四步结果与结论可见', (tester) async {
    final engine = _FakeEngine();
    await _pump(tester, engine);

    await tester.tap(find.byKey(const Key('novel-debug-verify')));
    await tester.pumpAndSettle();

    expect(find.text('搜索'), findsWidgets);
    expect(find.text('详情'), findsWidgets);
    expect(find.text('目录'), findsWidgets);
    expect(find.text('正文'), findsWidgets);
    expect(find.textContaining('全部通过'), findsOneWidget);
  });

  testWidgets('校验失败：失败步骤标红并给可读错误', (tester) async {
    await _pump(tester, _FakeEngine(failSearch: true));

    await tester.tap(find.byKey(const Key('novel-debug-verify')));
    await tester.pumpAndSettle();

    expect(find.textContaining('搜索失败'), findsOneWidget);
    expect(find.textContaining('搜索挂了'), findsWidgets);
  });

  testWidgets('切换动作后按钮文案跟着变', (tester) async {
    await _pump(tester, _FakeEngine());

    await tester.tap(find.text('正文'));
    await tester.pumpAndSettle();
    expect(find.text('跑「正文」'), findsOneWidget);
  });

  testWidgets('批量校验入口存在；空书源时给可操作空态', (tester) async {
    final engine = _FakeEngine();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: NovelSourceDebugPage(engine: engine, store: _EmptyStore()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有书源'), findsOneWidget);
    expect(find.textContaining('先到「规则管理'), findsOneWidget);
  });
}

class _EmptyStore implements NovelSourceStorage {
  @override
  Future<List<NovelBookSource>> loadAll() async => const <NovelBookSource>[];

  @override
  Future<int> saveAll(Iterable<NovelBookSource> sources) async => 0;

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async => false;
}
