// ignore_for_file: deprecated_member_use — 与其他小说页面同款 Flutter 3.50 说明。
/// 书源调试面板：**只在 debug 构建出现**（路由注册处用 `kDebugMode` 把关，
/// release 里这段代码不可达，AOT 会整支剔除）。
///
/// 面板内容：
/// - 选一条书源 + 一个动作（搜索 / 详情 / 目录 / 正文），跑同一个引擎实例；
/// - 左栏是校验链（搜索 → 详情 → 目录 → 正文，每步耗时与结果摘要）；
/// - 右栏按页签展示「执行链路 / 原始 HTML / JS 控制台 / 错误堆栈」；
/// - 长任务可取消（步骤之间生效，面板文案照实说）。
///
/// 也支持「一键校验全部书源」：逐条跑完整链，汇总通过/失败，可中途取消。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/debug/novel_engine_trace.dart';
import 'package:mimao/novel/debug/novel_source_debugger.dart';
import 'package:mimao/novel/engine/online_engine.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

class NovelSourceDebugPage extends StatefulWidget {
  const NovelSourceDebugPage({
    super.key,
    required this.engine,
    required this.store,
    this.initialSourceKey,
    this.initialKeyword = '',
  });

  final NovelOnlineEngine engine;
  final NovelSourceStorage store;

  /// 从编辑器/管理页跳进来时预选的书源。
  final String? initialSourceKey;
  final String initialKeyword;

  @override
  State<NovelSourceDebugPage> createState() => _NovelSourceDebugPageState();
}

class _NovelSourceDebugPageState extends State<NovelSourceDebugPage> {
  late final NovelSourceDebugger _debugger = NovelSourceDebugger(
    engine: widget.engine,
  );

  List<NovelBookSource> _sources = const <NovelBookSource>[];
  NovelBookSource? _selected;
  bool _loading = true;
  String? _loadError;

  NovelDebugAction _action = NovelDebugAction.search;
  final TextEditingController _keywordController = TextEditingController();
  NovelSummary? _book;
  NovelChapter? _chapter;

  NovelDebugRun? _run;
  bool _running = false;
  NovelDebugCancellation? _cancellation;

  NovelVerifyResult? _verify;
  final Map<String, NovelVerifyResult> _batch = <String, NovelVerifyResult>{};
  bool _batchRunning = false;

  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _keywordController.text = widget.initialKeyword;
    unawaited(_load());
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final sources = await widget.store.loadAll();
      if (!mounted) return;
      final selected = sources
          .where((s) => s.key == widget.initialSourceKey)
          .firstOrNull;
      setState(() {
        _sources = sources;
        _selected = selected ?? sources.firstOrNull;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '读取书源失败：$error';
      });
    }
  }

  Future<void> _runAction() async {
    final source = _selected;
    if (source == null || _running) return;
    final cancellation = NovelDebugCancellation();
    setState(() {
      _running = true;
      _cancellation = cancellation;
      _run = null;
      _tab = 0;
    });
    final run = await _debugger.debug(
      source: source,
      action: _action,
      keyword: _keywordController.text,
      book: _book,
      chapter: _chapter,
      cancellation: cancellation,
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _cancellation = null;
      _run = run;
    });
  }

  Future<void> _runVerify() async {
    final source = _selected;
    if (source == null || _running) return;
    final cancellation = NovelDebugCancellation();
    setState(() {
      _running = true;
      _cancellation = cancellation;
      _verify = null;
      _batch.remove(source.key);
    });
    final result = await _debugger.verify(
      source,
      keyword: _keywordController.text,
      cancellation: cancellation,
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _cancellation = null;
      _verify = result;
      _batch[source.key] = result;
    });
  }

  Future<void> _runBatch() async {
    if (_batchRunning || _sources.isEmpty) return;
    final cancellation = NovelDebugCancellation();
    setState(() {
      _batchRunning = true;
      _cancellation = cancellation;
      _batch.clear();
    });
    for (final source in _sources) {
      if (cancellation.isCancelled) break;
      final result = await _debugger.verify(
        source,
        keyword: _keywordController.text,
        cancellation: cancellation,
      );
      if (!mounted) return;
      setState(() => _batch[source.key] = result);
    }
    if (!mounted) return;
    setState(() {
      _batchRunning = false;
      _cancellation = null;
    });
  }

  void _cancel() {
    _cancellation?.cancel();
    setState(() {});
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已复制$label')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('书源调试')),
        body: const NovelLoadingState(label: '正在读取书源…'),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('书源调试')),
        body: NovelErrorState(message: _loadError!, onRetry: _load),
      );
    }
    if (_sources.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('书源调试')),
        body: NovelEmptyState(
          icon: Icons.bug_report_outlined,
          title: '还没有书源',
          message: '先到「规则管理 → 书源」导入或新建一条书源，再回来调试。',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('书源调试'),
        actions: <Widget>[
          if (_running)
            TextButton.icon(
              key: const Key('novel-debug-cancel'),
              onPressed: _cancel,
              icon: const Icon(Icons.stop_circle_outlined, size: 18),
              label: const Text('取消'),
            ),
          IconButton(
            key: const Key('novel-debug-batch'),
            tooltip: '校验全部书源',
            onPressed: _running || _batchRunning ? null : _runBatch,
            icon: const Icon(Icons.playlist_add_check_circle_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: NovelFillContent(
        maxWidth: 1400,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildControls(theme, cs),
            const SizedBox(height: 12),
            if (_batchRunning || _batch.isNotEmpty) ...<Widget>[
              _BatchSummary(
                results: _batch,
                total: _sources.length,
                running: _batchRunning,
                onCancel: _cancel,
                onPick: (key) {
                  final source = _sources
                      .where((s) => s.key == key)
                      .firstOrNull;
                  if (source == null) return;
                  setState(() {
                    _selected = source;
                    _verify = _batch[key];
                    _run = null;
                  });
                },
              ),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  final left = _buildLeft(theme, cs);
                  final right = _buildRight(theme, cs);
                  if (!wide) {
                    return ListView(
                      children: <Widget>[
                        left,
                        const SizedBox(height: 12),
                        SizedBox(height: 520, child: right),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(width: 360, child: left),
                      const SizedBox(width: 14),
                      Expanded(child: right),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(ThemeData theme, ColorScheme cs) {
    return NovelCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: const Key('novel-debug-source'),
                  initialValue: _selected?.key,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '书源',
                    isDense: true,
                  ),
                  items: <DropdownMenuItem<String>>[
                    for (final source in _sources)
                      DropdownMenuItem<String>(
                        value: source.key,
                        child: Text(
                          '${source.name}${source.enabled ? '' : '（已停用）'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    final source = _sources
                        .where((s) => s.key == value)
                        .firstOrNull;
                    if (source == null) return;
                    setState(() {
                      _selected = source;
                      _run = null;
                      _verify = null;
                      _book = null;
                      _chapter = null;
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const Key('novel-debug-keyword'),
                  controller: _keywordController,
                  decoration: const InputDecoration(
                    labelText: '关键词 / 校验用搜索词',
                    hintText: '留空用书源名',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: SegmentedButton<NovelDebugAction>(
                  key: const Key('novel-debug-action'),
                  segments: <ButtonSegment<NovelDebugAction>>[
                    for (final action in NovelDebugAction.values)
                      ButtonSegment<NovelDebugAction>(
                        value: action,
                        label: Text(action.label),
                      ),
                  ],
                  selected: <NovelDebugAction>{_action},
                  onSelectionChanged: (value) =>
                      setState(() => _action = value.first),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                key: const Key('novel-debug-run'),
                onPressed: _running || _selected == null ? null : _runAction,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text('跑「${_action.label}」'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('novel-debug-verify'),
                onPressed: _running || _selected == null ? null : _runVerify,
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('完整校验'),
              ),
            ],
          ),
          if (_book != null) ...<Widget>[
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                NovelTag(label: '当前书：${_book!.title}'),
                const SizedBox(width: 8),
                if (_chapter != null) NovelTag(label: '章节：${_chapter!.title}'),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() {
                    _book = null;
                    _chapter = null;
                  }),
                  child: const Text('清除选择'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLeft(ThemeData theme, ColorScheme cs) {
    final verify = _verify;
    if (verify == null) {
      return NovelCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            NovelSectionHeader(icon: Icons.route, title: '校验链'),
            const SizedBox(height: 8),
            Text(
              '点「完整校验」依次跑 搜索 → 详情 → 目录 → 正文，'
              '每步给出耗时与结果摘要；失败的那一步会指出具体规则。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '当前动作：${_action.label} —— ${_action.description}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            if (_running) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(minHeight: 4),
              const SizedBox(height: 6),
              Text(
                '执行中…（取消在当前步骤结束后生效）',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      );
    }
    return NovelCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NovelSectionHeader(
            icon: Icons.route,
            title: '校验链 · ${verify.sourceName}',
            trailing: NovelTag(
              label: verify.headline,
              highlighted: verify.passed,
            ),
          ),
          const SizedBox(height: 10),
          for (final step in verify.steps) ...<Widget>[
            _VerifyStepRow(step: step),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          Text(
            '总耗时 ${(verify.totalMs / 1000).toStringAsFixed(2)}s',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          if (verify.firstFailure?.detail.isNotEmpty ?? false) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _copy(verify.firstFailure!.detail, '错误堆栈'),
                icon: const Icon(Icons.copy_all_outlined, size: 16),
                label: const Text('复制错误堆栈'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRight(ThemeData theme, ColorScheme cs) {
    final run = _run;
    final tabs = <String>['执行链路', '原始 HTML', 'JS 控制台', '错误堆栈'];
    return NovelCard(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  onTap: (index) => setState(() => _tab = index),
                  tabs: <Widget>[for (final tab in tabs) Tab(text: tab)],
                ),
              ),
              if (run != null)
                IconButton(
                  tooltip: '复制当前页签内容',
                  onPressed: () => _copy(_tabText(run), tabs[_tab]),
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                ),
            ],
          ),
          if (run == null)
            Expanded(
              child: Center(
                child: Text(
                  _running ? '正在跑…' : '选一个动作后点「跑」，这里会显示链路、原始响应与 JS 输出。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: <Widget>[
                        NovelTag(
                          label: run.isOk ? '成功' : '失败',
                          highlighted: run.isOk,
                        ),
                        NovelTag(label: '${run.durationMs} ms'),
                        if (run.summary.isNotEmpty)
                          NovelTag(label: run.summary),
                        if (run.truncated) const NovelTag(label: '响应已截断'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _MonospacePane(
                      text: _tabText(run),
                      emptyHint: switch (_tab) {
                        1 => '这次动作没有发生 HTTP 请求（或响应为空）。',
                        2 => '脚本没有输出（java.log 为空）。',
                        3 => '没有异常。',
                        _ => '没有记录到执行链路。',
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _tabText(NovelDebugRun run) {
    switch (_tab) {
      case 1:
        return '${run.rawUrl.isEmpty ? '' : '${run.rawUrl}\n\n'}${run.rawHtml}';
      case 2:
        return run.jsLogs.isEmpty ? '' : run.jsLogs.join('\n');
      case 3:
        final errors = run.events
            .where((event) => event.kind == NovelTraceKind.error)
            .toList();
        if (run.error != null && errors.isEmpty) return run.error!;
        return errors
            .map((event) => '${event.label}\n${event.detail}')
            .join('\n\n');
      default:
        return run.events
            .map((event) {
              final elapsed = event.elapsedMs > 0
                  ? '${event.elapsedMs}ms '
                  : '';
              final detail = event.detail.isEmpty
                  ? ''
                  : '\n${_indent(event.detail)}';
              return '$elapsed[${event.kind.label}] ${event.label}$detail';
            })
            .join('\n\n');
    }
  }

  static String _indent(String text) =>
      text.split('\n').map((line) => '    $line').join('\n');
}

class _VerifyStepRow extends StatelessWidget {
  const _VerifyStepRow({required this.step});

  final NovelVerifyStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (icon, color) = switch (step.status) {
      NovelVerifyStatus.ok => (Icons.check_circle, cs.primary),
      NovelVerifyStatus.failed => (Icons.error, cs.error),
      NovelVerifyStatus.cancelled => (Icons.cancel, cs.onSurfaceVariant),
      NovelVerifyStatus.skipped => (Icons.skip_next, cs.onSurfaceVariant),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(step.name, style: theme.textTheme.titleSmall),
                  const SizedBox(width: 8),
                  if (step.durationMs > 0)
                    Text(
                      '${step.durationMs} ms',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                step.isOk
                    ? step.summary
                    : step.status == NovelVerifyStatus.cancelled
                    ? step.summary
                    : step.error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: step.status == NovelVerifyStatus.failed
                      ? cs.error
                      : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BatchSummary extends StatelessWidget {
  const _BatchSummary({
    required this.results,
    required this.total,
    required this.running,
    required this.onCancel,
    required this.onPick,
  });

  final Map<String, NovelVerifyResult> results;
  final int total;
  final bool running;
  final VoidCallback onCancel;
  final void Function(String sourceKey) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final passed = results.values.where((r) => r.passed).length;
    final failed = results.length - passed;
    return NovelCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '批量校验 · ${results.length}/$total'
                  '（通过 $passed，失败 $failed）',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (running)
                TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text('取消'),
                ),
            ],
          ),
          if (running) ...<Widget>[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: total == 0 ? null : results.length / total,
              minHeight: 4,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              for (final entry in results.entries)
                ActionChip(
                  key: ValueKey<String>('batch-${entry.key}'),
                  avatar: Icon(
                    entry.value.passed ? Icons.check : Icons.error,
                    size: 16,
                    color: entry.value.passed ? cs.primary : cs.error,
                  ),
                  label: Text(
                    '${entry.value.sourceName}：${entry.value.passed ? '通过' : entry.value.firstFailure?.name ?? '失败'}',
                  ),
                  onPressed: () => onPick(entry.key),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonospacePane extends StatelessWidget {
  const _MonospacePane({required this.text, required this.emptyHint});

  final String text;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(MimaoRadii.sm),
      ),
      child: text.isEmpty
          ? Center(
              child: Text(
                emptyHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            )
          : SingleChildScrollView(
              child: SelectableText(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'Consolas',
                  height: 1.45,
                ),
              ),
            ),
    );
  }
}
