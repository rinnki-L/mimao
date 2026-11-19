// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 comic 页面同款说明。
/// 音乐模块在全局设置抽屉里的分组（M4 骨架 + M4-L 扫码登录）。
///
/// 只读展示设备身份（不触发联网注册）；账号区由 [account] 驱动：
/// - null：保留契约占位（L 线未接线时既有测试锚点不变）；
/// - 非 null：匿名态显示「扫码登录」，登录态显示头像/昵称/ID 与退出入口。
///
/// 二维码是服务端直接给的 PNG data URL，用 [Image.memory] 渲染，不引二维码库。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/pages/qr_login_controller.dart';

class MusicModuleSettings extends StatefulWidget {
  const MusicModuleSettings({
    super.key,
    required this.api,
    this.account,
    this.pollInterval = const Duration(seconds: 2),
  });

  final MusicApi api;

  /// L 线登录门面；null 时保留「登录功能接线中」占位（既有测试锚点不变）。
  final MusicAccountApi? account;

  /// 轮询间隔（测试注入短间隔；生产默认 2 秒）。
  final Duration pollInterval;

  @override
  State<MusicModuleSettings> createState() => _MusicModuleSettingsState();
}

class _MusicModuleSettingsState extends State<MusicModuleSettings> {
  KugouIdentity? _identity;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reloadIdentity();
  }

  Future<void> _reloadIdentity() async {
    try {
      final identity = await widget.api.currentIdentity();
      if (!mounted) return;
      setState(() {
        _identity = identity;
        _loading = false;
      });
    } on Object {
      // 身份读盘失败不该挡住设置页——设备区按「未引导」展示。
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openLoginDialog() async {
    final account = widget.account;
    if (account == null) return;
    final identity = await showDialog<KugouIdentity>(
      context: context,
      builder: (context) =>
          _QrLoginDialog(account: account, pollInterval: widget.pollInterval),
    );
    if (!mounted || identity == null) return;
    setState(() => _identity = identity);
    _showSnack('登录成功');
  }

  Future<void> _logout() async {
    final account = widget.account;
    if (account == null) return;
    try {
      final identity = await account.logout();
      if (!mounted) return;
      setState(() => _identity = identity);
      _showSnack('已退出，仍可匿名试听');
    } on Object {
      if (!mounted) return;
      _showSnack('退出登录失败，请重试');
    }
  }

  /// 后一条提示顶掉前一条（登录成功后马上退出时不会被队列挡住）。
  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('设备身份', style: theme.textTheme.titleSmall),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          _buildDevice(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('账号', style: theme.textTheme.titleSmall),
        ),
        // ── M4-L 登录 ──
        if (widget.account == null)
          const ListTile(
            leading: Icon(Icons.qr_code_2),
            title: Text('酷狗账号登录（二维码）'),
            subtitle: Text('登录态 API 客户端切片接入'),
            enabled: false,
            trailing: Icon(Icons.chevron_right),
          )
        else
          _buildAccount(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            '协议实现对照 EchoMusicNext crates/echo-api 逐函数翻译，'
            '上游酷狗概念版 API 取自 MakcRe/KuGouMusicApi（详见 lib/music/README.md）。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDevice() {
    final identity = _identity;
    if (identity == null) {
      return const ListTile(
        leading: Icon(Icons.devices_other),
        title: Text('尚未引导设备身份'),
        subtitle: Text('首次搜索时自动生成并注册'),
      );
    }
    final loggedIn = identity.hasAccount;
    return Column(
      children: <Widget>[
        ListTile(
          leading: Icon(loggedIn ? Icons.account_circle : Icons.devices_other),
          title: Text(loggedIn ? '酷狗账号已登录' : '匿名设备'),
          subtitle: Text(loggedIn ? '用户 ID：${identity.userId}' : '未登录（匿名态）'),
        ),
        _IdentityRow(label: 'GUID', value: identity.guid),
        _IdentityRow(label: 'MID', value: identity.mid),
        _IdentityRow(label: 'DFID', value: identity.dfid),
      ],
    );
  }

  Widget _buildAccount() {
    final identity = _identity;
    if (identity != null && identity.hasAccount) {
      return ListTile(
        leading: _AccountAvatar(identity: identity),
        title: Text(identity.accountLabel),
        subtitle: Text('用户 ID：${identity.userId}'),
        trailing: TextButton(onPressed: _logout, child: const Text('退出登录')),
      );
    }
    return ListTile(
      leading: const Icon(Icons.qr_code_2),
      title: const Text('当前：匿名设备 · 未登录'),
      subtitle: const Text('扫码登录后可同步账号权限'),
      trailing: FilledButton.tonal(
        onPressed: _openLoginDialog,
        child: const Text('扫码登录'),
      ),
    );
  }
}

/// 登录态头像：网络图必须带 errorBuilder（加载失败显示占位图标）。
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.identity});

  final KugouIdentity identity;

  @override
  Widget build(BuildContext context) {
    if (identity.avatarUrl.isEmpty) {
      return const CircleAvatar(child: Icon(Icons.person));
    }
    return ClipOval(
      child: Image.network(
        identity.avatarUrl,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const CircleAvatar(child: Icon(Icons.person)),
      ),
    );
  }
}

/// 扫码对话框：打开即取码并开始轮询（用户手势之后，非设置页 initState）。
class _QrLoginDialog extends StatefulWidget {
  const _QrLoginDialog({required this.account, required this.pollInterval});

  final MusicAccountApi account;
  final Duration pollInterval;

  @override
  State<_QrLoginDialog> createState() => _QrLoginDialogState();
}

class _QrLoginDialogState extends State<_QrLoginDialog> {
  late final QrLoginController _controller;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _controller = QrLoginController(
      account: widget.account,
      pollInterval: widget.pollInterval,
      onChanged: _onChanged,
    );
    _controller.start();
  }

  void _onChanged() {
    if (!mounted || _closed) return;
    if (_controller.phase == QrLoginPhase.authorized) {
      _closed = true;
      Navigator.of(context).pop(_controller.identity);
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    // 关闭/授权/取消都必须停表：widget 测试会断言无 pending timer。
    _controller.dispose();
    super.dispose();
  }

  void _cancel() {
    _closed = true;
    _controller.cancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final session = _controller.session;
    final bytes = session == null
        ? null
        : decodeQrImageData(session.imageDataUrl);
    return AlertDialog(
      title: const Text('扫码登录'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _QrImage(bytes: bytes, phase: _controller.phase),
            const SizedBox(height: 12),
            Text(
              _statusText(_controller),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _controller.phase == QrLoginPhase.loading
              ? null
              : _controller.refresh,
          child: const Text('刷新二维码'),
        ),
        TextButton(onPressed: _cancel, child: const Text('取消')),
      ],
    );
  }

  String _statusText(QrLoginController controller) {
    return switch (controller.phase) {
      QrLoginPhase.idle || QrLoginPhase.loading => '正在获取二维码…',
      QrLoginPhase.waiting => '等待扫码',
      QrLoginPhase.scanned => '已扫码，请在手机上确认',
      QrLoginPhase.authorized => '登录成功',
      QrLoginPhase.expired => '二维码已过期，点击刷新',
      QrLoginPhase.failed => controller.error ?? '登录失败，请重试',
    };
  }
}

/// 二维码展示：解析失败给可读占位，不把异常抛进 build。
class _QrImage extends StatelessWidget {
  const _QrImage({required this.bytes, required this.phase});

  final Uint8List? bytes;
  final QrLoginPhase phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = this.bytes;
    if (phase == QrLoginPhase.loading) {
      return const SizedBox(
        width: 220,
        height: 220,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (bytes == null) {
      return Container(
        width: 220,
        height: 220,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: MimaoShapes.sm,
        ),
        child: Text(
          '二维码图片解析失败，请刷新',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    return Image.memory(
      bytes,
      width: 220,
      height: 220,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const SizedBox(
        width: 220,
        height: 220,
        child: Center(child: Text('二维码图片解析失败，请刷新')),
      ),
    );
  }
}

/// 脱敏的一行标识（前 8 位 + …）。
class _IdentityRow extends StatelessWidget {
  const _IdentityRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : _mask(value),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  String _mask(String value) {
    if (value.length <= 8) return value;
    return '${value.substring(0, 8)}…（${value.length} 位）';
  }
}
