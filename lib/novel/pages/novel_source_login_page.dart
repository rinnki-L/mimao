// ignore_for_file: deprecated_member_use — 与其他小说页面同款 Flutter 3.50 说明。
/// 书源登录取 Cookie：打开内置 WebView 让用户登录站点，把 Cookie 写回书源。
///
/// 用法（编辑器/调试面板的「登录取 Cookie」按钮）：
///   1. push 本页，用户在内嵌 WebView 里登录；
///   2. 点「取 Cookie 并返回」→ 页面读出当前域 Cookie；
///   3. 调用方把 `Cookie: …` 合并进书源 `header` 的 JSON 里再落库。
///
/// 接口形态对齐上游 legado 的「登录 + 取 Cookie」：桌面端走应用内页面（不移植
/// Android 的 WebSocket 服务），Android 复用同一个页面与同一个返回契约。
/// 测试可注入 [webViewBuilder] 绕开 native 插件。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// 取 Cookie 的结果。
class NovelLoginCookieResult {
  const NovelLoginCookieResult({required this.cookieHeader, required this.url});

  /// `k1=v1; k2=v2` 形式（直接可拼进 `Cookie` 请求头）。
  final String cookieHeader;

  /// 取 Cookie 时所在的页面地址（决定 Cookie 归属域）。
  final String url;

  bool get isEmpty => cookieHeader.trim().isEmpty;
}

/// 打开登录取 Cookie 页；用户取消返回 null。
Future<NovelLoginCookieResult?> showNovelLoginCookiePage(
  BuildContext context, {
  required String url,
  required String title,
  Widget Function(
    BuildContext context,
    Future<NovelLoginCookieResult?> Function() readCookie,
  )?
  webViewBuilder,
}) {
  return Navigator.of(context).push<NovelLoginCookieResult>(
    MaterialPageRoute<NovelLoginCookieResult>(
      settings: const RouteSettings(name: 'novel/source-login'),
      builder: (_) => NovelSourceLoginPage(
        url: url,
        title: title,
        webViewBuilder: webViewBuilder,
      ),
    ),
  );
}

class NovelSourceLoginPage extends StatefulWidget {
  const NovelSourceLoginPage({
    super.key,
    required this.url,
    required this.title,
    this.webViewBuilder,
  });

  final String url;
  final String title;

  /// 测试注入缝：返回 WebView widget + 一个「读当前 Cookie」回调。
  final Widget Function(
    BuildContext context,
    Future<NovelLoginCookieResult?> Function() readCookie,
  )?
  webViewBuilder;

  @override
  State<NovelSourceLoginPage> createState() => _NovelSourceLoginPageState();
}

class _NovelSourceLoginPageState extends State<NovelSourceLoginPage> {
  InAppWebViewController? _controller;
  bool _reading = false;
  String? _error;

  /// 当前页面地址（取 Cookie 时用它做域，而不是登录页初始地址）。
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
  }

  Future<NovelLoginCookieResult?> _readCookie() async {
    final controller = _controller;
    if (controller == null) {
      setState(() => _error = 'WebView 还没就绪');
      return null;
    }
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(_currentUrl.isEmpty ? widget.url : _currentUrl),
      );
      final header = <String>[
        for (final cookie in cookies)
          if (cookie.name.isNotEmpty) '${cookie.name}=${cookie.value}',
      ].join('; ');
      if (!mounted) return null;
      if (header.isEmpty) {
        setState(() {
          _reading = false;
          _error = '当前页面没有 Cookie；先在这个 WebView 里完成登录，再点取 Cookie。';
        });
        return null;
      }
      return NovelLoginCookieResult(cookieHeader: header, url: _currentUrl);
    } on Object catch (error) {
      if (!mounted) return null;
      setState(() {
        _reading = false;
        _error = '读取 Cookie 失败：$error';
      });
      return null;
    }
  }

  Future<void> _confirmAndPop() async {
    final result = await _readCookie();
    if (result == null || !mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final builder = widget.webViewBuilder;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          FilledButton.icon(
            key: const Key('novel-source-login-cookie'),
            onPressed: _reading ? null : _confirmAndPop,
            icon: _reading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cookie_outlined, size: 18),
            label: const Text('取 Cookie 并返回'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            color: cs.surfaceContainerHighest.withValues(alpha: .5),
            child: Text(
              '在这里登录书源站点；登录完成后点右上角「取 Cookie 并返回」，'
              'Cookie 会写进书源的请求头。Cookie 只存在本机。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _error!,
                key: const Key('novel-source-login-error'),
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ),
          Expanded(
            child: builder != null
                ? builder(context, _readCookie)
                : _RealLoginWebView(
                    url: widget.url,
                    onCreated: (controller) => _controller = controller,
                    onUrlChanged: (url) {
                      if (url.isNotEmpty) _currentUrl = url;
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RealLoginWebView extends StatelessWidget {
  const _RealLoginWebView({
    required this.url,
    required this.onCreated,
    required this.onUrlChanged,
  });

  final String url;
  final void Function(InAppWebViewController controller) onCreated;
  final void Function(String url) onUrlChanged;

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useHybridComposition: true,
        supportMultipleWindows: false,
      ),
      onWebViewCreated: onCreated,
      onLoadStop: (_, pageUrl) => onUrlChanged(pageUrl?.toString() ?? ''),
      onUpdateVisitedHistory: (_, pageUrl, _) =>
          onUrlChanged(pageUrl?.toString() ?? ''),
    );
  }
}

/// 把 `Cookie: …` 合并进书源 `header`（JSON 对象文本）。
///
/// 已有同名 Cookie 头则替换，没有则追加；`header` 为空/非法时给出新对象文本。
/// 纯函数，编辑器与调试面板共用，可单测。
String mergeNovelCookieIntoHeader(String headerJson, String cookieHeader) {
  final trimmedCookie = cookieHeader.trim();
  if (trimmedCookie.isEmpty) return headerJson;
  final parsed = _tryParseHeader(headerJson);
  if (parsed == null) {
    // 原 header 不是合法 JSON 对象：保留原文并提示用户自行处理（不静默丢）。
    return headerJson;
  }
  parsed['Cookie'] = trimmedCookie;
  return _encodeHeader(parsed);
}

Map<String, dynamic>? _tryParseHeader(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return null;
  } on Object {
    return null;
  }
}

String _encodeHeader(Map<String, dynamic> map) => jsonEncode(map);
