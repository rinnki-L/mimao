// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 阅读路由的真实落点：书源引擎/阅读器未接入时，展示这本书已记录的本地进度
/// 与能力边界，而不是一张"正在加载"的假页面。
///
/// 参数：`bookId`、可选 `title`。阅读器接入后，把本页替换成真正的阅读页即可，
/// 路由名与参数契约不变。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';

class NovelReadBoundaryPage extends StatefulWidget {
  const NovelReadBoundaryPage({
    super.key,
    required this.bookId,
    this.title,
    this.history,
  });

  final String bookId;
  final String? title;
  final NovelHistoryApi? history;

  @override
  State<NovelReadBoundaryPage> createState() => _NovelReadBoundaryPageState();
}

class _NovelReadBoundaryPageState extends State<NovelReadBoundaryPage> {
  Future<NovelHistoryItem?> _future = Future<NovelHistoryItem?>.value(null);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<NovelHistoryItem?> _load() async {
    final history = widget.history;
    if (history == null) return null;
    return history.latest(widget.bookId);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.title ?? '阅读';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: NovelPageContent(
        maxWidth: 760,
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                NovelEmptyState(
                  icon: Icons.auto_stories_outlined,
                  title: '阅读器尚未接入',
                  message:
                      '书源引擎负责抓目录与正文，阅读器负责排版与进度上报；'
                      '两者接入后，这个入口会直接打开正文。现在能做的只有查看本地进度。',
                  action: FilledButton.tonal(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('返回'),
                  ),
                ),
                const SizedBox(height: 16),
                FutureBuilder<NovelHistoryItem?>(
                  future: _future,
                  builder: (context, snapshot) {
                    final item = snapshot.data;
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const NovelLoadingState(label: '正在读取本地进度…');
                    }
                    if (item == null) {
                      return NovelCard(
                        child: Text(
                          '这本书还没有本地阅读进度。',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    }
                    final percent = novelBookPercent(
                      chapterIndex: item.chapterIndex,
                      chapterCount: item.chapterCount,
                    );
                    return NovelCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          NovelSectionHeader(
                            icon: Icons.history,
                            title: '本地阅读进度',
                          ),
                          const SizedBox(height: 12),
                          Text(
                            novelProgressText(
                              chapterIndex: item.chapterIndex,
                              chapterCount: item.chapterCount,
                            ),
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              MimaoRadii.pill,
                            ),
                            child: LinearProgressIndicator(
                              value: (percent ?? 0) / 100,
                              minHeight: 7,
                              backgroundColor:
                                  theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '上次阅读 · ${novelRelativeTime(item.openedAt)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
