// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 comic 页面同款说明。
/// 音乐模块主页「设置」tab 的内容（M4 骨架 + M4-L 扫码登录 + L5 登录扩展）。
///
/// 只读展示设备身份（不触发联网注册）；账号区由 [account] 驱动：
/// - null：保留契约占位（L 线未接线时既有测试锚点不变）；
/// - 非 null：匿名态显示「扫码登录」，登录态显示头像/昵称/ID 与退出入口。
///
/// L5 扩展全部是可选参数（null 时入口隐藏、既有构造不变）：
/// - [auth]+[verify]：push「更多登录方式」（手机号/QQ/微信/设备管理）；
/// - [verify]：push「安全验证」（事件号查挑战 + sideDt 提交）；
/// - [settings]：「听歌上报」开关（本地设置，ensureLoaded 后刷新）。
///
/// 二维码是服务端直接给的 PNG data URL，用 [Image.memory] 渲染，不引二维码库。
library;

import 'package:flutter/material.dart';
import 'package:mimao/music/api/auth_login_api.dart';
import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/api/search_ext_api.dart';
import 'package:mimao/music/api/verify_api.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/music_settings.dart';
import 'package:mimao/music/pages/music_login_methods_page.dart';
import 'package:mimao/music/pages/music_security_verify_page.dart';
import 'package:mimao/music/pages/qr_login_controller.dart';
import 'package:mimao/music/pages/qr_login_view.dart';

class MusicModuleSettings extends StatefulWidget {
  const MusicModuleSettings({
    super.key,
    required this.api,
    this.account,
    this.pollInterval = const Duration(seconds: 2),
    this.auth,
    this.verify,
    this.searchExt,
    this.settings,
  });

  final MusicApi api;

  /// L 线登录门面；null 时保留「登录功能接线中」占位（既有测试锚点不变）。
  final MusicAccountApi? account;

  /// 轮询间隔（测试注入短间隔；生产默认 2 秒）。
  final Duration pollInterval;

  /// L5 登录扩展门面；与 [verify] 齐备时显示「更多登录方式」入口。
  final MusicAuthApi? auth;

  /// L5 验证端点组；非空时显示「安全验证」入口（也是方法页的依赖）。
  final MusicVerifyApi? verify;

  /// L5 sidedt 提交通道；透传给方法页/安全验证页。
  final MusicSearchExtApi? searchExt;

  /// 本地设置（听歌上报开关）；null 时隐藏开关条目。
  final MusicSettings? settings;

  @override
  State<MusicModuleSettings> createState() => _MusicModuleSettingsState();
}

class _MusicModuleSettingsState extends State<MusicModuleSettings> {
  KugouIdentity? _identity;
  bool _loading = true;

  /// 听歌上报开关（null = 设置层尚未读盘，条目禁用）。
  bool? _listenReport;

  @override
  void initState() {
    super.initState();
    _reloadIdentity();
    _loadListenReport();
  }

  /// 先 ensureLoaded 再刷新开关初值（本地设置默认 true，读盘后才可信）。
  Future<void> _loadListenReport() async {
    final settings = widget.settings;
    if (settings == null) return;
    await settings.ensureLoaded();
    if (!mounted) return;
    setState(() => _listenReport = settings.listenReportEnabled);
  }

  /// 切换听歌上报：先改内存再落盘；落盘失败回滚并提示。
  Future<void> _toggleListenReport(bool value) async {
    final settings = widget.settings!;
    final previous = _listenReport;
    setState(() => _listenReport = value);
    try {
      await settings.setListenReportEnabled(value);
    } on Object {
      if (!mounted) return;
      setState(() => _listenReport = previous);
      _showSnack('听歌上报设置保存失败');
    }
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

  /// push 更多登录方式（手机号/QQ/微信/设备管理）；登录成功后刷新账号区。
  Future<void> _openLoginMethods() async {
    final auth = widget.auth;
    final verify = widget.verify;
    if (auth == null || verify == null) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: 'music/login-methods'),
        builder: (_) => MusicLoginMethodsPage(
          auth: auth,
          verify: verify,
          searchExt: widget.searchExt,
        ),
      ),
    );
    if (result != true || !mounted) return;
    await _reloadIdentity();
    _showSnack('登录成功');
  }

  /// push 安全验证页（事件号查挑战 + sideDt 提交）。
  Future<void> _openSecurityVerify() async {
    final verify = widget.verify;
    if (verify == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'music/security-verify'),
        builder: (_) => MusicSecurityVerifyPage(
          verify: verify,
          searchExt: widget.searchExt,
        ),
      ),
    );
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
        // ── L5 登录扩展 ──
        if (widget.auth != null && widget.verify != null)
          ListTile(
            leading: const Icon(Icons.login),
            title: const Text('更多登录方式'),
            subtitle: const Text('手机号验证码 / QQ / 微信 / 登录设备管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openLoginMethods,
          ),
        if (widget.verify != null)
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('安全验证'),
            subtitle: const Text('按事件号查询验证挑战并提交验证码'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openSecurityVerify,
          ),
        if (widget.settings != null)
          SwitchListTile(
            secondary: const Icon(Icons.graphic_eq),
            title: const Text('听歌上报'),
            subtitle: Text(
              _listenReport == null ? '正在读取本地设置…' : '播放歌曲时上报听歌记录（可在本地关闭）',
            ),
            value: _listenReport ?? false,
            // 读盘完成前禁用，避免用默认值覆盖真实偏好。
            onChanged: _listenReport == null ? null : _toggleListenReport,
          ),
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
    return AlertDialog(
      title: const Text('扫码登录'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            QrCodeImage(
              dataUrl: session?.imageDataUrl,
              phase: _controller.phase,
            ),
            const SizedBox(height: 12),
            Text(
              qrLoginStatusText(_controller),
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
