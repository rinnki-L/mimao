// WebDAV 备份编排：合并上传、恢复预览、执行、撤销、加密、凭据迁移。
// 全程离线（fake client + 内存文件/凭据存储）。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/novel/backup/backup_crypto.dart';
import 'package:mimao/novel/backup/backup_document.dart';
import 'package:mimao/novel/backup/backup_file_store.dart';
import 'package:mimao/novel/backup/backup_service.dart';
import 'package:mimao/novel/backup/backup_settings.dart';
import 'package:mimao/novel/backup/credential_store.dart';
import 'package:mimao/novel/backup/webdav_remote.dart';
import 'package:mimao/novel/collect_service.dart';
import 'package:mimao/novel/history_service.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/stats_service.dart';

void main() {
  late AppDb appDb;
  late NovelDb db;
  late LibraryRepository library;
  late NovelCollectService collect;
  late NovelHistoryService history;
  late NovelStatsService prefs;
  late _FakeClient client;
  late NovelMemoryBackupFileStore files;
  late NovelMemoryCredentialStore credentials;
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
    files = NovelMemoryBackupFileStore();
    credentials = NovelMemoryCredentialStore();
    service = NovelWebDavBackupService(
      client: client,
      db: db,
      library: library,
      prefs: prefs,
      credentials: credentials,
      files: files,
      deviceId: 'device-a',
    );
  });

  tearDown(() async {
    await appDb.close();
    await db.close();
  });

  NovelSummary book(String id, String title) =>
      NovelSummary(id: id, title: title, coverUrl: '');

  group('上传', () {
    test('采集本机数据上传成 v2 文档（带 deviceId），并记下上次备份时间', () async {
      await collect.collect(book('b1', '三体'));
      await collect.setGroup('b1', '科幻');
      await history.saveProgress(book('b1', '三体'), 12, 400);

      final run = await service.backup(config);

      expect(run.collects, 1);
      expect(run.histories, 1);
      expect(run.mergedWithRemote, isFalse);
      final uploaded = NovelBackupDocument.decode(client.bodyOf(config.url)!);
      expect(uploaded.deviceId, 'device-a');
      expect(uploaded.collects.single.groupName, '科幻');
      expect(uploaded.progress.single.chapterIndex, 12);
      expect(
        DateTime.tryParse(await prefs.read(novelWebdavLastBackupAtKey) ?? ''),
        isNotNull,
      );
    });

    test('上传是合并写：另一台设备的独有进度不会被抹掉', () async {
      await collect.collect(book('b1', '三体'));
      await history.saveProgress(book('b1', '三体'), 5, 400);

      client.seed(
        config.url,
        NovelBackupDocument(
          collects: <NovelBackupCollect>[
            NovelBackupCollect(book: book('b2', '球状闪电')),
          ],
          histories: <NovelBackupHistory>[
            NovelBackupHistory(book: book('b1', '三体'), chapterIndex: 20),
          ],
          searchKeywords: const <String>[],
          sources: const <NovelBookSource>[],
          prefs: const <String, String>{},
          exportedAt: DateTime.utc(2026, 11, 20),
          deviceId: 'device-b',
          progress: <NovelBackupProgress>[
            NovelBackupProgress(bookId: 'b1', chapterIndex: 20),
          ],
          bookmarks: <NovelBackupBookmark>[
            NovelBackupBookmark(
              bookId: 'b2',
              chapterIndex: 3,
              createdAt: DateTime.utc(2026, 11, 1),
            ),
          ],
        ).encode(),
      );

      final run = await service.backup(config);

      expect(run.mergedWithRemote, isTrue);
      final uploaded = NovelBackupDocument.decode(client.bodyOf(config.url)!);
      expect(uploaded.progress.single.chapterIndex, 20);
      expect(uploaded.collects.map((item) => item.book.id), contains('b2'));
      expect(uploaded.bookmarks.single.bookId, 'b2');
      expect(client.bodyOf(config.backupUrl), isNotNull);
    });

    test('远端是加密包且没有密码：跳过合并并说明原因', () async {
      await collect.collect(book('b1', '三体'));
      client.seed(
        config.url,
        encryptNovelBackupText(
          NovelBackupDocument(
            collects: const <NovelBackupCollect>[],
            histories: const <NovelBackupHistory>[],
            searchKeywords: const <String>[],
            sources: const <NovelBookSource>[],
            prefs: const <String, String>{},
            exportedAt: DateTime.utc(2026, 11, 20),
            progress: <NovelBackupProgress>[
              NovelBackupProgress(bookId: 'b1', chapterIndex: 99),
            ],
          ).encode(),
          'secret',
          iterations: 500,
        ).encode(),
      );

      final run = await service.backup(config);

      expect(run.mergedWithRemote, isFalse);
      expect(run.mergeSkipReason, contains('需要密码'));
      final uploaded = NovelBackupDocument.decode(client.bodyOf(config.url)!);
      // 本机没读过这本书 → 进度段为空；远端那 99 章没有被并进来。
      expect(uploaded.progress, isEmpty);
    });

    test('带密码上传：落盘是加密包，且能解回', () async {
      await collect.collect(book('b1', '三体'));
      final run = await service.backup(config, password: 'hunter2');

      expect(run.encrypted, isTrue);
      final bundle = parseNovelBackupBundle(client.bodyOf(config.url)!);
      expect(bundle, isA<NovelBackupEncryptedBundle>());
      final doc = (bundle as NovelBackupEncryptedBundle).decrypt('hunter2');
      expect(doc.collects.single.book.id, 'b1');
    });
  });

  group('恢复', () {
    void seedRemote() {
      client.seed(
        config.url,
        NovelBackupDocument(
          collects: <NovelBackupCollect>[
            NovelBackupCollect(book: book('b1', '三体'), groupName: '科幻'),
            NovelBackupCollect(book: book('b2', '球状闪电')),
          ],
          histories: <NovelBackupHistory>[
            NovelBackupHistory(book: book('b1', '三体'), chapterIndex: 12),
          ],
          searchKeywords: const <String>['三体'],
          sources: const <NovelBookSource>[],
          prefs: const <String, String>{},
          exportedAt: DateTime.utc(2026, 11, 20),
          deviceId: 'device-b',
          deviceName: '另一台机器',
          progress: <NovelBackupProgress>[
            NovelBackupProgress(bookId: 'b1', chapterIndex: 12),
          ],
        ).encode(),
      );
    }

    test('预览给出新增/更新/冲突计数，且不落库', () async {
      await collect.collect(book('b1', '三体'));
      await collect.setGroup('b1', '待读');
      await history.saveProgress(book('b1', '三体'), 3, 400);
      seedRemote();

      final preview = await service.preview(config);

      expect(preview.deviceName, '另一台机器');
      expect(preview.sourceLabel, contains('另一台机器'));
      expect(preview.counts.added, 2); // b2 + 搜索词
      expect(preview.counts.updated, 1); // 进度 12 > 3
      expect(preview.counts.conflicts, 1); // 分组 待读 vs 科幻

      expect((await collect.list()).length, 1);
      expect((await history.latest('b1'))!.chapterIndex, 3);
    });

    test('执行计划后落库，冲突默认保本地', () async {
      await collect.collect(book('b1', '三体'));
      await collect.setGroup('b1', '待读');
      await history.saveProgress(book('b1', '三体'), 3, 400);
      seedRemote();
      final preview = await service.preview(config);

      final report = await service.apply(preview);

      expect(report.failed, 0);
      final rows = await collect.list();
      expect(rows.map((item) => item.ref.id), contains('b2'));
      expect((await history.latest('b1'))!.chapterIndex, 12);
      expect(rows.firstWhere((item) => item.ref.id == 'b1').groupName, '待读');
      expect(
        (await files.list()).where((name) => name.startsWith('pre-restore-')),
        hasLength(1),
      );
      expect(report.journalName, isNotNull);
    });

    test('用户选远端后冲突按选择落库', () async {
      await collect.collect(book('b1', '三体'));
      await collect.setGroup('b1', '待读');
      seedRemote();
      final preview = await service.preview(config);
      final conflict = preview.plan.conflicts.single;

      await service.apply(
        preview,
        useRemote: <String, bool>{conflict.id: true},
      );

      final rows = await collect.list();
      expect(rows.firstWhere((item) => item.ref.id == 'b1').groupName, '科幻');
    });

    test('撤销：精确回滚本次改动，恢复后新增的数据不动', () async {
      await collect.collect(book('b1', '三体'));
      await history.saveProgress(book('b1', '三体'), 3, 400);
      seedRemote();
      final preview = await service.preview(config);
      await service.apply(preview);
      expect((await history.latest('b1'))!.chapterIndex, 12);

      // 恢复之后用户又加了一本书、把进度改到 13。
      await collect.collect(book('b9', '三体 II'));
      await history.saveProgress(book('b1', '三体'), 13, 400);

      final undo = await service.undo();

      expect(undo.errors, isEmpty);
      expect(undo.restored, greaterThan(0));
      expect((await history.latest('b1'))!.chapterIndex, 13);
      expect((await collect.list()).map((item) => item.ref.id), contains('b9'));
      expect(await service.lastUndo(), isNull);
    });

    test('加密远端：密码错给可读错误，密码对能预览', () async {
      await collect.collect(book('b1', '三体'));
      client.seed(
        config.url,
        encryptNovelBackupText(
          NovelBackupDocument(
            collects: <NovelBackupCollect>[
              NovelBackupCollect(book: book('b2', '球状闪电')),
            ],
            histories: const <NovelBackupHistory>[],
            searchKeywords: const <String>[],
            sources: const <NovelBookSource>[],
            prefs: const <String, String>{},
            exportedAt: DateTime.utc(2026, 11, 20),
            deviceName: '另一台机器',
          ).encode(),
          'right',
          iterations: 500,
        ).encode(),
      );

      await expectLater(
        service.preview(config, password: 'wrong'),
        throwsA(isA<NovelBackupCryptoException>()),
      );

      final preview = await service.preview(config, password: 'right');
      expect(preview.encrypted, isTrue);
      expect(preview.counts.added, 1);
    });

    test('远端没有文件：给「路径不存在」而不是卡住', () async {
      await expectLater(
        service.preview(config),
        throwsA(
          isA<NovelWebDavException>().having(
            (error) => error.kind,
            'kind',
            NovelWebDavErrorKind.notFound,
          ),
        ),
      );
    });
  });

  group('连接与实际错误', () {
    test('测试连接：远端还没有文件也算连通', () async {
      final health = await service.testConnection(config);
      expect(health.ok, isTrue);
      expect(health.message, contains('还没有备份文件'));
    });

    test('401 翻成可读错误，带下一步', () async {
      client.failWith(
        config.url,
        const NovelWebDavException(
          NovelWebDavErrorKind.unauthorized,
          statusCode: 401,
        ),
      );
      final health = await service.testConnection(config);
      expect(health.ok, isFalse);
      expect(health.message, contains('账号或密码'));
      expect(health.hint, isNotEmpty);
    });
  });

  group('凭据', () {
    test('旧版明文密码迁进安全存储并清掉 kv', () async {
      await prefs.write(novelWebDavUrlKey, config.url);
      await prefs.write(novelWebDavUserKey, 'u');
      await prefs.write(novelWebDavPasswordKey, 'legacy-pass');

      final loaded = await readNovelWebDavConfig(
        prefs,
        credentials: credentials,
      );

      expect(loaded!.password, 'legacy-pass');
      expect(loaded.passwordSource, NovelPasswordSource.secure);
      expect(await prefs.read(novelWebDavPasswordKey), '');
      expect(
        await credentials.read(novelCredentialWebDavPassword),
        'legacy-pass',
      );
    });

    test('toJson 不带密码', () {
      expect(config.toJson().containsKey('password'), isFalse);
    });

    test('安全存储写失败：退回 kv 并标明来源', () async {
      final broken = _BrokenCredentialStore();
      await prefs.write(novelWebDavUrlKey, config.url);
      final saved = await writeNovelWebDavConfig(
        prefs,
        config,
        credentials: broken,
      );
      expect(saved.passwordSource, NovelPasswordSource.legacyKv);
      expect(await prefs.read(novelWebDavPasswordKey), 'p');
    });
  });

  test('进度包地址由主地址推导', () {
    expect(
      novelProgressUrlFor('https://dav.example.com/mimao/novel-backup.json'),
      'https://dav.example.com/mimao/novel-backup-progress.json',
    );
    expect(
      novelProgressUrlFor('https://dav.example.com/mimao/backup'),
      'https://dav.example.com/mimao/backup-progress',
    );
  });
}

class _FakeClient implements NovelWebDavClient {
  final Map<String, String> _bodies = <String, String>{};
  final Map<String, NovelWebDavException> _failures =
      <String, NovelWebDavException>{};

  void seed(String url, String body) => _bodies[url] = body;

  String? bodyOf(String url) => _bodies[url];

  void failWith(String url, NovelWebDavException error) =>
      _failures[url] = error;

  @override
  Future<void> put(String url, String body, NovelWebDavConfig config) async {
    final failure = _failures[url];
    if (failure != null) throw failure;
    _bodies[url] = body;
  }

  @override
  Future<String> get(String url, NovelWebDavConfig config) async {
    final failure = _failures[url];
    if (failure != null) throw failure;
    final body = _bodies[url];
    if (body == null) {
      throw const NovelWebDavException(NovelWebDavErrorKind.notFound);
    }
    return body;
  }
}

class _BrokenCredentialStore implements NovelCredentialStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('safe storage unavailable');

  @override
  Future<void> delete(String key) async {}
}
