// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头说明。
// 书内搜索：按章节并发（顺序）抓正文并匹配关键词，点结果跳到所在段落。
//
// 只依赖一个「按章取段落」的闭包，阅读页据此接引擎缓存；搜到 200 条即停，
// 可随时取消。不联网时（章节都没抓过）会逐章走网络，界面显示进度。

import 'dart:async';

import 'package:flutter/material.dart';

/// 一条书内搜索结果。
class NovelSearchHit {
  const NovelSearchHit({
    required this.chapterIndex,
    required this.chapterTitle,
    required this.paragraph,
    required this.snippet,
  });

  final int chapterIndex;
  final String chapterTitle;
  final int paragraph;
  final String snippet;
}

class NovelSearchSheet extends StatefulWidget {
  const NovelSearchSheet({
    super.key,
    required this.chapterTitles,
    required this.currentChapterIndex,
    required this.loadChapter,
    required this.onPick,
  });

  /// 与章节下标一一对应的标题（卷名不算命中，但保留占位）。
  final List<String> chapterTitles;
  final int currentChapterIndex;
  final Future<List<String>> Function(int chapterIndex) loadChapter;
  final void Function(int chapterIndex, int paragraph) onPick;

  @override
  State<NovelSearchSheet> createState() => _NovelSearchSheetState();
}

class _NovelSearchSheetState extends State<NovelSearchSheet> {
  static const int _maxHits = 200;

  final TextEditingController _keyword = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _wholeBook = true;
  bool _searching = false;
  bool _cancelled = false;
  int _done = 0;
  int _total = 0;
  String? _error;
  List<NovelSearchHit> _hits = const <NovelSearchHit>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _keyword.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final keyword = _keyword.text.trim();
    if (keyword.isEmpty) return;
    final indices = <int>[
      if (_wholeBook)
        for (var i = 0; i < widget.chapterTitles.length; i++) i
      else
        widget.currentChapterIndex,
    ];
    setState(() {
      _searching = true;
      _cancelled = false;
      _error = null;
      _hits = const <NovelSearchHit>[];
      _done = 0;
      _total = indices.length;
    });

    final hits = <NovelSearchHit>[];
    var failures = 0;
    for (final index in indices) {
      if (_cancelled || !mounted) break;
      try {
        final paragraphs = await widget.loadChapter(index);
        for (var p = 0; p < paragraphs.length; p++) {
          final paragraph = paragraphs[p];
          final at = paragraph.indexOf(keyword);
          if (at < 0) continue;
          final start = (at - 16).clamp(0, paragraph.length);
          final end = (at + keyword.length + 30).clamp(start, paragraph.length);
          hits.add(
            NovelSearchHit(
              chapterIndex: index,
              chapterTitle: widget.chapterTitles[index],
              paragraph: p,
              snippet: paragraph.substring(start, end),
            ),
          );
          if (hits.length >= _maxHits) break;
        }
      } on Object {
        failures++;
      }
      _done++;
      if (mounted) {
        setState(() => _hits = List<NovelSearchHit>.unmodifiable(hits));
      }
      if (hits.length >= _maxHits) break;
    }

    if (!mounted) return;
    setState(() {
      _searching = false;
      if (hits.isEmpty && failures == indices.length && indices.isNotEmpty) {
        _error = '所有章节都抓取失败，可能是书源失效或网络异常';
      }
    });
  }

  void _stop() {
    _cancelled = true;
    if (mounted) setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
              child: Row(
                children: <Widget>[
                  Text('书内搜索', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    key: const Key('novel-search-close'),
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      key: const Key('novel-search-field'),
                      controller: _keyword,
                      focusNode: _focus,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: const InputDecoration(
                        hintText: '输入要搜索的文字',
                        prefixIcon: Icon(Icons.search, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('novel-search-submit'),
                    onPressed: _searching ? null : _search,
                    child: const Text('搜索'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: <Widget>[
                  SegmentedButton<bool>(
                    key: const Key('novel-search-scope'),
                    showSelectedIcon: false,
                    segments: const <ButtonSegment<bool>>[
                      ButtonSegment<bool>(value: true, label: Text('全书')),
                      ButtonSegment<bool>(value: false, label: Text('本章')),
                    ],
                    selected: <bool>{_wholeBook},
                    onSelectionChanged: (selection) =>
                        setState(() => _wholeBook = selection.first),
                  ),
                  const Spacer(),
                  if (_searching)
                    Text(
                      '已搜 $_done/$_total 章',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  else if (_hits.isNotEmpty)
                    Text(
                      '${_hits.length} 条结果',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (_searching)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: LinearProgressIndicator(
                        value: _total <= 0 ? null : _done / _total,
                        minHeight: 3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      key: const Key('novel-search-stop'),
                      onPressed: _stop,
                      child: const Text('停止'),
                    ),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
            Expanded(
              child: _hits.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _searching ? '正在逐章搜索…' : '输入关键词后搜索；全书搜索会逐章抓取，首次较慢',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      key: const Key('novel-search-results'),
                      itemCount: _hits.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: scheme.outlineVariant),
                      itemBuilder: (context, index) {
                        final hit = _hits[index];
                        return ListTile(
                          title: Text(
                            hit.chapterTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge,
                          ),
                          subtitle: Text(
                            hit.snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            widget.onPick(hit.chapterIndex, hit.paragraph);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
