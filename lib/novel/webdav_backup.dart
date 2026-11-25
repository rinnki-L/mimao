/// 小说 WebDAV 备份/恢复的门面。
///
/// 具体实现在 `backup/` 下，按职责分层：
/// - `backup_document.dart`  文档 v2 模型与 v1 兼容（纯 Dart）
/// - `backup_plan.dart`      合并/预览（纯函数）
/// - `backup_crypto.dart`    可选密码加密（AES-256-GCM）
/// - `backup_snapshot.dart`  采集本机快照
/// - `backup_apply.dart`     执行计划 + 精确撤销
/// - `backup_service.dart`   上传/预览/恢复的编排
/// - `progress_sync.dart`    进度专用包
/// - `auto_backup.dart`      退出时/每天一次的自动备份
/// - `webdav_remote.dart`    配置、凭据、客户端与可读错误
/// - `backup_settings.dart`  备份设置与判定
///
/// 这里只做转出，外加几个旧名字的别名（首页与既有测试按旧名调用）。
library;

import 'package:mimao/novel/backup/webdav_remote.dart';
import 'package:mimao/novel/library_api.dart';

export 'backup/auto_backup.dart';
export 'backup/backup_apply.dart'
    show
        NovelBackupApplier,
        NovelBackupApplyReport,
        NovelBackupJournal,
        NovelBackupJournalEntry,
        NovelBackupUndoReport;
export 'backup/backup_crypto.dart'
    show
        NovelBackupBundle,
        NovelBackupCryptoException,
        NovelBackupEncryptedBundle,
        NovelBackupEnvelope,
        NovelBackupPlainBundle,
        encryptNovelBackupText,
        novelBackupCipherName,
        novelBackupKdfIterations,
        novelBackupKdfName,
        parseNovelBackupBundle;
export 'backup/backup_document.dart';
export 'backup/backup_file_store.dart';
export 'backup/backup_plan.dart';
export 'backup/backup_service.dart';
export 'backup/backup_settings.dart';
export 'backup/backup_snapshot.dart' show collectNovelBackupSnapshot;
export 'backup/novel_tombstone_service.dart';
export 'backup/progress_sync.dart';
export 'backup/webdav_remote.dart';

/// 旧名：读 WebDAV 配置（密码走系统安全存储）。
Future<NovelWebDavConfig?> readWebDavConfig(
  NovelPrefsApi prefs, {
  NovelCredentialStore? credentials,
}) => readNovelWebDavConfig(prefs, credentials: credentials);

/// 旧名：写 WebDAV 配置。
Future<NovelWebDavConfig> writeWebDavConfig(
  NovelPrefsApi prefs,
  NovelWebDavConfig config, {
  NovelCredentialStore? credentials,
}) => writeNovelWebDavConfig(prefs, config, credentials: credentials);
