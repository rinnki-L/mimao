// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 小说设置页：今日阅读目标、数据清理、规则管理与关于。
///
/// 主题/外观归壳的全局设置抽屉，这里不重复；本页只放小说模块自己的设置。
/// 字号/行距/翻页等待阅读器接入后启用，当前明确标注，不做假开关。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/source/novel_source_importer.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

class NovelSettingsPage extends StatefulWidget {
  const NovelSettingsPage({
    super.key,
    this.stats,
    this.searchHistory,
    this.history,
    this.sourceImporter,
    this.openRoute,
    this.embedded = false,
  });

  final NovelStatsApi? stats;
  final NovelSearchHistoryApi? searchHistory;
  final NovelHistoryApi? history;
  final NovelSourceImporter? sourceImporter;
  final NovelRouteOpener? openRoute;

  /// true 时不画自己的 Scaffold/AppBar，只返回设置内容——供模块侧栏底部
  /// 「设置」项用 showModalBottomSheet 弹出（与漫画/音乐同款）。
  final bool embedded;

  @override
  State<NovelSettingsPage> createState() => _NovelSettingsPageState();
}

class _NovelSettingsPageState extends State<NovelSettingsPage> {
  late Future<_SettingsData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<_SettingsData> _load() async {
    var stats = const NovelStats(
      booksRead: 0,
      collected: 0,
      totalSeconds: 0,
      todaySeconds: 0,
      goalMinutes: novelDefaultGoalMinutes,
    );
    var searchCount = 0;
    var sources = const <NovelBookSource>[];
    final errors = <String>[];
    final statsApi = widget.stats;
    if (statsApi != null) {
      try {
        stats = await statsApi.snapshot();
      } on Object catch (error) {
        errors.add('统计读取失败：$error');
      }
    }
    final searchHistory = widget.searchHistory;
    if (searchHistory != null) {
      try {
        searchCount = (await searchHistory.recent(limit: 200)).length;
      } on Object catch (error) {
        errors.add('搜索历史读取失败：$error');
      }
    }
    final importer = widget.sourceImporter;
    if (importer != null) {
      try {
        sources = await importer.store.loadAll();
      } on Object catch (error) {
        errors.add('书源读取失败：$error');
      }
    }
    return _SettingsData(
      stats: stats,
      searchCount: searchCount,
      sourceCount: sources.length,
      error: errors.isEmpty ? null : errors.join('\n'),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editGoal(int initial) async {
    final stats = widget.stats;
    if (stats == null) {
      _toast('阅读统计未接线，目标暂时不能保存。');
      return;
    }
    final minutes = await showDialog<int>(
      context: context,
      builder: (_) => NovelGoalDialog(initialMinutes: initial),
    );
    if (minutes == null) return;
    try {
      await stats.setGoalMinutes(minutes);
      _reload();
      _toast(minutes == 0 ? '已关闭今日阅读目标' : '目标已设为 $minutes 分钟');
    } on Object catch (error) {
      _toast('保存失败：$error');
    }
  }

  Future<void> _clearSearchHistory() async {
    final api = widget.searchHistory;
    if (api == null) {
      _toast('搜索历史未接线。');
      return;
    }
    try {
      await api.clear();
      _reload();
      _toast('搜索历史已清除');
    } on Object catch (error) {
      _toast('清除失败：$error');
    }
  }

  Future<void> _clearReadingHistory() async {
    final api = widget.history;
    if (api == null) {
      _toast('阅读记录未接线。');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空阅读记录？'),
        content: const Text('所有书的阅读进度会被删除；收藏的书仍留在书架，进度回到未读。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await api.clear();
      _reload();
      _toast('阅读记录已清空');
    } on Object catch (error) {
      _toast('清空失败：$error');
    }
  }

  Future<void> _openSources() async {
    await openNovelRoute(context, widget.openRoute, NovelRoute.sourceManage);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final content = FutureBuilder<_SettingsData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const NovelLoadingState(label: '正在读取设置…');
        }
        if (snapshot.hasError) {
          return NovelErrorState(
            message: '${snapshot.error}',
            onRetry: _reload,
          );
        }
        final data = snapshot.data ?? _SettingsData.empty;
        return NovelPageContent(
          maxWidth: 860,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: ListView(
            children: <Widget>[
              if (data.error != null) ...<Widget>[
                Text(
                  data.error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const _SettingsSectionLabel('阅读'),
              NovelCard(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  children: <Widget>[
                    _SettingsRow(
                      icon: Icons.flag_outlined,
                      title: '今日阅读目标',
                      subtitle: data.stats.goalMinutes == 0
                          ? '未设置（点右侧修改）'
                          : '每天 ${data.stats.goalMinutes} 分钟 · 今日已读 '
                                '${data.stats.todayMinutes} 分钟',
                      trailing: TextButton(
                        onPressed: () => _editGoal(data.stats.goalMinutes),
                        child: const Text('修改'),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.format_size,
                      title: '字号与行距',
                      subtitle: '在阅读页右上角调整',
                      onTap: () => _toast('打开一本书，在阅读页右上角调整字号。'),
                    ),
                    _SettingsRow(
                      icon: Icons.swap_horiz,
                      title: '翻页方式',
                      subtitle: '在阅读页右上角调整',
                      onTap: () => _toast('打开一本书，在阅读页右上角调整字号。'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const _SettingsSectionLabel('数据'),
              NovelCard(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  children: <Widget>[
                    _SettingsRow(
                      icon: Icons.search_off,
                      title: '清除搜索历史',
                      subtitle: data.searchCount == 0
                          ? '还没有搜索历史'
                          : '${data.searchCount} 个关键词',
                      trailing: TextButton(
                        onPressed: data.searchCount == 0
                            ? null
                            : _clearSearchHistory,
                        child: const Text('清除'),
                      ),
                    ),
                    _SettingsRow(
                      icon: Icons.history_toggle_off,
                      title: '清空阅读记录',
                      subtitle: data.stats.booksRead == 0
                          ? '还没有阅读记录'
                          : '${data.stats.booksRead} 本书有记录',
                      trailing: TextButton(
                        onPressed: data.stats.booksRead == 0
                            ? null
                            : _clearReadingHistory,
                        child: const Text('清空'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const _SettingsSectionLabel('规则'),
              NovelCard(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  children: <Widget>[
                    _SettingsRow(
                      icon: Icons.source_outlined,
                      title: '规则管理',
                      subtitle: data.sourceCount == 0
                          ? '还没有规则（书源 / 订阅源 / 替换规则）'
                          : '${data.sourceCount} 个书源 · 订阅源 · 替换规则',
                      onTap: _openSources,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              const _SettingsSectionLabel('关于'),
              NovelCard(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  children: <Widget>[
                    const _SettingsRow(
                      icon: Icons.info_outline,
                      title: '版本',
                      // 与 pubspec.yaml 的 version 同步；发版时一起改。
                      subtitle: '0.1.0 · 本地优先，无自建服务器',
                    ),
                    _SettingsRow(
                      icon: Icons.description_outlined,
                      title: '开源许可',
                      subtitle: 'Flutter · drift · dio 等第三方许可',
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'mimao',
                        applicationLegalese: '本地优先的媒体聚合应用',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('小说设置')),
      body: content,
    );
  }
}

class _SettingsData {
  const _SettingsData({
    required this.stats,
    required this.searchCount,
    required this.sourceCount,
    this.error,
  });

  static const _SettingsData empty = _SettingsData(
    stats: NovelStats(
      booksRead: 0,
      collected: 0,
      totalSeconds: 0,
      todaySeconds: 0,
      goalMinutes: novelDefaultGoalMinutes,
    ),
    searchCount: 0,
    sourceCount: 0,
  );

  final NovelStats stats;
  final int searchCount;
  final int sourceCount;
  final String? error;
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 22, color: cs.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.bodyLarge),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (onTap != null)
            Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
        ],
      ),
    );
    if (onTap == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: BorderRadius.circular(MimaoRadii.md),
        onTap: onTap,
        child: row,
      ),
    );
  }
}
