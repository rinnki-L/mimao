// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 小说「订阅」：展示订阅源（书源来源站点的集合），并从这里导入三类规则。
///
/// 每个订阅是一张卡片（默认「喵公子书源管理」），显示它下面的书源数量；
/// 点卡片满窗口打开该订阅站点（与规则管理 → 订阅源里点卡片同一套站点页）。
/// 导入入口叫「导入规则」而不是「导入书源」：书源 / 订阅源 / 替换规则都从
/// 同一个弹窗进来，按类型分流落库。
library;

import 'package:flutter/material.dart';
import 'package:mimao/novel/pages/novel_rule_import_dialog.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_source_site_page.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/source/novel_source_importer.dart';
import 'package:mimao/novel/source/novel_source_model.dart'
    show novelSourceSiteUrl;
import 'package:mimao/novel/source/novel_subscription.dart';

class NovelSubscribePage extends StatefulWidget {
  const NovelSubscribePage({
    super.key,
    required this.active,
    this.sourceImporter,
    this.subscriptionStore,
    this.openRoute,
    this.webViewBuilder,
  });

  final bool active;
  final NovelSourceImporter? sourceImporter;

  /// 订阅列表仓库；null 时用内置默认订阅（内存，不落盘）。
  final NovelSubscriptionStore? subscriptionStore;
  final NovelRouteOpener? openRoute;

  /// 测试注入缝：转发给订阅站点页，替换真实 WebView。
  final Widget Function(
    BuildContext context,
    void Function(String link) onImportLink,
  )?
  webViewBuilder;

  @override
  State<NovelSubscribePage> createState() => _NovelSubscribePageState();
}

class _NovelSubscribePageState extends State<NovelSubscribePage> {
  List<NovelSourceSubscription> _subscriptions =
      const <NovelSourceSubscription>[defaultNovelSubscription];
  int _sourceCount = 0;
  bool _loading = true;
  String? _error;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NovelSubscribePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((!oldWidget.active && widget.active) ||
        oldWidget.sourceImporter != widget.sourceImporter ||
        oldWidget.subscriptionStore != widget.subscriptionStore) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final store = widget.subscriptionStore;
    final importer = widget.sourceImporter;
    try {
      final subscriptions = store == null
          ? const <NovelSourceSubscription>[defaultNovelSubscription]
          : await store.loadAll();
      var count = 0;
      if (importer != null) {
        count = (await importer.store.loadAll()).length;
      }
      if (!mounted) return;
      setState(() {
        _subscriptions = subscriptions;
        _sourceCount = count;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '读取订阅失败：$error';
      });
    }
  }

  Future<void> _openManage([String? siteUrl]) async {
    await openNovelRoute(
      context,
      widget.openRoute,
      NovelRoute.sourceManage,
      args: siteUrl == null
          ? const <String, Object?>{}
          : <String, Object?>{'siteUrl': siteUrl},
    );
    if (mounted) await _load();
  }

  /// 点订阅卡片：满窗口打开订阅站点；返回后刷新书源数量。
  Future<void> _openSite(NovelSourceSubscription subscription) async {
    final importer = widget.sourceImporter;
    if (importer == null) {
      // 没接线时退回规则管理页，至少能看已有规则。
      await _openManage(subscription.siteUrl);
      return;
    }
    final url = subscription.siteUrl.isEmpty
        ? novelSourceSiteUrl
        : subscription.siteUrl;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'novel/source-site'),
        builder: (_) => NovelSourceSitePage(
          title: subscription.name,
          url: url,
          importer: importer,
          webViewBuilder: widget.webViewBuilder,
        ),
      ),
    );
    if (mounted) await _load();
  }

  /// 三类规则共用一个导入弹窗：书源 / 订阅源 / 替换规则，类型可自动识别。
  Future<void> _importRule() async {
    final importer = widget.sourceImporter;
    if (importer == null) return;
    final result = await showNovelRuleImportDialog(context, importer: importer);
    if (result == null || !mounted) return;
    setState(() {
      _status = result.message ?? '已导入 ${result.saved} 条${result.kind.label}';
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _subscriptions.isEmpty
        ? '还没有订阅'
        : '${_subscriptions.length} 个订阅源 · $_sourceCount 个书源';
    return NovelFillContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NovelPageHeader(
            title: '订阅',
            subtitle: subtitle,
            actions: <Widget>[
              NovelCircleAction(
                icon: Icons.refresh,
                tooltip: '刷新订阅',
                onPressed: _load,
              ),
            ],
            bottom: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                FilledButton.tonalIcon(
                  key: const Key('novel-subscribe-import-rule'),
                  onPressed: widget.sourceImporter == null ? null : _importRule,
                  icon: const Icon(Icons.rule),
                  label: const Text('导入规则'),
                ),
                OutlinedButton.icon(
                  key: const Key('novel-subscribe-manage-rules'),
                  onPressed: () => _openManage(),
                  icon: const Icon(Icons.tune),
                  label: const Text('规则管理'),
                ),
              ],
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _status!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const NovelLoadingState(label: '正在读取订阅…')
                : widget.sourceImporter == null
                ? NovelEmptyState(
                    icon: Icons.rss_feed,
                    title: '书源仓库未接线',
                    message: '书源订阅需要书源仓库；当前宿主没有注入该能力。',
                  )
                : _subscriptions.isEmpty
                ? NovelEmptyState(
                    icon: Icons.rss_feed,
                    title: '还没有订阅源',
                    message:
                        '订阅一个书源站点后，它的书源集合会出现在这里。'
                        '书源 / 订阅源 / 替换规则都可以从「导入规则」进来。',
                    action: FilledButton.tonalIcon(
                      onPressed: widget.sourceImporter == null
                          ? null
                          : _importRule,
                      icon: const Icon(Icons.rule),
                      label: const Text('去导入规则'),
                    ),
                  )
                : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980 ? 2 : 1;
        final items = _subscriptions
            .map(
              (sub) => SizedBox(
                width: columns == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 16) / 2,
                child: _SubscriptionCard(
                  subscription: sub,
                  sourceCount: _sourceCount,
                  onOpen: () => _openSite(sub),
                ),
              ),
            )
            .toList();
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: columns == 1
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final item in items) ...<Widget>[
                      item,
                      const SizedBox(height: 12),
                    ],
                  ],
                )
              : Wrap(spacing: 16, runSpacing: 16, children: items),
        );
      },
    );
  }
}

/// 一张订阅卡片：站点图标 + 名称 + 书源数量 + 站点地址，点整卡进书源管理页。
class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
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
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              NovelSourceBadge(name: subscription.name, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      subscription.name,
                      style: theme.textTheme.titleMedium,
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
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
          if (subscription.note.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              subscription.note,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            subscription.siteUrl,
            style: theme.textTheme.labelSmall?.copyWith(color: cs.primary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
