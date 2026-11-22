// ignore_for_file: deprecated_member_use — 与 shell/漫画各页同款说明（Flutter 3.50 弃用整个 material.dart）。
/// 浏览器验证（Cloudflare / 站方 gatekeeper）的内嵌 WebView 实现。
///
/// 把被拦的 URL 交给 WebView，等站点自己下发通过凭证（Cloudflare 是
/// `cf_clearance`，gatekeeper 是 `__Host-gk_clearance_*`），然后把该 URL 的
/// 全部 Cookie + WebView UA 交给 [ComicWebClient] 重试。用户取消/超时返回
/// null，调用方保留原 403。
///
/// 有些站点按 TLS 指纹拦抓取器、却直接放行真实浏览器引擎：WebView 加载
/// 被拦 URL 时根本不出现挑战页、也不会生成凭证 Cookie，干等只会超时。这
/// 种情况下页面会转入「无挑战快速通过」：确认 WebView 停在无挑战特征的
/// 页面上后，把渲染后的正文连同 Cookie / UA 一起作为
/// [ComicChallengePass.fetchedBody] 返回，调用方在重试仍被拦时直接采用。
///
/// 读 Cookie 的方式按平台分：
/// - Windows 走当前 WebView 的 DevTools `Network.getCookies`（HttpOnly 也能读到，
///   且不受 WebView2 环境实例影响——实测 CookieManager 会读到另一个 Cookie 库）；
/// - Android 走 `CookieManager`。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../request/challenge.dart';

/// 用 `NavigatorState` 打开验证页；navigator 为 null（壳未就绪）时放弃。
///
/// 同一主机的并发挑战经 [ComicChallengeCoordinator] 合并成一次弹页：页面
/// 加载会同时打出多个被拦请求，各弹各的话，用户关一页就弹出一页。
class ComicChallengeWebViewSolver implements ComicChallengeSolver {
  ComicChallengeWebViewSolver({required this.navigatorProvider});

  final NavigatorState? Function() navigatorProvider;

  /// 每主机的合并与取消冷却（生产一个 solver 实例贯穿全程）。
  final ComicChallengeCoordinator coordinator = ComicChallengeCoordinator();

  @override
  Future<ComicChallengePass?> solve(ComicChallenge challenge) {
    final navigator = navigatorProvider();
    if (navigator == null) return Future<ComicChallengePass?>.value();
    return coordinator.join(challenge.url.host, () async {
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
    });
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

  /// 「无挑战快速通过」的观察期：页面无挑战特征需要持续这么久才算过，
  /// 给站点 JS 留下发凭证 Cookie / 跳回原页的时间，避免把正在初始化的
  /// 挑战页误判成放行。
  static const Duration _cleanGrace = Duration(seconds: 3);

  InAppWebViewController? _controller;
  Timer? _poll;
  DateTime? _deadline;
  bool _checking = false;
  bool _finished = false;
  bool _timedOut = false;
  String? _error;

  /// WebView 当前地址（重定向后）与最近一次无挑战特征的起点；null 表示
  /// 尚未观察到无特征页面（或又出现了挑战特征）。
  String? _currentUrl;
  DateTime? _cleanSince;

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
      final probe = await _probePage();
      _noteProbe(probe);
      final cookiePassed = cookies.any(_isPassedCookie);
      final cleanReady = _cleanSince != null &&
          DateTime.now().difference(_cleanSince!) >= _cleanGrace &&
          _sameHost(probe?.href);
      if (!cookiePassed && !cleanReady) return;
      if (!mounted || _finished) return;
      _finished = true;
      _poll?.cancel();
      final userAgent = await _readUserAgent();
      // 页面已是真实内容时顺手带回正文：站点若只放行浏览器（TLS 指纹被
      // 拦），重试注定 403，调用方直接采用这份正文。
      final fetchedBody = cleanReady ? await _captureBody() : null;
      if (!mounted) return;
      Navigator.of(context).pop(
        ComicChallengePass(
          cookies: cookies,
          userAgent: userAgent,
          fetchedBody: fetchedBody,
        ),
      );
    } on Object catch (error) {
      if (mounted && !_finished) setState(() => _error = error.toString());
    } finally {
      _checking = false;
    }
  }

  /// WebView 当前页的挑战特征探针；eval 失败（导航瞬间）返回 null 下轮再试。
  Future<_PageProbe?> _probePage() async {
    final controller = _controller;
    if (controller == null) return null;
    final Object? raw;
    try {
      raw = await controller.evaluateJavascript(source: r'''
(() => {
  try {
    return JSON.stringify({
      cf: !!window._cf_chl_opt,
      cfTitle: /just a moment|attention required/i.test(String(document.title || '')),
      gk: String(document.documentElement.innerHTML).indexOf('__gatekeeper_challenge') >= 0,
      href: String(location.href),
    });
  } catch (e) { return JSON.stringify({error: String(e)}); }
})()
''');
    } on Object {
      return null;
    }
    final decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is! Map) return null;
    return _PageProbe(
      challenged:
          decoded['cf'] == true ||
          decoded['cfTitle'] == true ||
          decoded['gk'] == true ||
          decoded['error'] != null,
      href: decoded['href']?.toString(),
    );
  }

  /// 记录探针结果：无挑战特征从现在起算观察期；出现特征则重置。
  void _noteProbe(_PageProbe? probe) {
    if (probe == null || probe.challenged) {
      _cleanSince = null;
      return;
    }
    _cleanSince ??= DateTime.now();
    if (probe.href != null && probe.href!.isNotEmpty) _currentUrl = probe.href;
  }

  bool _sameHost(String? href) {
    if (href == null || href.isEmpty) return false;
    final uri = Uri.tryParse(href);
    if (uri == null || !uri.hasScheme) return false;
    return uri.host.toLowerCase() == widget.challenge.url.host.toLowerCase();
  }

  /// 抓当前页渲染后的正文（无挑战快速通过路径）。
  Future<ComicChallengeFetchedBody?> _captureBody() async {
    final controller = _controller;
    if (controller == null) return null;
    try {
      final html = await controller.evaluateJavascript(
        source: 'document.documentElement.outerHTML',
      );
      if (html == null || html.toString().isEmpty) return null;
      return ComicChallengeFetchedBody(
        statusCode: HttpStatus.ok,
        url: _currentUrl ?? widget.challenge.url.toString(),
        headers: const <String, String>{
          'content-type': 'text/html; charset=utf-8',
        },
        body: html.toString(),
      );
    } on Object {
      return null;
    }
  }

  /// 该类型的通过凭证是否已出现。
  bool _isPassedCookie(ComicChallengeCookie cookie) {
    if (cookie.value.isEmpty) return false;
    return isChallengeCredentialCookie(widget.challenge.kind, cookie.name);
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

/// 一次页面探针的结果。
class _PageProbe {
  const _PageProbe({required this.challenged, this.href});

  /// 当前页是否仍是挑战页（Cloudflare / gatekeeper 特征）。
  final bool challenged;

  /// 当前地址（重定向后）。
  final String? href;
}
