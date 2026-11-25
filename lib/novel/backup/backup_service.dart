/// 备份/恢复的编排层：采集 → 拉远端 → 合并 → 加密 → PUT；以及
/// 拉远端 → 预览计划 → 执行 + 撤销。
///
/// 三个约束照需求落地：
/// 1. **上传是合并写**：先读远端再写超集，别把另一台设备的进度抹掉；
/// 2. **恢复不直接清库**：先算出计划给用户看（新增/更新/冲突），确认后才落库；
/// 3. **可撤销**：执行前既写一份整库快照（兜底），又逐行记 journal（精确回滚）。
library;

import 'package:mimao/core/library.dart';
import 'package:mimao/novel/backup/backup_apply.dart';
import 'package:mimao/novel/backup/backup_crypto.dart';
import 'package:mimao/novel/backup/backup_document.dart';
import 'package:mimao/novel/backup/backup_file_store.dart';
import 'package:mimao/novel/backup/backup_plan.dart';
import 'package:mimao/novel/backup/credential_store.dart';
import 'package:mimao/novel/backup/backup_settings.dart';
import 'package:mimao/novel/backup/backup_snapshot.dart';
import 'package:mimao/novel/backup/webdav_remote.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/source/novel_source_store.dart'
    show NovelSourceStorage;

/// 本地兜底快照的文件名前缀（撤销的第一道保险）。
const String novelBackupPreRestorePrefix = 'pre-restore-';

/// 一次备份上传的结果。
class NovelBackupRun {
  const NovelBackupRun({
    required this.exportedAt,
    required this.collects,
    required this.histories,
    required this.sources,
    required this.progress,
    this.mergedWithRemote = false,
    this.mergeSkipReason = '',
    this.encrypted = false,
  });

  final DateTime exportedAt;
  final int collects;
  final int histories;
  final int sources;
  final int progress;

  /// 是否把远端旧内容并了进来。
  final bool mergedWithRemote;

  /// 没合并的原因（远端是加密包但没给密码等）。
  final String mergeSkipReason;

  final bool encrypted;

  /// 界面上的一句话。
  String get summary {
    final parts = <String>['$collects 本收藏', '$histories 条阅读记录', '$sources 个书源'];
    return parts.join(' · ');
  }
}

/// 恢复预览：远端文档 + 已经算好的计划。
class NovelBackupPreview {
  const NovelBackupPreview({
    required this.remote,
    required this.plan,
    required this.encrypted,
    this.deviceName = '',
    this.exportedAt,
  });

  final NovelBackupDocument remote;
  final NovelBackupPlan plan;

  /// 远端是不是加密包（界面要标出来）。
  final bool encrypted;
  final String deviceName;
  final DateTime? exportedAt;

  NovelBackupCounts get counts => plan.counts;

  /// 预览页头部的一句描述。
  String get sourceLabel {
    final name = deviceName.trim().isEmpty ? '未知设备' : deviceName.trim();
    final at = exportedAt;
    if (at == null) return name;
    final clock =
        '${at.year}-${_two(at.month)}-${_two(at.day)} '
        '${_two(at.hour)}:${_two(at.minute)}';
    return '$name · $clock';
  }
}

String _two(int value) => value.toString().padLeft(2, '0');

/// 连接测试的结果。
class NovelBackupHealth {
  const NovelBackupHealth({
    required this.ok,
    required this.message,
    this.hint = '',
  });

  final bool ok;
  final String message;
  final String hint;
}

/// 备份服务。远端只有 PUT/GET 两个动作（WebDAV 不支持实时双向同步）。
class NovelWebDavBackupService {
  NovelWebDavBackupService({
    required this.client,
    required this.db,
    this.library,
    this.sourceStorage,
    this.prefs,
    this.credentials,
    this.files,
    this.deviceId,
    String? deviceName,
  }) : _deviceName = deviceName;

  final NovelWebDavClient client;
  final NovelDb db;
  final LibraryRepository? library;
  final NovelSourceStorage? sourceStorage;
  final NovelPrefsApi? prefs;
  final NovelCredentialStore? credentials;
  final NovelBackupFileStore? files;
  final String? deviceId;
  final String? _deviceName;

  NovelBackupFileStore get _files => files ?? NovelSupportBackupFileStore();

  Future<String> _deviceNameOrPref() async {
    final injected = _deviceName;
    if (injected != null && injected.trim().isNotEmpty) return injected.trim();
    final api = prefs;
    if (api != null) {
      final stored = await api.read(novelWebdavDeviceNameKey);
      if (stored != null && stored.trim().isNotEmpty) return stored.trim();
    }
    return defaultNovelDeviceName();
  }

  /// 采集本机快照（kind = full）。
  Future<NovelBackupDocument> snapshot({DateTime? now}) =>
      collectNovelBackupSnapshot(
        db: db,
        sourceStorage: sourceStorage,
        prefs: prefs,
        deviceId: deviceId,
        deviceName: '',
        now: now,
      );

  // ── 上传 ────────────────────────────────────────────────────────────────

  /// 采集 + 合并远端 + 上传。
  ///
  /// [password] 非空时会加密上传；远端若是加密包但没给密码，则**跳过合并**
  /// （不能拿不解密的远端去合并，否则会盲写覆盖另一台设备的数据），并把原因
  /// 放进 [NovelBackupRun.mergeSkipReason]。
  Future<NovelBackupRun> backup(
    NovelWebDavConfig config, {
    String password = '',
    bool mergeRemote = true,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final name = await _deviceNameOrPref();
    final local = await snapshot(now: at);
    final withName = NovelBackupDocument(
      collects: local.collects,
      histories: local.histories,
      searchKeywords: local.searchKeywords,
      sources: local.sources,
      prefs: local.prefs,
      exportedAt: at,
      deviceId: local.deviceId,
      deviceName: name,
      progress: local.progress,
      series: local.series,
      bookmarks: local.bookmarks,
      markings: local.markings,
      readRecords: local.readRecords,
      tombstones: local.tombstones,
    );

    String? remoteText;
    var merged = false;
    var skipReason = '';
    if (mergeRemote) {
      try {
        remoteText = await _fetch(config.url, config);
      } on NovelWebDavException catch (error) {
        if (error.kind != NovelWebDavErrorKind.notFound) rethrow;
        remoteText = null;
      }
      if (remoteText != null && remoteText.trim().isNotEmpty) {
        final remote = _decodeRemote(remoteText, password);
        if (remote == null) {
          skipReason = '远端是加密备份，需要密码才能合并；本次按本机内容覆盖上传';
        } else {
          merged = true;
          final union = mergeNovelBackupDocuments(
            local: withName,
            remote: remote,
            now: at,
          );
          // 合并只取数据，设备名/设备 id 用本机的。
          final document = NovelBackupDocument(
            collects: union.collects,
            histories: union.histories,
            searchKeywords: union.searchKeywords,
            sources: union.sources,
            prefs: union.prefs,
            exportedAt: at,
            deviceId: withName.deviceId,
            deviceName: name,
            progress: union.progress,
            series: union.series,
            bookmarks: union.bookmarks,
            markings: union.markings,
            readRecords: union.readRecords,
            tombstones: union.tombstones,
          );
          await _upload(
            config,
            document,
            previous: remoteText,
            password: password,
          );
          return NovelBackupRun(
            exportedAt: at,
            collects: document.collects.length,
            histories: document.histories.length,
            sources: document.sources.length,
            progress: document.progress.length,
            mergedWithRemote: true,
            encrypted: password.isNotEmpty,
          );
        }
      }
    }

    await _upload(config, withName, previous: remoteText, password: password);
    return NovelBackupRun(
      exportedAt: at,
      collects: withName.collects.length,
      histories: withName.histories.length,
      sources: withName.sources.length,
      progress: withName.progress.length,
      mergedWithRemote: merged,
      mergeSkipReason: skipReason,
      encrypted: password.isNotEmpty,
    );
  }

  /// 写 `.bak` 备份上一代内容，再 PUT 新内容。
  Future<void> _upload(
    NovelWebDavConfig config,
    NovelBackupDocument document, {
    String? previous,
    String password = '',
  }) async {
    var text = document.encode();
    if (password.isNotEmpty) {
      text = encryptNovelBackupText(text, password).encode();
    }
    if (previous != null && previous.trim().isNotEmpty) {
      try {
        await client.put(config.backupUrl, previous, config);
      } on NovelWebDavException {
        // `.bak` 只是保险，写不进去不该挡住主上传。
      }
    }
    await client.put(config.url, text, config);
    final api = prefs;
    if (api != null) {
      await api.write(
        novelWebdavLastBackupAtKey,
        document.exportedAt.toIso8601String(),
      );
    }
  }

  // ── 预览 / 恢复 ─────────────────────────────────────────────────────────

  /// 拉远端并算出恢复计划（不落库）。
  Future<NovelBackupPreview> preview(
    NovelWebDavConfig config, {
    String password = '',
    DateTime? now,
  }) async {
    final text = await _fetch(config.url, config);
    if (text == null || text.trim().isEmpty) {
      throw const NovelWebDavException(NovelWebDavErrorKind.notFound);
    }
    final bundle = parseNovelBackupBundle(text);
    final NovelBackupDocument remote;
    if (bundle is NovelBackupPlainBundle) {
      remote = bundle.document;
    } else if (bundle is NovelBackupEncryptedBundle) {
      remote = bundle.decrypt(password);
    } else {
      throw const FormatException('备份文件格式不认识');
    }
    final local = await snapshot(now: now ?? DateTime.now());
    final plan = planNovelRestore(
      local: local,
      remote: remote,
      localDeviceId: deviceId ?? await db.ensureDeviceId(),
      now: now ?? DateTime.now(),
    );
    return NovelBackupPreview(
      remote: remote,
      plan: plan,
      encrypted: bundle is NovelBackupEncryptedBundle,
      deviceName: remote.deviceName,
      exportedAt: remote.exportedAt,
    );
  }

  /// 执行预览里的计划。
  ///
  /// [useRemote] 的键是 `NovelBackupConflict.id`：true = 用远端，缺省 = 用本地。
  Future<NovelBackupApplyReport> apply(
    NovelBackupPreview preview, {
    Map<String, bool> useRemote = const <String, bool>{},
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final resolved = preview.plan.resolveConflicts(useRemote);
    final applier = NovelBackupApplier(
      db: db,
      library: library,
      sourceStorage: sourceStorage,
      prefs: prefs,
      files: _files,
      deviceId: deviceId,
    );
    // 兜底快照：即使 journal 丢了，也能看出"恢复前长什么样"。
    await _writePreRestoreSnapshot(at);
    return applier.apply(resolved, label: preview.sourceLabel, now: at);
  }

  Future<void> _writePreRestoreSnapshot(DateTime at) async {
    try {
      final store = _files;
      final doc = await snapshot(now: at);
      await store.write(
        '$novelBackupPreRestorePrefix${at.millisecondsSinceEpoch}.json',
        doc.encode(),
      );
      final names =
          (await store.list())
              .where((name) => name.startsWith(novelBackupPreRestorePrefix))
              .toList()
            ..sort();
      while (names.length > 1) {
        await store.delete(names.removeAt(0));
      }
    } on Object {
      // 兜底快照写失败不该挡住恢复；journal 仍在。
    }
  }

  /// 撤销上次恢复。
  Future<NovelBackupUndoReport> undo({String? journalName}) =>
      NovelBackupApplier(
        db: db,
        library: library,
        sourceStorage: sourceStorage,
        prefs: prefs,
        files: _files,
        deviceId: deviceId,
      ).undo(journalName: journalName);

  /// 最近一次可撤销的恢复记录。
  Future<NovelBackupJournal?> lastUndo() => NovelBackupApplier(
    db: db,
    library: library,
    sourceStorage: sourceStorage,
    prefs: prefs,
    files: _files,
    deviceId: deviceId,
  ).latestJournal();

  // ── 连接测试 ────────────────────────────────────────────────────────────

  Future<NovelBackupHealth> testConnection(NovelWebDavConfig config) async {
    if (!config.isValid) {
      return const NovelBackupHealth(
        ok: false,
        message: '地址不完整',
        hint: '填成 https://dav.example.com/mimao/novel-backup.json 这种形式',
      );
    }
    try {
      final text = await _fetch(config.url, config);
      if (text == null) {
        return const NovelBackupHealth(
          ok: true,
          message: '连上了，远端还没有备份文件',
          hint: '第一次备份会新建它',
        );
      }
      return NovelBackupHealth(
        ok: true,
        message: '连上了，远端已有一份备份（${text.length} 字节）',
      );
    } on NovelWebDavException catch (error) {
      return NovelBackupHealth(
        ok: false,
        message: error.message,
        hint: error.hint,
      );
    }
  }

  // ── 内部 ────────────────────────────────────────────────────────────────

  /// GET；404 返回 null（远端还没有文件不是错误）。
  Future<String?> _fetch(String url, NovelWebDavConfig config) async {
    try {
      return await client.get(url, config);
    } on NovelWebDavException catch (error) {
      if (error.kind == NovelWebDavErrorKind.notFound) return null;
      rethrow;
    }
  }

  /// 远端文本 → 文档；加密包且没有密码时返回 null（调用方决定跳过合并）。
  NovelBackupDocument? _decodeRemote(String text, String password) {
    final bundle = parseNovelBackupBundle(text);
    if (bundle is NovelBackupPlainBundle) return bundle.document;
    if (bundle is NovelBackupEncryptedBundle) {
      return password.isEmpty ? null : bundle.decrypt(password);
    }
    return null;
  }
}
