// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 进入音乐模块时的登录闸门（L 线）。
///
/// 用户拍板：**未登录时每次点进音乐都全屏弹出扫码登录，且可跳过**。
/// - 已登录（身份含 token/userid）→ 直进主页；
/// - 匿名/无身份 → push 全屏 [QrLoginScreen]；跳过或授权都 pop 回主页。
/// - [account] 为 null（未接线/测试）→ 纯透传，不改变既有行为。
///
/// 闸门放在模块出口（MusicModule.buildHome）而非壳层：壳对模块无感知，
/// 登录是音乐自己的事。每次重新进入模块都会新建本 widget、重新判定，
/// 因此「未登录每次进入都弹」由生命周期自然保证。
library;

import 'package:flutter/material.dart';
import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/pages/qr_login_view.dart';

class MusicLoginGate extends StatefulWidget {
  const MusicLoginGate({
    super.key,
    required this.api,
    required this.account,
    required this.child,
    this.pollInterval = const Duration(seconds: 2),
  });

  final MusicApi api;

  /// 登录门面；null 时纯透传（登录功能未接线）。
  final MusicAccountApi? account;

  /// 登录成功后要回到的音乐主页。
  final Widget child;

  /// 扫码轮询间隔（生产默认 2 秒）。
  final Duration pollInterval;

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
