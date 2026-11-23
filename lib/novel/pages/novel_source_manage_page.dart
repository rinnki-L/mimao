// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他三个模块的页面同款说明：保持类型一致、patch 可重放。
/// 小说规则管理页：书源 / 订阅源 / 替换规则三个分类，各自导入、启停、删除。
///
/// 点「订阅源」里的订阅站点卡片会 push 满窗口的 [NovelSourceSitePage] 打开该
/// 站点，站点上的「一键导入」（`yuedu://booksource/importonline?src=…`）由那边
/// 拦截并落库，返回本页后重新读取列表。
/// 三个分类各自用固定类型的「导入书源 / 导入订阅源 / 导入替换规则」弹窗粘贴链接。
///
/// 本页不构造 WebView，页面进场零插件调用——无插件测试环境也能渲染列表与按钮。
library;

import 'package:flutter/material.dart';

import '../source/novel_rule_model.dart';
import '../source/novel_source_importer.dart';
import '../source/novel_source_model.dart';
import '../source/novel_source_store.dart' show NovelSourceStorage;
import '../source/novel_subscription.dart'
    show
        NovelSourceSubscription,
        NovelSubscriptionStore,
        defaultNovelSubscription;
import 'novel_source_site_page.dart';
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

  /// 测试注入缝：转发给订阅站点页，替换真实 WebView。
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

  /// 点订阅站点卡片：满窗口打开这个站点；返回后刷新规则列表。
  Future<void> _openSite(NovelSourceSubscription subscription) async {
    final url = subscription.siteUrl.isEmpty
        ? widget.siteUrl
        : subscription.siteUrl;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'novel/source-site'),
        builder: (_) => NovelSourceSitePage(
          title: subscription.name,
          url: url,
          importer: widget.importer,
          webViewBuilder: widget.webViewBuilder,
        ),
      ),
    );
    if (mounted) await _reloadAll();
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
                onPressed: () => _openImportDialog(NovelRuleKind.bookSource),
                icon: const Icon(Icons.add_link),
                label: const Text('导入书源'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Feedback(status: _status, error: _error),
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
          _Feedback(status: _status, error: _error),
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
          _Feedback(status: _status, error: _error),
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
        onPressed: () => _openImportDialog(kind),
        icon: const Icon(Icons.add_link),
        label: Text('导入${kind.label}'),
      ),
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
              onOpen: () => _openSite(subscription),
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

/// 导入结果 / 读取错误，三个 tab 共用同一份状态。
class _Feedback extends StatelessWidget {
  const _Feedback({required this.status, required this.error});

  final String? status;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
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
