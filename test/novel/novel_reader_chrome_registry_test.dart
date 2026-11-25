// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头说明。
// 顶栏/底栏/浮动栏按注册表渲染：配置顺序、启用、行数、图标文字都生效。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_reader_page.dart';
import 'package:mimao/novel/reader/novel_menu_actions.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

const _source = NovelBookSource(
  key: 'src1',
  name: '测试源',
  url: 'https://site.test',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{},
);

final _chapters = <NovelChapter>[
  const NovelChapter(
    id: 'https://site.test/book/1/1',
    title: '第一章',
    index: 0,
    url: 'https://site.test/book/1/1',
  ),
];

class _Engine implements NovelOnlineEngine {
  @override
  void close() {}

  @override
  Future<List<NovelSummary>> searchSource(
    NovelBookSource source,
    String keyword, {
    int page = 1,
  }) async => const <NovelSummary>[];

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
  Future<NovelDetail> bookDetail(
    NovelBookSource source,
    NovelRef ref, {
    String? titleHint,
    String? authorHint,
  }) async =>
      NovelDetail(ref: ref, title: '菜单书', author: '作者', chapters: _chapters);

  @override
  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) async => NovelContent(
    chapterId: chapter.id,
    title: chapter.title,
    paragraphs: <String>[for (var i = 0; i < 20; i++) '第$i段：正文正文正文。'],
  );
}

class _Store implements NovelSourceStorage {
  @override
  Future<List<NovelBookSource>> loadAll() async => <NovelBookSource>[_source];

  @override
  Future<int> saveAll(Iterable<NovelBookSource> sources) async => 0;

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async => false;
}

Future<void> _pump(
  WidgetTester tester,
  NovelReaderSettings settings, {
  Key? key,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: NovelReaderPage(
        key: key,
        bookId: 'book1',
        title: '菜单书',
        sourceKey: 'src1',
        bookUrl: 'https://site.test/book/1',
        chapterIndex: 0,
        chapters: _chapters,
        onlineEngine: _Engine(),
        sourceStore: _Store(),
        settingsStore: MemoryNovelReaderSettingsStore(settings),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('顶栏按配置顺序渲染，禁用的不出现', (tester) async {
    await _pump(
      tester,
      const NovelReaderSettings(
        titleBarMenu: <NovelMenuButtonItem>[
          NovelMenuButtonItem(novelMenuActionMore),
          NovelMenuButtonItem(novelMenuActionSwitchSource),
          // 禁用项：配置里留着，但不该渲染。
          NovelMenuButtonItem(novelMenuActionRefresh, enabled: false),
        ],
      ),
    );

    expect(find.byKey(const Key('novel-reader-more')), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-switch-source')), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-refresh')), findsNothing);
  });

  testWidgets('顶栏紧凑模式只留「更多」，不显示章节副标题与书源名', (tester) async {
    await _pump(tester, const NovelReaderSettings(titleBarCompact: true));

    expect(find.byKey(const Key('novel-reader-more')), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-download')), findsNothing);
    expect(find.byKey(const Key('novel-reader-switch-source')), findsNothing);
    expect(find.byKey(const Key('novel-reader-source-name')), findsNothing);
    // 书名仍在。
    expect(find.text('菜单书'), findsWidgets);
  });

  testWidgets('底栏按配置渲染：自定义项出现、默认项被换掉', (tester) async {
    await _pump(
      tester,
      const NovelReaderSettings(
        bottomBarMenu: <NovelMenuButtonItem>[
          NovelMenuButtonItem(novelMenuActionCatalog),
          NovelMenuButtonItem(novelMenuActionPreviousChapter),
          NovelMenuButtonItem(novelMenuActionNextChapter),
        ],
      ),
    );

    expect(find.byKey(const Key('novel-reader-catalog')), findsOneWidget);
    expect(
      find.byKey(const Key('novel-reader-previousChapter')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('novel-reader-nextChapter')), findsOneWidget);
    // 默认的搜索/朗读被换掉，不再渲染。
    expect(find.byKey(const Key('novel-reader-search')), findsNothing);
    expect(find.byKey(const Key('novel-reader-tts')), findsNothing);
  });

  testWidgets('图标显示文字开关生效', (tester) async {
    await _pump(
      tester,
      const NovelReaderSettings(
        menuShowIconText: true,
        bottomBarMenu: <NovelMenuButtonItem>[
          NovelMenuButtonItem(novelMenuActionCatalog),
        ],
      ),
    );
    // 文字标签出现（底栏按钮下方）。
    expect(find.text('目录'), findsWidgets);
  });

  testWidgets('浮动行默认不渲染；配上之后出现', (tester) async {
    await _pump(tester, const NovelReaderSettings(), key: const Key('a'));
    expect(find.byKey(const Key('novel-reader-previousChapter')), findsNothing);

    // 换 key 强制重建 State，让新的 settingsStore 被读一次。
    await _pump(
      tester,
      const NovelReaderSettings(
        floatingBarMenu: <NovelMenuButtonItem>[
          NovelMenuButtonItem(novelMenuActionPreviousChapter),
          NovelMenuButtonItem(novelMenuActionNextChapter),
        ],
      ),
      key: const Key('b'),
    );
    expect(
      find.byKey(const Key('novel-reader-previousChapter')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('novel-reader-nextChapter')), findsOneWidget);
  });

  testWidgets('底栏圆角配置真正落到 Material 的 shape 上', (tester) async {
    await _pump(tester, const NovelReaderSettings(menuBottomRadius: 0));
    final panel = tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(const Key('novel-reader-catalog')),
            matching: find.byType(Material),
          )
          .first,
    );
    final shape = panel.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.zero);
  });

  testWidgets('底栏放不下的动作收进「更多动作」，不静默消失', (tester) async {
    // 每行 2 个、1 行 = 容量 2；配 4 个动作 → 1 个 + 「更多动作」入口。
    await _pump(
      tester,
      const NovelReaderSettings(
        menuIconItemsPerRow: 2,
        menuIconRowCount: 1,
        bottomBarMenu: <NovelMenuButtonItem>[
          NovelMenuButtonItem(novelMenuActionSearch),
          NovelMenuButtonItem(novelMenuActionCatalog),
          NovelMenuButtonItem(novelMenuActionTts),
          NovelMenuButtonItem(novelMenuActionSettings),
        ],
      ),
    );

    // 第一个动作 + 「更多动作」入口可见；被挤出的不直接渲染。
    expect(find.byKey(const Key('novel-reader-search')), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-moreActions')), findsOneWidget);
    expect(find.byKey(const Key('novel-reader-settings')), findsNothing);

    // 点开「更多动作」能看到被挤出的那批。
    await tester.tap(find.byKey(const Key('novel-reader-moreActions')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('novel-more-action-catalog')), findsOneWidget);
    expect(find.byKey(const Key('novel-more-action-menu')), findsOneWidget);
  });
}
