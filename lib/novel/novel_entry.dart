// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart，与 music_entry.dart 同款说明。
/// 小说模块对壳的唯一出口——实现 [AppModule]，由 app_registry 注入全部依赖
/// （docs/architecture.md §4.3）。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/novel/engine/engine.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/pages/novel_module_page.dart'
    show NovelModulePage, NovelSettingsPlaceholder;
import 'package:mimao/novel/pages/novel_source_manage_page.dart'
    show NovelSourceManagePage;
import 'package:mimao/novel/pages/novel_routes.dart'
    show NovelRoute, pushNovelRoute, registerNovelRoutePage;
import 'package:mimao/novel/source/novel_source_importer.dart'
    show NovelSourceImporter;

class NovelModule implements AppModule {
  NovelModule({
    this.engine,
    this.dataSource,
    this.collect,
    this.history,
    this.searchHistory,
    this.sourceStore,
    this.sourceImporter,
  });

  final NovelEngine? engine;
  final NovelDataSource? dataSource;
  final NovelCollectApi? collect;
  final NovelHistoryApi? history;
  final NovelSearchHistoryApi? searchHistory;
  final Object? sourceStore; // 书源仓库缝（保留旧注入点）
  final NovelSourceImporter? sourceImporter;

  @override
  MediaType get type => MediaType.novel;
  @override
  String get label => '小说';
  @override
  IconData get icon => MediaType.novel.icon;

  @override
  Widget buildHome(BuildContext context) {
    // 数据层三服务已接线：书架/继续阅读/搜索历史真实读本地库并投影统一书架。
    // 书源导入已接线：网站「一键导入」深链 → 下载 Legado 书源文件 → 本地书源仓库。
    // 抓取流水线（engine/dataSource）仍是纯接口零实现，搜索结果页与阅读页保持
    // 占位——这是能力边界，不再假装"搜索已联通"。

    // 书源管理页：注入真实 WebView + 导入页（依赖齐全时），否则沿用占位屏。
    // 构造器是静态全局注册，按当前模块的依赖解析——多模块实例场景以最后一次
    // buildHome 为准（应用只有一个小说模块实例）。
    final importer = sourceImporter;
    registerNovelRoutePage(
      NovelRoute.sourceManage,
      importer == null
          ? null
          : (_) => NovelSourceManagePage(
              store: importer.store,
              importer: importer,
            ),
    );

    return NovelModulePage(
      embedded: true,
      settingsTab: buildSettings(context),
      collect: collect,
      history: history,
      searchHistory: searchHistory,
      sourceImporter: importer,
      onOpenRoute: (route, {args = const <String, Object?>{}}) =>
          pushNovelRoute<void>(context, route, args: args),
    );
  }

  @override
  Widget buildSettings(BuildContext context) => searchHistory == null
      ? const NovelSettingsPlaceholder()
      : _NovelSettingsWithData(searchHistory: searchHistory!);
}

/// 设置页（接线版）：提供真实可操作的"清除搜索历史"。
/// 搜索历史服务由 NovelModule 注入，清理由服务落本地库。
class _NovelSettingsWithData extends StatelessWidget {
  const _NovelSettingsWithData({required this.searchHistory});

  final NovelSearchHistoryApi searchHistory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.delete_sweep_outlined),
          title: const Text('清除搜索历史'),
          subtitle: const Text('删除本地保存的搜索关键词'),
          onTap: () async {
            await searchHistory.clear();
            if (!context.mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('搜索历史已清除')));
          },
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('阅读器与书源设置随书源引擎切片接入。', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
