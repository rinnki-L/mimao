// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart，与 music_entry.dart 同款说明。
/// 小说模块对壳的唯一出口——实现 [AppModule]，由 app_registry 注入全部依赖
/// （docs/architecture.md §4.3）。
///
/// 页面只认注入的窄接口：书架/历史/搜索历史/统计/偏好/书源导入，以及
/// `NovelOnlineEngine`（搜索→发现→目录→正文）。引擎未注入时页面回落到
/// 本地快照/能力边界，不造假数据。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/novel/booklist_io.dart' show NovelBooklistFileGate;
import 'package:mimao/novel/engine/engine.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_book_detail_page.dart';
import 'package:mimao/novel/pages/novel_history_page.dart';
import 'package:mimao/novel/pages/novel_module_page.dart' show NovelModulePage;
import 'package:mimao/novel/pages/novel_reader_page.dart';
import 'package:mimao/novel/pages/novel_routes.dart'
    show NovelRoute, pushNovelRoute, registerNovelRoutePage;
import 'package:mimao/novel/pages/novel_search_page.dart';
import 'package:mimao/novel/pages/novel_settings_page.dart';
import 'package:mimao/novel/pages/novel_source_manage_page.dart'
    show NovelSourceManagePage;
import 'package:mimao/novel/source/novel_rule_model.dart' show NovelRuleKind;
import 'package:mimao/novel/source/novel_rule_store.dart'
    show NovelReplaceRuleStorage;
import 'package:mimao/novel/source/novel_source_importer.dart'
    show NovelSourceImporter;
import 'package:mimao/novel/source/novel_subscription.dart'
    show NovelSubscriptionStore;
import 'package:mimao/novel/webdav_backup.dart' show NovelWebDavClient;

class NovelModule implements AppModule {
  NovelModule({
    this.engine,
    this.dataSource,
    this.onlineEngine,
    this.collect,
    this.history,
    this.searchHistory,
    this.stats,
    this.prefs,
    this.sourceStore,
    this.sourceImporter,
    this.replaceStore,
    this.booklistGate,
    this.subscriptionStore,
    this.backupClient,
  });

  final NovelEngine? engine;
  final NovelDataSource? dataSource;
  final NovelOnlineEngine? onlineEngine;
  final NovelCollectApi? collect;
  final NovelHistoryApi? history;
  final NovelSearchHistoryApi? searchHistory;
  final NovelStatsApi? stats;
  final NovelPrefsApi? prefs;
  final Object? sourceStore; // 书源仓库缝（保留旧注入点）
  final NovelSourceImporter? sourceImporter;

  /// 替换规则仓库：阅读器展示正文/标题前按规则净化。
  final NovelReplaceRuleStorage? replaceStore;
  final NovelBooklistFileGate? booklistGate;
  final NovelSubscriptionStore? subscriptionStore;
  final NovelWebDavClient? backupClient;

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
          : (args) => NovelSourceManagePage(
              store: importer.store,
              importer: importer,
              initialTab: _ruleKindFromTab(args['tab']),
            ),
    );
    registerNovelRoutePage(
      NovelRoute.bookInfo,
      (args) => NovelBookDetailPage(
        bookId: '${args['bookId'] ?? ''}',
        titleHint: args['title']?.toString(),
        authorHint: args['author']?.toString(),
        coverUrlHint: args['coverUrl']?.toString(),
        introHint: args['intro']?.toString(),
        sourceKey: args['sourceKey']?.toString(),
        bookUrl: args['bookUrl']?.toString(),
        onlineEngine: onlineEngine,
        sourceStore: importer?.store,
        collect: collectApi,
        history: historyApi,
      ),
    );
    registerNovelRoutePage(
      NovelRoute.read,
      (args) => NovelReaderPage(
        bookId: '${args['bookId'] ?? ''}',
        title: args['title']?.toString(),
        author: args['author']?.toString(),
        sourceKey: args['sourceKey']?.toString(),
        bookUrl: args['bookUrl']?.toString(),
        chapterId: args['chapterId']?.toString(),
        chapterIndex: args['chapterIndex'] is int
            ? args['chapterIndex'] as int
            : int.tryParse('${args['chapterIndex'] ?? ''}'),
        chapterUrl: args['chapterUrl']?.toString(),
        chapterTitle: args['chapterTitle']?.toString(),
        coverUrl: args['coverUrl']?.toString(),
        chapters: args['chapters'] is List<NovelChapter>
            ? args['chapters'] as List<NovelChapter>
            : null,
        onlineEngine: onlineEngine,
        sourceStore: importer?.store,
        history: historyApi,
        stats: statsApi,
        prefs: prefsApi,
        replaceRules: replaceStore,
      ),
    );
    registerNovelRoutePage(
      NovelRoute.search,
      (args) => NovelSearchPage(
        initialQuery: args['q']?.toString(),
        collect: collectApi,
        history: historyApi,
        searchHistory: searchApi,
        sourceImporter: importer,
        onlineEngine: onlineEngine,
        sourceStore: importer?.store,
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
      onlineEngine: onlineEngine,
      collect: collectApi,
      history: historyApi,
      searchHistory: searchApi,
      sourceImporter: importer,
      stats: statsApi,
      prefs: prefsApi,
      booklistGate: booklistGate,
      subscriptionStore: subscriptionStore,
      backupClient: backupClient,
      // 侧栏底部「设置」项弹这张面板（与漫画/音乐同款），不是独立 tab。
      settingsTab: NovelSettingsPage(
        stats: statsApi,
        searchHistory: searchApi,
        history: historyApi,
        sourceImporter: importer,
        embedded: true,
      ),
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

/// 规则管理页的进参 `tab`（'book' / 'rss' / 'replace'）→ 默认分类。
NovelRuleKind _ruleKindFromTab(Object? tab) => switch ('$tab'.toLowerCase()) {
  'rss' || 'rsssource' || 'subscription' => NovelRuleKind.rssSource,
  'replace' || 'replacerule' => NovelRuleKind.replaceRule,
  _ => NovelRuleKind.bookSource,
};
