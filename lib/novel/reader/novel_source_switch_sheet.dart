// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头说明。
// 换源面板：在当前启用书源里按「书名（+作者）」搜索同一本书，
// 列出可切换的源；点一项返回给阅读页做目录对齐与进度迁移。
//
// 过滤规则与 legado 的「同名书」一致：去标点后书名相等/包含，作者能对上
// 时优先。找不到就明说，不拿相近书名凑数。

import 'dart:async';

import 'package:flutter/material.dart';

import '../engine/online_engine.dart';
import '../models/novel_models.dart';
import '../source/novel_source_model.dart';

/// 一条可切换的源命中。
class NovelSourceHit {
  const NovelSourceHit({required this.source, required this.book});

  final NovelBookSource source;
  final NovelSummary book;
}

class NovelSourceSwitchSheet extends StatefulWidget {
  const NovelSourceSwitchSheet({
    super.key,
    required this.title,
    required this.author,
    required this.currentSourceKey,
    required this.sources,
    required this.engine,
  });

  final String title;
  final String author;
  final String currentSourceKey;
  final List<NovelBookSource> sources;
  final NovelOnlineEngine engine;

  @override
  State<NovelSourceSwitchSheet> createState() => _NovelSourceSwitchSheetState();
}

class _NovelSourceSwitchSheetState extends State<NovelSourceSwitchSheet> {
  static const int _concurrency = 6;

  bool _searching = true;
  bool _cancelled = false;
  int _done = 0;
  int _total = 0;
  int _failed = 0;
  List<NovelSourceHit> _hits = const <NovelSourceHit>[];

  @override
  void initState() {
    super.initState();
    unawaited(_search());
  }

  Future<void> _search() async {
    final candidates = <NovelBookSource>[
      for (final source in widget.sources)
        if (source.enabled && source.key != widget.currentSourceKey) source,
    ];
    setState(() {
      _searching = true;
      _cancelled = false;
      _hits = const <NovelSourceHit>[];
      _done = 0;
      _total = candidates.length;
      _failed = 0;
    });
    if (candidates.isEmpty) {
      setState(() => _searching = false);
      return;
    }

    final hits = <NovelSourceHit>[];
    var next = 0;
    Future<void> worker() async {
      while (true) {
        if (_cancelled || !mounted) return;
        final index = next++;
        if (index >= candidates.length) return;
        final source = candidates[index];
        try {
          final results = await widget.engine.searchSource(
            source,
            widget.title,
          );
          final matched = results.where(_matches).take(3);
          for (final book in matched) {
            hits.add(NovelSourceHit(source: source, book: book));
          }
        } on Object {
          _failed++;
        }
        _done++;
        if (mounted) {
          setState(() => _hits = List<NovelSourceHit>.unmodifiable(hits));
        }
      }
    }

    await Future.wait(<Future<void>>[
      for (var i = 0; i < _concurrency; i++) worker(),
    ]);
    if (!mounted) return;
    setState(() => _searching = false);
  }

  bool _matches(NovelSummary book) {
    final target = _normalize(widget.title);
    final candidate = _normalize(book.title);
    if (target.isEmpty || candidate.isEmpty) return false;
    final titleMatches =
        target == candidate ||
        candidate.contains(target) ||
        target.contains(candidate);
    if (!titleMatches) return false;
    final author = _normalize(widget.author);
    if (author.isEmpty) return true;
    final otherAuthor = _normalize(book.author);
    return otherAuthor.isEmpty ||
        otherAuthor == author ||
        otherAuthor.contains(author) ||
        author.contains(otherAuthor);
  }

  String _normalize(String value) => value
      .replaceAll(RegExp(r'[\s《》「」『』（）()\[\]【】\-—_·,，。.!！?？:：;；]'), '')
      .toLowerCase();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
              child: Row(
                children: <Widget>[
                  Text('换源', style: theme.textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    key: const Key('novel-switch-source-close'),
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                widget.author.isEmpty
                    ? widget.title
                    : '${widget.title} · ${widget.author}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: LinearProgressIndicator(
                        value: _total <= 0 ? null : _done / _total,
                        minHeight: 3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '已搜 $_done/$_total 源',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    TextButton(
                      key: const Key('novel-switch-source-stop'),
                      onPressed: () {
                        _cancelled = true;
                        setState(() => _searching = false);
                      },
                      child: const Text('停止'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _hits.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _searching
                              ? '正在其它书源里找同名书…'
                              : _total == 0
                              ? '没有其它启用的书源可切换；先在规则管理里导入/启用更多书源'
                              : _failed == _total
                              ? '其它书源全部搜索失败，检查网络或书源状态'
                              : '没有找到同名书，可换关键词在搜索页手动找',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      key: const Key('novel-switch-source-results'),
                      itemCount: _hits.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: scheme.outlineVariant),
                      itemBuilder: (context, index) {
                        final hit = _hits[index];
                        final book = hit.book;
                        return ListTile(
                          leading: const Icon(Icons.swap_horiz),
                          title: Text(
                            book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            <String>[
                              hit.source.name,
                              if (book.author.isNotEmpty) book.author,
                              if (book.latestChapter.isNotEmpty)
                                '最新：${book.latestChapter}',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).pop(hit),
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
