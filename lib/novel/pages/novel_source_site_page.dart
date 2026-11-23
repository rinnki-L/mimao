// ignore_for_file: deprecated_member_use — 与其他小说页面同款 Flutter 3.50 说明。
/// 订阅站点页：满窗口打开订阅源站点（如「喵公子书源管理」），拦截「一键导入」。
///
/// 从「规则管理 → 订阅源」点订阅站点卡片 push 进来，AppBar 带返回键，返回后
/// 规则管理页重新读取规则列表。站点里的 `yuedu://…importonline?src=…` 链接由
/// 注入的 JS 改道到 JS Handler，交给导入服务按深链类型下载落库；导入结果用
/// SnackBar 反馈。
///
/// WebView 只在本页构造；测试可注入 [webViewBuilder] 绕开 native 插件。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../source/novel_source_importer.dart';
import '../source/novel_source_model.dart' show parseNovelRuleLink;

class NovelSourceSitePage extends StatefulWidget {
  const NovelSourceSitePage({
    super.key,
    required this.title,
    required this.url,
    required this.importer,
    this.webViewBuilder,
  });

  final String title;
  final String url;
  final NovelSourceImporter importer;

  /// 测试注入缝：返回 WebView widget；null 时用真实 [InAppWebView]。
  final Widget Function(
    BuildContext context,
    void Function(String link) onImportLink,
  )?
  webViewBuilder;

  @override
  State<NovelSourceSitePage> createState() => _NovelSourceSitePageState();
}

class _NovelSourceSitePageState extends State<NovelSourceSitePage> {
  bool _importing = false;

  Future<void> _handleImportLink(String link) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final result = await widget.importer.importFromLink(link);
      if (!mounted) return;
      _toast(
        result.message ?? '已导入 ${result.saved} 条${result.kind.label}',
        error: false,
      );
    } on NovelSourceImportException catch (error) {
      if (mounted) _toast(error.message, error: true);
    } on Object catch (error) {
      if (mounted) _toast('导入失败：$error', error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _toast(String message, {required bool error}) {
    final theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? theme.colorScheme.errorContainer : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final builder = widget.webViewBuilder;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: _importing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: builder != null
          ? builder(context, _handleImportLink)
          : _RealSourceWebView(
              url: widget.url,
              onImportLink: _handleImportLink,
            ),
    );
  }
}

/// 真正的内嵌 WebView（仅桌面/移动端有插件的运行环境里被构造）。
class _RealSourceWebView extends StatefulWidget {
  const _RealSourceWebView({required this.url, required this.onImportLink});

  final String url;
  final void Function(String link) onImportLink;

  @override
  State<_RealSourceWebView> createState() => _RealSourceWebViewState();
}

class _RealSourceWebViewState extends State<_RealSourceWebView> {
  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(widget.url)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        useHybridComposition: true,
        // 不自动打开外部应用：深链由 shouldOverrideUrlLoading + JS handler 拦截。
        supportMultipleWindows: false,
      ),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: _kJsHandlerName,
          callback: (args) {
            if (args.isEmpty) return;
            final link = args.first?.toString();
            if (link != null && link.isNotEmpty) widget.onImportLink(link);
          },
        );
      },
      onLoadStop: (controller, _) =>
          unawaited(_injectLinkInterceptor(controller)),
      shouldOverrideUrlLoading: (controller, action) async {
        final url = action.request.url?.toString() ?? '';
        if (parseNovelRuleLink(url) != null) {
          widget.onImportLink(url);
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
    );
  }

  /// 注入脚本：给所有 `yuedu://` 的锚点挂 click 拦截，走 JS Handler 回传 Flutter。
  /// 站点是静态 HTML、不会重绘这些按钮，onLoadStop 注入一次足够；重复导航再注入
  /// 也幂等（用 dataset 标记防重复挂监听）。
  Future<void> _injectLinkInterceptor(InAppWebViewController controller) async {
    try {
      await controller.evaluateJavascript(
        source:
            '''
(function () {
  if (window.__mimaoSourceHookInstalled) return;
  window.__mimaoSourceHookInstalled = true;
  window.__mimaoOnImport = function (link) {
    if (window.flutter_inappwebview &&
        window.flutter_inappwebview.callHandler) {
      window.flutter_inappwebview.callHandler('$_kJsHandlerName', link);
    }
  };
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a') : null;
    if (a && a.href && a.href.indexOf('yuedu://') === 0) {
      e.preventDefault();
      window.__mimaoOnImport(a.href);
    }
  }, true);
})();
''',
      );
    } on Object catch (_) {
      // 注入失败不致命：shouldOverrideUrlLoading 仍是第二道防线。
    }
  }
}

const String _kJsHandlerName = 'mimaoSourceImport';
