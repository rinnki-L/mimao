// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 书籍详情：本地收藏 + 阅读记录的真实快照，收藏切换、分组、清记录、进阅读。
///
/// 目录/简介/正文来自书源引擎，尚未接入，所以只给一条能力边界说明；详情页
/// 不摆假章节。参数：`bookId`（必填）、`title`（无本地快照时的兜底标题）。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_routes.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';

class NovelBookDetailPage extends StatefulWidget {
  const NovelBookDetailPage({
    super.key,
    required this.bookId,
    this.titleHint,
    this.collect,
    this.history,
    this.openRoute,
  });

  final String bookId;
  final String? titleHint;
  final NovelCollectApi? collect;
  final NovelHistoryApi? history;
  final NovelRouteOpener? openRoute;

  @override
  State<NovelBookDetailPage> createState() => _NovelBookDetailPageState();
}

class _NovelBookDetailPageState extends State<NovelBookDetailPage> {
  late Future<_DetailData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DetailData> _load() async {
    NovelCollectItem? collect;
    final collectApi = widget.collect;
    if (collectApi != null) {
      final items = await collectApi.list();
      for (final item in items) {
        if (item.ref.id == widget.bookId) {
          collect = item;
          break;
        }
      }
    }
    final history = await widget.history?.latest(widget.bookId);
    final book =
        collect?.book ??
        history?.book ??
        NovelSummary(
          id: widget.bookId,
          title: widget.titleHint ?? '未知书籍',
          coverUrl: collect?.coverUrl ?? '',
        );
    final groups = await widget.collect?.groups() ?? const <String>[];
    return _DetailData(
      book: book,
      collect: collect,
      history: history,
      groups: groups,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleCollect(_DetailData data) async {
    final api = widget.collect;
    if (api == null) {
      _toast('书架未接线，暂时不能收藏。');
      return;
    }
    try {
      if (data.collect == null) {
        await api.collect(data.book);
        _toast('已加入书架');
      } else {
        await api.remove(data.book.id);
        _toast('已从书架移除（阅读记录保留）');
      }
      _reload();
    } on Object catch (error) {
      _toast('操作失败：$error');
    }
  }

  Future<void> _openRead(_DetailData data) async {
    await openNovelRoute(
      context,
      widget.openRoute,
      NovelRoute.read,
      args: <String, Object?>{'bookId': data.book.id, 'title': data.book.title},
    );
    if (mounted) _reload();
  }

  Future<void> _setGroup(_DetailData data) async {
    final api = widget.collect;
    if (api == null || data.collect == null) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => _DetailGroupDialog(
        groups: data.groups,
        current: data.collect!.groupName,
      ),
    );
    if (choice == null) return;
    try {
      await api.setGroup(data.book.id, choice.isEmpty ? null : choice);
      _reload();
      _toast(choice.isEmpty ? '已移出分组' : '已加入「$choice」');
    } on Object catch (error) {
      _toast('设置分组失败：$error');
    }
  }

  Future<void> _clearHistory(_DetailData data) async {
    final api = widget.history;
    if (api == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空这本书的阅读记录？'),
        content: const Text('阅读进度会丢失；收藏不受影响。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await api.remove(data.book.id);
      _reload();
      _toast('阅读记录已清空');
    } on Object catch (error) {
      _toast('清空失败：$error');
    }
  }

  Future<void> _removeLocal(_DetailData data) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('从本地移除《${data.book.title}》？'),
        content: const Text('收藏与阅读记录都会删除，此操作不可撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.collect?.remove(data.book.id);
      await widget.history?.remove(data.book.id);
      if (mounted) Navigator.of(context).maybePop();
    } on Object catch (error) {
      _toast('移除失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('书籍详情'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<_DetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const NovelLoadingState(label: '正在读取本地记录…');
          }
          if (snapshot.hasError) {
            return NovelErrorState(
              message: '${snapshot.error}',
              onRetry: _reload,
            );
          }
          final data = snapshot.data;
          if (data == null || (data.collect == null && data.history == null)) {
            return const NovelEmptyState(
              icon: Icons.menu_book_outlined,
              title: '本地没有这本书',
              message: '收藏或阅读过之后，详情才会出现在这里。返回书架重新选一本。',
            );
          }
          return NovelPageContent(
            maxWidth: 980,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: ListView(
              children: <Widget>[
                _DetailHero(
                  data: data,
                  onRead: () => _openRead(data),
                  onToggleCollect: () => _toggleCollect(data),
                  onGroup: data.collect == null ? null : () => _setGroup(data),
                  onClearHistory: data.history == null
                      ? null
                      : () => _clearHistory(data),
                  onRemove: () => _removeLocal(data),
                ),
                const SizedBox(height: 20),
                _ProgressCard(item: data.history),
                const SizedBox(height: 16),
                const _TocBoundaryCard(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DetailData {
  const _DetailData({
    required this.book,
    required this.collect,
    required this.history,
    required this.groups,
  });

  final NovelSummary book;
  final NovelCollectItem? collect;
  final NovelHistoryItem? history;
  final List<String> groups;

  bool get collected => collect != null;
}

class _DetailHero extends StatelessWidget {
  const _DetailHero({
    required this.data,
    required this.onRead,
    required this.onToggleCollect,
    required this.onGroup,
    required this.onClearHistory,
    required this.onRemove,
  });

  final _DetailData data;
  final VoidCallback onRead;
  final VoidCallback onToggleCollect;
  final VoidCallback? onGroup;
  final VoidCallback? onClearHistory;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final book = data.book;
    final history = data.history;
    final percent = history == null
        ? null
        : novelBookPercent(
            chapterIndex: history.chapterIndex,
            chapterCount: history.chapterCount,
          );
    final cover = SizedBox(
      width: 168,
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: NovelBookCover(url: book.coverUrl, title: book.title),
      ),
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(book.title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          book.author.isEmpty ? '作者未知' : book.author,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: <Widget>[
            NovelTag(
              label: data.collected ? '已收藏' : '未收藏',
              highlighted: data.collected,
            ),
            if (data.collect?.groupName != null &&
                data.collect!.groupName!.isNotEmpty)
              NovelTag(label: data.collect!.groupName!),
            if (book.sourceName.isNotEmpty) NovelTag(label: '书源'),
          ],
        ),
        const SizedBox(height: 18),
        if (history != null) ...<Widget>[
          Text(
            novelProgressText(
              chapterIndex: history.chapterIndex,
              chapterCount: history.chapterCount,
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(MimaoRadii.pill),
            child: LinearProgressIndicator(
              value: (percent ?? 0) / 100,
              minHeight: 7,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '上次阅读 · ${novelRelativeTime(history.openedAt)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ] else
          Text(
            '还没有阅读进度',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            FilledButton.icon(
              onPressed: onRead,
              icon: const Icon(Icons.auto_stories),
              label: const Text('继续阅读'),
            ),
            FilledButton.tonalIcon(
              onPressed: onToggleCollect,
              icon: Icon(
                data.collected
                    ? Icons.bookmark_remove_outlined
                    : Icons.bookmark_add_outlined,
              ),
              label: Text(data.collected ? '取消收藏' : '加入书架'),
            ),
            PopupMenuButton<String>(
              tooltip: '更多操作',
              icon: const Icon(Icons.more_horiz),
              onSelected: (value) {
                switch (value) {
                  case 'group':
                    onGroup?.call();
                  case 'history':
                    onClearHistory?.call();
                  case 'remove':
                    onRemove();
                }
              },
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                if (onGroup != null)
                  const PopupMenuItem<String>(
                    value: 'group',
                    child: Text('设置分组'),
                  ),
                if (onClearHistory != null)
                  const PopupMenuItem<String>(
                    value: 'history',
                    child: Text('清空阅读记录'),
                  ),
                if (onGroup != null || onClearHistory != null)
                  const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'remove',
                  child: Text('从本地移除', style: TextStyle(color: cs.error)),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(child: cover),
              const SizedBox(height: 18),
              info,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            cover,
            const SizedBox(width: 24),
            Expanded(child: info),
          ],
        );
      },
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.item});

  final NovelHistoryItem? item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final data = item;
    return NovelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const NovelSectionHeader(icon: Icons.history, title: '本地阅读记录'),
          const SizedBox(height: 12),
          if (data == null)
            Text(
              '这本书还没有阅读记录。开始阅读后，章节进度会出现在这里。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 28,
              runSpacing: 12,
              children: <Widget>[
                _DetailStat(
                  label: '章节',
                  value: data.chapterCount > 0
                      ? '${data.chapterIndex} / ${data.chapterCount}'
                      : '未知',
                ),
                _DetailStat(
                  label: '进度',
                  value: novelProgressText(
                    chapterIndex: data.chapterIndex,
                    chapterCount: data.chapterCount,
                  ),
                ),
                _DetailStat(
                  label: '上次阅读',
                  value: novelRelativeTime(data.openedAt),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  const _DetailStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _TocBoundaryCard extends StatelessWidget {
  const _TocBoundaryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NovelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const NovelSectionHeader(icon: Icons.list_alt, title: '目录与正文'),
          const SizedBox(height: 10),
          Text(
            '目录、简介与正文需要书源引擎抓取，当前还未接入。接入后这里会直接'
            '列出章节，并行内跳转阅读。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 详情页的分组选择（比书架批量版更轻：单选 + 新建 + 移出）。
class _DetailGroupDialog extends StatefulWidget {
  const _DetailGroupDialog({required this.groups, required this.current});

  final List<String> groups;
  final String? current;

  @override
  State<_DetailGroupDialog> createState() => _DetailGroupDialogState();
}

class _DetailGroupDialogState extends State<_DetailGroupDialog> {
  final TextEditingController _controller = TextEditingController();
  late String _selected = widget.current ?? '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('设置分组'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final group in widget.groups)
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                value: group,
                groupValue: _selected,
                title: Text(group),
                onChanged: (value) => setState(() {
                  _selected = value ?? '';
                  _controller.clear();
                }),
              ),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: '',
              groupValue: _selected,
              title: const Text('移出分组'),
              onChanged: (value) => setState(() {
                _selected = value ?? '';
                _controller.clear();
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: '或新建分组'),
            ),
            const SizedBox(height: 6),
            Text(
              '新建分组会在确定后立即生效。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final typed = _controller.text.trim();
            Navigator.of(context).pop(typed.isNotEmpty ? typed : _selected);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
