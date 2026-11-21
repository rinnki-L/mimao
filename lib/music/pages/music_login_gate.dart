// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 进入音乐模块时的登录闸门（L 线 + L5 扩展）。
///
/// 用户拍板：**未登录时每次点进音乐都全屏弹出扫码登录，且可跳过**。
/// - 已登录（身份含 token/userid）→ 直进主页；
/// - 匿名/无身份 → push 全屏登录页；跳过或授权都 pop 回主页；
/// - L5：[auth]/[verify]/[searchExt] 三者齐备时 push 带有「使用其他方式登录」
///   的全屏登录页（复用扫码控制器与二维码组件，底部按钮进方法页）；
///   任一缺失时保持现状（push 原始 [QrLoginScreen]）。
/// - [account] 为 null（未接线/测试）→ 纯透传，不改变既有行为。
///
/// 闸门放在模块出口（MusicModule.buildHome）而非壳层：壳对模块无感知，
/// 登录是音乐自己的事。每次重新进入模块都会新建本 widget、重新判定，
/// 因此「未登录每次进入都弹」由生命周期自然保证。
library;

import 'package:flutter/material.dart';
import 'package:mimao/music/api/auth_login_api.dart';
import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/api/search_ext_api.dart';
import 'package:mimao/music/api/verify_api.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/pages/music_login_methods_page.dart';
import 'package:mimao/music/pages/qr_login_controller.dart';
import 'package:mimao/music/pages/qr_login_view.dart';

class MusicLoginGate extends StatefulWidget {
  const MusicLoginGate({
    super.key,
    required this.api,
    required this.account,
    required this.child,
    this.pollInterval = const Duration(seconds: 2),
    this.auth,
    this.verify,
    this.searchExt,
  });

  final MusicApi api;

  /// 登录门面；null 时纯透传（登录功能未接线）。
  final MusicAccountApi? account;

  /// 登录成功后要回到的音乐主页。
  final Widget child;

  /// 扫码轮询间隔（生产默认 2 秒）。
  final Duration pollInterval;

  /// L5 登录扩展门面；与 [verify] 齐备时扫码页提供「使用其他方式登录」。
  final MusicAuthApi? auth;

  /// L5 验证端点组（方法页的依赖）。
  final MusicVerifyApi? verify;

  /// L5 sidedt 提交通道（透传给方法页）。
  final MusicSearchExtApi? searchExt;

  @override
  State<MusicLoginGate> createState() => _MusicLoginGateState();
}

class _MusicLoginGateState extends State<MusicLoginGate> {
  @override
  void initState() {
    super.initState();
    // initState 里 context 还没挂到 Navigator 上，直接 push 会抛
    // 「Navigator.of() called with a context that does not contain a Navigator」。
    // 延到首帧后再判定/弹出。
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowLogin());
  }

  Future<void> _maybeShowLogin() async {
    final account = widget.account;
    if (account == null) return;

    KugouIdentity? identity;
    try {
      identity = await widget.api.currentIdentity();
    } on Object {
      // 读盘失败不挡进入：按「不弹」处理，避免抖动导致反复弹登录。
      return;
    }
    if (!mounted) return;
    // 已登录直进；匿名（含首次无身份）弹全屏登录。
    if (identity != null && identity.hasAccount) return;

    final auth = widget.auth;
    final verify = widget.verify;
    if (auth != null && verify != null) {
      // L5：扩展登录门面齐备 → 用带「使用其他方式登录」的全屏页。
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          settings: const RouteSettings(name: 'music/login'),
          builder: (_) => _GateLoginPage(
            account: account,
            auth: auth,
            verify: verify,
            searchExt: widget.searchExt,
            pollInterval: widget.pollInterval,
          ),
        ),
      );
      // 授权成功（任意方式）后身份已落盘；跳过则保持匿名。
      return;
    }

    await Navigator.of(context).push<KugouIdentity?>(
      MaterialPageRoute<KugouIdentity?>(
        fullscreenDialog: true,
        settings: const RouteSettings(name: 'music/login'),
        builder: (_) =>
            QrLoginScreen(account: account, pollInterval: widget.pollInterval),
      ),
    );
    // 授权成功后身份已落盘；本页无需重建，下次搜索自动带 token。
    // 跳过则保持匿名，用户仍可在设置页再次扫码。
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 闸门全屏登录页（L5）：结构与 [QrLoginScreen] 一致（扫码控制器 +
/// 二维码组件 + 状态文案），底部多一个「使用其他方式登录」文字按钮。
///
/// 不能直接在 QrLoginScreen 上叠按钮（那是既有扫码线文件，本切片不改动），
/// 故复用其公开部件（[QrLoginController]/[QrCodeImage]/[qrLoginStatusText]）
/// 在闸门文件内组装。成功路径 pop(true)：扫码授权或方法页登录成功均视为
/// 关闭闸门；「稍后再说」pop(null)。
class _GateLoginPage extends StatefulWidget {
  const _GateLoginPage({
    required this.account,
    required this.auth,
    required this.verify,
    required this.pollInterval,
    this.searchExt,
  });

  final MusicAccountApi account;
  final MusicAuthApi auth;
  final MusicVerifyApi verify;
  final MusicSearchExtApi? searchExt;
  final Duration pollInterval;

  @override
  State<_GateLoginPage> createState() => _GateLoginPageState();
}

class _GateLoginPageState extends State<_GateLoginPage> {
  late final QrLoginController _controller = QrLoginController(
    account: widget.account,
    pollInterval: widget.pollInterval,
    onChanged: () {
      if (!mounted) return;
      if (_controller.phase == QrLoginPhase.authorized) {
        // 扫码授权成功：身份已由控制器落盘，关闭闸门。
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {});
    },
  );

  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    // 跳过/授权/去方法页/关闭都必须停表：widget 测试会断言无 pending timer。
    _controller.dispose();
    super.dispose();
  }

  void _skip() {
    _closed = true;
    _controller.cancel();
    Navigator.of(context).pop();
  }

  /// 进「更多登录方式」：先停扫码轮询（避免方法页登录成功与本页扫码授权
  /// 双路 pop 竞态），返回未成功则恢复轮询。
  Future<void> _openMethods() async {
    _controller.cancel();
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => MusicLoginMethodsPage(
          auth: widget.auth,
          verify: widget.verify,
          searchExt: widget.searchExt,
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      if (!_closed) {
        _closed = true;
        Navigator.of(context).pop(true);
      }
      return;
    }
    _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录酷狗账号'),
        actions: <Widget>[
          TextButton(
            key: const Key('qr-login-skip'),
            onPressed: _skip,
            child: const Text('稍后再说'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                QrCodeImage(
                  dataUrl: _controller.session?.imageDataUrl,
                  phase: _controller.phase,
                ),
                const SizedBox(height: 16),
                Text(
                  qrLoginStatusText(_controller),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '扫码登录后可同步歌单与账号权限；不登录也能匿名搜索与试听。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _controller.phase == QrLoginPhase.loading
                      ? null
                      : _controller.refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新二维码'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('gate-open-methods'),
                  onPressed: _openMethods,
                  child: const Text('使用其他方式登录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
