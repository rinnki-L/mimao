// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 更多登录方式页（L5）：手机号验证码 / QQ 扫码 / 微信扫码 / 登录设备管理。
///
/// 页面只依赖 [MusicAuthApi] / [MusicVerifyApi] / [MusicSearchExtApi] 接口，
/// 不认识 dio 与信封细节。四个 tab 各自独立状态、独立计时器：
/// - 手机号：captchaSent 发码（倒计时总长可注入）→ loginCellphone；
///   撞上 34175（多账号）时展示候选列表，选中带 userId 重试；
/// - QQ：loginQqQrCreate 取码 → 周期轮询 loginQqQrCheck → provider_authorized
///   时 loginQq 并回身份；过期可刷新；
/// - 微信：loginWxCreate 取码 → 轮询 loginWxCheck → provider_code 时按
///   端点语义两步走：authorize 用授权码换 openid/access_token（纯 provider
///   HTTP，不写身份），finish 拿凭证走 openplat 登录（partner=36，并回身份）；
/// - 设备：loginDevice 列表 + loginDeviceKick（确认对话框，成功后刷新）。
///
/// 所有计时器在 dispose 取消（widget 测试断言无 pending timer）；异步错误
/// 一律收口成页内文案 / SnackBar，不向 Flutter 抛未捕获异常。
///
/// [searchExt] 为预留参数：安全验证（sideDt 提交）由
/// `MusicSecurityVerifyPage` 使用；本页与设置页/登录闸门保持同一组参数形态，
/// 便于集成者按同一份 API 门面接线。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mimao/music/api/auth_login_api.dart';
import 'package:mimao/music/api/captcha_sent.dart';
import 'package:mimao/music/api/login_cellphone.dart';
import 'package:mimao/music/api/login_device_kick.dart';
import 'package:mimao/music/api/login_openplat.dart';
import 'package:mimao/music/api/search_ext_api.dart';
import 'package:mimao/music/api/verify_api.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/auth_models.dart';
import 'package:mimao/music/pages/qr_login_controller.dart';
import 'package:mimao/music/pages/qr_login_view.dart';

/// 更多登录方式页。
class MusicLoginMethodsPage extends StatefulWidget {
  const MusicLoginMethodsPage({
    super.key,
    required this.auth,
    required this.verify,
    this.searchExt,
    this.pollInterval = const Duration(seconds: 2),
    this.codeCountdown = const Duration(seconds: 60),
    this.initialTab = 0,
  }) : assert(initialTab >= 0 && initialTab < 4, '登录 tab 越界');

  final MusicAuthApi auth;

  /// 发码端点组（手机号 tab 的「发送验证码」）。
  final MusicVerifyApi verify;

  /// 预留（见文件头注释）；null 不影响本页任何功能。
  final MusicSearchExtApi? searchExt;

  /// QQ/微信扫码轮询间隔（生产默认 2 秒，测试注入短间隔）。
  final Duration pollInterval;

  /// 验证码发送后的冷却总时长（生产默认 60 秒，测试注入短时长便于 pump 到 0）。
  final Duration codeCountdown;

  /// 初始 tab：0 手机号 / 1 QQ / 2 微信 / 3 登录设备。登录首屏按需直达。
  final int initialTab;

  @override
  State<MusicLoginMethodsPage> createState() => _MusicLoginMethodsPageState();
}

class _MusicLoginMethodsPageState extends State<MusicLoginMethodsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 4,
    vsync: this,
    initialIndex: widget.initialTab,
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('更多登录方式'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const <Tab>[
            Tab(text: '手机号'),
            Tab(text: 'QQ扫码'),
            Tab(text: '微信扫码'),
            Tab(text: '登录设备'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: <Widget>[
          _PhoneLoginTab(
            auth: widget.auth,
            verify: widget.verify,
            codeCountdown: widget.codeCountdown,
          ),
          _QqQrLoginTab(auth: widget.auth, pollInterval: widget.pollInterval),
          _WxQrLoginTab(auth: widget.auth, pollInterval: widget.pollInterval),
          _DeviceTab(auth: widget.auth),
        ],
      ),
    );
  }
}

/// 错误文案：KugouApiException 用服务端中文 message，其它异常给网络兜底话术。
String _messageOf(Object error) {
  if (error is KugouApiException) {
    final message = error.message.trim();
    if (message.isNotEmpty) return message;
  }
  return '网络异常，请稍后重试';
}

// ── 手机号验证码登录 ────────────────────────────────────────────────────────

class _PhoneLoginTab extends StatefulWidget {
  const _PhoneLoginTab({
    required this.auth,
    required this.verify,
    required this.codeCountdown,
  });

  final MusicAuthApi auth;
  final MusicVerifyApi verify;
  final Duration codeCountdown;

  @override
  State<_PhoneLoginTab> createState() => _PhoneLoginTabState();
}

class _PhoneLoginTabState extends State<_PhoneLoginTab> {
  final TextEditingController _mobile = TextEditingController();
  final TextEditingController _code = TextEditingController();

  /// 冷却倒计时（每秒一跳）；dispose 必须取消。
  Timer? _countdown;
  int _remainSeconds = 0;

  bool _sending = false;
  bool _loggingIn = false;

  /// 34175 多账号候选；非空时展示选择列表。
  List<MusicLoginCandidate> _candidates = const <MusicLoginCandidate>[];

  /// 登录失败的页内提示（不弹 SnackBar，便于重试时留在原处）。
  String? _error;

  @override
  void dispose() {
    _countdown?.cancel();
    _mobile.dispose();
    _code.dispose();
    super.dispose();
  }

  /// 发码成功后的冷却倒计时（总长 = codeCountdown；每秒一跳，到 0 可重发）。
  /// 总长不足 1 秒视为无冷却（测试兜底，生产默认 60 秒）。
  void _startCountdown() {
    _countdown?.cancel();
    final int seconds = widget.codeCountdown.inSeconds;
    if (seconds <= 0) return;
    setState(() => _remainSeconds = seconds);
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remainSeconds -= 1;
        if (_remainSeconds <= 0) {
          _remainSeconds = 0;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _sendCode() async {
    final mobile = _mobile.text.trim();
    // 本地先按端点同口径校验，避免无效请求。
    if (!validMobile(mobile)) {
      _showSnack('请输入正确的 11 位手机号码');
      return;
    }
    setState(() => _sending = true);
    try {
      await widget.verify.captchaSent(MusicCaptchaSentQuery(mobile: mobile));
      if (!mounted) return;
      _startCountdown();
      _showSnack('验证码已发送，请查收');
    } on Object catch (error) {
      if (!mounted) return;
      _showSnack(_messageOf(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// 登录（[userId] 为 34175 候选重试时指定）。
  Future<void> _login({int? userId}) async {
    final mobile = _mobile.text.trim();
    final code = _code.text.trim();
    if (mobile.isEmpty || code.isEmpty) {
      setState(() => _error = '请输入手机号码和验证码');
      return;
    }
    setState(() {
      _loggingIn = true;
      _error = null;
    });
    try {
      final result = await widget.auth.loginCellphone(
        MusicCellphoneQuery(mobile: mobile, code: code, userId: userId),
      );
      if (!mounted) return;
      if (result.authorization != null) {
        // 登录成功（账号已由门面并回本地身份）。
        Navigator.of(context).pop(true);
        return;
      }
      // 34175：该手机号下有多个账号，展示候选等待用户选择。
      setState(() {
        _candidates = result.candidates;
        _loggingIn = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loggingIn = false;
        _error = _messageOf(error);
      });
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool cooling = _remainSeconds > 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        TextField(
          controller: _mobile,
          keyboardType: TextInputType.phone,
          maxLength: 11,
          decoration: const InputDecoration(
            labelText: '手机号',
            hintText: '11 位手机号码',
            counterText: '',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '验证码',
            hintText: '短信验证码',
            suffixIcon: TextButton(
              // 冷却中或发送中禁用；冷却结束可重发。
              onPressed: _sending || cooling ? null : _sendCode,
              child: Text(cooling ? '重新发送（$_remainSeconds s）' : '发送验证码'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _loggingIn ? null : () => _login(),
          child: _loggingIn
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('登录'),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            '登录失败：$_error',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        if (_candidates.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Text('该手机号下存在多个账号，请选择要登录的账号', style: theme.textTheme.titleSmall),
          for (final candidate in _candidates)
            ListTile(
              leading: candidate.avatarUrl.isEmpty
                  ? const CircleAvatar(child: Icon(Icons.person))
                  : CircleAvatar(
                      backgroundImage: NetworkImage(candidate.avatarUrl),
                      onBackgroundImageError: (_, __) {},
                    ),
              title: Text(candidate.nickname),
              subtitle: candidate.username.isEmpty
                  ? null
                  : Text('账号：${candidate.username}'),
              onTap: _loggingIn ? null : () => _login(userId: candidate.userId),
            ),
        ],
      ],
    );
  }
}

// ── 扫码登录（QQ / 微信共用骨架） ──────────────────────────────────────────

/// 扫码 tab 的阶段；映射到 [QrLoginPhase] 交给 [QrCodeImage] 渲染。
enum _QrPhase { loading, waiting, scanned, confirming, expired, failed }

QrLoginPhase _qrPhaseOf(_QrPhase phase) => switch (phase) {
  _QrPhase.loading => QrLoginPhase.loading,
  _QrPhase.waiting => QrLoginPhase.waiting,
  _QrPhase.scanned => QrLoginPhase.scanned,
  _QrPhase.confirming => QrLoginPhase.authorized,
  _QrPhase.expired => QrLoginPhase.expired,
  _QrPhase.failed => QrLoginPhase.failed,
};

/// QQ 扫码：create 取码 → 周期轮询 → provider_authorized 时 loginQq 并回身份。
class _QqQrLoginTab extends StatefulWidget {
  const _QqQrLoginTab({required this.auth, required this.pollInterval});

  final MusicAuthApi auth;
  final Duration pollInterval;

  @override
  State<_QqQrLoginTab> createState() => _QqQrLoginTabState();
}

class _QqQrLoginTabState extends State<_QqQrLoginTab> {
  _QrPhase _phase = _QrPhase.loading;
  MusicQqQrSession? _session;
  String? _error;

  Timer? _timer;
  bool _polling = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    // 离开 tab / 关闭页面都必须停表（测试断言无 pending timer）。
    _stopTimer();
    super.dispose();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// 取新码（首次 / 过期后刷新）。
  Future<void> _create() async {
    _stopTimer();
    final epoch = ++_epoch;
    setState(() {
      _phase = _QrPhase.loading;
      _error = null;
      _session = null;
    });
    try {
      final session = await widget.auth.loginQqQrCreate();
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _session = session;
        _phase = _QrPhase.waiting;
      });
      _timer = Timer.periodic(widget.pollInterval, (_) => _poll());
    } on Object catch (error) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _phase = _QrPhase.failed;
        _error = _messageOf(error);
      });
    }
  }

  Future<void> _poll() async {
    final session = _session;
    if (_timer == null || _polling || session == null) return;
    final epoch = _epoch;
    _polling = true;
    try {
      final result = await widget.auth.loginQqQrCheck(session);
      if (!mounted || epoch != _epoch) return;
      switch (result.state) {
        case MusicQqQrCheckResult.stateWaiting:
          setState(() => _phase = _QrPhase.waiting);
        case MusicQqQrCheckResult.stateScanned:
          setState(() => _phase = _QrPhase.scanned);
        case MusicQqQrCheckResult.stateExpired:
          _stopTimer();
          setState(() => _phase = _QrPhase.expired);
        case MusicQqQrCheckResult.stateProviderAuthorized:
          _stopTimer();
          setState(() => _phase = _QrPhase.confirming);
          final authorization = result.authorization;
          if (authorization == null) {
            _fail('登录凭证缺失，请刷新二维码重试');
            return;
          }
          // provider 已授权：用凭证走酷狗登录并回身份。
          try {
            await widget.auth.loginQq(authorization);
            if (!mounted || epoch != _epoch) return;
            Navigator.of(context).pop(true);
          } on Object catch (error) {
            if (mounted && epoch == _epoch) _fail(_messageOf(error));
          }
      }
    } on Object catch (error) {
      if (mounted && epoch == _epoch) _fail(_messageOf(error));
    } finally {
      _polling = false;
    }
  }

  void _fail(String message) {
    _stopTimer();
    setState(() {
      _phase = _QrPhase.failed;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusText = switch (_phase) {
      _QrPhase.loading => '正在获取二维码…',
      _QrPhase.waiting => '等待扫码',
      _QrPhase.scanned => '已扫码，请在手机上确认',
      _QrPhase.confirming => '已授权，正在登录…',
      _QrPhase.expired => '二维码已过期，点击刷新',
      _QrPhase.failed => _error ?? '登录失败，请重试',
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          QrCodeImage(
            dataUrl: _session?.imageDataUrl,
            phase: _qrPhaseOf(_phase),
          ),
          const SizedBox(height: 16),
          Text(
            'QQ 扫码登录',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            statusText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // 过期/失败后允许重新取码；轮询期间按钮隐藏（无刷新语义）。
          if (_phase == _QrPhase.expired || _phase == _QrPhase.failed)
            OutlinedButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新二维码'),
            ),
        ],
      ),
    );
  }
}

/// 微信扫码：create 取码 → 轮询 → provider_code → authorize 换凭证 →
/// finish 登录（两步语义见 login_openplat.dart 端点注释）。
class _WxQrLoginTab extends StatefulWidget {
  const _WxQrLoginTab({required this.auth, required this.pollInterval});

  final MusicAuthApi auth;
  final Duration pollInterval;

  @override
  State<_WxQrLoginTab> createState() => _WxQrLoginTabState();
}

class _WxQrLoginTabState extends State<_WxQrLoginTab> {
  _QrPhase _phase = _QrPhase.loading;
  MusicWxSession? _session;
  String? _error;

  Timer? _timer;
  bool _polling = false;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _create() async {
    _stopTimer();
    final epoch = ++_epoch;
    setState(() {
      _phase = _QrPhase.loading;
      _error = null;
      _session = null;
    });
    try {
      final session = await widget.auth.loginWxCreate();
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _session = session;
        _phase = _QrPhase.waiting;
      });
      _timer = Timer.periodic(widget.pollInterval, (_) => _poll());
    } on Object catch (error) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _phase = _QrPhase.failed;
        _error = _messageOf(error);
      });
    }
  }

  Future<void> _poll() async {
    final session = _session;
    if (_timer == null || _polling || session == null) return;
    final epoch = _epoch;
    _polling = true;
    try {
      final result = await widget.auth.loginWxCheck(session.key);
      if (!mounted || epoch != _epoch) return;
      switch (result.state) {
        case MusicWxCheckResult.stateWaiting:
          setState(() => _phase = _QrPhase.waiting);
        case MusicWxCheckResult.stateScanned:
          setState(() => _phase = _QrPhase.scanned);
        case MusicWxCheckResult.stateExpired:
          _stopTimer();
          setState(() => _phase = _QrPhase.expired);
        case MusicWxCheckResult.stateProviderCode:
          _stopTimer();
          final code = result.code;
          if (code == null || code.isEmpty) {
            _fail('微信授权码缺失，请刷新二维码重试');
            return;
          }
          await _finishLogin(code, epoch);
      }
    } on Object catch (error) {
      if (mounted && epoch == _epoch) _fail(_messageOf(error));
    } finally {
      _polling = false;
    }
  }

  /// 两步登录（端点注释原语义）：
  /// 1. authorize：授权码换 openid/access_token（纯 provider HTTP，不写身份）；
  /// 2. finish：凭证走 /v6/login_by_openplat（partner=36）并回身份。
  Future<void> _finishLogin(String code, int epoch) async {
    setState(() => _phase = _QrPhase.confirming);
    try {
      final provider = await widget.auth.loginOpenplat(
        MusicOpenplatQuery.authorize(code),
      );
      if (!mounted || epoch != _epoch) return;
      if (provider is! MusicProviderAuthorization) {
        _fail('微信授权响应无效，请刷新二维码重试');
        return;
      }
      final login = await widget.auth.loginOpenplat(
        MusicOpenplatQuery.finish(provider),
      );
      if (!mounted || epoch != _epoch) return;
      if (login is! MusicLoginAuthorization) {
        _fail('微信登录响应无效，请刷新二维码重试');
        return;
      }
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (mounted && epoch == _epoch) _fail(_messageOf(error));
    }
  }

  void _fail(String message) {
    _stopTimer();
    setState(() {
      _phase = _QrPhase.failed;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusText = switch (_phase) {
      _QrPhase.loading => '正在获取二维码…',
      _QrPhase.waiting => '等待扫码',
      _QrPhase.scanned => '已扫码，请在手机上确认',
      _QrPhase.confirming => '已确认，正在登录…',
      _QrPhase.expired => '二维码已过期，点击刷新',
      _QrPhase.failed => _error ?? '登录失败，请重试',
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: <Widget>[
          QrCodeImage(
            dataUrl: _session?.imageDataUrl,
            phase: _qrPhaseOf(_phase),
          ),
          const SizedBox(height: 16),
          Text(
            '微信扫码登录',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            statusText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (_phase == _QrPhase.expired || _phase == _QrPhase.failed)
            OutlinedButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.refresh),
              label: const Text('刷新二维码'),
            ),
        ],
      ),
    );
  }
}

// ── 登录设备管理 ────────────────────────────────────────────────────────────

enum _DevicePhase { loading, error, ready }

class _DeviceTab extends StatefulWidget {
  const _DeviceTab({required this.auth});

  final MusicAuthApi auth;

  @override
  State<_DeviceTab> createState() => _DeviceTabState();
}

class _DeviceTabState extends State<_DeviceTab> {
  _DevicePhase _phase = _DevicePhase.loading;
  List<MusicLoginDevice> _devices = const <MusicLoginDevice>[];

  /// 列表加载失败原因（匿名/登录过期时给登录引导文案）。
  Object? _loadError;

  /// 正在踢出的设备 mid（防重复提交）。
  String? _kickingMid;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _phase = _DevicePhase.loading);
    try {
      final devices = await widget.auth.loginDevice();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _phase = _DevicePhase.ready;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _phase = _DevicePhase.error;
      });
    }
  }

  Future<void> _kick(MusicLoginDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除登录设备'),
        content: Text('确定移除「${device.model}」吗？移除后该设备需要重新登录。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _kickingMid = device.id);
    try {
      await widget.auth.loginDeviceKick(
        MusicDeviceKickQuery(
          targetMid: device.id,
          activeAtSeconds: device.activeAtSeconds ?? 0,
          appId: device.appId ?? 0,
          clientVersion: device.clientVersion ?? 0,
          transportFingerprint: device.transportFingerprint,
        ),
      );
      if (!mounted) return;
      setState(() => _kickingMid = null);
      _showSnack('设备已移除');
      // 成功后刷新列表（服务端移除后本地列表必须同步）。
      await _reload();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _kickingMid = null);
      _showSnack(_messageOf(error));
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (_phase) {
      case _DevicePhase.loading:
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      case _DevicePhase.error:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(_deviceErrorText(), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _reload, child: const Text('重试')),
            ],
          ),
        );
      case _DevicePhase.ready:
        if (_devices.isEmpty) {
          return const Center(child: Text('暂无登录设备'));
        }
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '当前设备优先显示；移除其它设备后，该设备需要重新登录。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final device in _devices) _buildRow(device),
          ],
        );
    }
  }

  /// 设备列表错误文案：匿名/登录过期给登录引导，其它用服务端话术。
  String _deviceErrorText() {
    final error = _loadError;
    if (error is KugouApiException && error.kind == 'authentication') {
      return '请先登录酷狗账号，登录后即可管理登录设备';
    }
    return error == null ? '设备列表加载失败' : _messageOf(error);
  }

  Widget _buildRow(MusicLoginDevice device) {
    final theme = Theme.of(context);
    final bool current = device.current;
    // 端点校验要求 activeAt/appid/clientver 齐备；缺信息的设备不可移除。
    final bool kickable =
        !current &&
        (device.activeAtSeconds ?? 0) != 0 &&
        (device.appId ?? 0) != 0 &&
        (device.clientVersion ?? 0) != 0;
    final String? activeAt = _formatActiveTime(device.activeAtSeconds);
    return ListTile(
      leading: Icon(current ? Icons.phone_iphone : Icons.devices_other),
      title: Text(
        device.model.isEmpty ? '未知设备' : device.model,
        style: current
            ? theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              )
            : null,
      ),
      subtitle: Text(
        <String>[
          if (device.platform.isNotEmpty) device.platform,
          if (device.location.isNotEmpty) device.location,
          if (activeAt != null) '活跃于 $activeAt',
        ].join(' · '),
      ),
      trailing: current
          ? const Text('当前设备')
          : TextButton(
              onPressed: kickable && _kickingMid != device.id
                  ? () => _kick(device)
                  : null,
              child: _kickingMid == device.id
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('移除'),
            ),
    );
  }

  String? _formatActiveTime(int? seconds) {
    if (seconds == null || seconds <= 0) return null;
    final time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
