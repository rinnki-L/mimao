/// 本地书引擎：让 TXT / EPUB / Markdown 走**同一个** [NovelOnlineEngine]。
///
/// 设计要点（关键约束：页面里不许出现 `if (isLocal)`）：
/// - 本地书挂在一个固定的虚拟书源下（[novelLocalSourceKey]），
///   [NovelLocalSourceStore] 把这个源「混进」书源列表，于是详情页/阅读器
///   用同一套「按 sourceKey 找源」的代码就能找到它；
/// - [NovelLocalEngine] 按 sourceKey 分流：虚拟源交给本地服务，其余原样转给
///   被包裹的 legado 引擎。搜索/发现/换源对本地源一律返回空，避免本地书
///   出现在「在线搜索结果」里。
///
/// 这样进度、书签、划线、替换规则、TTS 全部复用现有链路：它们只认
/// (bookId, sourceKey, chapterIndex/段落)，不关心正文来自网络还是磁盘。
library;

import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/debug/novel_engine_trace.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/local/local_book_service.dart';
import 'package:mimao/novel/local/local_models.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

/// 虚拟本地书源：`enabled` 恒真（阅读器要求源存在），但不参与搜索/发现。
NovelBookSource get novelLocalBookSource => NovelBookSource(
  key: novelLocalSourceKey,
  name: novelLocalSourceLabel,
  url: novelLocalSourceUrl,
  type: 3, // legado bookSourceType=3（文件），语义上最接近「本地文件」
  enabled: true,
  raw: const <String, dynamic>{
    'bookSourceName': novelLocalSourceLabel,
    'bookSourceUrl': novelLocalSourceUrl,
    'bookSourceType': 3,
    'bookSourceGroup': '本地',
    // 没有 searchUrl / exploreUrl：搜索与发现页按「配置了地址」过滤时天然排除它。
  },
);

/// 把虚拟本地源追加到真实书源列表末尾。
///
/// 只给「详情页 / 阅读器」用（它们按 sourceKey 找源）；搜索页与发现页仍拿
/// 原始仓库，本地书不会出现在在线搜索与源管理列表里。
class NovelLocalSourceStore implements NovelSourceStorage {
  NovelLocalSourceStore(this._inner);

  final NovelSourceStorage _inner;

  @override
  Future<List<NovelBookSource>> loadAll() async {
    final sources = await _inner.loadAll();
    if (sources.any((source) => source.key == novelLocalSourceKey)) {
      return sources;
    }
    return List<NovelBookSource>.unmodifiable(<NovelBookSource>[
      ...sources,
      novelLocalBookSource,
    ]);
  }

  @override
  Future<int> saveAll(Iterable<NovelBookSource> sources) =>
      _inner.saveAll(sources);

  @override
  Future<void> setEnabled(String key, bool enabled) {
    // 虚拟源不可启停（它代表「本地文件」这个能力本身）。
    if (key == novelLocalSourceKey) return Future<void>.value();
    return _inner.setEnabled(key, enabled);
  }

  @override
  Future<bool> delete(String key) {
    if (key == novelLocalSourceKey) return Future<bool>.value(false);
    return _inner.delete(key);
  }
}

/// 本地书引擎：按 sourceKey 分流到本地服务或被包裹的在线引擎。
class NovelLocalEngine implements NovelOnlineEngine, NovelEngineTraceable {
  NovelLocalEngine({required this.local, this.online});

  final NovelLocalBookStorage local;

  /// 被包裹的在线引擎；null 时本地书仍可读，在线能力返回空。
  final NovelOnlineEngine? online;

  bool _isLocal(NovelBookSource source) => source.key == novelLocalSourceKey;

  @override
  Future<List<NovelSummary>> searchSource(
    NovelBookSource source,
    String keyword, {
    int page = 1,
  }) async {
    if (_isLocal(source)) return const <NovelSummary>[];
    final inner = online;
    if (inner == null) {
      throw StateError('在线书源引擎未启用，无法搜索。重启应用后再试。');
    }
    return inner.searchSource(source, keyword, page: page);
  }

  @override
  Future<List<NovelExploreKind>> exploreKinds(NovelBookSource source) async {
    if (_isLocal(source)) return const <NovelExploreKind>[];
    final inner = online;
    if (inner == null) return const <NovelExploreKind>[];
    return inner.exploreKinds(source);
  }

  @override
  Future<List<NovelSummary>> exploreSource(
    NovelBookSource source,
    NovelExploreKind kind, {
    int page = 1,
  }) async {
    if (_isLocal(source)) return const <NovelSummary>[];
    final inner = online;
    if (inner == null) {
      throw StateError('在线书源引擎未启用，无法浏览分类。重启应用后再试。');
    }
    return inner.exploreSource(source, kind, page: page);
  }

  @override
  Future<NovelDetail> bookDetail(
    NovelBookSource source,
    NovelRef ref, {
    String? titleHint,
    String? authorHint,
  }) async {
    if (!_isLocal(source)) {
      final inner = online;
      if (inner == null) {
        throw StateError('在线书源引擎未启用，无法加载目录。重启应用后再试。');
      }
      return inner.bookDetail(
        source,
        ref,
        titleHint: titleHint,
        authorHint: authorHint,
      );
    }

    final book = await _requireBook(ref.id);
    final chapters = <NovelChapter>[
      for (var i = 0; i < book.chapters.length; i++)
        NovelChapter(
          id: _chapterIdOf(book, i),
          title: book.chapters[i].title,
          index: i,
          url: '',
        ),
    ];
    return NovelDetail(
      ref: _localRef(book),
      title: book.title,
      author: book.author,
      coverUrl: '',
      intro: _introOf(book),
      kind: book.format.label,
      latestChapter: chapters.isEmpty ? '' : chapters.last.title,
      wordCount: '',
      chapters: chapters,
    );
  }

  @override
  Future<NovelContent> contentFor(
    NovelBookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) async {
    if (!_isLocal(source)) {
      final inner = online;
      if (inner == null) {
        throw StateError('在线书源引擎未启用，无法加载正文。重启应用后再试。');
      }
      return inner.contentFor(source, ref, chapter);
    }

    final book = await _requireBook(ref.id);
    // 优先按章 id（EPUB 的 href / TXT 的下标串）定位；找不到再用 index。
    final index = _resolveChapterIndex(book, chapter);
    if (index < 0) {
      throw StateError(
        '这一章不在本地书的目录里（文件可能换过版本）。'
        '回到详情页刷新目录，或重新导入这个文件。',
      );
    }
    final paragraphs = await local.readChapter(book, index);
    return NovelContent(
      chapterId: _chapterIdOf(book, index),
      title: book.chapters[index].title,
      paragraphs: paragraphs,
    );
  }

  @override
  void close() {
    online?.close();
  }

  // 调试追踪必须穿透这层包装：书源调试面板拿到的引擎是 `NovelLocalEngine`，
  // 它把在线请求转给 `online`。不转发的话，调试面板「跑」出来只有一条解析
  // 结果、看不到 HTTP 与规则链路（真源联调时踩到）。
  @override
  void attachTrace(NovelTraceSink? sink) {
    final inner = online;
    if (inner is NovelEngineTraceable) {
      (inner as NovelEngineTraceable).attachTrace(sink);
    }
  }

  @override
  void beginTracePhase(String phase) {
    final inner = online;
    if (inner is NovelEngineTraceable) {
      (inner as NovelEngineTraceable).beginTracePhase(phase);
    }
  }

  Future<NovelLocalBook> _requireBook(String id) async {
    final book = await local.byId(id);
    if (book != null) return book;
    throw StateError(
      '这本书不在本地书库里（导入记录可能已被删除）。'
      '回到书架重新导入这个文件。',
    );
  }

  int _resolveChapterIndex(NovelLocalBook book, NovelChapter chapter) {
    if (chapter.id.isNotEmpty) {
      for (var i = 0; i < book.chapters.length; i++) {
        if (_chapterIdOf(book, i) == chapter.id) return i;
      }
    }
    if (chapter.index >= 0 && chapter.index < book.chapters.length) {
      return chapter.index;
    }
    return -1;
  }

  String _chapterIdOf(NovelLocalBook book, int index) {
    final href = book.chapters[index].href;
    return href.isNotEmpty ? href : '$index';
  }

  NovelRef _localRef(NovelLocalBook book) => NovelRef(
    id: book.id,
    sourceName: novelLocalSourceName,
    sourceKey: novelLocalSourceKey,
    bookUrl: '$novelLocalSourceUrl/${book.id}',
  );

  String _introOf(NovelLocalBook book) {
    final size = book.byteSize;
    final sizeText = size >= 1024 * 1024
        ? '${(size / 1024 / 1024).toStringAsFixed(1)} MB'
        : '${(size / 1024).ceil()} KB';
    final encoding = book.encoding == null ? '' : ' · ${book.encoding!.label}';
    return '本地文件 · ${book.format.label}$encoding · $sizeText\n${book.path}';
  }
}

/// 详情页 / 阅读器要的「能认出本地书」的 ref（供页面构造路由参数时复用）。
NovelRef novelLocalRefOf(NovelLocalBook book) => NovelRef(
  id: book.id,
  sourceName: novelLocalSourceName,
  sourceKey: novelLocalSourceKey,
  bookUrl: '$novelLocalSourceUrl/${book.id}',
);
