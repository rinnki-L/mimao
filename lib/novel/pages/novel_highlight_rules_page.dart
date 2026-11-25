// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他小说页面同款说明。
/// 高亮规则管理：正则 → 日夜两套样式，可按全局或只对某本书生效。
///
/// 页面只做增删改查与预览；真正匹配/渲染在 `reader/novel_highlight_rules.dart`
/// 与阅读页。取色板从当前 `ColorScheme` 角色生成，不写死色值。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/reader/novel_highlight_rule_service.dart';
import 'package:mimao/novel/reader/novel_highlight_rules.dart';

class NovelHighlightRulesPage extends StatefulWidget {
  const NovelHighlightRulesPage({
    super.key,
    required this.store,
    required this.bookId,
    this.bookTitle = '',
  });

  final NovelHighlightRuleStorage store;
  final String bookId;
  final String bookTitle;

  @override
  State<NovelHighlightRulesPage> createState() =>
      _NovelHighlightRulesPageState();
}

class _NovelHighlightRulesPageState extends State<NovelHighlightRulesPage> {
  bool _loading = true;
  String? _error;
  List<NovelHighlightRule> _rules = const <NovelHighlightRule>[];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rules = await widget.store.loadAll();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '读取高亮规则失败：$error';
        _loading = false;
      });
    }
  }

  Future<void> _edit([NovelHighlightRule? rule]) async {
    final saved = await showNovelHighlightRuleDialog(
      context,
      initial: rule,
      bookId: widget.bookId,
      bookTitle: widget.bookTitle,
    );
    if (saved == null || !mounted) return;
    try {
      await widget.store.save(saved);
      await _reload();
    } on Object catch (error) {
      _toast('保存失败：$error');
    }
  }

  Future<void> _delete(NovelHighlightRule rule) async {
    final id = rule.id;
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除高亮规则「${rule.name}」？'),
        content: const Text('删除后正文不再按这条规则上色；已存在的书签/划线不受影响。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.store.delete(id);
    await _reload();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('高亮规则'),
        actions: <Widget>[
          IconButton(
            key: const Key('novel-highlight-refresh'),
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          FilledButton.tonalIcon(
            key: const Key('novel-highlight-new'),
            onPressed: () => _edit(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新建规则'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: NovelPageContent(
        maxWidth: 900,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: _loading
            ? const NovelLoadingState(label: '正在读取高亮规则…')
            : _error != null
            ? NovelErrorState(message: _error!, onRetry: _reload)
            : _rules.isEmpty
            ? NovelEmptyState(
                icon: Icons.border_color_outlined,
                title: '还没有高亮规则',
                message:
                    '点右上角「新建规则」，用正则圈出要标记的文字'
                    '（例如 `第[一二三四五六七八九十百千0-9]+章`），'
                    '再选日间/夜间颜色。保存后阅读页立刻生效。',
                action: FilledButton.tonalIcon(
                  key: const Key('novel-highlight-empty-new'),
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建第一条规则'),
                ),
              )
            : ListView.separated(
                itemCount: _rules.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _HighlightRuleCard(
                  rule: _rules[index],
                  currentBookId: widget.bookId,
                  onToggle: (value) async {
                    final id = _rules[index].id;
                    if (id == null) return;
                    await widget.store.setEnabled(id, value);
                    await _reload();
                  },
                  onEdit: () => _edit(_rules[index]),
                  onDelete: () => _delete(_rules[index]),
                ),
              ),
      ),
    );
  }
}

class _HighlightRuleCard extends StatelessWidget {
  const _HighlightRuleCard({
    required this.rule,
    required this.currentBookId,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final NovelHighlightRule rule;
  final String currentBookId;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = rule.styleFor(dark: theme.brightness == Brightness.dark);
    return NovelCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.border_color_outlined, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        rule.name,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    NovelTag(label: rule.scopeLabel),
                    if (rule.isGlobal && currentBookId.isNotEmpty) ...<Widget>[
                      const SizedBox(width: 6),
                      const NovelTag(label: '对本书生效'),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  rule.pattern,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      const TextSpan(text: '预览：'),
                      TextSpan(
                        text: '命中这段文字',
                        style: TextStyle(
                          color: style.foreground,
                          backgroundColor: style.background,
                          fontWeight: style.bold ? MimaoFonts.bold : null,
                          decoration: style.underline
                              ? TextDecoration.underline
                              : null,
                          decorationColor: style.underline
                              ? style.foreground
                              : null,
                        ),
                      ),
                    ],
                  ),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '编辑',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
          Switch(value: rule.enabled, onChanged: onToggle),
        ],
      ),
    );
  }
}

/// 新建/编辑高亮规则的对话框；取消返回 null。
Future<NovelHighlightRule?> showNovelHighlightRuleDialog(
  BuildContext context, {
  NovelHighlightRule? initial,
  required String bookId,
  required String bookTitle,
}) {
  return showDialog<NovelHighlightRule>(
    context: context,
    builder: (_) => _HighlightRuleDialog(
      initial: initial,
      bookId: bookId,
      bookTitle: bookTitle,
    ),
  );
}

class _HighlightRuleDialog extends StatefulWidget {
  const _HighlightRuleDialog({
    required this.initial,
    required this.bookId,
    required this.bookTitle,
  });

  final NovelHighlightRule? initial;
  final String bookId;
  final String bookTitle;

  @override
  State<_HighlightRuleDialog> createState() => _HighlightRuleDialogState();
}

class _HighlightRuleDialogState extends State<_HighlightRuleDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late final TextEditingController _pattern = TextEditingController(
    text: widget.initial?.pattern ?? '',
  );
  late bool _global = widget.initial?.isGlobal ?? true;
  late bool _underline = widget.initial?.underline ?? false;
  late bool _bold = widget.initial?.bold ?? false;
  late int _foregroundLight;
  late int _foregroundDark;
  int? _backgroundLight;
  int? _backgroundDark;
  String? _error;

  bool _colorsReady = false;

  @override
  void initState() {
    super.initState();
    _backgroundLight = widget.initial?.backgroundLightArgb;
    _backgroundDark = widget.initial?.backgroundDarkArgb;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_colorsReady) return;
    // Theme 依赖只能在 initState 之后读：这里补默认色，已有规则的颜色不被覆盖。
    final cs = Theme.of(context).colorScheme;
    _foregroundLight = widget.initial?.foregroundLightArgb ?? _toArgb(cs.error);
    _foregroundDark = widget.initial?.foregroundDarkArgb ?? _toArgb(cs.error);
    _colorsReady = true;
  }

  @override
  void dispose() {
    _name.dispose();
    _pattern.dispose();
    super.dispose();
  }

  static int _toArgb(Color color) => color.toARGB32();

  void _submit() {
    final pattern = _pattern.text.trim();
    if (pattern.isEmpty) {
      setState(() => _error = '请填写要匹配的正则表达式');
      return;
    }
    try {
      RegExp(pattern);
    } on Object catch (error) {
      setState(() => _error = '正则不合法：$error');
      return;
    }
    final name = _name.text.trim();
    Navigator.of(context).pop(
      NovelHighlightRule(
        id: widget.initial?.id,
        bookId: _global ? '' : widget.bookId,
        name: name.isEmpty ? pattern : name,
        pattern: pattern,
        foregroundLightArgb: _foregroundLight,
        backgroundLightArgb: _backgroundLight,
        foregroundDarkArgb: _foregroundDark,
        backgroundDarkArgb: _backgroundDark,
        enabled: widget.initial?.enabled ?? true,
        underline: _underline,
        bold: _bold,
        raw: widget.initial?.raw ?? const <String, Object?>{},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final lightSwatches = _swatches(cs, background: false);
    final lightBackgrounds = _swatches(cs, background: true);
    final darkScheme = ColorScheme.fromSeed(
      seedColor: cs.primary,
      brightness: Brightness.dark,
    );
    final darkSwatches = _swatches(darkScheme, background: false);
    final darkBackgrounds = _swatches(darkScheme, background: true);
    return AlertDialog(
      title: Text(widget.initial == null ? '新建高亮规则' : '编辑高亮规则'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                key: const Key('novel-highlight-name'),
                controller: _name,
                decoration: InputDecoration(
                  labelText: '名称（留空用正则本身）',
                  filled: true,
                  fillColor: cs.surfaceContainerLowest,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('novel-highlight-pattern'),
                controller: _pattern,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: '正则表达式',
                  hintText: r'例如 (\d+)章',
                  helperText: _error,
                  helperStyle: TextStyle(color: cs.error),
                  filled: true,
                  fillColor: cs.surfaceContainerLowest,
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                key: const Key('novel-highlight-scope'),
                segments: <ButtonSegment<bool>>[
                  const ButtonSegment<bool>(value: true, label: Text('全局')),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text(
                      widget.bookTitle.isEmpty
                          ? '仅本书'
                          : '仅《${widget.bookTitle}》',
                    ),
                  ),
                ],
                selected: <bool>{_global},
                onSelectionChanged: (selection) =>
                    setState(() => _global = selection.first),
              ),
              const SizedBox(height: 14),
              _ColorRow(
                label: '日间文字色',
                colors: lightSwatches,
                selected: _foregroundLight,
                onPick: (value) {
                  if (value != null) {
                    setState(() => _foregroundLight = value);
                  }
                },
              ),
              const SizedBox(height: 8),
              _ColorRow(
                label: '日间背景色',
                colors: lightBackgrounds,
                selected: _backgroundLight,
                allowNone: true,
                onPick: (value) => setState(() => _backgroundLight = value),
              ),
              const SizedBox(height: 8),
              _ColorRow(
                label: '夜间文字色',
                colors: darkSwatches,
                selected: _foregroundDark,
                onPick: (value) {
                  if (value != null) {
                    setState(() => _foregroundDark = value);
                  }
                },
              ),
              const SizedBox(height: 8),
              _ColorRow(
                label: '夜间背景色',
                colors: darkBackgrounds,
                selected: _backgroundDark,
                allowNone: true,
                onPick: (value) => setState(() => _backgroundDark = value),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  FilterChip(
                    label: const Text('下划线'),
                    selected: _underline,
                    onSelected: (value) => setState(() => _underline = value),
                  ),
                  const SizedBox(width: 10),
                  FilterChip(
                    label: const Text('加粗'),
                    selected: _bold,
                    onSelected: (value) => setState(() => _bold = value),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    const TextSpan(text: '效果预览：'),
                    TextSpan(
                      text: _pattern.text.isEmpty ? '命中这段文字' : '正文中的匹配片段',
                      style: TextStyle(
                        color: Color(_foregroundLight),
                        backgroundColor: _backgroundLight == null
                            ? null
                            : Color(_backgroundLight!),
                        fontWeight: _bold ? MimaoFonts.bold : null,
                        decoration: _underline
                            ? TextDecoration.underline
                            : null,
                        decorationColor: Color(_foregroundLight),
                      ),
                    ),
                  ],
                ),
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('novel-highlight-save'),
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }

  /// 取色板全部来自 ColorScheme 角色；背景用半透明，避免盖住正文。
  static List<int> _swatches(ColorScheme cs, {required bool background}) {
    final colors = background
        ? <Color>[
            cs.primaryContainer.withValues(alpha: 0.55),
            cs.secondaryContainer.withValues(alpha: 0.55),
            cs.tertiaryContainer.withValues(alpha: 0.55),
            cs.errorContainer.withValues(alpha: 0.55),
            cs.surfaceContainerHighest.withValues(alpha: 0.6),
          ]
        : <Color>[
            cs.primary,
            cs.secondary,
            cs.tertiary,
            cs.error,
            cs.onSurface,
          ];
    return <int>[for (final color in colors) color.toARGB32()];
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.label,
    required this.colors,
    required this.selected,
    required this.onPick,
    this.allowNone = false,
  });

  final String label;
  final List<int> colors;
  final int? selected;
  final ValueChanged<int?> onPick;
  final bool allowNone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final value in colors)
                InkWell(
                  borderRadius: MimaoShapes.pill,
                  onTap: () => onPick(value),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Color(value),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected == value
                            ? cs.primary
                            : cs.outlineVariant,
                        width: selected == value ? 2.5 : 1,
                      ),
                    ),
                  ),
                ),
              if (allowNone)
                InkWell(
                  borderRadius: MimaoShapes.pill,
                  onTap: () => onPick(null),
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected == null
                            ? cs.primary
                            : cs.outlineVariant,
                        width: selected == null ? 2.5 : 1,
                      ),
                    ),
                    child: Icon(
                      Icons.block,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
