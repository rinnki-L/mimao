// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart，与 music_entry.dart 同款说明。
/// 小说模块对壳的唯一出口——实现 [AppModule]，由 app_registry 注入全部依赖
/// （docs/architecture.md §4.3）。
///
/// 页面只认注入的窄接口：书架/历史/搜索历史/统计/偏好/书源导入。书源引擎
/// （搜索→目录→正文）尚未实现，所有依赖它的入口都落到可读的能力边界页。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/novel/booklist_io.dart' show NovelBooklistFileGate;
import 'package:mimao/novel/engine/engine.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/pages/novel_book_detail_page.dart';
import 'package:mimao/novel/pages/novel_history_page.dart';
import 'package:mimao/novel/pages/novel_module_page.dart' show NovelModulePage;
import 'package:mimao/novel/pages/novel_read_page.dart';
import 'package:mimao/novel/pages/novel_routes.dart'
    show NovelRoute, pushNovelRoute, registerNovelRoutePage;
import 'package:mimao/novel/pages/novel_search_page.dart';
import 'package:mimao/novel/pages/novel_settings_page.dart';
import 'package:mimao/novel/pages/novel_source_manage_page.dart'
    show NovelSourceManagePage;
import 'package:mimao/novel/source/novel_source_importer.dart'
    show NovelSourceImporter;

class NovelModule implements AppModule {
  NovelModule({
    this.engine,
    this.dataSource,
    this.collect,
    this.history,
    this.searchHistory,
    this.stats,
    this.prefs,
    this.sourceStore,
    this.sourceImporter,
    this.booklistGate,
  });

  final NovelEngine? engine;
  final NovelDataSource? dataSource;
  final NovelCollectApi? collect;
  final NovelHistoryApi? history;
  final NovelSearchHistoryApi? searchHistory;
  final NovelStatsApi? stats;
  final NovelPrefsApi? prefs;
  final Object? sourceStore; // 书源仓库缝（保留旧注入点）
  final NovelSourceImporter? sourceImporter;
  final NovelBooklistFileGate? booklistGate;

  @override
  MediaType get type => MediaType.novel;
  @override
  String get label => '小说';
  @override
  IconData get icon => MediaType.novel.icon;

  /// 统计实现同时承担模块 kv；只注入 stats 时自动复用同一实例。
  NovelPrefsApi? get _prefs {
    final current = prefs;
    if (current != null) return current;
    final statsApi = stats;
    if (statsApi is NovelPrefsApi) return statsApi as NovelPrefsApi;
    return null;
  }

  @override
  Widget buildHome(BuildContext context) {
    // 数据层已接线；书源导入已接线。抓取流水线（engine/dataSource）仍是纯
    // 接口零实现，搜索/阅读/目录页一律给能力边界说明，不假装已联通。
    final importer = sourceImporter;
    final statsApi = stats;
    final prefsApi = _prefs;
    final collectApi = collect;
    final historyApi = history;
    final searchApi = searchHistory;

    registerNovelRoutePage(
      NovelRoute.sourceManage,
      importer == null
          ? null
          : (_) => NovelSourceManagePage(
              store: importer.store,
              importer: importer,
            ),
    );
    registerNovelRoutePage(
      NovelRoute.bookInfo,
      (args) => NovelBookDetailPage(
        bookId: '${args['bookId'] ?? ''}',
        titleHint: args['title']?.toString(),
        collect: collectApi,
        history: historyApi,
      ),
    );
    registerNovelRoutePage(
      NovelRoute.read,
      (args) => NovelReadBoundaryPage(
        bookId: '${args['bookId'] ?? ''}',
        title: args['title']?.toString(),
        history: historyApi,
      ),
    );
    registerNovelRoutePage(
      NovelRoute.search,
      (_) => NovelSearchPage(
        collect: collectApi,
        history: historyApi,
        searchHistory: searchApi,
        sourceImporter: importer,
      ),
    );
    registerNovelRoutePage(
      NovelRoute.history,
      (_) => NovelHistoryPage(history: historyApi),
    );
    registerNovelRoutePage(
      NovelRoute.settings,
      (_) => NovelSettingsPage(
        stats: statsApi,
        searchHistory: searchApi,
        history: historyApi,
        sourceImporter: importer,
      ),
    );

    return NovelModulePage(
      embedded: true,
      collect: collectApi,
      history: historyApi,
      searchHistory: searchApi,
      sourceImporter: importer,
      stats: statsApi,
      prefs: prefsApi,
      booklistGate: booklistGate,
      onOpenRoute: (route, {args = const <String, Object?>{}}) =>
          pushNovelRoute<void>(context, route, args: args),
    );
  }

  @override
  Widget buildSettings(BuildContext context) => NovelSettingsPage(
    stats: stats,
    searchHistory: searchHistory,
    history: history,
    sourceImporter: sourceImporter,
  );
}
