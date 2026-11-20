// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 扫码登录的共享 UI：二维码图片 + 阶段文案 + 全屏登录页。
///
/// 两处复用同一套二维码渲染与轮询控制器：
/// - 设置页账号区的扫码对话框（既有入口，便于重新登录）；
/// - 进入音乐入口、匿名态弹出的全屏页（用户拍板：可跳过 / 每次进入都弹）。
///
/// 控制器本身在 [QrLoginController] 里、不依赖 Flutter；本文件只负责展示。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/pages/qr_login_controller.dart';

/// 全屏扫码登录页：进入音乐模块且匿名时由模块出口 push。
///
/// 授权成功 pop 回 [KugouIdentity]；点「稍后再说」跳过（匿名功能不受影响）。
class QrLoginScreen extends StatefulWidget {
  const QrLoginScreen({
    super.key,
    required this.account,
    this.pollInterval = const Duration(seconds: 2),
  });

  final MusicAccountApi account;
  final Duration pollInterval;

  @override
  State<QrLoginScreen> createState() => _QrLoginScreenState();
}

class _QrLoginScreenState extends State<QrLoginScreen> {
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
    // 关闭/授权/跳过都必须停表：widget 测试会断言无 pending timer。
    _controller.dispose();
    super.dispose();
  }

  void _skip() {
    _closed = true;
    _controller.cancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = _controller.session;
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
                  dataUrl: session?.imageDataUrl,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 二维码图片：加载中 / 解析失败给占位，不把异常抛进 build。
class QrCodeImage extends StatelessWidget {
  const QrCodeImage({super.key, required this.dataUrl, required this.phase});

  /// 服务端给的 PNG data URL（或纯 base64）；null 表示还没取到码。
  final String? dataUrl;
  final QrLoginPhase phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (phase == QrLoginPhase.loading) {
      return const SizedBox(
        width: 220,
        height: 220,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final url = dataUrl;
    final bytes = url == null ? null : decodeQrImageData(url);
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

/// 登录阶段文案（对话框与全屏页共用）。
String qrLoginStatusText(QrLoginController controller) =>
    switch (controller.phase) {
      QrLoginPhase.idle || QrLoginPhase.loading => '正在获取二维码…',
      QrLoginPhase.waiting => '等待扫码',
      QrLoginPhase.scanned => '已扫码，请在手机上确认',
      QrLoginPhase.authorized => '登录成功',
      QrLoginPhase.expired => '二维码已过期，点击刷新',
      QrLoginPhase.failed => controller.error ?? '登录失败，请重试',
    };
