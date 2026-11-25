// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他 novel 页面同款说明。
/// 备份中心：WebDAV 配置、加密、自动备份、上传/预览恢复/同步进度、撤销上次恢复。
///
/// 交互纪律（AGENTS.md「界面什么时候算做完」）：
/// - 恢复**先预览再执行**，破坏性动作二次确认；
/// - 空态写"为什么空 + 下一步"，错误态给可操作的建议，堆栈只进日志；
/// - 可点区域有 hover/focus（`NovelCard` / 标准按钮自带）。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/backup/backup_apply.dart';
import 'package:mimao/novel/backup/backup_crypto.dart';
import 'package:mimao/novel/backup/backup_service.dart';
import 'package:mimao/novel/backup/backup_settings.dart';
import 'package:mimao/novel/backup/credential_store.dart';
import 'package:mimao/novel/backup/progress_sync.dart';
import 'package:mimao/novel/backup/webdav_remote.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';

class NovelBackupPage extends StatefulWidget {
  const NovelBackupPage({
    super.key,
    required this.service,
    required this.prefs,
    this.progressSync,
    this.credentials,
    this.onChanged,
  });

  final NovelWebDavBackupService service;
  final NovelPrefsApi prefs;

  /// 进度同步（装配处注入）；null 时「立即同步」置灰并说明原因。
  final NovelProgressSync? progressSync;

  /// 凭据存储缝（测试注入内存实现；生产走系统安全存储）。
  final NovelCredentialStore? credentials;

  /// 备份/恢复/撤销完成时回调（首页据此重读数据）。
  final VoidCallback? onChanged;

  @override
  State<NovelBackupPage> createState() => _NovelBackupPageState();
}

class _NovelBackupPageState extends State<NovelBackupPage> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _user = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _deviceName = TextEditingController();
  final TextEditingController _backupPassword = TextEditingController();

  NovelBackupSettings _settings = const NovelBackupSettings(
    mode: NovelAutoBackupMode.off,
    encrypt: false,
    progressAuto: false,
    deviceName: '',
  );
  NovelWebDavConfig? _config;
  DateTime? _lastBackupAt;
  NovelBackupJournal? _journal;
  bool _rememberBackupPassword = true;
  bool _ready = false;
  bool _busy = false;
  String _busyLabel = '';
  String _error = '';
  String _hint = '';
  String _notice = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _password.dispose();
    _deviceName.dispose();
    _backupPassword.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = widget.prefs;
    NovelWebDavConfig? config;
    NovelBackupSettings settings = const NovelBackupSettings(
      mode: NovelAutoBackupMode.off,
      encrypt: false,
      progressAuto: false,
      deviceName: '',
    );
    var remembered = '';
    DateTime? lastBackup;
    NovelBackupJournal? journal;
    var error = '';
    try {
      config = await readNovelWebDavConfig(
        prefs,
        credentials: widget.credentials,
      );
    } on Object catch (e) {
      error = '读 WebDAV 配置失败：$e';
    }
    try {
      settings = await NovelBackupSettings.load(prefs);
    } on Object catch (e) {
      error = error.isEmpty ? '读备份设置失败：$e' : error;
    }
    try {
      remembered = await readNovelBackupPassword(
        credentials: widget.credentials,
      );
      lastBackup = DateTime.tryParse(
        await prefs.read(novelWebdavLastBackupAtKey) ?? '',
      );
    } on Object {
      // 安全存储不可用：当作"没有记住密码"，界面会提示重新输入。
    }
    try {
      // 本地快照目录不可用（测试/无 path_provider）不该让整页打不开。
      journal = await widget.service.lastUndo();
    } on Object {
      journal = null;
    }
    if (!mounted) return;
    setState(() {
      _config = config;
      _settings = settings;
      _url.text = config?.url ?? '';
      _user.text = config?.user ?? '';
      _password.text = config?.password ?? '';
      _deviceName.text = settings.deviceName;
      _backupPassword.text = remembered;
      _lastBackupAt = lastBackup;
      _journal = journal;
      _ready = true;
      if (error.isNotEmpty) {
        _error = error;
        _hint = '重启应用后再试；完整错误在应用日志里';
      }
    });
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyLabel = label;
      _error = '';
      _hint = '';
      _notice = '';
    });
    try {
      await action();
    } on NovelWebDavException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _hint = error.hint;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
          _hint = '完整错误已进应用日志（/logs）';
        });
      }
      debugPrint('novel backup: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  NovelWebDavConfig _draftConfig() => NovelWebDavConfig(
    url: _url.text.trim(),
    user: _user.text.trim(),
    password: _password.text,
    passwordSource: _config?.passwordSource ?? NovelPasswordSource.none,
  );

  Future<bool> _saveConfig({bool silent = false}) async {
    final draft = _draftConfig();
    if (!draft.isValid) {
      setState(() {
        _error = 'WebDAV 地址不完整';
        _hint = '填成 https://dav.example.com/mimao/novel-backup.json 这种形式';
      });
      return false;
    }
    final saved = await writeNovelWebDavConfig(
      widget.prefs,
      draft,
      credentials: widget.credentials,
    );
    final settings = NovelBackupSettings(
      mode: _settings.mode,
      encrypt: _settings.encrypt,
      progressAuto: _settings.progressAuto,
      deviceName: _deviceName.text.trim().isEmpty
          ? defaultNovelDeviceName()
          : _deviceName.text.trim(),
      lastAuto: _settings.lastAuto,
    );
    await settings.save(widget.prefs);
    if (_backupPassword.text.isNotEmpty) {
      await writeNovelBackupPassword(
        _rememberBackupPassword ? _backupPassword.text : '',
        credentials: widget.credentials,
      );
    } else {
      await writeNovelBackupPassword('', credentials: widget.credentials);
    }
    if (!mounted) return false;
    setState(() {
      _config = saved;
      _settings = settings;
      if (!silent) {
        _notice = saved.passwordSource == NovelPasswordSource.legacyKv
            ? '已保存，但本机安全存储不可用：密码暂时存在模块数据库里'
            : '配置已保存';
      }
    });
    return true;
  }

  /// 加密时取备份密码；本机没记住就问一次。
  Future<String?> _ensureBackupPassword({bool force = false}) async {
    if (!force && !_settings.encrypt) return '';
    if (_backupPassword.text.isNotEmpty) return _backupPassword.text;
    final typed = await _askPassword();
    if (typed == null) return null;
    if (mounted) setState(() => _backupPassword.text = typed);
    return typed;
  }

  Future<String?> _askPassword() async {
    if (!mounted) return null;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入备份密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('这份备份设了密码。密码只用于解开备份文件，不会上传。'),
            const SizedBox(height: 12),
            TextField(
              key: const Key('novel-backup-password-prompt'),
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: '备份密码'),
              onSubmitted: (value) => Navigator.pop(context, value),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _test() => _run('正在测试连接…', () async {
    if (!await _saveConfig(silent: true)) return;
    final config = _config;
    if (config == null) return;
    final health = await widget.service.testConnection(config);
    if (!mounted) return;
    setState(() {
      if (health.ok) {
        _notice = health.message;
      } else {
        _error = health.message;
        _hint = health.hint;
      }
    });
  });

  Future<void> _backup() => _run('正在合并并上传…', () async {
    if (!await _saveConfig(silent: true)) return;
    final config = _config;
    if (config == null) return;
    final password = await _ensureBackupPassword();
    if (password == null) return;
    final run = await widget.service.backup(config, password: password);
    if (!mounted) return;
    setState(() {
      _notice = [
        '备份完成（${run.exportedAt.hour.toString().padLeft(2, '0')}:'
            '${run.exportedAt.minute.toString().padLeft(2, '0')}）'
            ' · ${run.summary}',
        if (run.mergedWithRemote) ' · 已与远端合并（保留另一台设备的进度）',
        if (run.mergeSkipReason.isNotEmpty) ' · ${run.mergeSkipReason}',
        if (run.encrypted) ' · 已加密',
      ].join();
      _lastBackupAt = run.exportedAt;
    });
    widget.onChanged?.call();
  });

  Future<void> _restore() => _run('正在读取远端备份…', () async {
    if (!await _saveConfig(silent: true)) return;
    final config = _config;
    if (config == null) return;
    final password = await _ensureBackupPassword();
    if (password == null) return;

    NovelBackupPreview preview;
    try {
      preview = await widget.service.preview(config, password: password);
    } on NovelBackupCryptoException catch (error) {
      // 远端是加密包但本机没猜对：问一次再试。
      if (mounted) {
        setState(() {
          _error = error.message;
          _hint = '输入这份备份的密码后重试';
        });
      }
      return;
    }

    if (!mounted) return;
    final decision = await showDialog<_RestoreDecision>(
      context: context,
      builder: (_) => _RestorePreviewDialog(preview: preview),
    );
    if (decision == null) return;
    if (!mounted) return;

    // 注意：这里不能再套一层 _run——它会在 _busy 时直接返回，恢复就静默不执行。
    setState(() => _busyLabel = '正在应用恢复计划…');
    final report = await widget.service.apply(
      preview,
      useRemote: decision.useRemote,
    );
    if (!mounted) return;
    setState(() {
      _notice =
          '恢复完成：应用 ${report.applied} 处'
          '${report.failed > 0 ? '，${report.failed} 处失败' : ''}'
          ' · 可在下方撤销';
      if (report.errors.isNotEmpty) {
        _error = '部分条目没写进去';
        _hint = report.errors.take(3).join('；');
      }
    });
    _journal = await widget.service.lastUndo();
    widget.onChanged?.call();
  });

  Future<void> _undo() async {
    final journal = _journal;
    if (journal == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销上次恢复？'),
        content: Text(
          '将把 ${journal.rowCount} 处改动回滚到恢复前的状态。'
          '恢复之后你自己又改过的条目会保留，不会一并抹掉。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('novel-backup-undo-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _run('正在撤销上次恢复…', () async {
      final report = await widget.service.undo();
      if (!mounted) return;
      setState(() {
        _notice =
            '已回滚 ${report.restored} 处'
            '${report.skipped > 0 ? '，${report.skipped} 处因后来改过而保留' : ''}';
        if (report.errors.isNotEmpty) {
          _error = '部分条目没能回滚';
          _hint = report.errors.take(3).join('；');
        }
      });
      _journal = await widget.service.lastUndo();
      widget.onChanged?.call();
    });
  }

  Future<void> _syncProgress() => _run('正在同步进度…', () async {
    final sync = widget.progressSync;
    if (sync == null) return;
    final result = await sync.syncNow();
    if (!mounted) return;
    setState(() {
      if (result.ok) {
        _notice = result.summary;
      } else {
        _error = result.error;
        _hint = result.hint;
      }
    });
    if (result.updated > 0) widget.onChanged?.call();
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('备份中心')),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 32),
              children: <Widget>[
                NovelPageHeader(
                  title: '备份中心',
                  subtitle: _lastBackupAt == null
                      ? '还没有备份过 · 填好地址后先上传一次'
                      : '上次备份 ${novelRelativeTime(_lastBackupAt!)}',
                ),
                if (_error.isNotEmpty)
                  NovelCard(
                    color: cs.errorContainer,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _error,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: cs.onErrorContainer,
                          ),
                        ),
                        if (_hint.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 6),
                          Text(
                            _hint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onErrorContainer,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                if (_notice.isNotEmpty)
                  NovelCard(
                    color: cs.secondaryContainer,
                    child: Text(
                      _notice,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSecondaryContainer,
                      ),
                    ),
                  ),
                if (_busy)
                  NovelCard(
                    child: Row(
                      children: <Widget>[
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(_busyLabel),
                      ],
                    ),
                  ),
                _connectionCard(theme),
                const SizedBox(height: 12),
                _actionsCard(theme),
                const SizedBox(height: 12),
                _autoBackupCard(theme),
                const SizedBox(height: 12),
                _undoCard(theme),
              ],
            ),
    );
  }

  Widget _connectionCard(ThemeData theme) => NovelCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const NovelSectionHeader(icon: Icons.cloud_outlined, title: '连接'),
        const SizedBox(height: 12),
        TextField(
          key: const Key('novel-backup-url'),
          controller: _url,
          decoration: const InputDecoration(
            labelText: 'WebDAV 地址',
            hintText: 'https://dav.example.com/mimao/novel-backup.json',
            prefixIcon: Icon(Icons.link),
          ),
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('novel-backup-user'),
          controller: _user,
          decoration: const InputDecoration(
            labelText: '用户名（可选）',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('novel-backup-password'),
          controller: _password,
          obscureText: true,
          decoration: InputDecoration(
            labelText: '密码（可选）',
            prefixIcon: const Icon(Icons.lock_outline),
            helperText: switch (_config?.passwordSource) {
              NovelPasswordSource.secure => '已存进系统安全存储',
              NovelPasswordSource.legacyKv => '安全存储不可用，暂时存在模块数据库里',
              _ => '密码不会进备份文件，也不写日志',
            },
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('novel-backup-device-name'),
          controller: _deviceName,
          decoration: const InputDecoration(
            labelText: '本机名称（备份里显示）',
            prefixIcon: Icon(Icons.computer_outlined),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('novel-backup-save'),
                onPressed: _busy
                    ? null
                    : () => _run('正在保存…', () async {
                        await _saveConfig();
                      }),
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存配置'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('novel-backup-test'),
                onPressed: _busy ? null : _test,
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('测试连接'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _actionsCard(ThemeData theme) {
    final sync = widget.progressSync;
    return NovelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const NovelSectionHeader(
            icon: Icons.cloud_sync_outlined,
            title: '备份与恢复',
          ),
          const SizedBox(height: 8),
          Text(
            '上传会先读远端再合并，不会把另一台设备的进度抹掉。'
            '恢复先给你看「新增 / 更新 / 冲突」，确认后才落库，并且可以撤销。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          FieldPair(
            left: FilledButton.icon(
              key: const Key('novel-backup-run'),
              onPressed: _busy ? null : _backup,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('备份上传'),
            ),
            right: OutlinedButton.icon(
              key: const Key('novel-backup-restore'),
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('从远端恢复…'),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('novel-backup-sync'),
            onPressed: _busy || sync == null ? null : _syncProgress,
            icon: const Icon(Icons.sync),
            label: Text(sync == null ? '立即同步进度（服务未启用）' : '立即同步进度'),
          ),
        ],
      ),
    );
  }

  Widget _autoBackupCard(ThemeData theme) => NovelCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const NovelSectionHeader(icon: Icons.schedule, title: '自动备份'),
        const SizedBox(height: 8),
        Text(
          '「每次退出时」会在关窗前跑一次（10 秒超时，失败重试一次并记日志）。'
          '「每天一次」用 24 小时判定，启动与回到前台时检查。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<NovelAutoBackupMode>(
          segments: <ButtonSegment<NovelAutoBackupMode>>[
            for (final mode in NovelAutoBackupMode.values)
              ButtonSegment<NovelAutoBackupMode>(
                value: mode,
                label: Text(mode.label),
              ),
          ],
          selected: <NovelAutoBackupMode>{_settings.mode},
          onSelectionChanged: _busy
              ? null
              : (values) async {
                  final next = values.first;
                  setState(() {
                    _settings = NovelBackupSettings(
                      mode: next,
                      encrypt: _settings.encrypt,
                      progressAuto: _settings.progressAuto,
                      deviceName: _settings.deviceName,
                      lastAuto: _settings.lastAuto,
                    );
                  });
                  await _settings.save(widget.prefs);
                },
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          key: const Key('novel-backup-progress-auto'),
          contentPadding: EdgeInsets.zero,
          title: const Text('自动同步进度'),
          subtitle: const Text('离开阅读器时同步一次（节流 5 分钟）'),
          value: _settings.progressAuto,
          onChanged: _busy
              ? null
              : (value) async {
                  setState(() {
                    _settings = NovelBackupSettings(
                      mode: _settings.mode,
                      encrypt: _settings.encrypt,
                      progressAuto: value,
                      deviceName: _settings.deviceName,
                      lastAuto: _settings.lastAuto,
                    );
                  });
                  await _settings.save(widget.prefs);
                },
        ),
        const SizedBox(height: 8),
        Text(
          _settings.lastAuto?.label ?? '还没有自动备份记录',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Divider(height: 28),
        SwitchListTile(
          key: const Key('novel-backup-encrypt'),
          contentPadding: EdgeInsets.zero,
          title: const Text('备份文件加密'),
          subtitle: const Text('AES-256-GCM；密码只用于解开文件，不上传'),
          value: _settings.encrypt,
          onChanged: _busy
              ? null
              : (value) {
                  setState(() {
                    _settings = NovelBackupSettings(
                      mode: _settings.mode,
                      encrypt: value,
                      progressAuto: _settings.progressAuto,
                      deviceName: _settings.deviceName,
                      lastAuto: _settings.lastAuto,
                    );
                  });
                },
        ),
        if (_settings.encrypt) ...<Widget>[
          const SizedBox(height: 8),
          TextField(
            key: const Key('novel-backup-password-field'),
            controller: _backupPassword,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '备份密码',
              prefixIcon: Icon(Icons.key_outlined),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _rememberBackupPassword,
            onChanged: _busy
                ? null
                : (value) =>
                      setState(() => _rememberBackupPassword = value ?? false),
            title: const Text('记住密码（存进系统安全存储）'),
            subtitle: const Text('不记住的话，自动备份与进度同步会因为没有密码而跳过'),
          ),
        ],
      ],
    ),
  );

  Widget _undoCard(ThemeData theme) {
    final journal = _journal;
    return NovelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const NovelSectionHeader(icon: Icons.undo, title: '撤销上次恢复'),
          const SizedBox(height: 8),
          Text(
            journal == null
                ? '还没有可撤销的恢复。执行过一次恢复后，这里会出现撤销入口。'
                : '上次恢复：${journal.label.isEmpty ? '未知来源' : journal.label}'
                      ' · 共 ${journal.rowCount} 处改动',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('novel-backup-undo'),
            onPressed: _busy || journal == null ? null : _undo,
            icon: const Icon(Icons.settings_backup_restore),
            label: const Text('撤销上次恢复'),
          ),
        ],
      ),
    );
  }
}

/// 两列等宽按钮（窄窗自动换行）。
class FieldPair extends StatelessWidget {
  const FieldPair({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < 360) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[left, const SizedBox(height: 8), right],
        );
      }
      return Row(
        children: <Widget>[
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      );
    },
  );
}

/// 恢复预览里用户做的决定。
class _RestoreDecision {
  const _RestoreDecision(this.useRemote);

  final Map<String, bool> useRemote;
}

/// 恢复预览：来源、计数、分类明细、逐个冲突选择。
class _RestorePreviewDialog extends StatefulWidget {
  const _RestorePreviewDialog({required this.preview});

  final NovelBackupPreview preview;

  @override
  State<_RestorePreviewDialog> createState() => _RestorePreviewDialogState();
}

class _RestorePreviewDialogState extends State<_RestorePreviewDialog> {
  late final Map<String, bool> _useRemote = <String, bool>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final preview = widget.preview;
    final counts = preview.counts;
    final conflicts = preview.plan.conflicts;

    return AlertDialog(
      title: const Text('恢复预览'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '来自 ${preview.sourceLabel}'
                '${preview.encrypted ? ' · 已加密' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  _CountChip(label: '新增', value: counts.added),
                  _CountChip(label: '更新', value: counts.updated),
                  if (counts.removed > 0)
                    _CountChip(label: '删除', value: counts.removed),
                  _CountChip(label: '冲突', value: counts.conflicts),
                  _CountChip(label: '未变', value: counts.unchanged),
                ],
              ),
              if (preview.plan.byTarget.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text('按类型', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final row in preview.plan.byTarget)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${row.target.label}：${row.text}'),
                  ),
              ],
              if (conflicts.isNotEmpty) ...<Widget>[
                const SizedBox(height: 16),
                Text('冲突（默认保留本机，逐条可以选择远端）', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final conflict in conflicts)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${conflict.target.label} · ${conflict.title}',
                            style: theme.textTheme.titleSmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            conflict.detail,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '本机：${conflict.localText}',
                            style: theme.textTheme.bodySmall,
                          ),
                          Text(
                            '远端：${conflict.remoteText}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          SegmentedButton<bool>(
                            key: Key('novel-restore-conflict-${conflict.id}'),
                            segments: const <ButtonSegment<bool>>[
                              ButtonSegment<bool>(
                                value: false,
                                label: Text('用本机'),
                              ),
                              ButtonSegment<bool>(
                                value: true,
                                label: Text('用远端'),
                              ),
                            ],
                            selected: <bool>{_useRemote[conflict.id] ?? false},
                            onSelectionChanged: (values) => setState(
                              () => _useRemote[conflict.id] = values.first,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              Text(
                '执行前会自动把当前库导出一份到本机（备份目录），'
                '并在备份中心提供「撤销上次恢复」。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          key: const Key('novel-restore-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('novel-restore-confirm'),
          onPressed: () => Navigator.pop(context, _RestoreDecision(_useRemote)),
          child: const Text('执行恢复'),
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: MimaoShapes.pill,
      ),
      child: Text('$label $value', style: theme.textTheme.labelLarge),
    );
  }
}
