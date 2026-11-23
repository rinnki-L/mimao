// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 小说「我的」：书源/阅读数据总览 + 规则入口 + 其它（设置/记录/缓存/文件/关于）。
///
/// 能被真实执行的入口全部接本地服务；替换净化、TXT 目录规则、字典/标签规则、
/// 书签这类依赖书源引擎或阅读器的入口保留在列表里但明确标"未接入"，点击给出
/// 说明，不做假跳转。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/source/novel_source_importer.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class NovelProfilePage extends StatefulWidget {
  const NovelProfilePage({
    super.key,
    required this.active,
    this.collect,
    this.history,
    this.searchHistory,
    this.stats,
    this.sourceImporter,
    this.openRoute,
    this.onSelectTab,
  });

  final bool active;
  final NovelCollectApi? collect;
  final NovelHistoryApi? history;
  final NovelSearchHistoryApi? searchHistory;
  final NovelStatsApi? stats;
  final NovelSourceImporter? sourceImporter;
  final NovelRouteOpener? openRoute;
  final ValueChanged<int>? onSelectTab;

  @override
  State<NovelProfilePage> createState() => _NovelProfilePageState();
}

class _NovelProfilePageState extends State<NovelProfilePage> {
  late Future<_ProfileData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(NovelProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameActive = !oldWidget.active && widget.active;
    final servicesChanged =
        oldWidget.stats != widget.stats ||
        oldWidget.sourceImporter != widget.sourceImporter ||
        oldWidget.searchHistory != widget.searchHistory;
    if (becameActive || servicesChanged) _reload();
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<_ProfileData> _load() async {
    final errors = <String>[];

    var stats = const NovelStats(
      booksRead: 0,
      collected: 0,
      totalSeconds: 0,
      todaySeconds: 0,
      goalMinutes: novelDefaultGoalMinutes,
    );
    final statsApi = widget.stats;
    if (statsApi != null) {
      try {
        stats = await statsApi.snapshot();
      } on Object catch (error) {
        errors.add('统计读取失败：$error');
      }
    }

    var sources = const <NovelBookSource>[];
    final importer = widget.sourceImporter;
    if (importer != null) {
      try {
        sources = await importer.store.loadAll();
      } on Object catch (error) {
        errors.add('书源读取失败：$error');
      }
    }

    var searchCount = 0;
    final searchHistory = widget.searchHistory;
    if (searchHistory != null) {
      try {
        searchCount = (await searchHistory.recent(limit: 200)).length;
      } on Object catch (error) {
        errors.add('搜索历史读取失败：$error');
      }
    }

    return _ProfileData(
      stats: stats,
      sources: sources,
      searchCount: searchCount,
      error: errors.isEmpty ? null : errors.join('\n'),
    );
  }

  Future<void> _openRoute(
    NovelRoute route, {
    Map<String, Object?> args = const <String, Object?>{},
  }) async {
    await openNovelRoute(context, widget.openRoute, route, args: args);
    if (mounted) _reload();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _clearSearchHistory() async {
    final api = widget.searchHistory;
    if (api == null) {
      _toast('搜索历史未接线。');
      return;
    }
    await api.clear();
    _reload();
    _toast('搜索历史已清除');
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

  Future<void> _showCacheDialog(_ProfileData data) async {
    final theme = Theme.of(context);
    final (duration, unit) = novelDurationParts(data.stats.totalSeconds);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('缓存管理'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _InfoLine(label: '阅读记录', value: '${data.stats.booksRead} 本'),
              _InfoLine(label: '阅读时长', value: '$duration $unit'),
              _InfoLine(label: '搜索历史', value: '${data.searchCount} 条'),
              const SizedBox(height: 12),
              Text(
                '正文缓存随阅读器接入；当前可清理的是搜索历史与阅读记录。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _clearSearchHistory();
            },
            child: const Text('清搜索历史'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _clearReadingHistory();
            },
            child: const Text('清阅读记录'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFileDialog() async {
    String? documents;
    String? support;
    try {
      documents = (await getApplicationDocumentsDirectory()).path;
      support = (await getApplicationSupportDirectory()).path;
    } on Object catch (error) {
      _toast('读取目录失败：$error');
      return;
    }
    final sourceDir = p.join(support, 'novel_sources');
    final databasePath = p.join(documents, 'mimao_novel.sqlite');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('文件管理'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _PathLine(label: '小说库', path: databasePath),
                const SizedBox(height: 10),
                _PathLine(label: '书源目录', path: sourceDir),
                const SizedBox(height: 12),
                Text(
                  '数据库与书源都是本机文件，可整体复制做备份。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: sourceDir));
                if (context.mounted) {
                  Navigator.of(context).pop();
                  _toast('书源目录路径已复制');
                }
              },
              child: const Text('复制书源路径'),
            ),
            if (Platform.isWindows)
              OutlinedButton.icon(
                onPressed: () async {
                  final dir = Directory(sourceDir);
                  try {
                    if (!await dir.exists()) await dir.create(recursive: true);
                    await Process.run('explorer', <String>[sourceDir]);
                  } on Object catch (error) {
                    _toast('打开目录失败：$error');
                  }
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('打开目录'),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'mimao · 小说',
      applicationIcon: Icon(
        Icons.menu_book,
        size: 40,
        color: Theme.of(context).colorScheme.primary,
      ),
      applicationLegalese: '本地优先 · 无自建服务器 · 数据只在本机',
      children: <Widget>[
        const SizedBox(height: 12),
        const Text(
          '小说模块负责本地书架、阅读记录与书源管理；跨源搜索、目录与正文'
          '由 legado 书源引擎抓取。',
        ),
      ],
    );
  }

  void _showUnavailable(String feature) {
    _toast('$feature尚未实现。');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ProfileData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const NovelLoadingState(label: '正在读取本地数据…');
        }
        if (snapshot.hasError) {
          return NovelErrorState(
            message: '${snapshot.error}',
            onRetry: _reload,
          );
        }
        final data = snapshot.data ?? _ProfileData.empty;
        return NovelPageContent(
          maxWidth: 980,
          child: ListView(
            children: <Widget>[
              NovelPageHeader(
                title: '我的',
                subtitle: '本地数据 · 不登录也能用',
                actions: <Widget>[
                  NovelCircleAction(
                    key: const Key('novel-profile-settings'),
                    icon: Icons.settings_outlined,
                    tooltip: '小说设置',
                    onPressed: () => _openRoute(NovelRoute.settings),
                  ),
                ],
              ),
              if (data.error != null) ...<Widget>[
                _InlineWarning(message: data.error!, onRetry: _reload),
                const SizedBox(height: 16),
              ],
              _ProfileHero(data: data),
              const SizedBox(height: 24),
              const _SectionLabel('规则'),
              _ProfileSection(
                children: <Widget>[
                  _ProfileRow(
                    icon: Icons.source_outlined,
                    title: '规则管理',
                    subtitle: data.sources.isEmpty
                        ? '还没有规则，点这里导入书源 / 订阅源 / 替换规则'
                        : '${data.sources.length} 个书源 · 订阅源 · 替换规则',
                    onTap: () => _openRoute(NovelRoute.sourceManage),
                  ),
                  _ProfileRow(
                    icon: Icons.auto_fix_high_outlined,
                    title: '替换规则',
                    subtitle: '正文 / 标题净化 · 导入 · 启停',
                    onTap: () => _openRoute(
                      NovelRoute.sourceManage,
                      args: const <String, Object?>{'tab': 'replace'},
                    ),
                  ),
                  _ProfileRow(
                    icon: Icons.format_list_numbered,
                    title: 'TXT 目录规则',
                    subtitle: '需要阅读器',
                    onTap: () => _showUnavailable('TXT 目录规则'),
                  ),
                  _ProfileRow(
                    icon: Icons.translate,
                    title: '字典规则',
                    subtitle: '需要书源引擎',
                    onTap: () => _showUnavailable('字典规则'),
                  ),
                  _ProfileRow(
                    icon: Icons.sell_outlined,
                    title: '标签规则',
                    subtitle: '需要书源引擎',
                    onTap: () => _showUnavailable('标签规则'),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const _SectionLabel('其它'),
              _ProfileSection(
                children: <Widget>[
                  _ProfileRow(
                    icon: Icons.settings_outlined,
                    title: '设置',
                    subtitle: '阅读目标 · 数据清理 · 关于',
                    onTap: () => _openRoute(NovelRoute.settings),
                  ),
                  _ProfileRow(
                    icon: Icons.history,
                    title: '阅读记录',
                    subtitle: data.stats.booksRead == 0
                        ? '还没有阅读记录'
                        : '${data.stats.booksRead} 本书有记录',
                    onTap: () => _openRoute(NovelRoute.history),
                  ),
                  _ProfileRow(
                    icon: Icons.cleaning_services_outlined,
                    title: '缓存管理',
                    subtitle:
                        '搜索历史 ${data.searchCount} 条 · 阅读记录 '
                        '${data.stats.booksRead} 本',
                    onTap: () => _showCacheDialog(data),
                  ),
                  _ProfileRow(
                    icon: Icons.folder_outlined,
                    title: '文件管理',
                    subtitle: '查看本地库与书源目录',
                    onTap: _showFileDialog,
                  ),
                  _ProfileRow(
                    icon: Icons.bookmark_border,
                    title: '书签',
                    subtitle: '阅读器接入后可用',
                    onTap: () => _showUnavailable('书签'),
                  ),
                  _ProfileRow(
                    icon: Icons.info_outline,
                    title: '关于',
                    subtitle: 'mimao · 本地优先',
                    onTap: _showAbout,
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileData {
  const _ProfileData({
    required this.stats,
    required this.sources,
    required this.searchCount,
    this.error,
  });

  static const _ProfileData empty = _ProfileData(
    stats: NovelStats(
      booksRead: 0,
      collected: 0,
      totalSeconds: 0,
      todaySeconds: 0,
      goalMinutes: novelDefaultGoalMinutes,
    ),
    sources: <NovelBookSource>[],
    searchCount: 0,
  );

  final NovelStats stats;
  final List<NovelBookSource> sources;
  final int searchCount;
  final String? error;
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.data});

  final _ProfileData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final enabled = data.sources.where((source) => source.enabled).length;
    final (duration, unit) = novelDurationParts(data.stats.totalSeconds);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(MimaoRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: cs.onPrimaryContainer.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(MimaoRadii.md),
                ),
                child: Icon(Icons.menu_book, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'mimao · 小说',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '书源 ${data.sources.length} 个（$enabled 启用）',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onPrimaryContainer.withValues(alpha: .75),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 32,
            runSpacing: 14,
            children: <Widget>[
              _HeroStat(
                value: '${data.stats.collected}',
                unit: '本收藏',
                color: cs.onPrimaryContainer,
              ),
              _HeroStat(
                value: '${data.stats.booksRead}',
                unit: '本读过',
                color: cs.onPrimaryContainer,
              ),
              _HeroStat(
                value: duration,
                unit: unit,
                color: cs.onPrimaryContainer,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.value,
    required this.unit,
    required this.color,
  });

  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(color: color),
        ),
        Text(
          unit,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color.withValues(alpha: .75),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

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

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return NovelCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(children: children),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: BorderRadius.circular(MimaoRadii.md),
        onTap: onTap,
        child: Padding(
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
              Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _PathLine extends StatelessWidget {
  const _PathLine({required this.label, required this.path});

  final String label;
  final String path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          path,
          style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurface),
        ),
      ],
    );
  }
}

class _InlineWarning extends StatelessWidget {
  const _InlineWarning({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(MimaoRadii.md),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: cs.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onErrorContainer,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
