// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头说明。
// 翻页动画风格 + 九宫格点击区的页面级行为：
// - 点按按九宫格分发（默认手感不变）；
// - 章末「下一章」按钮仍可点（旧全屏热区的回归）；
// - 长按默认仍是选文（SelectionArea 不被抢）；
// - 六种动画风格都能渲染并翻页。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_reader_page.dart';
import 'package:mimao/novel/reader/novel_click_actions.dart';
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
  const NovelChapter(
    id: 'https://site.test/book/1/2',
    title: '第二章',
    index: 1,
    url: 'https://site.test/book/1/2',
  ),
];

class _LongEngine implements NovelOnlineEngine {
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
      NovelDetail(ref: ref, title: '长书', author: '作者', chapters: _chapters);

  @override
  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) async => NovelContent(
    chapterId: chapter.id,
    title: chapter.title,
    paragraphs: <String>[
      for (var i = 0; i < 60; i++)
        '第$i段：${List<String>.filled(120, '字').join()}',
    ],
  );
}

class _FixedStore implements NovelSourceStorage {
  @override
  Future<List<NovelBookSource>> loadAll() async => <NovelBookSource>[_source];

  @override
  Future<int> saveAll(Iterable<NovelBookSource> sources) async => 0;

  @override
  Future<void> setEnabled(String key, bool enabled) async {}

  @override
  Future<bool> delete(String key) async => false;
}

/// 短正文：一屏放得下，章末「下一章」按钮不用滚就能看到。
class _ShortEngine extends _LongEngine {
  @override
  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) async => NovelContent(
    chapterId: chapter.id,
    title: chapter.title,
    paragraphs: <String>['短篇第一段', '短篇第二段', '短篇第三段'],
  );
}

/// 底部面板的滑入偏移：Offset.zero = 菜单展开，非零 = 收起。
Offset _bottomPanelOffset(WidgetTester tester) {
  final slide = tester.widget<AnimatedSlide>(
    find
        .ancestor(
          of: find.byKey(const Key('novel-reader-settings')),
          matching: find.byType(AnimatedSlide),
        )
        .first,
  );
  return slide.offset;
}

Finder _footerWith(String prefix) => find.byWidgetPredicate(
  (widget) =>
      widget is Text &&
      widget.data != null &&
      widget.data!.startsWith(prefix) &&
      widget.data!.contains('/'),
);

Widget _reader({required NovelReaderSettings settings}) => MaterialApp(
  home: NovelReaderPage(
    bookId: 'book1',
    title: '长书',
    sourceKey: 'src1',
    bookUrl: 'https://site.test/book/1',
    chapterIndex: 0,
    chapters: _chapters,
    onlineEngine: _LongEngine(),
    sourceStore: _FixedStore(),
    settingsStore: MemoryNovelReaderSettingsStore(settings),
  ),
);

void main() {
  group('九宫格点击分发', () {
    testWidgets('默认：左侧上一页、右侧下一页、中间呼出菜单', (tester) async {
      await tester.pumpWidget(
        _reader(
          settings: const NovelReaderSettings(pageMode: NovelPageMode.page),
        ),
      );
      await tester.pumpAndSettle();
      expect(_footerWith('1/'), findsOneWidget);

      // 右侧 30%：下一页。
      await tester.tapAt(const Offset(760, 300));
      await tester.pumpAndSettle();
      expect(_footerWith('2/'), findsOneWidget);

      // 左侧 30%：上一页。
      await tester.tapAt(const Offset(40, 300));
      await tester.pumpAndSettle();
      expect(_footerWith('1/'), findsOneWidget);

      // 正中：菜单（底部功能键出现）。
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('novel-reader-settings')), findsOneWidget);
    });

    testWidgets('上/下两行默认无动作：点了不翻页也不弹菜单', (tester) async {
      await tester.pumpWidget(
        _reader(
          settings: const NovelReaderSettings(pageMode: NovelPageMode.page),
        ),
      );
      await tester.pumpAndSettle();
      expect(_footerWith('1/'), findsOneWidget);

      // 上中格、下中格：默认无动作。
      await tester.tapAt(const Offset(400, 40));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(400, 560));
      await tester.pumpAndSettle();
      expect(_footerWith('1/'), findsOneWidget);
    });

    testWidgets('自定义九宫格：左上格配成目录，点它就开目录', (tester) async {
      final zones = List<NovelClickAction>.from(novelDefaultClickZones);
      zones[NovelClickZone.topLeft.index] = NovelClickAction.catalog;
      await tester.pumpWidget(
        _reader(
          settings: NovelReaderSettings(
            pageMode: NovelPageMode.page,
            clickZones: zones,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 收起菜单，否则顶栏/底栏会盖住上排格子（正常阅读时也是收起的）。
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(40, 40));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('novel-catalog-list')), findsOneWidget);
    });

    testWidgets('九宫格配成无动作：中间点了不弹菜单', (tester) async {
      final zones = List<NovelClickAction>.from(novelDefaultClickZones);
      zones[NovelClickZone.center.index] = NovelClickAction.none;
      await tester.pumpWidget(
        _reader(
          settings: NovelReaderSettings(
            pageMode: NovelPageMode.page,
            clickZones: zones,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_bottomPanelOffset(tester), Offset.zero);

      // 用 Esc 收起菜单（中格此时无动作，点它收不起来）。
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_bottomPanelOffset(tester), isNot(Offset.zero));

      // 点中格：无动作，菜单不该再展开。
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();
      expect(_bottomPanelOffset(tester), isNot(Offset.zero));
    });
  });

  group('六种翻页动画', () {
    for (final style in NovelPageAnimStyle.values) {
      testWidgets('${style.name} 风格能翻页', (tester) async {
        await tester.pumpWidget(
          _reader(
            settings: NovelReaderSettings(
              pageMode: NovelPageMode.page,
              pageAnimStyle: style,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(_footerWith('1/'), findsOneWidget);

        await tester.tapAt(const Offset(760, 300));
        await tester.pumpAndSettle();
        expect(_footerWith('2/'), findsOneWidget);

        await tester.tapAt(const Offset(40, 300));
        await tester.pumpAndSettle();
        expect(_footerWith('1/'), findsOneWidget);
      });
    }

    testWidgets('系统「减少动态效果」开着时即使选了动画也不播', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _reader(
            settings: const NovelReaderSettings(
              pageMode: NovelPageMode.page,
              pageAnimStyle: NovelPageAnimStyle.cover,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(760, 300));
      // 不 pumpAndSettle 也立刻换页：没有过渡动画在跑。
      await tester.pump();
      expect(_footerWith('2/'), findsOneWidget);
    });
  });

  group('手势回归', () {
    testWidgets('章末「下一章」按钮仍可点（没被九宫格热区吃掉）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NovelReaderPage(
            bookId: 'book1',
            title: '短书',
            sourceKey: 'src1',
            bookUrl: 'https://site.test/book/1',
            chapterIndex: 0,
            chapters: _chapters,
            onlineEngine: _ShortEngine(),
            sourceStore: _FixedStore(),
            settingsStore: MemoryNovelReaderSettingsStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('novel-reader-next-chapter')));
      await tester.pumpAndSettle();
      expect(find.textContaining('第二章'), findsWidgets);
    });

    testWidgets('长按默认仍是选文：SelectionArea 存在且不注册长按接管', (tester) async {
      await tester.pumpWidget(_reader(settings: const NovelReaderSettings()));
      await tester.pumpAndSettle();

      expect(find.byType(SelectionArea), findsOneWidget);
      // 默认配置下正文手势层没有 onLongPressStart（否则会和选文抢）。
      final gesture = tester.widget<GestureDetector>(
        find
            .descendant(
              of: find.byType(SelectionArea),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(gesture.onLongPressStart, isNull);
      expect(gesture.onDoubleTap, isNull);
    });

    testWidgets('长按配成菜单后接管：正文手势注册了长按', (tester) async {
      await tester.pumpWidget(
        _reader(
          settings: const NovelReaderSettings(
            longPressAction: NovelLongPressAction.menu,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = tester.widget<GestureDetector>(
        find
            .descendant(
              of: find.byType(SelectionArea),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(gesture.onLongPressStart, isNotNull);
    });
  });
}
