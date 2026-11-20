// ignore_for_file: deprecated_member_use — 与 shell/漫画各页同款说明（Flutter 3.50 弃用整个 material.dart）。
/// 浏览器验证（Cloudflare / 站方 gatekeeper）的内嵌 WebView 实现。
///
/// 把被拦的 URL 交给 WebView，等站点自己下发通过凭证（Cloudflare 是
/// `cf_clearance`，gatekeeper 是 `__Host-gk_clearance_*`），然后把该 URL 的
/// 全部 Cookie + WebView UA 交给 [ComicWebClient] 重试。用户取消/超时返回
/// null，调用方保留原 403。
///
/// 读 Cookie 的方式按平台分：
/// - Windows 走当前 WebView 的 DevTools `Network.getCookies`（HttpOnly 也能读到，
///   且不受 WebView2 环境实例影响——实测 CookieManager 会读到另一个 Cookie 库）；
/// - Android 走 `CookieManager`。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../request/challenge.dart';

/// 用 `NavigatorState` 打开验证页；navigator 为 null（壳未就绪）时放弃。
class ComicChallengeWebViewSolver implements ComicChallengeSolver {
  ComicChallengeWebViewSolver({required this.navigatorProvider});

  final NavigatorState? Function() navigatorProvider;

  @override
  Future<ComicChallengePass?> solve(ComicChallenge challenge) async {
    final navigator = navigatorProvider();
    if (navigator == null) return null;
    // 验证期间暂停源执行超时；求解器自身有 2 分钟上限，finally 一定释放。
    ComicChallengeGate.begin();
    try {
      return await navigator.push<ComicChallengePass>(
        MaterialPageRoute<ComicChallengePass>(
          fullscreenDialog: true,
          builder: (_) => _ChallengeVerifyPage(challenge: challenge),
        ),
      );
    } finally {
      ComicChallengeGate.end();
    }
  }
}

class _ChallengeVerifyPage extends StatefulWidget {
  const _ChallengeVerifyPage({required this.challenge});

  final ComicChallenge challenge;

  @override
  State<_ChallengeVerifyPage> createState() => _ChallengeVerifyPageState();
}

class _ChallengeVerifyPageState extends State<_ChallengeVerifyPage> {
  /// 轮询 Cookie 的间隔：挑战通过后 cookie 由 WebView 进程写入，只能轮询。
  static const Duration _pollInterval = Duration(milliseconds: 700);

  /// 等用户完成人机验证的上限。
  static const Duration _timeout = Duration(minutes: 2);

  InAppWebViewController? _controller;
  Timer? _poll;
  DateTime? _deadline;
  bool _checking = false;
  bool _finished = false;
  bool _timedOut = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _deadline = DateTime.now().add(_timeout);
    _poll = Timer.periodic(_pollInterval, (_) => unawaited(_check()));
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    if (_finished || _checking || !mounted) return;
    if (DateTime.now().isAfter(_deadline!)) {
      setState(() => _timedOut = true);
      _poll?.cancel();
      return;
    }
    _checking = true;
    try {
      final cookies = await _readCookies();
      if (!cookies.any(_isPassedCookie)) return;
      if (!mounted || _finished) return;
      _finished = true;
      _poll?.cancel();
      final userAgent = await _readUserAgent();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(ComicChallengePass(cookies: cookies, userAgent: userAgent));
    } on Object catch (error) {
      if (mounted && !_finished) setState(() => _error = error.toString());
    } finally {
      _checking = false;
    }
  }

  /// 该类型的通过凭证是否已出现。
  bool _isPassedCookie(ComicChallengeCookie cookie) {
    if (cookie.value.isEmpty) return false;
    switch (widget.challenge.kind) {
      case ComicChallengeKind.cloudflare:
        return cookie.name == 'cf_clearance';
      case ComicChallengeKind.gatekeeper:
        // baozi 等站方 gatekeeper：`__Host-gk_clearance_<hash>`。
        return cookie.name.contains('gk_clearance');
    }
  }

  /// 读当前 WebView 对 [widget.challenge.url] 可见的全部 Cookie。
  Future<List<ComicChallengeCookie>> _readCookies() async {
    final controller = _controller;
    if (controller == null) return const <ComicChallengeCookie>[];
    if (Platform.isWindows) {
      // DevTools 协议：与当前 WebView 同一 Cookie 库，含 HttpOnly。
      final result = await controller.callDevToolsProtocolMethod(
        methodName: 'Network.getCookies',
        parameters: <String, dynamic>{
          'urls': <String>[widget.challenge.url.toString()],
        },
      );
      final raw = result is Map ? result['cookies'] : null;
      if (raw is! List) return const <ComicChallengeCookie>[];
      final cookies = <ComicChallengeCookie>[];
      for (final item in raw) {
        final cookie = _fromCdp(item);
        if (cookie != null) cookies.add(cookie);
      }
      return cookies;
    }
    final cookies = await CookieManager.instance().getCookies(
      url: WebUri(widget.challenge.url.toString()),
      webViewController: controller,
    );
    return <ComicChallengeCookie>[
      for (final cookie in cookies)
        ComicChallengeCookie(
          name: cookie.name,
          value: cookie.value?.toString() ?? '',
          domain: cookie.domain,
          path: cookie.path ?? '/',
          expires: cookie.expiresDate == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(cookie.expiresDate!),
          secure: cookie.isSecure ?? false,
          httpOnly: cookie.isHttpOnly ?? false,
        ),
    ];
  }

  /// CDP `Network.getCookies` 的单个条目 → 契约类型。
  ComicChallengeCookie? _fromCdp(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name']?.toString() ?? '';
    final value = raw['value']?.toString() ?? '';
    if (name.isEmpty) return null;
    final expiresRaw = raw['expires'];
    final expires = expiresRaw is num && expiresRaw > 0
        ? DateTime.fromMillisecondsSinceEpoch((expiresRaw * 1000).round())
        : null;
    return ComicChallengeCookie(
      name: name,
      value: value,
      domain: raw['domain']?.toString(),
      path: raw['path']?.toString() ?? '/',
      expires: expires,
      secure: raw['secure'] == true,
      httpOnly: raw['httpOnly'] == true,
    );
  }

  Future<String?> _readUserAgent() async {
    try {
      final value = await _controller?.evaluateJavascript(
        source: 'navigator.userAgent',
      );
      return value?.toString();
    } on Object {
      return null;
    }
  }

  void _cancel() {
    if (_finished) return;
    _finished = true;
    _poll?.cancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('通过安全验证'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: '取消',
          onPressed: _cancel,
        ),
      ),
      body: Column(
        children: <Widget>[
          const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Text(
              _timedOut
                  ? '验证等待超时：可以继续操作页面，或关闭后重新搜索。'
                  : '站点要求先完成人机验证。页面通过后会自动返回并重试。',
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '验证页加载失败：$_error',
                style: theme.textTheme.bodySmall?.apply(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(widget.challenge.url.toString()),
              ),
              initialSettings: InAppWebViewSettings(
                // 挑战页通常需要第三方 Cookie 与 JS；默认值在 Android 上够用，
                // 这里显式打开对 Cloudflare 更稳。
                thirdPartyCookiesEnabled: true,
                javaScriptEnabled: true,
                useHybridComposition: true,
              ),
              onWebViewCreated: (controller) => _controller = controller,
              onLoadStop: (_, _) => unawaited(_check()),
              onReceivedError: (_, _, error) {
                if (mounted && !_finished) {
                  setState(() => _error = error.description);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
