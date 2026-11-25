// 进度专用同步：只搬章号/位置/时间，本地更新过的记录不被覆盖。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/novel/backup/backup_crypto.dart';
import 'package:mimao/novel/backup/backup_document.dart';
import 'package:mimao/novel/backup/backup_settings.dart';
import 'package:mimao/novel/backup/credential_store.dart';
import 'package:mimao/novel/backup/progress_sync.dart';
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
  late NovelMemoryCredentialStore credentials;
  late _FakeClient client;
  late NovelProgressSync sync;

  const config = NovelWebDavConfig(
    url: 'https://dav.example.com/mimao/novel-backup.json',
  );
  final progressUrl = config.progressUrl;

  setUp(() {
    appDb = AppDb.forTesting(NativeDatabase.memory());
    db = NovelDb.forTesting(NativeDatabase.memory());
    library = LibraryRepository(appDb);
    collect = NovelCollectService(db, library);
    history = NovelHistoryService(db, library);
    prefs = NovelStatsService(db);
    credentials = NovelMemoryCredentialStore();
    client = _FakeClient();
    sync = NovelProgressSync(
      client: client,
      db: db,
      library: library,
      prefs: prefs,
      credentials: credentials,
      deviceId: 'device-a',
    );
  });

  tearDown(() async {
    await appDb.close();
    await db.close();
  });

  NovelSummary book(String id) =>
      NovelSummary(id: id, title: '书$id', coverUrl: '');

  NovelBackupDocument progressDoc(String bookId, int chapter, {DateTime? at}) =>
      NovelBackupDocument(
        collects: const <NovelBackupCollect>[],
        histories: const <NovelBackupHistory>[],
        searchKeywords: const <String>[],
        sources: const <NovelBookSource>[],
        prefs: const <String, String>{},
        exportedAt: at ?? DateTime.utc(2026, 11, 20),
        kind: NovelBackupKind.progress,
        progress: <NovelBackupProgress>[
          NovelBackupProgress(bookId: bookId, chapterIndex: chapter),
        ],
      );

  Future<void> enableWebDav() async {
    await prefs.write(novelWebDavUrlKey, config.url);
    await NovelBackupSettings(
      mode: NovelAutoBackupMode.off,
      encrypt: false,
      progressAuto: true,
      deviceName: '测试机',
    ).save(prefs);
  }

  test('未配置地址：给可读错误，不抛异常', () async {
    final result = await sync.syncNow();
    expect(result.ok, isFalse);
    expect(result.error, contains('地址'));
    expect(result.hint, isNotEmpty);
  });

  test('远端更靠后：本地进度被更新', () async {
    await enableWebDav();
    await collect.collect(book('b1'));
    await history.saveProgress(book('b1'), 3, 400);
    client.seed(progressUrl, progressDoc('b1', 12).encode());

    final result = await sync.syncNow();

    expect(result.ok, isTrue);
    expect(result.updated, 1);
    expect((await history.latest('b1'))!.chapterIndex, 12);
    // 同步后把「两边取更靠后」的结果写回远端。
    final uploaded = NovelBackupDocument.decode(client.bodyOf(progressUrl)!);
    expect(uploaded.progress.single.chapterIndex, 12);
  });

  test('本地更靠后：不被覆盖，跳过计数', () async {
    await enableWebDav();
    await collect.collect(book('b1'));
    await history.saveProgress(book('b1'), 30, 400);
    client.seed(progressUrl, progressDoc('b1', 5).encode());

    final result = await sync.syncNow();

    expect(result.ok, isTrue);
    expect(result.updated, 0);
    expect(result.skipped, greaterThan(0));
    expect((await history.latest('b1'))!.chapterIndex, 30);
    final uploaded = NovelBackupDocument.decode(client.bodyOf(progressUrl)!);
    expect(uploaded.progress.single.chapterIndex, 30);
  });

  test('远端没有进度包：视为空，上传本地进度', () async {
    await enableWebDav();
    await collect.collect(book('b1'));
    await history.saveProgress(book('b1'), 7, 400);

    final result = await sync.syncNow();

    expect(result.ok, isTrue);
    expect(result.uploaded, 1);
    expect(client.bodyOf(progressUrl), isNotNull);
    expect((await history.latest('b1'))!.chapterIndex, 7);
  });

  test('本地没有这本书：跳过，不造幽灵条目', () async {
    await enableWebDav();
    client.seed(progressUrl, progressDoc('ghost', 40).encode());

    final result = await sync.syncNow();

    expect(result.ok, isTrue);
    expect(await history.latest('ghost'), isNull);
  });

  test('加密备份但没有密码：给可读错误', () async {
    await enableWebDav();
    await NovelBackupSettings(
      mode: NovelAutoBackupMode.off,
      encrypt: true,
      progressAuto: true,
      deviceName: '测试机',
    ).save(prefs);

    final result = await sync.syncNow();

    expect(result.ok, isFalse);
    expect(result.error, contains('密码'));
  });

  test('加密远端 + 有密码：能解开并同步', () async {
    await enableWebDav();
    await NovelBackupSettings(
      mode: NovelAutoBackupMode.off,
      encrypt: true,
      progressAuto: true,
      deviceName: '测试机',
    ).save(prefs);
    await writeNovelBackupPassword('pw', credentials: credentials);
    await collect.collect(book('b1'));
    await history.saveProgress(book('b1'), 2, 400);
    client.seed(
      progressUrl,
      encryptNovelBackupText(
        progressDoc('b1', 11).encode(),
        'pw',
        iterations: 500,
      ).encode(),
    );

    final result = await sync.syncNow();

    expect(result.ok, isTrue);
    expect(result.updated, 1);
    expect((await history.latest('b1'))!.chapterIndex, 11);
    // 写回的也是加密包。
    final bundle = parseNovelBackupBundle(client.bodyOf(progressUrl)!);
    expect(bundle, isA<NovelBackupEncryptedBundle>());
  });
}

class _FakeClient implements NovelWebDavClient {
  final Map<String, String> _bodies = <String, String>{};

  void seed(String url, String body) => _bodies[url] = body;

  String? bodyOf(String url) => _bodies[url];

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
