// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他三个模块的页面同款说明：保持类型一致、patch 可重放。
/// 小说规则管理页：书源 / 订阅源 / 替换规则三个分类，各自导入、启停、删除。
///
/// 书源 tab 保留内嵌 WebView：点「订阅源」里的订阅站点卡片会切到书源分类并
/// 打开该站点，站点上的「一键导入」（`yuedu://booksource/importonline?src=…`）
/// 由注入的 JS 改道到 JS Handler，再交给导入服务按类型下载落库。
/// 三个分类各自用固定类型的「导入书源 / 导入订阅源 / 导入替换规则」弹窗粘贴链接。
///
/// WebView 只在用户点订阅站点卡片后构造，页面进场本身零插件调用——
/// 这样无插件测试环境也能渲染列表与按钮。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../source/novel_rule_model.dart';
import '../source/novel_source_importer.dart';
import '../source/novel_source_model.dart';
import '../source/novel_source_store.dart' show NovelSourceStorage;
import '../source/novel_subscription.dart'
    show
        NovelSourceSubscription,
        NovelSubscriptionStore,
        defaultNovelSubscription;
import 'novel_rule_import_dialog.dart';
import 'novel_widgets.dart';

/// 打开规则管理页。由 NovelModule 出口接到 Navigator。
class NovelSourceManagePage extends StatefulWidget {
  const NovelSourceManagePage({
    super.key,
    required this.store,
    required this.importer,
    this.subscriptionStore,
    this.siteUrl = novelSourceSiteUrl,
    this.initialTab = NovelRuleKind.bookSource,
    this.webViewBuilder,
  });

  final NovelSourceStorage store;
  final NovelSourceImporter importer;

  /// 订阅站点仓库：订阅页里的「喵公子」等条目也属于订阅源。
  /// null 时显示内置默认订阅（与订阅页的回落一致）。
  final NovelSubscriptionStore? subscriptionStore;
  final String siteUrl;

  /// 进场默认选中的分类（书源 / 订阅源 / 替换规则）。
  final NovelRuleKind initialTab;

  /// 测试注入缝：返回 WebView widget；null 时用真实 [InAppWebView]。
  final Widget Function(
    BuildContext context,
    void Function(String link) onImportLink,
  )?
  webViewBuilder;

  @override
  State<NovelSourceManagePage> createState() => _NovelSourceManagePageState();
}

class _NovelSourceManagePageState extends State<NovelSourceManagePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: NovelRuleKind.values.length,
    vsync: this,
    initialIndex: widget.initialTab.index,
  );

  bool _showWeb = false;
  String? _webSiteUrl;
  bool _importing = false;
  bool _loading = true;
  String? _status;
  String? _error;
  List<NovelBookSource> _sources = const <NovelBookSource>[];
  List<NovelRssSource> _rssSources = const <NovelRssSource>[];
  List<NovelReplaceRule> _replaceRules = const <NovelReplaceRule>[];
  List<NovelSourceSubscription> _subscriptions =
      const <NovelSourceSubscription>[defaultNovelSubscription];

  @override
  void initState() {
    super.initState();
    _reloadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reloadAll() async {
    try {
      final sources = await widget.store.loadAll();
      final rssStore = widget.importer.rssStore;
      final replaceStore = widget.importer.replaceStore;
      final rss = rssStore == null
          ? const <NovelRssSource>[]
          : await rssStore.loadAll();
      final rules = replaceStore == null
          ? const <NovelReplaceRule>[]
          : await replaceStore.loadAll();
      final subscriptionStore = widget.subscriptionStore;
      final subscriptions = subscriptionStore == null
          ? const <NovelSourceSubscription>[defaultNovelSubscription]
          : await subscriptionStore.loadAll();
      if (!mounted) return;
      setState(() {
        _sources = sources;
        _rssSources = rss;
        _replaceRules = rules;
        _subscriptions = subscriptions;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取规则失败：$error';
      });
    }
  }

  /// 深链导入（WebView 或粘贴共用）。
  Future<void> _importLink(String link) async {
    if (_importing) return;
    setState(() {
      _importing = true;
      _status = '正在导入规则…';
      _error = null;
    });
    try {
      final result = await widget.importer.importFromLink(link);
      await _reloadAll();
      if (!mounted) return;
      setState(() {
        _status = result.message ?? '已导入 ${result.saved} 条${result.kind.label}';
      });
    } on NovelSourceImportException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object catch (error) {
      if (mounted) setState(() => _error = '导入失败：$error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _openImportDialog(NovelRuleKind kind) async {
    final result = await showNovelRuleImportDialog(
      context,
      importer: widget.importer,
      initialKind: kind,
      // 分类内导入锁死类型：书源 tab 就只导书源，不在弹窗里再选一遍。
      allowTypeSwitch: false,
    );
    if (result == null || !mounted) return;
    setState(() {
      _status = result.message ?? '已导入 ${result.saved} 条${result.kind.label}';
      _error = null;
    });
    await _reloadAll();
  }

  /// 点订阅站点卡片：在书源分类里打开这个站点的内嵌网页。
  void _openSite(String siteUrl) {
    setState(() {
      _webSiteUrl = siteUrl.isEmpty ? widget.siteUrl : siteUrl;
      _showWeb = true;
    });
    _tabs.animateTo(NovelRuleKind.bookSource.index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('规则管理'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新规则',
            onPressed: _reloadAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: <Widget>[
            for (final kind in NovelRuleKind.values) Tab(text: kind.label),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: <Widget>[_buildBookTab(), _buildRssTab(), _buildReplaceTab()],
      ),
    );
  }

  Widget _buildBookTab() {
    return NovelFillContent(
      maxWidth: 1100,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              OutlinedButton.icon(
                key: const Key('novel-source-paste-import'),
                onPressed: _importing
                    ? null
                    : () => _openImportDialog(NovelRuleKind.bookSource),
                icon: const Icon(Icons.add_link),
                label: const Text('导入书源'),
              ),
              if (_showWeb)
                TextButton.icon(
                  onPressed: () => setState(() => _showWeb = false),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('收起网页'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _Feedback(importing: _importing, status: _status, error: _error),
          if (_showWeb)
            SizedBox(
              height: 260,
              child: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 10),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: _buildWebView(),
                ),
              ),
            ),
          Expanded(child: _buildSourceList()),
        ],
      ),
    );
  }

  Widget _buildRssTab() {
    return NovelFillContent(
      maxWidth: 1100,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildRuleImportBar(
            kind: NovelRuleKind.rssSource,
            key: const Key('novel-rss-paste-import'),
          ),
          _Feedback(importing: _importing, status: _status, error: _error),
          Expanded(child: _buildRssList()),
        ],
      ),
    );
  }

  Widget _buildReplaceTab() {
    return NovelFillContent(
      maxWidth: 1100,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildRuleImportBar(
            kind: NovelRuleKind.replaceRule,
            key: const Key('novel-replace-paste-import'),
          ),
          _Feedback(importing: _importing, status: _status, error: _error),
          Expanded(child: _buildReplaceList()),
        ],
      ),
    );
  }

  Widget _buildRuleImportBar({required NovelRuleKind kind, required Key key}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.tonalIcon(
        key: key,
        onPressed: _importing ? null : () => _openImportDialog(kind),
        icon: const Icon(Icons.add_link),
        label: Text('导入${kind.label}'),
      ),
    );
  }

  Widget _buildWebView() {
    final url = _webSiteUrl ?? widget.siteUrl;
    final builder = widget.webViewBuilder;
    return builder != null
        ? builder(context, _importLink)
        : _RealSourceWebView(
            key: ValueKey<String>(url),
            url: url,
            onImportLink: _importLink,
          );
  }

  Widget _buildSourceList() {
    if (_loading) {
      return const NovelLoadingState(label: '正在读取规则…');
    }
    if (_sources.isEmpty) {
      return NovelEmptyState(
        icon: Icons.source_outlined,
        title: '还没有书源',
        message:
            '点上方「导入书源」粘贴链接；或在「订阅源」里点订阅站点卡片，'
            '打开网站后点「一键导入」。',
        action: FilledButton.tonalIcon(
          key: const Key('novel-source-import-empty'),
          onPressed: () => _openImportDialog(NovelRuleKind.bookSource),
          icon: const Icon(Icons.add_link),
          label: const Text('导入书源'),
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
            await _reloadAll();
          },
          trailing: IconButton(
            tooltip: '删除书源',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(
              title: '删除书源「${source.name}」？',
              message: '只会删除本机保存的书源文件，不影响网站上的书源。',
              onDelete: () => widget.store.delete(source.key),
            ),
          ),
        );
      },
    );
  }

  /// 订阅源 tab：先列订阅站点（订阅页那批），再列导入的 RSS 订阅规则。
  ///
  /// 两者在用户语义里都叫「订阅源」：订阅站点是书源的来源站点（默认为
  /// 「喵公子书源管理」），RSS 是 Legado `rsssource` 规则。订阅站点只读展示，
  /// 点按切回「书源」分类看它导入的源。
  Widget _buildRssList() {
    if (_loading) {
      return const NovelLoadingState(label: '正在读取订阅源…');
    }
    final hasSubscriptions = _subscriptions.isNotEmpty;
    final hasRss = _rssSources.isNotEmpty;
    if (!hasSubscriptions && !hasRss) {
      return NovelEmptyState(
        icon: Icons.rss_feed,
        title: '还没有订阅源',
        message: '导入订阅源规则后会出现在这里，可以启停或删除。',
        action: FilledButton.tonalIcon(
          key: const Key('novel-rss-import-empty'),
          onPressed: () => _openImportDialog(NovelRuleKind.rssSource),
          icon: const Icon(Icons.add_link),
          label: const Text('导入订阅源'),
        ),
      );
    }
    final store = widget.importer.rssStore;
    return ListView(
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      children: <Widget>[
        if (hasSubscriptions) ...<Widget>[
          const NovelSectionHeader(icon: Icons.rss_feed, title: '订阅站点'),
          const SizedBox(height: 8),
          for (final subscription in _subscriptions) ...<Widget>[
            _SubscriptionSiteCard(
              subscription: subscription,
              sourceCount: _sources.length,
              onOpen: () => _openSite(subscription.siteUrl),
            ),
            const SizedBox(height: 8),
          ],
        ],
        const SizedBox(height: 12),
        if (hasRss) ...<Widget>[
          const NovelSectionHeader(
            icon: Icons.subscriptions_outlined,
            title: 'RSS 订阅规则',
          ),
          const SizedBox(height: 8),
          for (final source in _rssSources) ...<Widget>[
            _RuleCard(
              icon: Icons.rss_feed,
              title: source.name,
              subtitle: source.url,
              tag: source.group,
              enabled: source.enabled,
              onToggle: store == null
                  ? null
                  : (value) async {
                      await store.setEnabled(source.key, value);
                      await _reloadAll();
                    },
              onDelete: () => _confirmDelete(
                title: '删除订阅源「${source.name}」？',
                message: '只会删除本机保存的规则，不影响订阅源网站。',
                onDelete: () async => await store?.delete(source.key) ?? false,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }

  Widget _buildReplaceList() {
    if (_loading) {
      return const NovelLoadingState(label: '正在读取替换规则…');
    }
    if (_replaceRules.isEmpty) {
      return NovelEmptyState(
        icon: Icons.auto_fix_high_outlined,
        title: '还没有替换规则',
        message: '导入替换规则后，阅读器加载正文和标题时会自动净化。',
        action: FilledButton.tonalIcon(
          key: const Key('novel-replace-import-empty'),
          onPressed: () => _openImportDialog(NovelRuleKind.replaceRule),
          icon: const Icon(Icons.add_link),
          label: const Text('导入替换规则'),
        ),
      );
    }
    final store = widget.importer.replaceStore;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _replaceRules.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final rule = _replaceRules[index];
        return _RuleCard(
          icon: Icons.auto_fix_high_outlined,
          title: rule.name,
          subtitle: '${rule.pattern} → ${rule.replacement}',
          tag: rule.isRegex ? '正则' : '普通',
          enabled: rule.enabled,
          onToggle: store == null
              ? null
              : (value) async {
                  await store.setEnabled(rule.key, value);
                  await _reloadAll();
                },
          onDelete: () => _confirmDelete(
            title: '删除替换规则「${rule.name}」？',
            message: '删除后阅读器不再应用这条替换。',
            onDelete: () async => await store?.delete(rule.key) ?? false,
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete({
    required String title,
    required String message,
    required Future<bool> Function() onDelete,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
    await onDelete();
    await _reloadAll();
  }
}

/// 导入进度 / 结果 / 错误，三个 tab 共用同一份状态。
class _Feedback extends StatelessWidget {
  const _Feedback({
    required this.importing,
    required this.status,
    required this.error,
  });

  final bool importing;
  final String? status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (importing)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(minHeight: 3),
          ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              status!,
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.primary),
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error!,
              style: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
            ),
          ),
      ],
    );
  }
}

/// 订阅站点卡：名称 + 书源数量 + 备注 + 站点地址，点按切到「书源」分类。
class _SubscriptionSiteCard extends StatelessWidget {
  const _SubscriptionSiteCard({
    required this.subscription,
    required this.sourceCount,
    required this.onOpen,
  });

  final NovelSourceSubscription subscription;
  final int sourceCount;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NovelCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: <Widget>[
          NovelSourceBadge(name: subscription.name, size: 44),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  subscription.name,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '$sourceCount 个书源 · 点按打开网站',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (subscription.note.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    subscription.note,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  subscription.siteUrl,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// 订阅源 / 替换规则列表卡：图标 + 名称 + 备注 + 标签 + 开关 + 删除。
class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.enabled,
    required this.onToggle,
    required this.onDelete,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String tag;
  final bool enabled;
  final ValueChanged<bool>? onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NovelCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: <Widget>[
          Icon(icon, color: cs.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (tag.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 8),
                      Text(
                        tag,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Switch(value: enabled, onChanged: onToggle),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// 真正的内嵌 WebView（仅桌面/移动端有插件的运行环境里被构造）。
class _RealSourceWebView extends StatefulWidget {
  const _RealSourceWebView({
    super.key,
    required this.url,
    required this.onImportLink,
  });

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
