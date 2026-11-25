/// 进度专用同步：只搬各书的 `(chapterIndex, locator, 时间)`。
///
/// 与全量备份分开的理由：全量包要 GET+PUT 整份数据（几十上百 KB，还要合并），
/// 进度同步是高频动作，单独一个小包才适合"离开阅读器就同步一次"。
///
/// **不覆盖本地更新的记录**：只写"远端章号更大 / 同章时间更新"的书；本地领先的
/// 那部分照样写回远端，所以两边最终都取到更靠后的那个。
library;

import 'package:mimao/core/library.dart';
import 'package:mimao/novel/backup/backup_apply.dart';
import 'package:mimao/novel/backup/backup_crypto.dart';
import 'package:mimao/novel/backup/backup_document.dart';
import 'package:mimao/novel/backup/backup_plan.dart';
import 'package:mimao/novel/backup/backup_service.dart'
    show NovelWebDavBackupService;
import 'package:mimao/novel/backup/backup_settings.dart';
import 'package:mimao/novel/backup/credential_store.dart';
import 'package:mimao/novel/backup/webdav_remote.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart'
    show NovelSourceStorage;

/// 一次进度同步的结果。
class NovelProgressSyncResult {
  const NovelProgressSyncResult({
    this.updated = 0,
    this.uploaded = 0,
    this.skipped = 0,
    this.failed = 0,
    this.message = '',
    this.error = '',
    this.hint = '',
  });

  /// 本地被远端更新的书数。
  final int updated;

  /// 写回远端的进度条数。
  final int uploaded;

  /// 本地已经更新、无需改动的书数。
  final int skipped;

  /// 单本失败数（不中断整次同步）。
  final int failed;

  /// 成功时的一句话。
  final String message;

  /// 失败时的可读原因与下一步。
  final String error;
  final String hint;

  bool get ok => error.isEmpty;

  String get summary {
    if (!ok) return error;
    if (updated == 0 && uploaded == 0) {
      return '进度已是最新（$skipped 本本地领先）';
    }
    final parts = <String>[];
    if (updated > 0) parts.add('更新 $updated 本');
    if (uploaded > 0) parts.add('上传 $uploaded 本');
    if (skipped > 0) parts.add('跳过 $skipped 本（本地更新）');
    if (failed > 0) parts.add('失败 $failed 本');
    return parts.join(' · ');
  }
}

class NovelProgressSync {
  NovelProgressSync({
    required this.client,
    required this.db,
    this.library,
    this.prefs,
    this.credentials,
    this.sourceStorage,
    this.deviceId,
  });

  final NovelWebDavClient client;
  final NovelDb db;
  final LibraryRepository? library;
  final NovelPrefsApi? prefs;
  final NovelCredentialStore? credentials;
  final NovelSourceStorage? sourceStorage;
  final String? deviceId;

  NovelWebDavBackupService get _service => NovelWebDavBackupService(
    client: client,
    db: db,
    library: library,
    sourceStorage: sourceStorage,
    prefs: prefs,
    credentials: credentials,
    files: null,
    deviceId: deviceId,
  );

  /// 配了地址就算可用（**不看**这次能不能连上——连不上是临时故障，
  /// 不该让菜单项永久消失）。
  Future<bool> isConfigured() async {
    final api = prefs;
    if (api == null) return false;
    final url = await api.read(novelWebDavUrlKey);
    return url != null && url.trim().isNotEmpty;
  }

  Future<NovelProgressSyncResult> syncNow({DateTime? now}) async {
    final api = prefs;
    if (api == null) {
      return const NovelProgressSyncResult(error: '模块设置不可用', hint: '重启应用后再试');
    }
    final config = await readNovelWebDavConfig(api, credentials: credentials);
    if (config == null || !config.isValid) {
      return const NovelProgressSyncResult(
        error: '还没配置 WebDAV 地址',
        hint: '在备份中心填入地址后再同步',
      );
    }
    final at = now ?? DateTime.now();
    final settings = await NovelBackupSettings.load(api);
    var password = '';
    if (settings.encrypt) {
      password = await readNovelBackupPassword(credentials: credentials);
      if (password.isEmpty) {
        return const NovelProgressSyncResult(
          error: '备份设了加密，但没有可用的密码',
          hint: '在备份中心输入一次备份密码并勾选记住',
        );
      }
    }

    final service = _service;
    final localDoc = (await service.snapshot(now: at)).progressOnly();

    String? remoteText;
    try {
      remoteText = await client.get(config.progressUrl, config);
    } on NovelWebDavException catch (error) {
      if (error.kind != NovelWebDavErrorKind.notFound) {
        return NovelProgressSyncResult(error: error.message, hint: error.hint);
      }
      remoteText = null;
    }

    var remote = NovelBackupDocument(
      collects: const <NovelBackupCollect>[],
      histories: const <NovelBackupHistory>[],
      searchKeywords: const <String>[],
      sources: const <NovelBookSource>[],
      prefs: const <String, String>{},
      exportedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
    if (remoteText != null && remoteText.trim().isNotEmpty) {
      try {
        final bundle = parseNovelBackupBundle(remoteText);
        if (bundle is NovelBackupPlainBundle) {
          remote = bundle.document;
        } else if (bundle is NovelBackupEncryptedBundle) {
          remote = bundle.decrypt(password);
        }
      } on NovelBackupCryptoException catch (error) {
        return NovelProgressSyncResult(
          error: error.message,
          hint: '确认备份密码是否改过',
        );
      } on FormatException catch (error) {
        return NovelProgressSyncResult(
          error: '远端进度包格式不对：${error.message}',
          hint: '可以在备份中心重新做一次全量备份',
        );
      }
    }

    // 只取进度段的合并计划：远端没有的书本地也不会被改动。
    final plan = planNovelRestore(local: localDoc, remote: remote, now: at);
    final applier = NovelBackupApplier(
      db: db,
      library: library,
      sourceStorage: sourceStorage,
      prefs: api,
      files: null,
      deviceId: deviceId,
    );
    final report = await applier.apply(plan, now: at, writeJournal: false);

    // 把"两边取更靠后"的结果写回远端，另一台设备下次同步就能拿到。
    final merged = mergeNovelBackupDocuments(
      local: localDoc,
      remote: remote,
      now: at,
    );
    var uploaded = 0;
    try {
      final text = password.isEmpty
          ? _progressDocument(merged, at).encode()
          : encryptNovelBackupText(
              _progressDocument(merged, at).encode(),
              password,
            ).encode();
      await client.put(config.progressUrl, text, config);
      uploaded = merged.progress.length;
    } on NovelWebDavException catch (error) {
      return NovelProgressSyncResult(
        updated: report.applied,
        error: error.message,
        hint: error.hint,
      );
    }

    return NovelProgressSyncResult(
      updated: report.applied,
      uploaded: uploaded,
      skipped: plan.counts.unchanged,
      failed: report.failed,
      message: '进度已同步',
    );
  }

  /// 只保留进度段的文档（上传用）。
  NovelBackupDocument _progressDocument(
    NovelBackupDocument source,
    DateTime at,
  ) => NovelBackupDocument(
    collects: const <NovelBackupCollect>[],
    histories: const <NovelBackupHistory>[],
    searchKeywords: const <String>[],
    sources: const <NovelBookSource>[],
    prefs: const <String, String>{},
    exportedAt: at,
    kind: NovelBackupKind.progress,
    deviceId: source.deviceId,
    deviceName: source.deviceName,
    progress: source.progress,
  );
}
