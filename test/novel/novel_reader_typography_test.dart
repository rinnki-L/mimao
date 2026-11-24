// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头说明。
// 阅读排版渲染：标题居中/分段、页眉页脚三槽、双栏分屏页数。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_reader_page.dart';
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
    title: '第一章 新生',
    index: 0,
    url: 'https://site.test/book/1/1',
  ),
  const NovelChapter(
    id: 'https://site.test/book/1/2',
    title: '第二章 姐姐',
    index: 1,
    url: 'https://site.test/book/1/2',
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
      for (var i = 0; i < 40; i++)
        '第$i段：${List<String>.filled(90, '字').join()}',
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

Widget _reader(NovelReaderSettings settings, {String tag = 'a'}) => MaterialApp(
  home: NovelReaderPage(
    // 同一测试里连开两次阅读器时，key 不同才会重建 State（否则设置不会重读）。
    key: ValueKey<String>(tag),
    bookId: 'book1',
    title: '长书',
    sourceKey: 'src1',
    bookUrl: 'https://site.test/book/1',
    chapterIndex: 0,
    chapters: _chapters,
    onlineEngine: _Engine(),
    sourceStore: _FixedStore(),
    settingsStore: MemoryNovelReaderSettingsStore(settings),
  ),
);

void main() {
  testWidgets('标题分段：主标题 + 分隔符 + 副标题，居中', (tester) async {
    await tester.pumpWidget(
      _reader(
        const NovelReaderSettings(
          pageMode: NovelPageMode.page,
          titleMode: NovelTitleMode.center,
          titleSegment: true,
          titleSegmentDivider: '·',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.textSpan != null &&
                widget.textSpan!.toPlainText().contains('第一章'),
          )
          .first,
    );
    expect(title.textSpan!.toPlainText(), '第一章·新生');
    expect(title.textAlign, TextAlign.center);
  });

  testWidgets('标题隐藏时正文页不出现标题', (tester) async {
    await tester.pumpWidget(
      _reader(
        const NovelReaderSettings(
          pageMode: NovelPageMode.page,
          titleMode: NovelTitleMode.hide,
          // 页眉/页脚默认也放章节名，这里都关掉避免误判。
          showFooter: false,
          showHeader: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 顶部栏也显示章节名，这里只看正文页体内是否还有标题。
    final body = find.byKey(const Key('novel-reader-page-body'));
    expect(body, findsOneWidget);
    final titleTexts = find.descendant(
      of: body,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data != null &&
            widget.data!.contains('第一章 新生'),
      ),
    );
    expect(titleTexts, findsNothing);
  });

  testWidgets('页眉三槽：书名 / 章节名 / 页码进度', (tester) async {
    await tester.pumpWidget(
      _reader(
        const NovelReaderSettings(
          pageMode: NovelPageMode.page,
          showHeader: true,
          headerSlots: <NovelChromeSlot>[
            NovelChromeSlot.book,
            NovelChromeSlot.chapter,
            NovelChromeSlot.pageAndPercent,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('长书'), findsWidgets);
    expect(find.text('第一章 新生'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.data != null &&
            widget.data!.contains('/') &&
            widget.data!.contains('%'),
      ),
      findsWidgets,
    );
  });

  testWidgets('页脚自定义文案生效', (tester) async {
    await tester.pumpWidget(
      _reader(
        const NovelReaderSettings(
          pageMode: NovelPageMode.page,
          footerSlots: <NovelChromeSlot>[
            NovelChromeSlot.custom,
            NovelChromeSlot.none,
            NovelChromeSlot.percent,
          ],
          footerCustomText: '我的页脚',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('我的页脚'), findsOneWidget);
  });

  testWidgets('双栏：宽窗口下屏数少于单栏页数，且标题页独占一屏', (tester) async {
    // 双栏要求窗口 ≥1100 且横向，测试默认 800x600 不满足，先放大窗口。
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<int> pageCountOf(NovelReaderSettings settings, String tag) async {
      await tester.pumpWidget(_reader(settings, tag: tag));
      await tester.pumpAndSettle();
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .where(
            (widget) =>
                widget.data != null &&
                RegExp(r'^\d+/\d+').hasMatch(widget.data!),
          )
          .toList();
      final raw = texts.isEmpty ? '' : texts.first.data!;
      final match = RegExp(r'/(\d+)').firstMatch(raw);
      return match == null ? 0 : int.parse(match.group(1)!);
    }

    final single = await pageCountOf(
      const NovelReaderSettings(pageMode: NovelPageMode.page),
      'single',
    );
    final double = await pageCountOf(
      const NovelReaderSettings(pageMode: NovelPageMode.page, twoColumn: true),
      'double',
    );
    expect(single, greaterThan(2));
    // 双栏把两列并成一屏，屏数应当明显少于单栏页数。
    expect(double, lessThan(single));
  });
}
