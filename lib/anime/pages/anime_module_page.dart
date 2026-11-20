// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'package:flutter/material.dart';
import 'package:mimao/anime/data/anime_data_source.dart';
import 'package:mimao/anime/data/anime_models.dart';
import 'package:mimao/anime/pages/anime_detail_page.dart';
import 'package:mimao/anime/pages/anime_schedule_page.dart';
import 'package:mimao/anime/pages/anime_search_page.dart';

/// 番剧模块层（壳钻进番剧入口后看到的那一层）。
///
/// 模块内部导航：底部 NavigationBar 在「搜索 / 时间表 / 设置」间切换；
/// 点任一番剧条目 → push 详情页 → 返回。模块对壳无感知（不 import shell/）。
/// 「设置」tab 放最右，内容由 AnimeModule.buildSettings 注入；null 时不显示
/// （模块级 widget 测试未注入设置时保持原有两 tab 行为）。
class AnimeModulePage extends StatefulWidget {
  const AnimeModulePage({
    super.key,
    required this.dataSource,
    this.embedded = false,
    this.settingsTab,
    this.onOpenDetail,
    this.isFavorite,
    this.onFavoriteChanged,
    this.onEpisodeTap,
  });

  final AnimeDataSource dataSource;

  /// true 时由壳提供顶部"返回 + 标题"，搜索/时间表页不再画自己的 AppBar。
  final bool embedded;

  /// 最右侧「设置」tab 的内容；由模块出口 buildSettings 注入。
  final Widget? settingsTab;

  /// 即将打开详情（导航前的最后一个异步点）：模块层在此接
  /// AnimeHistoryService.open 做打开点校正；抛错不挡导航。
  final Future<void> Function(AnimeSummary item)? onOpenDetail;

  /// 打开详情前读取权威收藏态；由模块层接收藏服务注入。
  final Future<bool> Function(AnimeSummary)? isFavorite;

  /// 追番切换；模块层把条目一起包进回调，详情页无需认识 AnimeSummary。
  final void Function(AnimeSummary item, bool favorite)? onFavoriteChanged;

  /// 点剧集；模块层把条目与完整详情一起交给播放器装配方。
  final void Function(
    AnimeSummary item,
    AnimeDetail detail,
    AnimeEpisode episode,
  )?
  onEpisodeTap;

  @override
  State<AnimeModulePage> createState() => _AnimeModulePageState();
}

class _AnimeModulePageState extends State<AnimeModulePage> {
  int _index = 0;

  Future<void> _openDetail(AnimeSummary item) async {
    // 打开点校正失败不应挡住导航：投影由下次打开再校正。
    try {
      await widget.onOpenDetail?.call(item);
    } on Object {
      // 校正是纯收益动作，失败静默。
    }
    // 收藏态读取失败不应挡住导航：退回"未收藏"继续打开详情。
    final favorite =
        await (widget.isFavorite?.call(item) ?? Future<bool>.value(false))
            .catchError((Object _) => false);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'anime/detail'),
        builder: (_) => AnimeDetailPage(
          dataSource: widget.dataSource,
          summary: item,
          initiallyFavorite: favorite,
          onFavoriteChanged: (v) => widget.onFavoriteChanged?.call(item, v),
          onEpisodeTap: (detail, ep) =>
              widget.onEpisodeTap?.call(item, detail, ep),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsTab = widget.settingsTab;
    final destinations = <NavigationDestination>[
      const NavigationDestination(
        icon: Icon(Icons.search_outlined),
        selectedIcon: Icon(Icons.search),
        label: '搜索',
      ),
      const NavigationDestination(
        icon: Icon(Icons.calendar_view_week_outlined),
        selectedIcon: Icon(Icons.calendar_view_week),
        label: '时间表',
      ),
    ];
    if (settingsTab != null) {
      destinations.add(
        const NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: '设置',
        ),
      );
    }
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          AnimeSearchPage(
            dataSource: widget.dataSource,
            showAppBar: !widget.embedded,
            onOpenDetail: _openDetail,
          ),
          AnimeSchedulePage(
            dataSource: widget.dataSource,
            showAppBar: !widget.embedded,
            onOpenDetail: _openDetail,
          ),
          if (settingsTab != null)
            SafeArea(child: SingleChildScrollView(child: settingsTab)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: destinations,
      ),
    );
  }
}
