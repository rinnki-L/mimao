// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 小说书源管理页：内嵌 WebView 打开书源网站 + 拦截「一键导入」深链 + 本地书源列表。
///
/// 用户在 WebView 里点网站的「一键导入」（`yuedu://booksource/importonline?src=…`），
/// 注入的 JS 把该链接改道到 JS Handler → Flutter 侧解析 src → 下载书源文件 →
/// 落本地书源仓库。整个过程不接管系统级 `yuedu://` 协议（不抢阅读 App 的协议），
/// 也不需要外部浏览器或 url_launcher 依赖。
///
/// WebView 只在用户主动点「打开书源网站」后构造，页面进场本身零插件调用——
/// 这样无插件测试环境也能渲染列表与按钮。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../source/novel_source_importer.dart';
import '../source/novel_source_model.dart';
import '../source/novel_source_store.dart' show NovelSourceStorage;
import 'novel_widgets.dart';

/// 打开书源网站页。由 NovelModule 出口接到 Navigator。
class NovelSourceManagePage extends StatefulWidget {
  const NovelSourceManagePage({
    super.key,
    required this.store,
    required this.importer,
    this.siteUrl = novelSourceSiteUrl,
    this.webViewBuilder,
  });

  final NovelSourceStorage store;
  final NovelSourceImporter importer;
  final String siteUrl;

  /// 测试注入缝：返回 WebView widget；null 时用真实 [InAppWebView]。
  final Widget Function(
    BuildContext context,
    void Function(String link) onImportLink,
  )?
  webViewBuilder;

  @override
  State<NovelSourceManagePage> createState() => _NovelSourceManagePageState();
}

class _NovelSourceManagePageState extends State<NovelSourceManagePage> {
  bool _showWeb = false;
  bool _importing = false;
  String? _status;
  String? _error;
  List<NovelBookSource> _sources = const <NovelBookSource>[];

  @override
  void initState() {
    super.initState();
    _reloadSources();
  }

  Future<void> _reloadSources() async {
    try {
      final sources = await widget.store.loadAll();
      if (mounted) setState(() => _sources = sources);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '读取书源失败：$error');
    }
  }

  /// 深链导入（WebView 或手动粘贴共用）。
  Future<void> _importLink(String link) async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _status = '正在导入书源…';
      _error = null;
    });
    try {
      final result = await widget.importer.importFromLink(link);
      await _reloadSources();
      if (mounted) {
        setState(() {
          _status = result.message ?? '已导入 ${result.saved} 个书源';
        });
      }
    } on NovelSourceImportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '导入失败：$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('书源管理'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新书源列表',
            onPressed: _reloadSources,
          ),
        ],
      ),
      body: NovelFillContent(
        maxWidth: 1100,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(theme),
            if (_showWeb) Expanded(child: _buildWebView()),
            Expanded(child: _buildSourceList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              FilledButton.icon(
                key: const Key('novel-source-open-site'),
                onPressed: () => setState(() => _showWeb = true),
                icon: const Icon(Icons.public),
                label: const Text('打开书源网站'),
              ),
              OutlinedButton.icon(
                key: const Key('novel-source-paste-import'),
                onPressed: _importing ? null : _showPasteDialog,
                icon: const Icon(Icons.link),
                label: const Text('粘贴书源链接导入'),
              ),
              if (_showWeb)
                TextButton.icon(
                  onPressed: () => setState(() => _showWeb = false),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('收起网页'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '打开网站后，点击页面里的「一键导入」，书源会自动下载并存入本应用；'
            '也可以直接粘贴书源文件地址。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          if (_importing)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(minHeight: 3),
            ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _status!,
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.primary),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWebView() {
    final builder = widget.webViewBuilder;
    final child = builder != null
        ? builder(context, _importLink)
        : _RealSourceWebView(url: widget.siteUrl, onImportLink: _importLink);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(clipBehavior: Clip.antiAlias, child: child),
    );
  }

  Widget _buildSourceList() {
    if (_sources.isEmpty) {
      return NovelEmptyState(
        icon: Icons.source_outlined,
        title: '还没有书源',
        message:
            '点上方「打开书源网站」，在网页里点「一键导入」即可。'
            '导入后可以在这里启停、删除书源。',
        action: FilledButton.tonalIcon(
          onPressed: () => setState(() => _showWeb = true),
          icon: const Icon(Icons.public),
          label: const Text('打开书源网站'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _sources.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final source = _sources[index];
        return NovelSourceCard(
          source: source,
          onToggle: (value) async {
            await widget.store.setEnabled(source.key, value);
            await _reloadSources();
          },
          trailing: IconButton(
            tooltip: '删除书源',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(source),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(NovelBookSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除书源「${source.name}」？'),
        content: const Text('只会删除本机保存的书源文件，不影响网站上的书源。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.delete(source.key);
    await _reloadSources();
  }

  void _showPasteDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('粘贴书源链接'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://… 或 yuedu://…importonline?src=…',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final link = controller.text.trim();
              Navigator.of(context).pop();
              if (link.isNotEmpty) _importLink(link);
            },
            child: const Text('导入'),
          ),
        ],
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
        if (parseImportSourceUrl(url) != null) {
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
