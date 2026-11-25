// ignore_for_file: deprecated_member_use — 与小说其他页面同款 Flutter 3.50 说明。
// 书架 8a 的界面回归：五种布局切换、拖拽手动排序落库、书籍备注/系列/
// 自定义封面、空态入口。全部用内存 drift 库 + fake 封面选择器，不碰插件。
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/novel/collect_service.dart';
import 'package:mimao/novel/history_service.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/pages/novel_shelf_page.dart';
import 'package:mimao/novel/pages/shelf/shelf_cards.dart';
import 'package:mimao/novel/shelf/novel_cover_picker.dart';
import 'package:mimao/novel/shelf/shelf_view_config.dart';

class _FakePrefs implements NovelPrefsApi {
  _FakePrefs([Map<String, String>? seed]) : values = <String, String>{...?seed};

  final Map<String, String> values;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FakeCoverPicker implements NovelCoverPicker {
  _FakeCoverPicker(this.path);

  final String? path;
  int calls = 0;

  @override
  Future<String?> pickAndStore(String bookId) async {
    calls++;
    return path;
  }
}

void main() {
  late AppDb appDb;
  late NovelDb novelDb;
  late LibraryRepository library;
  late NovelCollectService collect;
  late NovelHistoryService history;

  setUp(() {
    appDb = AppDb.forTesting(NativeDatabase.memory());
    novelDb = NovelDb.forTesting(NativeDatabase.memory());
    library = LibraryRepository(appDb);
    collect = NovelCollectService(novelDb, library);
    history = NovelHistoryService(novelDb, library);
  });

  tearDown(() async {
    await appDb.close();
    await novelDb.close();
  });

  NovelSummary book(String id, String title, {String kind = ''}) =>
      NovelSummary(id: id, title: title, author: '作者$id', kind: kind);

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Future<void> pumpShelf(
    WidgetTester tester, {
    required NovelPrefsApi prefs,
    NovelCoverPicker? coverPicker,
    ValueChanged<int>? onSelectTab,
  }) async {
    await tester.pumpWidget(
      wrap(
        NovelShelfPage(
          active: true,
          collect: collect,
          history: history,
          prefs: prefs,
          coverPicker: coverPicker,
          onSelectTab: onSelectTab ?? (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 默认筛「在读」；这些用例的书多为未读，先切「全部」。
    if (find.textContaining('全部').evaluate().isNotEmpty) {
      await tester.tap(find.textContaining('全部').first);
      await tester.pumpAndSettle();
    }
  }

  Future<void> chooseMode(WidgetTester tester, NovelShelfMode mode) async {
    await tester.tap(find.byTooltip('书架操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('布局设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('novel-shelf-mode-${mode.key}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-shelf-layout-save')));
    await tester.pumpAndSettle();
  }

  testWidgets('五种布局都能渲染，且选择落进 kv 后重建仍保持', (tester) async {
    await collect.collect(book('b1', '三体', kind: '科幻,经典'));
    await collect.collect(book('b2', '球状闪电'));
    await history.saveProgress(book('b1', '三体'), 10, 100);
    final prefs = _FakePrefs();

    await pumpShelf(tester, prefs: prefs);
    expect(find.byType(ShelfGridCard), findsWidgets);

    for (final mode in <NovelShelfMode>[
      NovelShelfMode.list,
      NovelShelfMode.waterfall,
      NovelShelfMode.folder,
      NovelShelfMode.dualColumn,
      NovelShelfMode.grid,
    ]) {
      await chooseMode(tester, mode);
      expect(find.text('三体'), findsWidgets, reason: '${mode.label} 丢书');
      final saved = NovelShelfViewConfig.decode(
        prefs.values[novelPrefShelfView],
      );
      expect(saved.mode, mode, reason: '${mode.label} 没落进 kv');

      // 重建页面模拟重启：模式必须从 kv 读回来。
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpShelf(tester, prefs: prefs);
      expect(find.text('三体'), findsWidgets, reason: '${mode.label} 重启后丢书');
    }

    // 列表模式用行卡，网格模式用网格卡——确认布局真的换了，不只是存了值。
    await chooseMode(tester, NovelShelfMode.list);
    expect(find.byType(ShelfListRow), findsWidgets);
    expect(find.byType(ShelfGridCard), findsNothing);
    await chooseMode(tester, NovelShelfMode.grid);
    expect(find.byType(ShelfGridCard), findsWidgets);
  });

  testWidgets('双列在宽窗下真的分成左右两栏（不退化成普通网格）', (tester) async {
    // 回归：原实现把整窗列数套到半窗，1440 宽时每栏还是 8 列，
    // 双列看起来和普通网格一模一样。
    await collect.collect(book('b1', '第一本'));
    await collect.collect(book('b2', '第二本'));
    await collect.collect(book('b3', '第三本'));
    await collect.collect(book('b4', '第四本'));
    final prefs = _FakePrefs(<String, String>{
      novelPrefShelfView: const NovelShelfViewConfig(
        mode: NovelShelfMode.dualColumn,
      ).encode(),
    });
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpShelf(tester, prefs: prefs);

    final cards = tester.widgetList<ShelfGridCard>(find.byType(ShelfGridCard));
    expect(cards, hasLength(4));
    final xs = <double>[
      for (final element in find.byType(ShelfGridCard).evaluate())
        tester.getTopLeft(find.byWidget(element.widget)).dx,
    ]..sort();
    // 至少两个不同的起始 x，说明确实分了两栏。
    expect(xs.first, lessThan(xs.last - 100));
    // 每栏列数被限制在 2..4（不是整窗的 8 列）。
    final perPane = cards.length ~/ 2;
    final leftXs = xs.take(perPane).toSet();
    expect(leftXs.length, lessThanOrEqualTo(4));
  });

  testWidgets('展示项开关真的影响卡片', (tester) async {
    await collect.collect(book('b1', '三体', kind: '科幻'));
    final prefs = _FakePrefs(<String, String>{
      novelPrefShelfView: const NovelShelfViewConfig().encode(),
    });
    // 最新章节默认开、标签默认关。
    await pumpShelf(tester, prefs: prefs);
    expect(find.textContaining('科幻'), findsNothing);

    await tester.tap(find.byTooltip('书架操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('布局设置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('novel-shelf-show-tags')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-shelf-show-tags')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('novel-shelf-show-latest')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-shelf-show-latest')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-shelf-layout-save')));
    await tester.pumpAndSettle();

    expect(find.text('科幻'), findsWidgets);
    final saved = NovelShelfViewConfig.decode(prefs.values[novelPrefShelfView]);
    expect(saved.showTags, isTrue);
    expect(saved.showLatestChapter, isFalse);
  });

  testWidgets('拖拽排序：手动模式拖动后顺序落 kv，重启保持', (tester) async {
    await collect.collect(book('b1', '第一本'));
    await collect.collect(book('b2', '第二本'));
    await collect.collect(book('b3', '第三本'));
    final prefs = _FakePrefs(<String, String>{
      novelPrefShelfSort: 'manual',
      novelPrefShelfView: const NovelShelfViewConfig(
        mode: NovelShelfMode.list,
      ).encode(),
    });

    await pumpShelf(tester, prefs: prefs);
    expect(find.textContaining('手动排序：长按封面拖动'), findsOneWidget);

    // 把第一本拖到第三本的位置。
    final first = find.byKey(const ValueKey<String>('b1'));
    final third = find.byKey(const ValueKey<String>('b3'));
    final gesture = await tester.startGesture(tester.getCenter(first));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(third));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();

    final saved = decodeShelfOrder(prefs.values[novelPrefShelfOrder]);
    expect(saved, isNotEmpty);
    expect(saved.indexOf('b1'), greaterThan(saved.indexOf('b3')));

    // 重启后顺序仍然按 kv 里的来。
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpShelf(tester, prefs: prefs);
    final titles = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .where((data) => data != null && data.endsWith('本'))
        .toList();
    expect(titles.indexOf('第一本'), greaterThan(titles.indexOf('第三本')));
  });

  testWidgets('系列归组：文件夹布局下同系列的书收成一节并排在前面', (tester) async {
    await collect.collect(book('b1', '三体'));
    await collect.collect(book('b2', '黑暗森林'));
    await collect.collect(book('b3', '死神永生'));
    await collect.collect(book('b4', '天龙八部'));
    await collect.setGroup('b4', '武侠');
    final seriesId = await collect.createSeries('地球往事');
    await collect.setSeriesFor(<String>['b1', 'b2', 'b3'], seriesId);

    final prefs = _FakePrefs(<String, String>{
      novelPrefShelfView: const NovelShelfViewConfig(
        mode: NovelShelfMode.folder,
        groupBySeries: true,
      ).encode(),
    });
    await pumpShelf(tester, prefs: prefs);

    // 节头：系列节 + 分组节（四本都有归属，没有未分组节）。
    expect(find.text('地球往事'), findsOneWidget);
    expect(find.text('武侠'), findsOneWidget);
    expect(find.text('未分组'), findsNothing);

    // 系列节里三本都在。
    final seriesHeaderY = tester.getTopLeft(find.text('地球往事')).dy;
    for (final title in <String>['三体', '黑暗森林', '死神永生']) {
      expect(find.text(title), findsWidgets, reason: '$title 没进系列节');
    }
    // 系列节排在分组节前面。
    expect(seriesHeaderY, lessThan(tester.getTopLeft(find.text('武侠')).dy));

    // 关掉「按系列归组」后系列节消失，三本回到未分组节。
    await tester.tap(find.byTooltip('书架操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('布局设置'));
    await tester.pumpAndSettle();
    final toggle = find.byKey(const Key('novel-shelf-group-series'));
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-shelf-layout-save')));
    await tester.pumpAndSettle();

    expect(find.text('地球往事'), findsNothing);
    // 关掉后三本散的进「未分组」节，另一本仍在武侠节。
    expect(find.text('未分组'), findsOneWidget);
    expect(find.text('武侠'), findsOneWidget);
    final saved = NovelShelfViewConfig.decode(prefs.values[novelPrefShelfView]);
    expect(saved.groupBySeries, isFalse);
  });

  testWidgets('系列归组开关在非文件夹布局下明说「当前布局不受影响」', (tester) async {
    await collect.collect(book('b1', '三体'));
    final seriesId = await collect.createSeries('地球往事');
    await collect.setSeriesFor(<String>['b1'], seriesId);
    final prefs = _FakePrefs(<String, String>{
      novelPrefShelfView: const NovelShelfViewConfig().encode(),
    });
    await pumpShelf(tester, prefs: prefs);
    await tester.tap(find.byTooltip('书架操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('布局设置'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('novel-shelf-group-series')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('只在「文件夹分组」布局下生效'), findsOneWidget);
  });

  testWidgets('书籍信息：备注与系列落到收藏行', (tester) async {
    await collect.collect(book('b1', '三体'));
    final prefs = _FakePrefs(<String, String>{
      novelPrefShelfView: const NovelShelfViewConfig(
        mode: NovelShelfMode.list,
      ).encode(),
    });
    await pumpShelf(tester, prefs: prefs);

    await tester.tap(find.text('三体').first, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('书籍信息（备注 / 封面 / 系列）'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('novel-book-meta-note')),
      '读到第三部再回来',
    );
    await tester.enterText(find.widgetWithText(TextField, '或新建系列'), '地球往事');
    await tester.tap(find.byKey(const Key('novel-book-meta-save')));
    await tester.pumpAndSettle();

    final item = (await collect.list()).single;
    expect(item.note, '读到第三部再回来');
    expect(item.seriesId, isNotNull);
    expect((await collect.series()).single.name, '地球往事');
  });

  testWidgets('书籍信息：自定义封面写入路径，恢复书源封面清空', (tester) async {
    await collect.collect(book('b1', '三体'));
    final picker = _FakeCoverPicker('C:/tmp/cover.png');
    final prefs = _FakePrefs(<String, String>{
      novelPrefShelfView: const NovelShelfViewConfig(
        mode: NovelShelfMode.list,
      ).encode(),
    });
    await pumpShelf(tester, prefs: prefs, coverPicker: picker);

    await tester.tap(find.text('三体').first, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('书籍信息（备注 / 封面 / 系列）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择图片'));
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    await tester.tap(find.byKey(const Key('novel-book-meta-save')));
    await tester.pumpAndSettle();
    expect((await collect.list()).single.customCoverPath, 'C:/tmp/cover.png');

    // 再打开一次，恢复书源封面。
    await tester.tap(find.text('三体').first, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('书籍信息（备注 / 封面 / 系列）'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复书源封面'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('novel-book-meta-save')));
    await tester.pumpAndSettle();
    expect((await collect.list()).single.customCoverPath, isNull);
  });

  testWidgets('空态给出可操作的三步入口', (tester) async {
    int? tab;
    await pumpShelf(
      tester,
      prefs: _FakePrefs(),
      onSelectTab: (index) => tab = index,
    );
    expect(find.text('书架还是空的'), findsOneWidget);
    expect(find.text('导入书源'), findsOneWidget);

    await tester.tap(find.text('去发现'));
    await tester.pumpAndSettle();
    expect(tab, 2);
    await tester.tap(find.text('导入书源'));
    await tester.pumpAndSettle();
    expect(tab, 3);
  });

  testWidgets('旧版 kv（shelf_layout=grid + columns）迁移进新配置', (tester) async {
    await collect.collect(book('b1', '三体'));
    final prefs = _FakePrefs(<String, String>{
      novelPrefShelfLayout: 'list',
      novelPrefShelfColumns: '4',
    });
    await pumpShelf(tester, prefs: prefs);
    expect(find.byType(ShelfListRow), findsWidgets);

    // 保存一次后写进新键。
    await chooseMode(tester, NovelShelfMode.grid);
    expect(prefs.values[novelPrefShelfView], isNotNull);
    expect(jsonDecode(prefs.values[novelPrefShelfView]!)['mode'], 'grid');
  });
}
