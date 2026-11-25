// 自动备份：判定矩阵 + 执行者（失败重试一次、加密缺密码、未配置）。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/novel/backup/auto_backup.dart';
import 'package:mimao/novel/backup/backup_service.dart';
import 'package:mimao/novel/backup/backup_settings.dart';
import 'package:mimao/novel/backup/credential_store.dart';
import 'package:mimao/novel/backup/webdav_remote.dart';
import 'package:mimao/novel/collect_service.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/stats_service.dart';

void main() {
  group('shouldAutoBackup 判定', () {
    final now = DateTime.utc(2026, 11, 25, 12);

    test('关闭：永不', () {
      expect(
        shouldAutoBackup(mode: NovelAutoBackupMode.off, now: now),
        isFalse,
      );
    });

    test('每次退出：恒跑', () {
      expect(
        shouldAutoBackup(
          mode: NovelAutoBackupMode.onExit,
          lastAt: now,
          now: now,
        ),
        isTrue,
      );
    });

    test('每天一次：没跑过 → 跑；不到 24 小时 → 不跑；满 24 小时 → 跑', () {
      expect(
        shouldAutoBackup(mode: NovelAutoBackupMode.daily, now: now),
        isTrue,
      );
      expect(
        shouldAutoBackup(
          mode: NovelAutoBackupMode.daily,
          lastAt: now.subtract(const Duration(hours: 23)),
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldAutoBackup(
          mode: NovelAutoBackupMode.daily,
          lastAt: now.subtract(const Duration(hours: 24)),
          now: now,
        ),
        isTrue,
      );
    });

    test('模式字符串解析：未知/空 → 关闭', () {
      expect(NovelAutoBackupMode.parse('exit'), NovelAutoBackupMode.onExit);
      expect(NovelAutoBackupMode.parse('DAILY'), NovelAutoBackupMode.daily);
      expect(NovelAutoBackupMode.parse(''), NovelAutoBackupMode.off);
      expect(NovelAutoBackupMode.parse(null), NovelAutoBackupMode.off);
    });

    test('上次结果编解码：失败原因里的竖线不被截断', () {
      final result = NovelAutoBackupResult(
        at: DateTime.utc(2026, 11, 25, 8, 30),
        ok: false,
        message: '账号或密码不对 · 检查密码',
      );
      final decoded = NovelAutoBackupResult.decode(result.encode())!;
      expect(decoded.ok, isFalse);
      expect(decoded.message, '账号或密码不对 · 检查密码');
      expect(decoded.label, contains('2026-11-25 08:30'));
      expect(decoded.label, contains('失败'));
    });
  });

  group('执行者', () {
    late AppDb appDb;
    late NovelDb db;
    late LibraryRepository library;
    late NovelCollectService collect;
    late NovelStatsService prefs;
    late _FlakyClient client;
    late NovelWebDavBackupService service;
    late NovelAutoBackupRunner runner;

    const config = NovelWebDavConfig(
      url: 'https://dav.example.com/mimao/novel-backup.json',
    );
    final now = DateTime.utc(2026, 11, 25, 12);

    setUp(() async {
      appDb = AppDb.forTesting(NativeDatabase.memory());
      db = NovelDb.forTesting(NativeDatabase.memory());
      library = LibraryRepository(appDb);
      collect = NovelCollectService(db, library);
      prefs = NovelStatsService(db);
      client = _FlakyClient();
      service = NovelWebDavBackupService(
        client: client,
        db: db,
        library: library,
        prefs: prefs,
        credentials: NovelMemoryCredentialStore(),
        deviceId: 'device-a',
      );
      runner = NovelAutoBackupRunner(
        service: service,
        prefs: prefs,
        credentials: NovelMemoryCredentialStore(),
        retryDelay: Duration.zero,
        clock: () => now,
      );
    });

    tearDown(() async {
      await appDb.close();
      await db.close();
    });

    Future<void> enable(
      NovelAutoBackupMode mode, {
      bool encrypt = false,
    }) async {
      final settings = NovelBackupSettings(
        mode: mode,
        encrypt: encrypt,
        progressAuto: false,
        deviceName: '测试机',
      );
      await settings.save(prefs);
      await prefs.write(novelWebDavUrlKey, config.url);
    }

    test('关闭模式：什么都不做，也不写结果', () async {
      await enable(NovelAutoBackupMode.off);
      expect(await runner.run(onExit: true), isNull);
      expect(await prefs.read(novelWebdavLastAutoResultKey), isNull);
    });

    test('每天一次且没到期：不跑', () async {
      await enable(NovelAutoBackupMode.daily);
      await prefs.write(
        novelWebdavLastAutoResultKey,
        NovelAutoBackupResult(at: now, ok: true).encode(),
      );
      expect(await runner.run(onExit: false), isNull);
    });

    test('跑成功：写 ok 结果 + 上次备份时间', () async {
      await enable(NovelAutoBackupMode.daily);
      await collect.collect(
        const NovelSummary(id: 'b1', title: '三体', coverUrl: ''),
      );

      final outcome = await runner.run(onExit: false);

      expect(outcome, isNotNull);
      expect(outcome!.ok, isTrue);
      expect(client.puts, 1);
      final stored = NovelAutoBackupResult.decode(
        await prefs.read(novelWebdavLastAutoResultKey),
      )!;
      expect(stored.ok, isTrue);
    });

    test('失败重试一次：第二次成功也算成功', () async {
      await enable(NovelAutoBackupMode.daily);
      client.failuresLeft = 1;

      final outcome = await runner.run(onExit: false);

      expect(outcome!.ok, isTrue);
      expect(client.putCalls, 2);
      expect(client.puts, 1);
      expect(
        NovelAutoBackupResult.decode(
          await prefs.read(novelWebdavLastAutoResultKey),
        )!.message,
        contains('重试'),
      );
    });

    test('两次都失败：记失败结果，不抛异常', () async {
      await enable(NovelAutoBackupMode.daily);
      client.failuresLeft = 2;

      final outcome = await runner.run(onExit: false);

      expect(outcome!.ok, isFalse);
      expect(outcome.message, contains('重试'));
      final stored = NovelAutoBackupResult.decode(
        await prefs.read(novelWebdavLastAutoResultKey),
      )!;
      expect(stored.ok, isFalse);
    });

    test('未配置地址：记一条可读原因', () async {
      await NovelBackupSettings(
        mode: NovelAutoBackupMode.onExit,
        encrypt: false,
        progressAuto: false,
        deviceName: '测试机',
      ).save(prefs);

      final outcome = await runner.run(onExit: true);

      expect(outcome!.ok, isFalse);
      expect(outcome.message, contains('WebDAV 地址'));
    });

    test('设了加密但没有密码：不静默跳过，记明确原因', () async {
      await enable(NovelAutoBackupMode.onExit, encrypt: true);

      final outcome = await runner.run(onExit: true);

      expect(outcome!.ok, isFalse);
      expect(outcome.message, contains('密码'));
      expect(client.puts, 0);
    });
  });
}

class _FlakyClient implements NovelWebDavClient {
  final Map<String, String> _bodies = <String, String>{};
  int failuresLeft = 0;

  /// 成功写入次数。
  int puts = 0;

  /// 尝试写入次数（含失败）。
  int putCalls = 0;

  @override
  Future<void> put(String url, String body, NovelWebDavConfig config) async {
    putCalls++;
    if (failuresLeft > 0) {
      failuresLeft--;
      throw const NovelWebDavException(NovelWebDavErrorKind.timeout);
    }
    puts++;
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
