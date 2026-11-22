// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/ 文件头同款说明。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/data/fixture_comic_data_source.dart';
import 'package:mimao/comic/download.dart' show ComicDownloadStatus;
import 'package:mimao/comic/download_api.dart';
import 'package:mimao/comic/library_api.dart';
import 'package:mimao/comic/pages/comic_detail_page.dart';
import 'package:mimao/comic/pages/comic_home_page.dart';
import 'package:mimao/comic/pages/comic_local_page.dart';

/// 详情页 fixture（星舟漫游 5 章）。
const FixtureComicDataSource fixture = FixtureComicDataSource();

Widget _app(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF7C6BFF),
  ),
  home: home,
);

/// 小屏 390×844：任何 render overflow 都会作为异常让测试失败。
void _usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 可变下载 API：tasks 可直接改，改完调用 [notify] 触发页面重读。
class FakeComicDownloadApi with ChangeNotifier implements ComicDownloadApi {
  List<ComicChapterDownload> tasks = const <ComicChapterDownload>[];

  int downloadChapterCalls = 0;
  int downloadAllCalls = 0;
  int cancelCalls = 0;
  ComicChapter? lastChapter;
  final List<String> canceledTaskIds = <String>[];

  @override
  Listenable get changes => this;

  void notify() => notifyListeners();

  @override
  Future<List<ComicChapterDownload>> tasksFor(ComicSummary item) async => tasks;

  @override
  Future<void> downloadChapter(
    ComicSummary item,
    ComicDetail detail,
    ComicChapter chapter,
  ) async {
    downloadChapterCalls++;
    lastChapter = chapter;
  }

  @override
  Future<void> downloadAll(ComicSummary item, ComicDetail detail) async {
    downloadAllCalls++;
  }

  @override
  Future<void> cancel(String taskId) async {
    cancelCalls++;
    canceledTaskIds.add(taskId);
  }
}

/// 本地数据假实现：同时满足 [ComicLocalApi] 与 [ComicLibraryApi]，
/// 与生产 `comic_entry.dart` 把同一个 ComicLibraryApiImpl 注入两处保持一致
/// （主页本地卡片的计数实际取自 library.local()）。
class FakeLocalApi implements ComicLocalApi, ComicLibraryApi {
  FakeLocalApi(this._entries);

  final List<ComicLibraryEntry> _entries;
  final List<ComicSummary> removed = <ComicSummary>[];

  @override
  Future<List<ComicLibraryEntry>> local() async =>
      List<ComicLibraryEntry>.unmodifiable(_entries);

  @override
  Future<ComicDetail> detail(ComicSummary item) async => ComicDetail(
    title: item.title,
    coverUrl: item.coverUrl,
    detailUrl: item.detailUrl,
    description: '',
    sourceName: item.sourceName,
  );

  @override
  Future<void> remove(ComicSummary item) async {
    removed.add(item);
    _entries.removeWhere((entry) => entry.id == item.id);
  }

  @override
  Future<List<ComicLibraryEntry>> collected() async =>
      const <ComicLibraryEntry>[];

  @override
  Future<List<ComicLibraryEntry>> recent({int limit = 20}) async =>
      const <ComicLibraryEntry>[];

  @override
  Future<void> removeHistoryEntry({
    required String id,
    required String sourceName,
  }) async {}

  @override
  Future<void> clearHistory() async {}
}

ComicLibraryEntry _entry(String id, String title, String subtitle) =>
    ComicLibraryEntry(
      id: id,
      sourceName: ComicLibraryEntry.localSource,
      title: title,
      subtitle: subtitle,
    );

void main() {
  group('主页本地卡片', () {
    testWidgets('两个本地条目显示「本地 / 已保存 2 部」且点击回调', (tester) async {
      _usePhoneSize(tester);
      final local = FakeLocalApi(<ComicLibraryEntry>[
        _entry('l1', '本地甲', '第 1 话 · 看到第 5 页'),
        _entry('l2', '本地乙', '全 12 话'),
      ]);
      var opened = 0;
      await tester.pumpWidget(
        _app(
          ComicHomePage(
            dataSource: fixture,
            library: local,
            localApi: local,
            onOpenLocalLibrary: () => opened++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final card = find.byKey(const Key('comic-home-local-card'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('本地')),
        findsOneWidget,
      );
      // 2026-11-22 排版拍板：本地卡改卡头计数徽标（纯数字）+ 纯封面横排，
      // 「已保存 N 部 · 点击管理」副标题行移除。
      expect(
        find.descendant(of: card, matching: find.text('2')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('comic-home-local-card-tap')));
      await tester.pump();
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('空列表显示引导文案', (tester) async {
      _usePhoneSize(tester);
      final local = FakeLocalApi(const <ComicLibraryEntry>[]);
      await tester.pumpWidget(
        _app(
          ComicHomePage(dataSource: fixture, library: local, localApi: local),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('comic-home-local-card')), findsOneWidget);
      expect(find.text('下载漫画后会出现在这里'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('localApi 为 null 时不渲染本地卡片', (tester) async {
      _usePhoneSize(tester);
      final library = FakeLocalApi(<ComicLibraryEntry>[
        _entry('l1', '本地甲', '第 1 话'),
      ]);
      await tester.pumpWidget(
        _app(ComicHomePage(dataSource: fixture, library: library)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('comic-home-local-card')), findsNothing);
      expect(find.text('已保存 1 部 · 点击管理'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('本地漫画管理页', () {
    testWidgets('两行渲染标题/副标题，点行回传条目', (tester) async {
      _usePhoneSize(tester);
      final local = FakeLocalApi(<ComicLibraryEntry>[
        _entry('l1', '本地甲', '第 1 话 · 看到第 5 页'),
        _entry('l2', '本地乙', '全 12 话'),
      ]);
      String? openedId;
      await tester.pumpWidget(
        _app(
          ComicLocalPage(
            local: local,
            onOpenDetail: (item) async => openedId = item.id,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('local-entry-l1')), findsOneWidget);
      expect(find.byKey(const Key('local-entry-l2')), findsOneWidget);
      expect(find.text('本地甲'), findsOneWidget);
      expect(find.text('第 1 话 · 看到第 5 页'), findsOneWidget);
      expect(find.text('本地乙'), findsOneWidget);
      expect(find.text('全 12 话'), findsOneWidget);

      await tester.tap(find.byKey(const Key('local-entry-l1')));
      await tester.pumpAndSettle();
      expect(openedId, 'l1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('删除确认框：取消保留，确认删除该行', (tester) async {
      _usePhoneSize(tester);
      final local = FakeLocalApi(<ComicLibraryEntry>[
        _entry('l1', '本地甲', '第 1 话'),
        _entry('l2', '本地乙', '全 12 话'),
      ]);
      await tester.pumpWidget(_app(ComicLocalPage(local: local)));
      await tester.pumpAndSettle();

      // 取消：条目保留，remove 未调用。
      await tester.tap(find.byKey(const Key('local-delete-l2')));
      await tester.pumpAndSettle();
      expect(find.text('删除本地漫画？'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(local.removed, isEmpty);
      expect(find.byKey(const Key('local-entry-l2')), findsOneWidget);

      // 确认：remove 收到正确条目，该行消失。
      await tester.tap(find.byKey(const Key('local-delete-l2')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(local.removed.length, 1);
      expect(local.removed.single.id, 'l2');
      expect(local.removed.single.title, '本地乙');
      expect(find.byKey(const Key('local-entry-l2')), findsNothing);
      expect(find.byKey(const Key('local-entry-l1')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('空列表显示「还没有本地漫画」', (tester) async {
      _usePhoneSize(tester);
      final local = FakeLocalApi(const <ComicLibraryEntry>[]);
      await tester.pumpWidget(_app(ComicLocalPage(local: local)));
      await tester.pumpAndSettle();
      expect(find.text('还没有本地漫画'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('详情页下载按钮', () {
    testWidgets('无任务时每章有下载按钮，单章与整本点击各调用一次', (tester) async {
      _usePhoneSize(tester);
      final api = FakeComicDownloadApi();
      await tester.pumpWidget(
        _app(
          ComicDetailPage(
            dataSource: fixture,
            summary: FixtureComicDataSource.xingzhou,
            downloads: api,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('download-all-button')), findsOneWidget);
      for (var n = 1; n <= 5; n++) {
        expect(
          find.byKey(ValueKey<String>('download-chapter-$n')),
          findsOneWidget,
        );
      }

      await tester.tap(find.byKey(const Key('download-chapter-2')));
      await tester.pumpAndSettle();
      expect(api.downloadChapterCalls, 1);
      expect(api.lastChapter, isNotNull);
      expect(api.lastChapter!.number, 2);
      expect(api.lastChapter!.title, '星图');

      await tester.tap(find.byKey(const Key('download-all-button')));
      await tester.pumpAndSettle();
      expect(api.downloadAllCalls, 1);
      expect(tester.takeException(), isNull);
    });
  });

  group('详情页下载状态', () {
    testWidgets('四种状态分别渲染对应 key，notify 后重建', (tester) async {
      _usePhoneSize(tester);
      final chapters =
          FixtureComicDataSource.defaultDetails['xingzhou']!.chapters;
      final api = FakeComicDownloadApi()
        ..tasks = <ComicChapterDownload>[
          ComicChapterDownload(
            taskId: 't1',
            chapterUrl: chapters[0].url,
            status: ComicDownloadStatus.pending,
          ),
          // total=0 → 不确定进度圈，避免 pumpAndSettle 卡在无限动画。
          ComicChapterDownload(
            taskId: 't2',
            chapterUrl: chapters[1].url,
            status: ComicDownloadStatus.running,
            received: 3,
          ),
          ComicChapterDownload(
            taskId: 't3',
            chapterUrl: chapters[2].url,
            status: ComicDownloadStatus.done,
            received: 12,
            total: 12,
          ),
          ComicChapterDownload(
            taskId: 't4',
            chapterUrl: chapters[3].url,
            status: ComicDownloadStatus.failed,
            error: '网络错误',
          ),
        ];

      await tester.pumpWidget(
        _app(
          ComicDetailPage(
            dataSource: fixture,
            summary: FixtureComicDataSource.xingzhou,
            downloads: api,
          ),
        ),
      );
      // running 态有不确定进度圈：用固定 pump，不用 pumpAndSettle。
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('download-pending-1')), findsOneWidget);
      expect(find.byKey(const Key('download-running-2')), findsOneWidget);
      expect(find.byKey(const Key('download-done-3')), findsOneWidget);
      expect(find.byKey(const Key('download-retry-4')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // 变更 fake 数据并通知：页面应重读任务并刷新状态图标。
      api.tasks = <ComicChapterDownload>[
        ComicChapterDownload(
          taskId: 't1',
          chapterUrl: chapters[0].url,
          status: ComicDownloadStatus.done,
          received: 10,
          total: 10,
        ),
      ];
      api.notify();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('download-done-1')), findsOneWidget);
      expect(find.byKey(const Key('download-pending-1')), findsNothing);
      expect(find.byKey(const Key('download-running-2')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点击等待/进行中指示图标调用 cancel(taskId)', (tester) async {
      _usePhoneSize(tester);
      final chapters =
          FixtureComicDataSource.defaultDetails['xingzhou']!.chapters;
      final api = FakeComicDownloadApi()
        ..tasks = <ComicChapterDownload>[
          ComicChapterDownload(
            taskId: 'pending-1',
            chapterUrl: chapters[0].url,
            status: ComicDownloadStatus.pending,
          ),
          ComicChapterDownload(
            taskId: 'running-2',
            chapterUrl: chapters[1].url,
            status: ComicDownloadStatus.running,
            received: 1,
          ),
        ];

      await tester.pumpWidget(
        _app(
          ComicDetailPage(
            dataSource: fixture,
            summary: FixtureComicDataSource.xingzhou,
            downloads: api,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // running 指示图标带不确定进度圈，全程用固定 pump 避免 settle 超时。
      await tester.tap(find.byKey(const Key('download-pending-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(api.cancelCalls, 1);
      expect(api.canceledTaskIds, contains('pending-1'));

      // running 指示图标为 InkWell、带不确定进度圈：用固定 pump。
      await tester.tap(find.byKey(const Key('download-running-2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(api.cancelCalls, 2);
      expect(api.canceledTaskIds, contains('running-2'));
      expect(tester.takeException(), isNull);
    });
  });

  group('本地/未接线详情页不显示下载入口', () {
    testWidgets('isLocal 为 true 时不显示下载按钮与状态 key', (tester) async {
      _usePhoneSize(tester);
      final api = FakeComicDownloadApi();
      await tester.pumpWidget(
        _app(
          ComicDetailPage(
            dataSource: fixture,
            summary: FixtureComicDataSource.xingzhou,
            downloads: api,
            isLocal: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('download-all-button')), findsNothing);
      expect(find.byKey(const Key('download-chapter-1')), findsNothing);
      for (final key in <String>[
        'download-pending-1',
        'download-running-1',
        'download-done-1',
        'download-retry-1',
      ]) {
        expect(find.byKey(Key(key)), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('downloads 为 null 时不显示下载按钮与状态 key', (tester) async {
      _usePhoneSize(tester);
      await tester.pumpWidget(
        _app(
          const ComicDetailPage(
            dataSource: fixture,
            summary: FixtureComicDataSource.xingzhou,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('download-all-button')), findsNothing);
      expect(find.byKey(const Key('download-chapter-1')), findsNothing);
      for (final key in <String>[
        'download-pending-1',
        'download-running-1',
        'download-done-1',
        'download-retry-1',
      ]) {
        expect(find.byKey(Key(key)), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  });
}
