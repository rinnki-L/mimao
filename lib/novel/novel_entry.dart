// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart，与 music_entry.dart 同款说明。
/// 小说模块对壳的唯一出口——实现 [AppModule]，由 app_registry 注入全部依赖
/// （docs/architecture.md §4.3）。
///
/// 页面只认注入的窄接口：书架/历史/搜索历史/统计/偏好/书源导入，以及
/// `NovelOnlineEngine`（搜索→发现→目录→正文）。引擎未注入时页面回落到
/// 本地快照/能力边界，不造假数据。
library;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/novel/booklist_io.dart' show NovelBooklistFileGate;
import 'package:mimao/novel/engine/engine.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/local/local_book_service.dart';
import 'package:mimao/novel/engine/local_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_book_detail_page.dart';
import 'package:mimao/novel/pages/novel_bookmarks_page.dart';
import 'package:mimao/novel/pages/novel_history_page.dart';
import 'package:mimao/novel/pages/novel_import_book_page.dart';
import 'package:mimao/novel/pages/novel_module_page.dart' show NovelModulePage;
import 'package:mimao/novel/pages/novel_reader_page.dart';
import 'package:mimao/novel/pages/novel_routes.dart'
    show NovelRoute, pushNovelRoute, registerNovelRoutePage;
import 'package:mimao/novel/pages/novel_search_page.dart';
import 'package:mimao/novel/pages/novel_settings_page.dart';
import 'package:mimao/novel/pages/novel_stats_page.dart';
import 'package:mimao/novel/pages/novel_source_debug_page.dart'
    show NovelSourceDebugPage;
import 'package:mimao/novel/pages/novel_source_edit_page.dart'
    show NovelSourceEditPage;
import 'package:mimao/novel/pages/novel_source_manage_page.dart'
    show NovelSourceManagePage;
import 'package:mimao/novel/source/novel_source_model.dart'
    show NovelBookSource;
import 'package:mimao/novel/pages/novel_txt_rules_page.dart';
import 'package:mimao/novel/reader/novel_bookmark_service.dart';
import 'package:mimao/novel/reader/novel_content_override_service.dart';
import 'package:mimao/novel/reader/novel_highlight_rule_service.dart';
import 'package:mimao/novel/reader/novel_locator.dart';
import 'package:mimao/novel/reader/novel_tts_cache.dart';
import 'package:mimao/novel/source/novel_rule_model.dart' show NovelRuleKind;
import 'package:mimao/novel/source/novel_rule_store.dart'
    show NovelReplaceRuleStorage;
import 'package:mimao/novel/source/novel_source_importer.dart'
    show NovelSourceImporter;
import 'package:mimao/novel/source/novel_source_store.dart'
    show NovelSourceStorage;
import 'package:mimao/novel/source/novel_subscription.dart'
    show NovelSubscriptionStore;
import 'package:mimao/novel/webdav_backup.dart'
    show NovelProgressSync, NovelWebDavBackupService;

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
    this.bookmarks,
    this.sourceStore,
    this.sourceImporter,
    this.replaceStore,
    this.highlightStore,
    this.contentOverrides,
    this.booklistGate,
    this.subscriptionStore,
    this.backupService,
    this.progressSync,
    this.ttsCache,
    this.localBooks,
    this.txtRules,
    this.localFileGate,
  });

  final NovelEngine? engine;
  final NovelDataSource? dataSource;
  final NovelOnlineEngine? onlineEngine;
  final NovelCollectApi? collect;
  final NovelHistoryApi? history;
  final NovelSearchHistoryApi? searchHistory;
  final NovelStatsApi? stats;
  final NovelPrefsApi? prefs;

  /// 书签/划线门面（与阅读器、书签页共用同一服务）。
  final NovelBookmarkApi? bookmarks;
  final Object? sourceStore; // 书源仓库缝（保留旧注入点）
  final NovelSourceImporter? sourceImporter;

  /// 本地书门面（TXT / EPUB / Markdown 第二条通路）：导入页与书架入口共用。
  final NovelLocalBookStorage? localBooks;

  /// TXT 目录规则仓库（导入页预览与「我的 → TXT 目录规则」共用）。
  final NovelTxtRuleStorage? txtRules;

  /// 本地书文件选择缝；null 时导入页用 file_picker 生产实现。
  final NovelLocalFileGate? localFileGate;

  /// 替换规则仓库：阅读器展示正文/标题前按规则净化。
  final NovelReplaceRuleStorage? replaceStore;

  /// 高亮规则仓库（阅读器按规则叠加样式）。
  final NovelHighlightRuleStorage? highlightStore;

  /// 单章本地覆盖仓库（阅读器正文编辑）。
  final NovelContentOverrideStorage? contentOverrides;

  /// 朗读音频缓存（L2）；null = 不做缓存（测试或未接数据层）。
  final NovelTtsCache? ttsCache;
  final NovelBooklistFileGate? booklistGate;
  final NovelSubscriptionStore? subscriptionStore;

  /// WebDAV 备份服务（装配处构造；含 client / db / 凭据）。
  final NovelWebDavBackupService? backupService;

  /// 进度同步（阅读页「同步进度」与备份中心共用）。
  final NovelProgressSync? progressSync;

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

  /// 详情页 / 阅读器用的书源仓库：追加虚拟本地源。
  ///
  /// 没有本地书能力（`localBooks == null`）时原样返回，不引入任何新行为。
  NovelSourceStorage? _readingSourceStore(NovelSourceImporter? importer) {
    final store = importer?.store;
    if (store == null) return null;
    if (localBooks == null) return store;
    return NovelLocalSourceStore(store);
  }

  @override
  Widget buildHome(BuildContext context) {
    // 数据层、书源导入与抓取流水线（LegadoNovelEngine）都已接线；宿主没注入
    // 某项依赖时，对应页面降级为能力说明，不假装已联通。
    final importer = sourceImporter;
    final statsApi = stats;
    final prefsApi = _prefs;
    final collectApi = collect;
    final historyApi = history;
    final searchApi = searchHistory;
    // 详情页/阅读器按 sourceKey 找源，本地书挂在虚拟源下——这两个页面拿
    // 「追加了虚拟本地源」的仓库；搜索/发现/规则管理仍用原始仓库，
    // 本地书不会混进在线搜索与源管理列表。
    final readingStore = _readingSourceStore(importer);

    registerNovelRoutePage(
      NovelRoute.sourceManage,
      importer == null
          ? null
          : (args) => NovelSourceManagePage(
              store: importer.store,
              importer: importer,
              subscriptionStore: subscriptionStore,
              initialTab: _ruleKindFromTab(args['tab']),
              enableDebug: kDebugMode,
              // 只在 debug 构建给出调试入口：release 传 null，管理页里
              // 没有任何路径能构造 NovelSourceDebugPage（AOT 整支剔除）。
              openDebug: kDebugMode
                  ? (sourceKey) => pushNovelRoute<void>(
                      context,
                      NovelRoute.sourceDebug,
                      args: <String, Object?>{'sourceKey': sourceKey},
                    )
                  : null,
            ),
    );
    registerNovelRoutePage(
      NovelRoute.sourceEdit,
      importer == null
          ? null
          : (args) => NovelSourceEditPage(
              store: importer.store,
              initial: args['source'] is NovelBookSource
                  ? args['source'] as NovelBookSource
                  : null,
              initialSourceKey: args['sourceKey']?.toString(),
              initialRaw: args['raw']?.toString(),
              onDebug: kDebugMode && onlineEngine != null
                  ? (saved) => pushNovelRoute<void>(
                      context,
                      NovelRoute.sourceDebug,
                      args: <String, Object?>{'sourceKey': saved.key},
                    )
                  : null,
            ),
    );
    // 调试面板只在 debug 构建注册：release 里该路由落到占位屏，
    // NovelSourceDebugPage 不会被任何可达路径构造（AOT 整支剔除）。
    registerNovelRoutePage(
      NovelRoute.sourceDebug,
      !kDebugMode || onlineEngine == null || importer == null
          ? null
          : (args) => NovelSourceDebugPage(
              engine: onlineEngine!,
              store: importer.store,
              initialSourceKey: args['sourceKey']?.toString(),
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
        sourceStore: readingStore,
        collect: collectApi,
        history: historyApi,
        localBooks: localBooks,
        openRoute: (route, {args = const <String, Object?>{}}) =>
            pushNovelRoute<void>(context, route, args: args),
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
        sourceStore: readingStore,
        history: historyApi,
        stats: statsApi,
        prefs: prefsApi,
        replaceRules: replaceStore,
        highlightRules: highlightStore,
        contentOverrides: contentOverrides,
        bookmarks: bookmarks,
        ttsCache: ttsCache,
        localBooks: localBooks,
        txtRules: txtRules,
        localFileGate: localFileGate,
        initialLocator: args['initialLocator'] is NovelLocator
            ? args['initialLocator'] as NovelLocator
            : null,
        progressSync: progressSync,
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
      (_) => NovelHistoryPage(history: historyApi, stats: statsApi),
    );
    registerNovelRoutePage(
      NovelRoute.stats,
      (_) => NovelStatsPage(stats: statsApi),
    );
    registerNovelRoutePage(
      NovelRoute.bookmarks,
      (args) => NovelBookmarksPage(
        bookmarks: bookmarks,
        bookId: args['bookId']?.toString(),
        bookTitle: args['title']?.toString(),
      ),
    );
    registerNovelRoutePage(
      NovelRoute.settings,
      (_) => NovelSettingsPage(
        stats: statsApi,
        searchHistory: searchApi,
        history: historyApi,
        sourceImporter: importer,
        replaceStore: replaceStore,
        highlightStore: highlightStore,
      ),
    );
    registerNovelRoutePage(
      NovelRoute.importBook,
      (args) => NovelImportBookPage(
        localBooks: localBooks,
        rules: txtRules,
        fileGate: localFileGate,
        collect: collectApi,
        relocateBookId: args['relocateBookId']?.toString(),
        initialPath: args['path']?.toString(),
      ),
    );
    registerNovelRoutePage(
      NovelRoute.txtRules,
      (_) => NovelTxtRulesPage(rules: txtRules),
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
      bookmarks: bookmarks,
      booklistGate: booklistGate,
      subscriptionStore: subscriptionStore,
      backupService: backupService,
      progressSync: progressSync,
      localBooks: localBooks,
      // 侧栏底部「设置」项弹这张面板（与漫画/音乐同款），不是独立 tab。
      settingsTab: NovelSettingsPage(
        stats: statsApi,
        searchHistory: searchApi,
        history: historyApi,
        sourceImporter: importer,
        replaceStore: replaceStore,
        highlightStore: highlightStore,
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
    replaceStore: replaceStore,
    highlightStore: highlightStore,
  );
}

/// 规则管理页的进参 `tab`（'book' / 'rss' / 'replace'）→ 默认分类。
NovelRuleKind _ruleKindFromTab(Object? tab) => switch ('$tab'.toLowerCase()) {
  'rss' || 'rsssource' || 'subscription' => NovelRuleKind.rssSource,
  'replace' || 'replacerule' => NovelRuleKind.replaceRule,
  _ => NovelRuleKind.bookSource,
};
