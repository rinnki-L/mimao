/// 自动备份的执行者：退出时 / 每天一次，失败静默重试一次并记日志。
///
/// 判定逻辑（[shouldAutoBackup]）是纯函数，单独可测；这里的职责只有
/// 「按设置决定要不要跑、跑失败怎么重试、结果写哪」。
///
/// 加密备份但本机没有密码时**不静默跳过**：写一条明确的结果，让备份页能说清
/// "为什么今天没自动备份"。
library;

import 'package:flutter/foundation.dart';

import 'package:mimao/novel/backup/backup_service.dart';
import 'package:mimao/novel/backup/backup_settings.dart';
import 'package:mimao/novel/backup/webdav_remote.dart';
import 'package:mimao/novel/library_api.dart';

/// 一次自动备份的结果（成功/失败都算"跑过"）。
class NovelAutoBackupOutcome {
  const NovelAutoBackupOutcome({
    required this.ok,
    required this.message,
    this.summary = '',
  });

  final bool ok;
  final String message;

  /// 成功时的数据摘要。
  final String summary;
}

class NovelAutoBackupRunner {
  NovelAutoBackupRunner({
    required this.service,
    required this.prefs,
    this.credentials,
    this.retryDelay = const Duration(seconds: 2),
    this.clock,
  });

  final NovelWebDavBackupService service;
  final NovelPrefsApi prefs;
  final NovelCredentialStore? credentials;

  /// 第一次失败后隔多久重试（需求：静默重试一次）。
  final Duration retryDelay;

  /// 注入时钟便于单测；null 走 `DateTime.now()`。
  final DateTime Function()? clock;

  bool _running = false;

  DateTime _now() => clock?.call() ?? DateTime.now();

  /// 按设置跑一次；不该跑时返回 null（不写任何状态）。
  ///
  /// [onExit] true = 由关窗钩子触发；false = 启动/回前台补跑。
  Future<NovelAutoBackupOutcome?> run({required bool onExit}) async {
    if (_running) return null;
    final settings = await NovelBackupSettings.load(prefs);
    if (settings.mode == NovelAutoBackupMode.off) return null;

    final now = _now();
    if (onExit) {
      // 「每次退出时」恒跑；「每天一次」在退出时只补跑还没到期的那次。
      if (settings.mode == NovelAutoBackupMode.daily &&
          !shouldAutoBackup(
            mode: NovelAutoBackupMode.daily,
            lastAt: settings.lastAuto?.at,
            now: now,
          )) {
        return null;
      }
    } else if (!shouldAutoBackup(
      mode: settings.mode,
      lastAt: settings.lastAuto?.at,
      now: now,
    )) {
      return null;
    }

    _running = true;
    try {
      final config = await readNovelWebDavConfig(
        prefs,
        credentials: credentials,
      );
      if (config == null || !config.isValid) {
        return await _record(now, ok: false, message: '还没配置 WebDAV 地址');
      }
      var password = '';
      if (settings.encrypt) {
        password = await readNovelBackupPassword(credentials: credentials);
        if (password.isEmpty) {
          return await _record(now, ok: false, message: '备份设了加密但本机没有密码');
        }
      }

      final first = await _attempt(config, password);
      if (first != null) {
        return await _record(
          now,
          ok: true,
          message: '成功',
          summary: first.summary,
        );
      }
      // 静默重试一次。
      await Future<void>.delayed(retryDelay);
      final second = await _attempt(config, password);
      if (second != null) {
        return await _record(
          now,
          ok: true,
          message: '重试后成功',
          summary: second.summary,
        );
      }
      return await _record(now, ok: false, message: '上传失败（已重试一次）');
    } on NovelWebDavException catch (error) {
      return await _record(
        now,
        ok: false,
        message: '${error.message} · ${error.hint}',
      );
    } on Object catch (error) {
      debugPrint('novel auto backup: $error');
      return await _record(now, ok: false, message: '$error');
    } finally {
      _running = false;
    }
  }

  /// 单次尝试；失败返回 null（由调用方决定重试）。
  Future<NovelBackupRun?> _attempt(
    NovelWebDavConfig config,
    String password,
  ) async {
    try {
      return await service.backup(config, password: password);
    } on NovelWebDavException catch (error) {
      debugPrint(
        'novel auto backup 失败（${error.kind.name}'
        '${error.statusCode == null ? '' : ' HTTP ${error.statusCode}'}）',
      );
      return null;
    } on Object catch (error) {
      debugPrint('novel auto backup 失败: $error');
      return null;
    }
  }

  Future<NovelAutoBackupOutcome> _record(
    DateTime at, {
    required bool ok,
    required String message,
    String summary = '',
  }) async {
    final result = NovelAutoBackupResult(at: at, ok: ok, message: message);
    try {
      await prefs.write(novelWebdavLastAutoResultKey, result.encode());
    } on Object {
      // 记不上就算了，不能因此让关窗流程挂住。
    }
    if (!ok) debugPrint('novel auto backup: $message');
    return NovelAutoBackupOutcome(ok: ok, message: message, summary: summary);
  }
}
