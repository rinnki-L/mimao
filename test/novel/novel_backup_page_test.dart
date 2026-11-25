// 备份中心：空态、配置回填、恢复预览（计数 + 冲突选择）、撤销入口。
// 服务走真实实现，远端用 fake client，文件与凭据用内存实现——不碰插件。
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/novel/backup/backup_document.dart';
import 'package:mimao/novel/backup/backup_file_store.dart';
import 'package:mimao/novel/backup/backup_service.dart';
import 'package:mimao/novel/backup/webdav_remote.dart';
import 'package:mimao/novel/collect_service.dart';
import 'package:mimao/novel/history_service.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/pages/novel_backup_page.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/stats_service.dart';

void main() {
  /// 有 `_busy` 的转圈动画时 `pumpAndSettle` 永远等不到静止（`LESSON.md`
  /// 「repeat() 无限动画让测试挂死」同款）。这里一律用有界 pump。
  Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  late AppDb appDb;
  late NovelDb db;
  late LibraryRepository library;
  late NovelCollectService collect;
  late NovelHistoryService history;
  late NovelStatsService prefs;
  late _FakeClient client;
  late NovelWebDavBackupService service;

  const config = NovelWebDavConfig(
    url: 'https://dav.example.com/mimao/novel-backup.json',
    user: 'u',
    password: 'p',
  );

  setUp(() {
    appDb = AppDb.forTesting(NativeDatabase.memory());
    db = NovelDb.forTesting(NativeDatabase.memory());
    library = LibraryRepository(appDb);
    collect = NovelCollectService(db, library);
    history = NovelHistoryService(db, library);
    prefs = NovelStatsService(db);
    client = _FakeClient();
    service = NovelWebDavBackupService(
      client: client,
      db: db,
      library: library,
      prefs: prefs,
      credentials: NovelMemoryCredentialStore(),
      files: NovelMemoryBackupFileStore(),
      deviceId: 'device-a',
    );
  });

  tearDown(() async {
    await appDb.close();
    await db.close();
  });

  Widget wrap(Widget child) => MaterialApp(home: child);

  Widget page() => wrap(
    NovelBackupPage(
      service: service,
      prefs: prefs,
      credentials: NovelMemoryCredentialStore(),
    ),
  );

  testWidgets('未配置：给地址输入与"还没有可撤销的恢复"', (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(page());
    await settle(tester);

    expect(find.byKey(const Key('novel-backup-url')), findsOneWidget);
    expect(find.byKey(const Key('novel-backup-save')), findsOneWidget);
    expect(find.byKey(const Key('novel-backup-run')), findsOneWidget);
    expect(find.textContaining('还没有可撤销的恢复'), findsOneWidget);
    expect(find.textContaining('还没有备份过'), findsOneWidget);
    // 服务没启用进度同步时按钮置灰并说明原因。
    expect(find.textContaining('服务未启用'), findsOneWidget);
  });

  testWidgets('已配置：地址回填 + 恢复预览展示计数与冲突', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await prefs.write(novelWebDavUrlKey, config.url);
    await prefs.write(novelWebDavUserKey, 'u');
    await collect.collect(
      const NovelSummary(id: 'b1', title: '三体', coverUrl: ''),
    );
    await collect.setGroup('b1', '待读');
    client.seed(
      config.url,
      NovelBackupDocument(
        collects: <NovelBackupCollect>[
          NovelBackupCollect(
            book: const NovelSummary(id: 'b1', title: '三体', coverUrl: ''),
            groupName: '科幻',
          ),
          NovelBackupCollect(
            book: const NovelSummary(id: 'b2', title: '球状闪电', coverUrl: ''),
          ),
        ],
        histories: const <NovelBackupHistory>[],
        searchKeywords: const <String>[],
        sources: const <NovelBookSource>[],
        prefs: const <String, String>{},
        exportedAt: DateTime.utc(2026, 11, 20),
        deviceId: 'device-b',
        deviceName: '另一台机器',
      ).encode(),
    );

    await tester.pumpWidget(page());
    await settle(tester);

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('novel-backup-url')))
          .controller
          ?.text,
      config.url,
    );

    await tester.tap(find.byKey(const Key('novel-backup-restore')));
    await settle(tester);

    expect(find.text('恢复预览'), findsOneWidget);
    expect(find.textContaining('另一台机器'), findsWidgets);
    expect(find.text('新增 1'), findsOneWidget);
    expect(find.text('冲突 1'), findsOneWidget);
    expect(find.textContaining('分组不同'), findsOneWidget);
    expect(find.byKey(const Key('novel-restore-confirm')), findsOneWidget);

    // 取消不落库。
    await tester.tap(find.byKey(const Key('novel-restore-cancel')));
    await settle(tester);
    expect(
      (await collect.list()).map((item) => item.ref.id),
      isNot(contains('b2')),
    );
  });

  testWidgets('恢复预览确认后落库，并出现撤销入口', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await prefs.write(novelWebDavUrlKey, config.url);
    client.seed(
      config.url,
      NovelBackupDocument(
        collects: <NovelBackupCollect>[
          NovelBackupCollect(
            book: const NovelSummary(id: 'b2', title: '球状闪电', coverUrl: ''),
          ),
        ],
        histories: const <NovelBackupHistory>[],
        searchKeywords: const <String>[],
        sources: const <NovelBookSource>[],
        prefs: const <String, String>{},
        exportedAt: DateTime.utc(2026, 11, 20),
        deviceId: 'device-b',
        deviceName: '另一台机器',
      ).encode(),
    );

    await tester.pumpWidget(page());
    await settle(tester);

    await tester.tap(find.byKey(const Key('novel-backup-restore')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('novel-restore-confirm')));
    await settle(tester);

    expect(find.textContaining('恢复完成'), findsOneWidget);
    expect(find.textContaining('处改动'), findsOneWidget);
    final undo = tester.widget<OutlinedButton>(
      find.byKey(const Key('novel-backup-undo')),
    );
    expect(undo.onPressed, isNotNull);
    expect((await collect.list()).single.ref.id, 'b2');
  });
}

class _FakeClient implements NovelWebDavClient {
  final Map<String, String> _bodies = <String, String>{};

  void seed(String url, String body) => _bodies[url] = body;

  @override
  Future<void> put(String url, String body, NovelWebDavConfig config) async {
    _bodies[url] = body;
  }

  @override
  Future<String> get(String url, NovelWebDavConfig config) async {
    final body = _bodies[url];
    if (body == null) {
      throw const NovelWebDavException(NovelWebDavErrorKind.notFound);
    }
    return body;
  }
}
