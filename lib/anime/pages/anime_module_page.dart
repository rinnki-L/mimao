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
/// 模块内部导航：底部 NavigationBar 在「搜索 / 时间表」间切换；
/// 点任一番剧条目 → push 详情页 → 返回。模块对壳无感知（不 import shell/）。
class AnimeModulePage extends StatefulWidget {
  const AnimeModulePage({
    super.key,
    required this.dataSource,
    this.onFavoriteChanged,
  });

  final AnimeDataSource dataSource;
  final ValueChanged<bool>? onFavoriteChanged;

  @override
  State<AnimeModulePage> createState() => _AnimeModulePageState();
}

class _AnimeModulePageState extends State<AnimeModulePage> {
  int _index = 0;

  void _openDetail(AnimeSummary item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnimeDetailPage(
          dataSource: widget.dataSource,
          summary: item,
          onFavoriteChanged: widget.onFavoriteChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          AnimeSearchPage(
            dataSource: widget.dataSource,
            onOpenDetail: _openDetail,
          ),
          AnimeSchedulePage(
            dataSource: widget.dataSource,
            onOpenDetail: _openDetail,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: '搜索',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_view_week_outlined),
            selectedIcon: Icon(Icons.calendar_view_week),
            label: '时间表',
          ),
        ],
      ),
    );
  }
}
