// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart，与小说其他页面同款说明。
/// 小说阅读器：目录/正文来自书源引擎，进度写 `novel_history` 并投影时间线。
///
/// 路由参数：`bookId`、`title`、`author`、`sourceKey`、`bookUrl`、`chapterId`、
/// `chapterIndex`、`chapterUrl`、`chapterTitle`。缺目录时按 bookId 重新抓目录。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

class NovelReaderPage extends StatefulWidget {
  const NovelReaderPage({
    super.key,
    required this.bookId,
    this.title,
    this.author,
    this.sourceKey,
    this.bookUrl,
    this.chapterId,
    this.chapterIndex,
    this.chapterUrl,
    this.chapterTitle,
    this.coverUrl,
    this.chapters,
    this.onlineEngine,
    this.sourceStore,
    this.history,
    this.stats,
    this.prefs,
  });

  final String bookId;
  final String? title;
  final String? author;
  final String? sourceKey;
  final String? bookUrl;
  final String? chapterId;
  final int? chapterIndex;
  final String? chapterUrl;
  final String? chapterTitle;
  final String? coverUrl;

  /// 详情页已抓到的目录；有它时阅读器不再重复抓目录。
  final List<NovelChapter>? chapters;
  final NovelOnlineEngine? onlineEngine;
  final NovelSourceStorage? sourceStore;
  final NovelHistoryApi? history;
  final NovelStatsApi? stats;
  final NovelPrefsApi? prefs;

  @override
  State<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends State<NovelReaderPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scroll = ScrollController();
  final Stopwatch _session = Stopwatch();

  NovelBookSource? _source;
  NovelDetail? _detail;
  NovelChapter? _chapter;
  NovelContent? _content;
  String? _loadError;
  bool _loadingDetail = true;
  bool _loadingContent = false;
  double _fontSize = 18;

  @override
  void initState() {
    super.initState();
    _session.start();
    unawaited(_loadFontSize());
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _flushReadingTime();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadFontSize() async {
    final value = await widget.prefs?.read(novelPrefReaderFontSize);
    final parsed = double.tryParse(value ?? '');
    if (parsed != null && mounted) {
      setState(() => _fontSize = parsed.clamp(14, 30));
    }
  }

  Future<void> _bootstrap() async {
    final engine = widget.onlineEngine;
    final store = widget.sourceStore;
    final sourceKey = widget.sourceKey ?? '';
    if (engine == null || store == null || sourceKey.isEmpty) {
      setState(() {
        _loadingDetail = false;
        _loadError = '阅读器未接线（缺少书源引擎或书源信息）';
      });
      return;
    }
    final preloaded = widget.chapters;
    if (preloaded != null && preloaded.isNotEmpty) {
      final detail = NovelDetail(
        ref: NovelRef(
          id: widget.bookId,
          sourceKey: sourceKey,
          bookUrl: widget.bookUrl ?? widget.bookId,
        ),
        title: widget.title ?? '',
        coverUrl: widget.coverUrl ?? '',
        author: widget.author ?? '',
        chapters: preloaded,
      );
      setState(() {
        _detail = detail;
        _loadingDetail = false;
      });
      // 源仍需用于正文抓取；只靠 key 从仓库取一次。
      try {
        final sources = await store.loadAll();
        for (final candidate in sources) {
          if (candidate.key == sourceKey) {
            _source = candidate;
            break;
          }
        }
      } on Object {
        // 忽略：下面统一判空。
      }
      if (_source == null) {
        setState(() => _loadError = '找不到书源（可能已被删除）');
        return;
      }
      final chapter = _pickChapter(detail.chapters);
      if (chapter == null) {
        setState(() => _loadError = '目录为空，无法开始阅读');
        return;
      }
      await _openChapter(chapter);
      return;
    }
    setState(() {
      _loadingDetail = true;
      _loadError = null;
    });
    try {
      final sources = await store.loadAll();
      NovelBookSource? source;
      for (final candidate in sources) {
        if (candidate.key == sourceKey) {
          source = candidate;
          break;
        }
      }
      if (source == null) {
        throw StateError('找不到书源（可能已被删除）');
      }
      final ref = NovelRef(
        id: widget.bookId,
        sourceKey: sourceKey,
        bookUrl: widget.bookUrl ?? widget.bookId,
      );
      final detail = await engine.bookDetail(
        source,
        ref,
        titleHint: widget.title,
        authorHint: widget.author,
      );
      if (!mounted) return;
      setState(() {
        _source = source;
        _detail = detail;
        _loadingDetail = false;
      });
      final chapter = _pickChapter(detail.chapters);
      if (chapter == null) {
        setState(() => _loadError = '目录为空，无法开始阅读');
        return;
      }
      await _openChapter(chapter);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingDetail = false;
        _loadError = '$error';
      });
    }
  }

  NovelChapter? _pickChapter(List<NovelChapter> chapters) {
    if (chapters.isEmpty) return null;
    final id = widget.chapterId;
    if (id != null && id.isNotEmpty) {
      for (final chapter in chapters) {
        if (chapter.id == id || chapter.url == id) return chapter;
      }
    }
    final index = widget.chapterIndex;
    if (index != null && index >= 0 && index < chapters.length) {
      return chapters[index];
    }
    return chapters.first;
  }

  Future<void> _openChapter(NovelChapter chapter) async {
    final engine = widget.onlineEngine;
    final source = _source;
    final detail = _detail;
    if (engine == null || source == null || detail == null) return;
    _flushReadingTime();
    setState(() {
      _chapter = chapter;
      _content = null;
      _loadingContent = true;
      _loadError = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    try {
      final content = await engine.contentFor(source, detail.ref, chapter);
      if (!mounted) return;
      setState(() {
        _content = content;
        _loadingContent = false;
      });
      await widget.history?.saveProgress(
        detail.summary,
        chapter.index,
        detail.chapters.length,
      );
      _session
        ..reset()
        ..start();
      if (!mounted) return;
      if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
        Navigator.of(context).maybePop();
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingContent = false;
        _loadError = '$error';
      });
    }
  }

  void _flushReadingTime() {
    if (!_session.isRunning) return;
    _session.stop();
    final elapsed = _session.elapsed;
    if (elapsed.inSeconds > 0) {
      unawaited(widget.stats?.addReadingTime(elapsed) ?? Future<void>.value());
    }
  }

  void _nextChapter() {
    final chapters = _detail?.chapters ?? const <NovelChapter>[];
    final chapter = _chapter;
    if (chapter == null) return;
    final index = chapter.index + 1;
    if (index < 0 || index >= chapters.length) return;
    unawaited(_openChapter(chapters[index]));
  }

  void _previousChapter() {
    final chapters = _detail?.chapters ?? const <NovelChapter>[];
    final chapter = _chapter;
    if (chapter == null) return;
    final index = chapter.index - 1;
    if (index < 0 || index >= chapters.length) return;
    unawaited(_openChapter(chapters[index]));
  }

  Future<void> _setFontSize(double value) async {
    setState(() => _fontSize = value);
    await widget.prefs?.write(
      novelPrefReaderFontSize,
      value.round().toString(),
    );
  }

  Future<void> _showFontDialog() async {
    var value = _fontSize;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('阅读字号'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Row(
            children: <Widget>[
              const Icon(Icons.text_fields, size: 16),
              Expanded(
                child: Slider(
                  value: value,
                  min: 14,
                  max: 30,
                  divisions: 16,
                  label: value.round().toString(),
                  onChanged: (next) {
                    setDialogState(() => value = next);
                    unawaited(_setFontSize(next));
                  },
                ),
              ),
              const Icon(Icons.text_fields, size: 28),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('完成'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chapters = _detail?.chapters ?? const <NovelChapter>[];
    final chapter = _chapter;
    final canPrevious = chapter != null && chapter.index > 0;
    final canNext = chapter != null && chapter.index + 1 < chapters.length;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          if (canPrevious) _previousChapter();
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          if (canNext) _nextChapter();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: _scaffoldKey,
          drawer: chapters.isEmpty
              ? null
              : Drawer(
                  child: SafeArea(
                    child: ListView.builder(
                      itemCount: chapters.length,
                      itemBuilder: (context, index) {
                        final item = chapters[index];
                        final selected = item.index == chapter?.index;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: item.isVip
                              ? const Icon(Icons.lock_outline, size: 14)
                              : null,
                          onTap: item.isVolume
                              ? null
                              : () => _openChapter(item),
                        );
                      },
                    ),
                  ),
                ),
          appBar: AppBar(
            title: Text(
              chapter?.title ?? widget.title ?? widget.chapterTitle ?? '阅读',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: <Widget>[
              IconButton(
                tooltip: '字号',
                icon: const Icon(Icons.text_fields),
                onPressed: _showFontDialog,
              ),
              IconButton(
                tooltip: '目录',
                icon: const Icon(Icons.list_alt),
                onPressed: chapters.isEmpty
                    ? null
                    : () => _scaffoldKey.currentState?.openDrawer(),
              ),
            ],
            bottom: _loadingContent
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(2),
                    child: LinearProgressIndicator(minHeight: 2),
                  )
                : null,
          ),
          bottomNavigationBar: chapter == null
              ? null
              : _ReaderBottomBar(
                  index: chapter.index,
                  count: chapters.length,
                  canPrevious: canPrevious,
                  canNext: canNext,
                  onPrevious: _previousChapter,
                  onNext: _nextChapter,
                ),
          body: _buildBody(theme),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loadingDetail) {
      return const NovelLoadingState(label: '正在加载目录…');
    }
    if (_loadError != null && _content == null) {
      return NovelErrorState(
        message: _loadError!,
        onRetry: () {
          if (_chapter == null) {
            unawaited(_bootstrap());
          } else {
            unawaited(_openChapter(_chapter!));
          }
        },
      );
    }
    final content = _content;
    if (content == null) {
      return const NovelLoadingState(label: '正在加载正文…');
    }
    return SelectionArea(
      child: Scrollbar(
        controller: _scroll,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: <Widget>[
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      content.title.isEmpty
                          ? _chapter?.title ?? ''
                          : content.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    for (final paragraph in content.paragraphs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Text(
                          paragraph,
                          style: TextStyle(
                            fontSize: _fontSize,
                            height: 1.8,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    if (_loadError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _loadError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({
    required this.index,
    required this.count,
    required this.canPrevious,
    required this.canNext,
    required this.onPrevious,
    required this.onNext,
  });

  final int index;
  final int count;
  final bool canPrevious;
  final bool canNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          children: <Widget>[
            TextButton.icon(
              onPressed: canPrevious ? onPrevious : null,
              icon: const Icon(Icons.chevron_left),
              label: const Text('上一章'),
            ),
            Expanded(
              child: Text(
                '${index + 1} / $count',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: canNext ? onNext : null,
              icon: const Icon(Icons.chevron_right),
              label: const Text('下一章'),
            ),
          ],
        ),
      ),
    );
  }
}
