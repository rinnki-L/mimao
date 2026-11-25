// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他小说页面同款说明。
// 选文菜单 + 划线/笔记编辑面板。
//
// 选区菜单只做四件事：复制 / 划线 / 笔记 / 搜索。划线不是「另一种书签」：
// 它存段内区间与样式，渲染层用背景/装饰叠加到正文上，不插 Widget、不改行高。
//
// 菜单本身不碰数据库：选中了什么由调用方转成 [NovelTextSelectionRange] 传进来，
// 点击后回调页面；编辑面板只负责样式/备注的收集，结果通过
// [NovelMarkingEditResult] 返回。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/bookmark/novel_bookmark_models.dart';

/// 一次选区的正文坐标（不含段首缩进）。
///
/// 跨段选择时 [startParagraph] != [endParagraph]；当前划线模型是「一段一区间」，
/// 因此跨段只允许复制/搜索，划线与笔记在菜单里显灰。
class NovelTextSelectionRange {
  const NovelTextSelectionRange({
    required this.startParagraph,
    required this.startOffset,
    required this.endParagraph,
    required this.endOffset,
  });

  final int startParagraph;
  final int startOffset;
  final int endParagraph;
  final int endOffset;

  bool get isCollapsed =>
      startParagraph == endParagraph && startOffset >= endOffset;

  bool get isSingleParagraph => startParagraph == endParagraph;

  bool get isValid => !isCollapsed && startParagraph >= 0;

  /// 按段落取展示文本（含缩进），拼出用户看到的选中内容。
  ///
  /// [paragraphText] 与阅读器渲染同一个函数，简繁转换/缩进都一致；复制出去的
  /// 就是屏幕上那串字。跨段时去掉段首缩进再拼。
  String textFrom(
    String Function(int paragraph) paragraphText, {
    int indentLength = 2,
  }) {
    if (!isValid) return '';
    if (isSingleParagraph) {
      final text = paragraphText(startParagraph);
      final start = (startOffset + indentLength).clamp(0, text.length);
      final end = (endOffset + indentLength).clamp(start, text.length);
      return text.substring(start, end);
    }
    final buffer = StringBuffer();
    for (var p = startParagraph; p <= endParagraph; p++) {
      final text = paragraphText(p);
      var start = indentLength;
      var end = text.length;
      if (p == startParagraph) {
        start = (startOffset + indentLength).clamp(0, text.length);
      }
      if (p == endParagraph) {
        end = (endOffset + indentLength).clamp(start, text.length);
      }
      if (p > startParagraph) buffer.write('\n');
      buffer.write(text.substring(start, end));
    }
    return buffer.toString();
  }
}

/// 选区菜单的动作。null 表示当前选区不支持该动作（跨段划线）。
class NovelSelectionActions {
  const NovelSelectionActions({
    required this.onCopy,
    required this.onMark,
    required this.onNote,
    required this.onSearch,
    this.onDict,
    this.canMark = true,
  });

  final VoidCallback onCopy;
  final VoidCallback onMark;
  final VoidCallback onNote;
  final VoidCallback onSearch;

  /// 查词典；null = 当前没接词典（不显示这一项）。
  final VoidCallback? onDict;
  final bool canMark;
}

/// 构建浮动选区菜单（[SelectionArea.contextMenuBuilder] 的返回值）。
Widget buildNovelSelectionMenu({
  required BuildContext context,
  required TextSelectionToolbarAnchors anchors,
  required NovelSelectionActions actions,
}) {
  final scheme = Theme.of(context).colorScheme;
  Widget item({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    String? hint,
  }) {
    final enabled = onPressed != null;
    final color = enabled
        ? scheme.onSurface
        : scheme.onSurface.withValues(alpha: 0.38);
    return TextButton(
      key: key,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: MimaoShapes.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            hint == null ? label : '$label（$hint）',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: MimaoFonts.regular,
            ),
          ),
        ],
      ),
    );
  }

  return AdaptiveTextSelectionToolbar(
    anchors: anchors,
    children: <Widget>[
      item(
        key: const Key('novel-selection-copy'),
        icon: Icons.copy_all_outlined,
        label: '复制',
        onPressed: actions.onCopy,
      ),
      item(
        key: const Key('novel-selection-mark'),
        icon: Icons.brush_outlined,
        label: '划线',
        onPressed: actions.canMark ? actions.onMark : null,
        hint: actions.canMark ? null : '跨段',
      ),
      item(
        key: const Key('novel-selection-note'),
        icon: Icons.sticky_note_2_outlined,
        label: '笔记',
        onPressed: actions.canMark ? actions.onNote : null,
        hint: actions.canMark ? null : '跨段',
      ),
      item(
        key: const Key('novel-selection-search'),
        icon: Icons.search,
        label: '搜索',
        onPressed: actions.onSearch,
      ),
      if (actions.onDict != null)
        item(
          key: const Key('novel-selection-dict'),
          icon: Icons.translate,
          label: '词典',
          onPressed: actions.onDict,
        ),
    ],
  );
}

/// 划线/笔记编辑面板的返回值。
class NovelMarkingEditResult {
  const NovelMarkingEditResult({
    required this.style,
    required this.note,
    this.delete = false,
  });

  final NovelMarkingStyle style;
  final String note;

  /// true = 用户在编辑已有划线时点了删除。
  final bool delete;
}

/// 打开划线/笔记编辑面板（底部弹层）。
Future<NovelMarkingEditResult?> showNovelMarkingEditor(
  BuildContext context, {
  required String excerpt,
  required NovelMarkingStyle initialStyle,
  String initialNote = '',
  bool editing = false,
  ThemeData? theme,
}) {
  return showModalBottomSheet<NovelMarkingEditResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: theme?.colorScheme.surfaceContainerLow,
    builder: (sheetContext) {
      final content = Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.paddingOf(sheetContext).bottom + 20,
        ),
        child: NovelMarkingEditorSheet(
          excerpt: excerpt,
          initialStyle: initialStyle,
          initialNote: initialNote,
          editing: editing,
        ),
      );
      // 阅读画布可能是深色，浮层要跟着画布走（与阅读器其它面板一致），
      // 不能直接套 App 的浅色主题。
      return theme == null ? content : Theme(data: theme, child: content);
    },
  );
}

/// 样式 + 备注编辑器。正文选中后「划线」用默认样式直接落库，
/// 「笔记」和点击已有划线都进来这里。
class NovelMarkingEditorSheet extends StatefulWidget {
  const NovelMarkingEditorSheet({
    super.key,
    required this.excerpt,
    required this.initialStyle,
    this.initialNote = '',
    this.editing = false,
  });

  /// 被划的原文（截断展示，不参与保存）。
  final String excerpt;
  final NovelMarkingStyle initialStyle;
  final String initialNote;
  final bool editing;

  @override
  State<NovelMarkingEditorSheet> createState() =>
      _NovelMarkingEditorSheetState();
}

class _NovelMarkingEditorSheetState extends State<NovelMarkingEditorSheet> {
  late NovelMarkingStyle _style = widget.initialStyle;
  late final TextEditingController _note = TextEditingController(
    text: widget.initialNote,
  );

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(
    context,
  ).pop(NovelMarkingEditResult(style: _style, note: _note.text.trim()));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final excerpt = widget.excerpt.trim();
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              widget.editing ? '编辑划线' : '划线笔记',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: MimaoFonts.bold,
              ),
            ),
            if (excerpt.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: MimaoShapes.sm,
                ),
                child: Text(
                  excerpt.length > 80
                      ? '${excerpt.substring(0, 80)}…'
                      : excerpt,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text('颜色', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: <Widget>[
                for (var i = 0; i < NovelMarkingStyle.presets.length; i++)
                  _ColorDot(
                    key: Key('novel-marking-color-$i'),
                    style: NovelMarkingStyle.presets[i],
                    selected:
                        NovelMarkingStyle.presets[i].colorArgb ==
                        _style.colorArgb,
                    onTap: () => setState(
                      () => _style = _style.copyWith(
                        colorArgb: NovelMarkingStyle.presets[i].colorArgb,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('样式', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<NovelMarkingDecoration>(
              key: const Key('novel-marking-decoration'),
              segments: <ButtonSegment<NovelMarkingDecoration>>[
                for (final decoration in NovelMarkingDecoration.values)
                  ButtonSegment<NovelMarkingDecoration>(
                    value: decoration,
                    label: Text(decoration.label),
                  ),
              ],
              selected: <NovelMarkingDecoration>{_style.decoration},
              onSelectionChanged: (selection) => setState(
                () => _style = _style.copyWith(decoration: selection.first),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('novel-marking-note'),
              controller: _note,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '备注（可选）',
                hintText: '写下此刻的想法…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                if (widget.editing)
                  TextButton.icon(
                    key: const Key('novel-marking-delete'),
                    onPressed: () => Navigator.of(context).pop(
                      const NovelMarkingEditResult(
                        style: NovelMarkingStyle.yellow,
                        note: '',
                        delete: true,
                      ),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('删除'),
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                  ),
                const Spacer(),
                TextButton(
                  key: const Key('novel-marking-cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('novel-marking-save'),
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    super.key,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final NovelMarkingStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 色板本身就是阅读画布上的叠加色（半透明），这里直接展示真实效果；
    // 外圈用主题色表示选中，不用固定色写死 UI 语义。
    return InkWell(
      onTap: onTap,
      borderRadius: MimaoShapes.pill,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Color(style.colorArgb),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: selected
            ? Icon(Icons.check, size: 18, color: scheme.onSurface)
            : null,
      ),
    );
  }
}

/// 把选区文本放进剪贴板；失败由调用方决定提示文案。
Future<void> copyNovelSelection(String text) async {
  if (text.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: text));
}
