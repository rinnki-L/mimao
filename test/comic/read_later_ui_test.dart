// 稍后阅读相关 UI 的 widget 测试：主页卡片、稍后阅读整页、详情页按钮。
//
// 全部离线：FixtureComicDataSource 提供搜索/详情，假 ComicReadLaterApi 持有
// 内存列表。不碰 drift、不发网络。
//
// ignore_for_file: deprecated_member_use
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/data/fixture_comic_data_source.dart';
import 'package:mimao/comic/library_api.dart';
import 'package:mimao/comic/pages/comic_detail_page.dart';
import 'package:mimao/comic/pages/comic_home_page.dart';
import 'package:mimao/comic/pages/comic_read_later_page.dart';

const FixtureComicDataSource comicFixture = FixtureComicDataSource();

/// 稍后阅读假数据：星舟漫游 / 夜雨剑歌两条，来源名与 fixture 对齐。
const List<ComicLibraryEntry> twoEntries = <ComicLibraryEntry>[
  ComicLibraryEntry(
    id: 'xingzhou',
    sourceName: '漫画DB',
    title: '星舟漫游',
    detailUrl: 'https://example.com/comic/xingzhou',
  ),
  ComicLibraryEntry(
    id: 'yeyu',
    sourceName: '酷漫屋',
    title: '夜雨剑歌',
    detailUrl: 'https://example.com/comic/yeyu',
  ),
];

typedef _SetCall = ({String id, String sourceName, bool included});

/// 内存版稍后阅读 API：记录 setReadLater 参数，移出后真从列表删掉以便重读。
class _FakeReadLaterApi implements ComicReadLaterApi {
  _FakeReadLaterApi([List<ComicLibraryEntry>? entries])
    : _entries = List<ComicLibraryEntry>.from(
        entries ?? const <ComicLibraryEntry>[],
      );

  final List<ComicLibraryEntry> _entries;
  final List<_SetCall> setCalls = <_SetCall>[];

  @override
  Future<List<ComicLibraryEntry>> readLater() async =>
      List<ComicLibraryEntry>.unmodifiable(_entries);

  @override
  Future<bool> isReadLater(String id, String sourceName) async =>
      _entries.any((entry) => entry.id == id && entry.sourceName == sourceName);

  @override
  Future<void> setReadLater({
    required String id,
    required String sourceName,
    required String title,
    String? coverUrl,
    String detailUrl = '',
    required bool included,
  }) async {
    setCalls.add((id: id, sourceName: sourceName, included: included));
    if (included) {
      if (!_entries.any(
        (entry) => entry.id == id && entry.sourceName == sourceName,
      )) {
        _entries.add(
          ComicLibraryEntry(
            id: id,
            sourceName: sourceName,
            title: title,
            coverUrl: coverUrl,
            detailUrl: detailUrl,
          ),
        );
      }
    } else {
      _entries.removeWhere(
        (entry) => entry.id == id && entry.sourceName == sourceName,
      );
    }
  }
}

Widget _app(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF7C6BFF),
  ),
  home: child,
);

/// 小屏 390×844：任何 render overflow 都会作为异常让测试失败。
void _usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('主页稍后阅读卡片', () {
    testWidgets('2 条：卡片可见、计数 2 部、两张海报、点头进整页', (tester) async {
      _usePhoneSize(tester);
      final api = _FakeReadLaterApi(twoEntries);
      var opened = 0;
      await tester.pumpWidget(
        _app(
          ComicHomePage(
            dataSource: comicFixture,
            readLater: api,
            onOpenReadLater: () => opened++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('comic-home-read-later-card')),
        findsOneWidget,
      );
      expect(find.text('2 部'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('home-read-later-xingzhou')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('home-read-later-yeyu')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('comic-home-read-later-card-tap')));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('空队列：卡片仍可见，显示引导文案且不渲染海报', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          ComicHomePage(
            dataSource: comicFixture,
            readLater: _FakeReadLaterApi(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('comic-home-read-later-card')),
        findsOneWidget,
      );
      expect(find.text('在漫画详情页点「稍后阅读」，想读的漫画会收在这里。'), findsOneWidget);
      expect(find.text('0 部'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key as ValueKey<String>).value.startsWith(
                'home-read-later-',
              ),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('readLater 为 null：卡片整体隐藏（降级路径）', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(const ComicHomePage(dataSource: comicFixture)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('comic-home-read-later-card')), findsNothing);
      expect(
        find.byKey(const Key('comic-home-read-later-card-tap')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('稍后阅读整页', () {
    testWidgets('2 条：网格渲染、长按取消保留、确认调用 API 并移出', (tester) async {
      _usePhoneSize(tester);
      final api = _FakeReadLaterApi(twoEntries);
      await tester.pumpWidget(_app(ComicReadLaterPage(api: api)));
      await tester.pumpAndSettle();

      expect(find.text('稍后阅读'), findsOneWidget);
      expect(find.text('共 2 部 · 长按可移出'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('read-later-xingzhou')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('read-later-yeyu')),
        findsOneWidget,
      );

      // 长按 → 取消：条目保留，API 不被调用。
      await tester.longPress(
        find.byKey(const ValueKey<String>('read-later-xingzhou')),
      );
      await tester.pumpAndSettle();
      expect(find.text('移出稍后阅读？'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(api.setCalls, isEmpty);
      expect(
        find.byKey(const ValueKey<String>('read-later-xingzhou')),
        findsOneWidget,
      );

      // 再长按 → 确认：带上匹配的 id/source，条目从列表消失。
      await tester.longPress(
        find.byKey(const ValueKey<String>('read-later-xingzhou')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '移出'));
      await tester.pumpAndSettle();

      expect(api.setCalls, hasLength(1));
      expect(api.setCalls.single.id, 'xingzhou');
      expect(api.setCalls.single.sourceName, '漫画DB');
      expect(api.setCalls.single.included, isFalse);
      expect(
        find.byKey(const ValueKey<String>('read-later-xingzhou')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('read-later-yeyu')),
        findsOneWidget,
      );
      expect(find.text('共 1 部 · 长按可移出'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('空队列：显示空态提示', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(ComicReadLaterPage(api: _FakeReadLaterApi())),
      );
      await tester.pumpAndSettle();

      expect(find.text('还没有稍后阅读'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key as ValueKey<String>).value.startsWith('read-later-'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('详情页稍后阅读按钮', () {
    testWidgets('初始未加入：点击切换文案并回调 true / false', (tester) async {
      _usePhoneSize(tester);
      final reported = <bool>[];
      await tester.pumpWidget(
        _app(
          ComicDetailPage(
            dataSource: comicFixture,
            summary: FixtureComicDataSource.xingzhou,
            initiallyReadLater: false,
            onReadLaterChanged: reported.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('read-later-button')), findsOneWidget);
      expect(find.text('稍后阅读'), findsOneWidget);
      expect(find.text('已加入'), findsNothing);

      await tester.tap(find.byKey(const Key('read-later-button')));
      await tester.pump();
      expect(find.text('已加入'), findsOneWidget);
      expect(reported, <bool>[true]);

      await tester.tap(find.byKey(const Key('read-later-button')));
      await tester.pump();
      expect(find.text('稍后阅读'), findsOneWidget);
      expect(reported, <bool>[true, false]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('初始已加入：起始即显示已加入', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          const ComicDetailPage(
            dataSource: comicFixture,
            summary: FixtureComicDataSource.xingzhou,
            initiallyReadLater: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('read-later-button')), findsOneWidget);
      expect(find.text('已加入'), findsOneWidget);
      expect(find.text('稍后阅读'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('无回调时按钮仍渲染且点击不崩', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          const ComicDetailPage(
            dataSource: comicFixture,
            summary: FixtureComicDataSource.xingzhou,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('read-later-button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('read-later-button')));
      await tester.pump();

      expect(find.text('已加入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
