// 统计页与阅读记录时间轴的渲染/交互测试：真实服务 + 内存库，全离线。
// 关注三件事：概览数字读得到、时间轴按天分组、章节维度能切书。
// ignore_for_file: deprecated_member_use — 与其他 novel 测试同款。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/history_service.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/pages/novel_history_page.dart';
import 'package:mimao/novel/pages/novel_stats_page.dart';
import 'package:mimao/novel/stats_service.dart';

void main() {
  late AppDb appDb;
  late NovelDb novelDb;
  late LibraryRepository library;
  late NovelHistoryService history;
  late NovelStatsService stats;

  setUp(() {
    appDb = AppDb.forTesting(NativeDatabase.memory());
    novelDb = NovelDb.forTesting(NativeDatabase.memory());
    library = LibraryRepository(appDb);
    history = NovelHistoryService(novelDb, library);
    stats = NovelStatsService(novelDb);
  });

  tearDown(() async {
    await appDb.close();
    await novelDb.close();
  });

  NovelSummary book(String id, String title) =>
      NovelSummary(id: id, title: title, author: '作者');

  Widget wrap(Widget page) {
    return MaterialApp(
      theme: buildMimaoTheme(
        seedColor: const Color(0xFF7C6BFF),
        brightness: Brightness.light,
      ),
      home: page,
    );
  }

  /// 统计页是长列表：默认 800×600 的测试视口会让热力图/章节维度落到
  /// ListView 的懒构建区外（`find.text` 找不到未构建的 widget）。
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> read({
    required String bookId,
    required String title,
    required int chapterIndex,
    required int seconds,
    required DateTime at,
    String chapterName = '',
  }) => stats.addReadingTime(
    Duration(seconds: seconds),
    at: at,
    target: NovelReadTarget(
      bookId: bookId,
      bookTitle: title,
      chapterIndex: chapterIndex,
      chapterName: chapterName,
    ),
  );

  testWidgets('统计页：概览/柱状图/热力图/章节维度都渲染出数据', (tester) async {
    useTallViewport(tester);
    final now = DateTime.now();
    await read(
      bookId: 'b1',
      title: '三体',
      chapterIndex: 1,
      chapterName: '科学边界',
      seconds: 600,
      at: now.subtract(const Duration(hours: 2)),
    );
    await read(
      bookId: 'b1',
      title: '三体',
      chapterIndex: 2,
      chapterName: '台球',
      seconds: 300,
      at: now.subtract(const Duration(hours: 1)),
    );
    await read(
      bookId: 'b2',
      title: '球状闪电',
      chapterIndex: 1,
      seconds: 120,
      at: now.subtract(const Duration(days: 1)),
    );

    await tester.pumpWidget(wrap(NovelStatsPage(stats: stats)));
    await tester.pumpAndSettle();

    // 概览：累计时长/本数/日均/最长连续四卡。
    expect(find.text('概览'), findsOneWidget);
    expect(find.text('累计时长'), findsOneWidget);
    expect(find.text('累计本数'), findsOneWidget);
    expect(find.text('最长连续'), findsOneWidget);
    expect(find.text('2'), findsWidgets); // 两本书 / 最长连续 2 天

    // 柱状图与热力图是 CustomPaint（不引入图表库）。
    expect(find.text('阅读时长'), findsOneWidget);
    expect(find.text('阅读热力图'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('近 7 天'), findsOneWidget);

    // 章节维度：默认选时长最长的书，列出两章。
    expect(find.text('章节维度'), findsOneWidget);
    expect(find.textContaining('第 1 章'), findsWidgets);
    expect(find.textContaining('第 2 章'), findsWidgets);
    expect(find.textContaining('科学边界'), findsWidgets);
  });

  testWidgets('统计页：切到近 30 天不报错，切书后章节跟着变', (tester) async {
    useTallViewport(tester);
    final now = DateTime.now();
    await read(
      bookId: 'b1',
      title: '三体',
      chapterIndex: 1,
      seconds: 600,
      at: now,
    );
    await read(
      bookId: 'b2',
      title: '球状闪电',
      chapterIndex: 5,
      chapterName: '夜航',
      seconds: 60,
      at: now,
    );

    await tester.pumpWidget(wrap(NovelStatsPage(stats: stats)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('近 30 天'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 切到球状闪电：章节维度变成第 5 章。
    await tester.tap(find.text('三体').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('球状闪电').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('第 5 章'), findsWidgets);
  });

  testWidgets('统计页：没有数据时是空态（不是空白图）', (tester) async {
    await tester.pumpWidget(wrap(NovelStatsPage(stats: stats)));
    await tester.pumpAndSettle();
    expect(find.text('还没有阅读时长记录'), findsOneWidget);
    expect(find.textContaining('读几页再回来看'), findsOneWidget);
  });

  testWidgets('统计页：没注入统计服务时说明能力边界，不伪造数字', (tester) async {
    await tester.pumpWidget(wrap(const NovelStatsPage()));
    await tester.pumpAndSettle();
    expect(find.text('还没有阅读时长记录'), findsOneWidget);
  });

  testWidgets('阅读记录：时间轴按天分组，显示书/时长/章', (tester) async {
    final now = DateTime.now();
    await read(
      bookId: 'b1',
      title: '三体',
      chapterIndex: 7,
      chapterName: '红岸之三',
      seconds: 600,
      at: now,
    );
    await read(
      bookId: 'b2',
      title: '球状闪电',
      chapterIndex: 2,
      seconds: 300,
      at: now.subtract(const Duration(days: 1)),
    );
    await history.saveProgress(book('b1', '三体'), 7, 400);

    await tester.pumpWidget(
      wrap(NovelHistoryPage(history: history, stats: stats)),
    );
    await tester.pumpAndSettle();

    expect(find.text('今天'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    expect(find.text('三体'), findsWidgets);
    expect(find.text('球状闪电'), findsWidgets);
    expect(find.textContaining('第 7 章'), findsWidgets);
    expect(find.textContaining('红岸之三'), findsWidgets);
    // 章名不带章号时，前缀只出现一次。
    expect(find.text('第 7 章 · 红岸之三'), findsOneWidget);
    expect(find.textContaining('第 7 章 · 第 7 章'), findsNothing);
  });

  testWidgets('章名本身以「第 N 章」开头时不重复拼前缀', (tester) async {
    useTallViewport(tester);
    final now = DateTime.now();
    // 书源目录原文就是「第 3 章」，旧实现会渲染成「第 3 章 · 第 3 章」。
    await read(
      bookId: 'b1',
      title: '诡秘之主',
      chapterIndex: 3,
      chapterName: '第 3 章',
      seconds: 600,
      at: now,
    );
    // 中文数字章名同样不该被拼成「第 5 章 · 第五章 夜航」。
    await read(
      bookId: 'b2',
      title: '长夜余火',
      chapterIndex: 5,
      chapterName: '第五章 夜航',
      seconds: 300,
      at: now,
    );

    await tester.pumpWidget(wrap(NovelStatsPage(stats: stats)));
    await tester.pumpAndSettle();
    // 章节维度与时间轴都不该出现重复前缀。
    expect(find.textContaining('第 3 章 · 第 3 章'), findsNothing);
    expect(find.textContaining('第 5 章 · 第五章'), findsNothing);
    expect(find.text('第 3 章'), findsWidgets);

    await tester.pumpWidget(
      wrap(NovelHistoryPage(history: history, stats: stats)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('第 3 章 · 第 3 章'), findsNothing);
    expect(find.textContaining('第 5 章 · 第五章'), findsNothing);
    expect(find.text('第五章 夜航'), findsWidgets);
  });

  testWidgets('阅读记录：时间轴空态与书目空态都给出下一步', (tester) async {
    await tester.pumpWidget(
      wrap(NovelHistoryPage(history: history, stats: stats)),
    );
    await tester.pumpAndSettle();
    expect(find.text('还没有阅读时长记录'), findsOneWidget);

    await tester.tap(find.text('书目'));
    await tester.pumpAndSettle();
    expect(find.text('还没有阅读记录'), findsOneWidget);
  });
}
