/// legado 书源四阶段流水线（搜索 → 发现 → 详情/目录 → 正文）的 Dart 实现。
///
/// 只做编排：规则解析在 `analyzer/`，URL/HTTP 在 `engine/analyze_url.dart`，
/// JS 在 `js/legado_js_host.dart`。失败收敛成 [NovelEngineException]，UI 直接
/// 展示可读原因；堆栈由调用方进日志。
library;

import 'dart:async';

import 'package:mimao/novel/analyzer/legado_rule_analyzer.dart';
import 'package:mimao/novel/analyzer/rule_models.dart';
import 'package:mimao/novel/cache/novel_cache.dart';
import 'package:mimao/novel/engine/analyze_url.dart';
import 'package:mimao/novel/engine/content_text.dart';
import 'package:mimao/novel/engine/engine.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/novel_http_client.dart';
import 'package:mimao/novel/js/legado_js_host.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

/// 书源流水线失败（搜索/目录/正文）。消息可直接展给用户。
class NovelEngineException implements Exception {
  const NovelEngineException(this.message, {this.sourceName = ''});

  final String message;
  final String sourceName;

  @override
  String toString() => sourceName.isEmpty ? message : '[$sourceName] $message';
}

/// 生产书源引擎。一个实例持有传输与每源一个 JS 宿主；用完调用 [close]。
class LegadoNovelEngine implements NovelEngine {
  LegadoNovelEngine({
    NovelHttpTransport? transport,
    this.cache,
    this.requestTimeout = const Duration(seconds: 30),
  }) : _transport = transport ?? DioNovelHttpTransport();

  final NovelHttpTransport _transport;
  final Map<String, LegadoJsHost> _hosts = <String, LegadoJsHost>{};
  final Set<String> _loadedLibraries = <String>{};
  final Map<String, String> _warnings = <String, String>{};

  /// 正文缓存（可空；null = 每次走网络）。
  final NovelCache? cache;
  final Duration requestTimeout;

  bool _closed = false;

  /// 某源最近一次非致命警告（如 webView 降级），UI 可选择展示。
  String? warningFor(String sourceKey) => _warnings[sourceKey];

  void close() {
    if (_closed) return;
    _closed = true;
    for (final host in _hosts.values) {
      host.dispose();
    }
    _hosts.clear();
    _transport.close();
  }

  // ---------------------------------------------------------------------------
  // NovelEngine 接口（书源参数必须是 [NovelBookSource]）

  @override
  Future<List<NovelSummary>> search(BookSource source, String keyword) =>
      searchSource(_legadoSource(source), keyword);

  @override
  Future<List<NovelSummary>> discover(BookSource source) async {
    final legado = _legadoSource(source);
    final kinds = await exploreKinds(legado);
    if (kinds.isEmpty) return const <NovelSummary>[];
    return exploreSource(legado, kinds.first);
  }

  @override
  Future<NovelDetail> chapters(BookSource source, NovelRef ref) =>
      bookDetail(_legadoSource(source), ref);

  @override
  Future<NovelContent> content(
    BookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) => contentFor(_legadoSource(source), ref, chapter);

  // ---------------------------------------------------------------------------
  // 搜索

  Future<List<NovelSummary>> searchSource(
    NovelBookSource source,
    String keyword, {
    int page = 1,
  }) async {
    final rules = source.ruleSet;
    if (source.searchUrl.trim().isEmpty) {
      throw NovelEngineException('书源没有搜索地址', sourceName: source.name);
    }
    await _loadLibrary(source);
    try {
      final fetched = await _fetch(
        source,
        ruleUrl: source.searchUrl,
        key: keyword,
        page: page,
      );
      final analyzer =
          _analyzer(
              source,
              content: fetched.response.body,
              baseUrl: fetched.response.url,
              redirectUrl: fetched.response.url,
            )
            ..page = page
            ..key = keyword;
      return await _parseBookList(
        source,
        analyzer,
        rules,
        baseUrl: fetched.response.url,
        isSearch: true,
      );
    } on NovelEngineException {
      rethrow;
    } on Object catch (error) {
      throw NovelEngineException('搜索失败：$error', sourceName: source.name);
    }
  }

  // ---------------------------------------------------------------------------
  // 发现

  Future<List<NovelExploreKind>> exploreKinds(NovelBookSource source) async {
    await _loadLibrary(source);
    try {
      return await parseExploreKinds(
        source.exploreUrl,
        jsRunner: _host(source).evaluate,
        baseUrl: source.url,
        sourceInfo: _sourceInfo(source),
      );
    } on Object catch (error) {
      throw NovelEngineException('发现分类解析失败：$error', sourceName: source.name);
    }
  }

  Future<List<NovelSummary>> exploreSource(
    NovelBookSource source,
    NovelExploreKind kind, {
    int page = 1,
  }) async {
    final rules = source.ruleSet;
    await _loadLibrary(source);
    try {
      final fetched = await _fetch(source, ruleUrl: kind.url, page: page);
      final analyzer = _analyzer(
        source,
        content: fetched.response.body,
        baseUrl: fetched.response.url,
        redirectUrl: fetched.response.url,
      )..page = page;
      return await _parseBookList(
        source,
        analyzer,
        rules,
        baseUrl: fetched.response.url,
        isSearch: false,
      );
    } on NovelEngineException {
      rethrow;
    } on Object catch (error) {
      throw NovelEngineException('发现列表失败：$error', sourceName: source.name);
    }
  }

  // ---------------------------------------------------------------------------
  // 详情 + 目录

  Future<NovelDetail> bookDetail(
    NovelBookSource source,
    NovelRef ref, {
    String? titleHint,
    String? authorHint,
  }) async {
    final rules = source.ruleSet;
    final bookUrl = _bookUrlOf(ref);
    if (bookUrl.isEmpty) {
      throw NovelEngineException('缺少详情页地址', sourceName: source.name);
    }
    await _loadLibrary(source);
    try {
      final fetched = await _fetch(source, ruleUrl: bookUrl, baseUrl: bookUrl);
      final response = fetched.response;
      final analyzer = _analyzer(
        source,
        content: response.body,
        baseUrl: bookUrl,
        redirectUrl: response.url,
      );
      if (rules.infoInit.isNotEmpty) {
        final init = await analyzer.getElement(rules.infoInit);
        if (init != null) analyzer.setContent(init);
      }
      final name = cleanTitle(await analyzer.getString(rules.infoName));
      final author = cleanTitle(await analyzer.getString(rules.infoAuthor));
      final kindList = await analyzer.getStringList(rules.infoKind);
      final intro = htmlToText(await analyzer.getString(rules.infoIntro));
      final latestChapter = cleanTitle(
        await analyzer.getString(rules.infoLastChapter),
      );
      final wordCount = cleanTitle(
        await analyzer.getString(rules.infoWordCount),
      );
      final coverRaw = await analyzer.getString(rules.infoCoverUrl);
      final coverUrl = coverRaw.isEmpty
          ? ''
          : _absolute(response.url, coverRaw);
      var tocUrl = await analyzer.getString(rules.infoTocUrl, isUrl: true);
      if (tocUrl.isEmpty) tocUrl = response.url;

      final detail = _detailBase(
        ref,
        bookUrl: bookUrl,
        title: name.isEmpty ? (titleHint ?? '') : name,
        author: author.isEmpty ? (authorHint ?? '') : author,
        intro: intro,
        kind: kindList == null ? '' : kindList.join(','),
        latestChapter: latestChapter,
        wordCount: wordCount,
        coverUrl: coverUrl,
      );

      final chapters = tocUrl == bookUrl || tocUrl == response.url
          ? await _parseToc(
              source,
              rules,
              detail,
              body: response.body,
              pageUrl: response.url,
              redirectUrl: response.url,
            )
          : await _fetchAndParseToc(source, rules, detail, tocUrl);

      return NovelDetail(
        ref: detail.ref,
        title: detail.title,
        coverUrl: detail.coverUrl,
        author: detail.author,
        intro: detail.intro,
        kind: detail.kind,
        latestChapter: detail.latestChapter,
        wordCount: detail.wordCount,
        chapters: chapters,
      );
    } on NovelEngineException {
      rethrow;
    } on Object catch (error) {
      throw NovelEngineException('详情/目录失败：$error', sourceName: source.name);
    }
  }

  Future<List<NovelChapter>> _fetchAndParseToc(
    NovelBookSource source,
    NovelSourceRules rules,
    NovelDetail detail,
    String tocUrl,
  ) async {
    final fetched = await _fetch(source, ruleUrl: tocUrl, baseUrl: tocUrl);
    return _parseToc(
      source,
      rules,
      detail,
      body: fetched.response.body,
      pageUrl: fetched.response.url,
      redirectUrl: fetched.response.url,
    );
  }

  Future<List<NovelChapter>> _parseToc(
    NovelBookSource source,
    NovelSourceRules rules,
    NovelDetail detail, {
    required String body,
    required String pageUrl,
    required String redirectUrl,
  }) async {
    final analyzer = _analyzer(
      source,
      content: body,
      baseUrl: pageUrl,
      redirectUrl: redirectUrl,
      bookInfo: _bookInfo(source, detail.summary),
    );
    if (rules.tocPreUpdateJs.isNotEmpty) {
      try {
        await analyzer.evalJs(rules.tocPreUpdateJs);
      } on Object {
        // preUpdateJs 失败不阻断目录（与 legado 一致）。
      }
    }

    var listRule = rules.tocChapterList;
    var reversed = false;
    if (listRule.startsWith('-')) {
      reversed = true;
      listRule = listRule.substring(1);
    }
    if (listRule.startsWith('+')) listRule = listRule.substring(1);

    // 先在原始目录页上取「下一页目录」；解析条目会把 analyzer.content
    // 换成最后一个章节节点，之后再取就拿不到分页链接了。
    final nextList =
        await analyzer.getStringList(rules.tocNextUrl, isUrl: true) ??
        const <String>[];

    final chapters = <NovelChapter>[];
    final visited = <String>{redirectUrl};
    await _parseTocPage(
      source,
      rules,
      analyzer,
      listRule,
      detail,
      redirectUrl,
      chapters,
    );
    var pageCount = 0;
    for (final next in nextList) {
      if (next.isEmpty || visited.contains(next) || pageCount++ > 40) {
        continue;
      }
      visited.add(next);
      try {
        final fetched = await _fetch(source, ruleUrl: next, baseUrl: pageUrl);
        final nextAnalyzer = _analyzer(
          source,
          content: fetched.response.body,
          baseUrl: next,
          redirectUrl: fetched.response.url,
          bookInfo: _bookInfo(source, detail.summary),
        );
        await _parseTocPage(
          source,
          rules,
          nextAnalyzer,
          listRule,
          detail,
          fetched.response.url,
          chapters,
        );
      } on Object {
        // 单页失败保留已拿到的章节；UI 仍可读。
      }
    }

    final seen = <String>{};
    var unique = <NovelChapter>[
      for (final chapter in chapters)
        if (seen.add(chapter.id)) chapter,
    ];
    // legado 的约定：`-` 前缀表示该源列表是倒序（最新在前），翻成阅读顺序；
    // 没有前缀就是源的自然顺序（多数站点即最旧在前），不要再翻。
    if (reversed) unique = unique.reversed.toList();
    return <NovelChapter>[
      for (var i = 0; i < unique.length; i++)
        NovelChapter(
          id: unique[i].id,
          title: unique[i].title,
          index: i,
          url: unique[i].url,
          isVolume: unique[i].isVolume,
          isVip: unique[i].isVip,
          tag: unique[i].tag,
        ),
    ];
  }

  Future<void> _parseTocPage(
    NovelBookSource source,
    NovelSourceRules rules,
    LegadoRuleAnalyzer analyzer,
    String listRule,
    NovelDetail detail,
    String pageUrl,
    List<NovelChapter> out,
  ) async {
    final elements = await analyzer.getElements(listRule);
    if (elements.isEmpty) return;
    final nameRule = rules.tocChapterName;
    final urlRule = rules.tocChapterUrl;
    final volumeRule = rules.tocIsVolume;
    final vipRule = rules.tocIsVip;
    final tagRule = rules.tocUpdateTime;
    for (final element in elements) {
      analyzer.setContent(element);
      final title = cleanTitle(await analyzer.getString(nameRule));
      if (title.isEmpty) continue;
      final isVolume =
          volumeRule.isNotEmpty &&
          _truthy(await analyzer.getString(volumeRule));
      var url = await analyzer.getString(urlRule, isUrl: true);
      if (url.isEmpty) {
        url = isVolume ? '$title${out.length}' : pageUrl;
      }
      final isVip =
          vipRule.isNotEmpty && _truthy(await analyzer.getString(vipRule));
      final tag = tagRule.isEmpty ? '' : await analyzer.getString(tagRule);
      out.add(
        NovelChapter(
          id: url.isEmpty ? '$pageUrl#$title' : url,
          title: title,
          index: out.length,
          url: url,
          isVolume: isVolume,
          isVip: isVip,
          tag: tag,
        ),
      );
    }
    // 每条 item 解析后 analyzer.content 被替换；本页不再需要原 body。
  }

  // ---------------------------------------------------------------------------
  // 正文

  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) async {
    final cached = await cache?.read(ref, chapter);
    if (cached != null) return cached;
    final rules = source.ruleSet;
    if (rules.contentRule.isEmpty) {
      throw NovelEngineException('书源没有正文规则', sourceName: source.name);
    }
    final chapterUrl = chapter.url.isNotEmpty ? chapter.url : _bookUrlOf(ref);
    if (chapterUrl.isEmpty) {
      throw NovelEngineException('章节缺少地址', sourceName: source.name);
    }
    await _loadLibrary(source);
    try {
      final fetched = await _fetch(
        source,
        ruleUrl: chapterUrl,
        baseUrl: _bookUrlOf(ref),
        chapter: chapter,
      );
      final bookInfo = _bookInfo(source, _summaryOf(ref, chapter));
      final analyzer = _analyzer(
        source,
        content: fetched.response.body,
        baseUrl: chapterUrl,
        redirectUrl: fetched.response.url,
        bookInfo: bookInfo,
        chapter: chapter,
      );
      var text = await analyzer.getString(rules.contentRule, unescape: false);

      final nextPages =
          await analyzer.getStringList(rules.contentNextUrl, isUrl: true) ??
          const <String>[];
      var pageCount = 0;
      for (final next in nextPages) {
        if (next.isEmpty || pageCount++ >= 20) continue;
        if (next == fetched.response.url) continue;
        try {
          final nextFetch = await _fetch(
            source,
            ruleUrl: next,
            baseUrl: chapterUrl,
            chapter: chapter,
          );
          analyzer
            ..baseUrl = next
            ..setRedirectUrl(nextFetch.response.url)
            ..setContent(nextFetch.response.body);
          final nextText = await analyzer.getString(
            rules.contentRule,
            unescape: false,
          );
          if (nextText.trim().isNotEmpty) text = '$text\n$nextText';
        } on Object {
          // 单页失败保留上一页正文。
        }
      }

      if (rules.contentSubContent.isNotEmpty) {
        analyzer
          ..baseUrl = chapterUrl
          ..setRedirectUrl(fetched.response.url)
          ..setContent(fetched.response.body);
        final sub = (await analyzer.getString(
          rules.contentSubContent,
          unescape: false,
        )).trim();
        if (sub.isNotEmpty) {
          if (sub.toLowerCase().startsWith('http')) {
            try {
              final subFetch = await _fetch(
                source,
                ruleUrl: sub,
                baseUrl: chapterUrl,
              );
              text = '$text\n${subFetch.response.body}';
            } on Object {
              // 补充内容失败不阻断正文。
            }
          } else {
            text = '$text\n$sub';
          }
        }
      }

      var title = chapter.title;
      if (rules.contentTitle.isNotEmpty) {
        analyzer
          ..baseUrl = chapterUrl
          ..setRedirectUrl(fetched.response.url)
          ..setContent(fetched.response.body);
        final parsedTitle = cleanTitle(
          await analyzer.getString(rules.contentTitle),
        );
        if (parsedTitle.isNotEmpty) title = parsedTitle;
      }

      if (rules.contentReplaceRegex.isNotEmpty) {
        final normalized = text
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .join('\n');
        analyzer
          ..baseUrl = chapterUrl
          ..setRedirectUrl(fetched.response.url)
          ..setContent(fetched.response.body);
        final replaced = await analyzer.getString(
          rules.contentReplaceRegex,
          content: normalized,
          unescape: false,
        );
        if (replaced.trim().isNotEmpty) text = replaced;
      }

      final paragraphs = htmlToParagraphs(text);
      if (paragraphs.isEmpty) {
        throw NovelEngineException(
          '正文为空（可能需登录或书源已失效）',
          sourceName: source.name,
        );
      }
      final content = NovelContent(
        chapterId: chapter.id,
        title: title,
        paragraphs: paragraphs,
      );
      await cache?.write(ref, chapter, content);
      return content;
    } on NovelEngineException {
      rethrow;
    } on Object catch (error) {
      throw NovelEngineException('正文抓取失败：$error', sourceName: source.name);
    }
  }

  // ---------------------------------------------------------------------------
  // 列表解析

  Future<List<NovelSummary>> _parseBookList(
    NovelBookSource source,
    LegadoRuleAnalyzer analyzer,
    NovelSourceRules rules, {
    required String baseUrl,
    required bool isSearch,
  }) async {
    var listRule = isSearch ? rules.searchBookList : rules.exploreBookList;
    if (listRule.isEmpty && !isSearch) listRule = rules.searchBookList;
    var reversed = false;
    if (listRule.startsWith('-')) {
      reversed = true;
      listRule = listRule.substring(1);
    }
    if (listRule.startsWith('+')) listRule = listRule.substring(1);

    final elements = listRule.isEmpty
        ? const <Object?>[]
        : await analyzer.getElements(listRule);
    var books = <NovelSummary>[];
    if (elements.isEmpty) {
      final single = await _summaryFromDetailPage(
        source,
        analyzer,
        rules,
        baseUrl,
        requirePatternMatch: isSearch,
      );
      if (single != null) books.add(single);
    } else {
      final nameRule = isSearch
          ? (rules.searchName)
          : (rules.exploreName.isEmpty ? rules.searchName : rules.exploreName);
      final authorRule = isSearch
          ? rules.searchAuthor
          : (rules.exploreAuthor.isEmpty
                ? rules.searchAuthor
                : rules.exploreAuthor);
      final kindRule = isSearch
          ? rules.searchKind
          : (rules.exploreKind.isEmpty ? rules.searchKind : rules.exploreKind);
      final introRule = isSearch
          ? rules.searchIntro
          : (rules.exploreIntro.isEmpty
                ? rules.searchIntro
                : rules.exploreIntro);
      final latestRule = isSearch
          ? rules.searchLastChapter
          : (rules.exploreLastChapter.isEmpty
                ? rules.searchLastChapter
                : rules.exploreLastChapter);
      final wordCountRule = isSearch
          ? rules.searchWordCount
          : (rules.exploreWordCount.isEmpty
                ? rules.searchWordCount
                : rules.exploreWordCount);
      final coverRule = isSearch
          ? rules.searchCoverUrl
          : (rules.exploreCoverUrl.isEmpty
                ? rules.searchCoverUrl
                : rules.exploreCoverUrl);
      final bookUrlRule = isSearch
          ? rules.searchBookUrl
          : (rules.exploreBookUrl.isEmpty
                ? rules.searchBookUrl
                : rules.exploreBookUrl);

      for (final element in elements) {
        analyzer.setContent(element);
        final title = cleanTitle(await analyzer.getString(nameRule));
        if (title.isEmpty) continue;
        final bookUrlRaw = await analyzer.getString(bookUrlRule, isUrl: true);
        final bookUrl = bookUrlRaw.isEmpty ? baseUrl : bookUrlRaw;
        final coverRaw = await analyzer.getString(coverRule);
        final coverUrl = coverRaw.isEmpty ? '' : _absolute(baseUrl, coverRaw);
        final kindList = kindRule.isEmpty
            ? const <String>[]
            : await analyzer.getStringList(kindRule) ?? const <String>[];
        books.add(
          NovelSummary(
            id: _bookId(source, bookUrl),
            title: title,
            coverUrl: coverUrl,
            author: cleanTitle(await analyzer.getString(authorRule)),
            sourceName: novelSourceName,
            sourceKey: source.key,
            bookUrl: bookUrl,
            intro: htmlToText(await analyzer.getString(introRule)),
            kind: kindList.join(','),
            latestChapter: cleanTitle(await analyzer.getString(latestRule)),
            wordCount: cleanTitle(await analyzer.getString(wordCountRule)),
            type: source.type,
          ),
        );
      }
    }
    if (reversed) books = books.reversed.toList();
    final seen = <String>{};
    return <NovelSummary>[
      for (final book in books)
        if (seen.add(book.id)) book,
    ];
  }

  Future<NovelSummary?> _summaryFromDetailPage(
    NovelBookSource source,
    LegadoRuleAnalyzer analyzer,
    NovelSourceRules rules,
    String baseUrl, {
    required bool requirePatternMatch,
  }) async {
    if (requirePatternMatch &&
        rules.infoName.isEmpty &&
        source.bookUrlPattern.isEmpty) {
      return null;
    }
    final title = cleanTitle(await analyzer.getString(rules.infoName));
    if (title.isEmpty) return null;
    if (requirePatternMatch && source.bookUrlPattern.isNotEmpty) {
      try {
        if (!RegExp(source.bookUrlPattern).hasMatch(baseUrl)) return null;
      } on Object {
        return null;
      }
    }
    final author = cleanTitle(await analyzer.getString(rules.infoAuthor));
    final coverRaw = await analyzer.getString(rules.infoCoverUrl);
    final coverUrl = coverRaw.isEmpty ? '' : _absolute(baseUrl, coverRaw);
    final kindList = await analyzer.getStringList(rules.infoKind);
    return NovelSummary(
      id: _bookId(source, baseUrl),
      title: title,
      coverUrl: coverUrl,
      author: author,
      sourceName: novelSourceName,
      sourceKey: source.key,
      bookUrl: baseUrl,
      intro: htmlToText(await analyzer.getString(rules.infoIntro)),
      kind: kindList == null ? '' : kindList.join(','),
      latestChapter: cleanTitle(
        await analyzer.getString(rules.infoLastChapter),
      ),
      type: source.type,
    );
  }

  // ---------------------------------------------------------------------------

  Future<({AnalyzeUrl analyze, NovelHttpResponse response})> _fetch(
    NovelBookSource source, {
    required String ruleUrl,
    String? baseUrl,
    String? key,
    int? page,
    NovelChapter? chapter,
  }) async {
    final host = _host(source);
    final analyze = await AnalyzeUrl.resolve(
      ruleUrl: ruleUrl,
      baseUrl: baseUrl ?? source.url,
      transport: _transport,
      source: source,
      jsRunner: host.evaluate,
      variables: <String, String>{
        if (chapter != null) ...<String, String>{
          'chapterTitle': chapter.title,
          'chapterIndex': '${chapter.index}',
        },
      },
      sourceInfo: _sourceInfo(source),
      key: key,
      page: page,
    );
    final response = await analyze.fetch();
    if (response.usedWebViewFallback) {
      _warnings[source.key] = '书源要求 WebView，本次按 HTTP 抓取';
    }
    return (analyze: analyze, response: response);
  }

  LegadoRuleAnalyzer _analyzer(
    NovelBookSource source, {
    Object? content,
    String? baseUrl,
    String? redirectUrl,
    Map<String, String>? bookInfo,
    NovelChapter? chapter,
  }) {
    final analyzer = LegadoRuleAnalyzer(
      content: content,
      baseUrl: baseUrl,
      bookName: bookInfo?['name'],
      chapterTitle: chapter?.title,
      jsRunner: _host(source).evaluate,
      sourceInfo: _sourceInfo(source),
      bookInfo: bookInfo,
      chapterInfo: chapter == null
          ? const <String, String>{}
          : <String, String>{
              'title': chapter.title,
              'index': '${chapter.index}',
              'url': chapter.url,
            },
    );
    analyzer.setRedirectUrl(redirectUrl);
    return analyzer;
  }

  LegadoJsHost _host(NovelBookSource source) => _hosts.putIfAbsent(
    source.key,
    () => LegadoJsHost(transport: _transport, source: source),
  );

  Future<void> _loadLibrary(NovelBookSource source) async {
    if (source.jsLib.trim().isEmpty || _loadedLibraries.contains(source.key)) {
      return;
    }
    _loadedLibraries.add(source.key);
    try {
      await _host(source).loadLibrary(source.jsLib);
    } on Object {
      // jsLib 失败不阻断主流程；规则里会自然落到空结果。
    }
  }

  Map<String, String> _sourceInfo(NovelBookSource source) => <String, String>{
    'bookSourceUrl': source.url,
    'bookSourceName': source.name,
    'bookSourceComment': '${source.raw['bookSourceComment'] ?? ''}',
    'bookSourceGroup': '${source.raw['bookSourceGroup'] ?? ''}',
    'bookSourceType': '${source.type}',
    'key': source.key,
  };

  Map<String, String> _bookInfo(NovelBookSource source, NovelSummary book) =>
      <String, String>{
        'name': book.title,
        'author': book.author,
        'bookUrl': book.bookUrl,
        'tocUrl': book.bookUrl,
        'origin': source.url,
        'originName': source.name,
        'kind': book.kind,
        'intro': book.intro,
        'type': '${book.type}',
        'durChapterIndex': '0',
        'durChapterTitle': book.latestChapter,
      };

  NovelDetail _detailBase(
    NovelRef ref, {
    required String bookUrl,
    required String title,
    String author = '',
    String intro = '',
    String kind = '',
    String latestChapter = '',
    String wordCount = '',
    String coverUrl = '',
  }) => NovelDetail(
    ref: NovelRef(
      id: ref.id,
      sourceName: ref.sourceName,
      sourceKey: ref.sourceKey,
      bookUrl: bookUrl,
    ),
    title: title,
    coverUrl: coverUrl,
    author: author,
    intro: intro,
    kind: kind,
    latestChapter: latestChapter,
    wordCount: wordCount,
  );

  NovelSummary _summaryOf(NovelRef ref, NovelChapter chapter) => NovelSummary(
    id: ref.id,
    title: chapter.title,
    sourceName: ref.sourceName,
    sourceKey: ref.sourceKey,
    bookUrl: ref.bookUrl,
  );

  static String _absolute(String base, String relative) {
    final trimmed = relative.trim();
    if (trimmed.isEmpty) return '';
    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) return trimmed;
    final baseUri = Uri.tryParse(base);
    if (baseUri == null) return trimmed;
    try {
      return baseUri.resolve(trimmed).toString();
    } on Object {
      return trimmed;
    }
  }

  static String _bookUrlOf(NovelRef ref) {
    if (ref.bookUrl.trim().isNotEmpty) return ref.bookUrl.trim();
    final index = ref.id.indexOf('::');
    if (index >= 0 && index + 2 < ref.id.length) {
      return ref.id.substring(index + 2);
    }
    return ref.id;
  }

  static String _bookId(NovelBookSource source, String bookUrl) =>
      '${source.key}::$bookUrl';

  static bool _truthy(String value) {
    final text = value.trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes' || text == '是';
  }

  static NovelBookSource _legadoSource(BookSource source) {
    if (source is NovelBookSource) return source;
    throw NovelEngineException('书源不是 legado 书源');
  }
}
