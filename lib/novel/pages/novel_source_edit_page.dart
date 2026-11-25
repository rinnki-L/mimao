// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 书源编辑器：JSON 表单 / 原始 JSON 双模式，字段校验，保存后即时生效。
///
/// 两种模式编辑的是同一份 raw JSON：表单改字段写回 raw，原始模式直接编辑
/// 整份 JSON 文本；切换模式时把当前编辑结果带过去，保存只落一份。
/// 保存走 [NovelSourceUpsert]（地址变了自动迁移主键），拿不到该能力时退回
/// 「先 saveAll 再 delete」的等价两步。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/pages/novel_source_login_page.dart'
    show
        NovelLoginCookieResult,
        mergeNovelCookieIntoHeader,
        showNovelLoginCookiePage;
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/source/novel_source_edit.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';

/// 编辑器两种模式。
enum NovelSourceEditorMode { form, raw }

class NovelSourceEditPage extends StatefulWidget {
  const NovelSourceEditPage({
    super.key,
    required this.store,
    this.initial,
    this.initialRaw,
    this.onSaved,
    this.onDebug,
    this.loginWebViewBuilder,
  });

  final NovelSourceStorage store;

  /// 编辑已有书源；null 表示新建（配合 [initialRaw] 预填）。
  final NovelBookSource? initial;

  /// 新建时的初始 JSON（如从剪贴板粘一条过来改）。
  final String? initialRaw;

  final void Function(NovelBookSource source)? onSaved;

  /// 「调试这条源」入口；null 时不显示按钮。
  final void Function(NovelBookSource source)? onDebug;

  /// 测试注入缝：登录取 Cookie 页的 WebView 替身。
  final Widget Function(
    BuildContext context,
    Future<NovelLoginCookieResult?> Function() readCookie,
  )?
  loginWebViewBuilder;

  @override
  State<NovelSourceEditPage> createState() => _NovelSourceEditPageState();
}

class _NovelSourceEditPageState extends State<NovelSourceEditPage> {
  late Map<String, dynamic> _raw;
  late final TextEditingController _rawController;
  final Map<String, TextEditingController> _fieldControllers =
      <String, TextEditingController>{};

  NovelSourceEditorMode _mode = NovelSourceEditorMode.form;
  List<NovelSourceIssue> _issues = const <NovelSourceIssue>[];
  String? _rawError;
  String? _status;
  bool _saving = false;

  bool get _isNew => widget.initial == null;

  @override
  void initState() {
    super.initState();
    _raw = _initialRawMap();
    _rawController = TextEditingController(text: _prettyRaw());
    for (final spec in novelSourceFieldSpecs) {
      _fieldControllers[spec.key] = TextEditingController(
        text: readNovelSourceField(_raw, spec.path),
      );
    }
    _issues = validateNovelSourceRaw(_raw);
  }

  Map<String, dynamic> _initialRawMap() {
    final initial = widget.initial;
    if (initial != null) return Map<String, dynamic>.from(initial.raw);
    final seed = widget.initialRaw?.trim() ?? '';
    if (seed.isNotEmpty) {
      try {
        final decoded = jsonDecode(seed);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on Object {
        // 初始 JSON 坏了就落到空白模板，错误留给原始模式展示。
      }
    }
    return <String, dynamic>{
      'bookSourceName': '',
      'bookSourceUrl': '',
      'bookSourceType': 0,
      'searchUrl': '',
    };
  }

  String _prettyRaw() => const JsonEncoder.withIndent('  ').convert(_raw);

  @override
  void dispose() {
    _rawController.dispose();
    for (final controller in _fieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// 表单 → raw：把当前输入写回（空值删除键）。
  void _syncFormToRaw() {
    var next = _raw;
    for (final spec in novelSourceFieldSpecs) {
      next = writeNovelSourceField(
        next,
        spec.path,
        _fieldControllers[spec.key]?.text ?? '',
      );
    }
    // 类型/权重是数字字段，写回时转成数字（引擎与排序按 num 读）。
    for (final spec in novelSourceFieldSpecs) {
      if (spec.kind != NovelSourceFieldKind.integer) continue;
      final text = readNovelSourceField(next, spec.path);
      if (text.isEmpty) continue;
      final parsed = int.tryParse(text);
      if (parsed == null) continue;
      next = _setRawValue(next, spec.path, parsed);
    }
    _raw = next;
  }

  /// raw → 表单：原始模式改完后同步回各输入框。
  void _syncRawToForm() {
    for (final spec in novelSourceFieldSpecs) {
      _fieldControllers[spec.key]?.text = readNovelSourceField(_raw, spec.path);
    }
  }

  static Map<String, dynamic> _setRawValue(
    Map<String, dynamic> raw,
    List<String> path,
    Object value,
  ) {
    final next = <String, dynamic>{
      for (final entry in raw.entries)
        entry.key: entry.value is Map
            ? Map<String, dynamic>.from(entry.value as Map)
            : entry.value,
    };
    var cursor = next;
    for (var i = 0; i < path.length - 1; i++) {
      final child = cursor[path[i]];
      final map = child is Map
          ? Map<String, dynamic>.from(child)
          : <String, dynamic>{};
      cursor[path[i]] = map;
      cursor = map;
    }
    cursor[path.last] = value;
    return next;
  }

  void _switchMode(NovelSourceEditorMode mode) {
    if (mode == _mode) return;
    if (mode == NovelSourceEditorMode.raw) {
      _syncFormToRaw();
      _rawController.text = _prettyRaw();
      setState(() {
        _mode = mode;
        _rawError = null;
        _issues = validateNovelSourceRaw(_raw);
      });
      return;
    }
    // raw → form：解析失败就留在原始模式并报错，不丢用户输入。
    final parsed = _parseRawText();
    if (parsed == null) return;
    setState(() {
      _raw = parsed;
      _mode = mode;
      _rawError = null;
      _issues = validateNovelSourceRaw(_raw);
    });
    _syncRawToForm();
  }

  Map<String, dynamic>? _parseRawText() {
    final text = _rawController.text.trim();
    if (text.isEmpty) {
      setState(() => _rawError = 'JSON 不能为空');
      return null;
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        setState(() => _rawError = '顶层必须是 JSON 对象（{…}），不是数组或标量');
        return null;
      }
      return Map<String, dynamic>.from(decoded);
    } on FormatException catch (error) {
      setState(() => _rawError = 'JSON 解析失败：${error.message}');
      return null;
    }
  }

  void _formatRaw() {
    final parsed = _parseRawText();
    if (parsed == null) return;
    _raw = parsed;
    _rawController.text = _prettyRaw();
    setState(() {
      _rawError = null;
      _issues = validateNovelSourceRaw(_raw);
    });
  }

  void _validate() {
    if (_mode == NovelSourceEditorMode.raw) {
      final parsed = _parseRawText();
      if (parsed == null) return;
      _raw = parsed;
    } else {
      _syncFormToRaw();
    }
    setState(() {
      _rawError = null;
      _issues = validateNovelSourceRaw(_raw);
      _status = null;
    });
  }

  Future<void> _save() async {
    if (_mode == NovelSourceEditorMode.raw) {
      final parsed = _parseRawText();
      if (parsed == null) return;
      _raw = parsed;
    } else {
      _syncFormToRaw();
    }
    final issues = validateNovelSourceRaw(_raw);
    setState(() {
      _issues = issues;
      _status = null;
    });
    final errors = issues.where((issue) => issue.isError).toList();
    if (errors.isNotEmpty) {
      setState(() => _status = '有 ${errors.length} 个错误，修完再保存');
      return;
    }

    setState(() => _saving = true);
    final previous = widget.initial;
    final rebuilt = previous == null
        ? novelSourceFromRaw(_raw)
        : applyNovelSourceRaw(previous, _raw);
    try {
      final store = widget.store;
      if (store is NovelSourceUpsert) {
        await (store as NovelSourceUpsert).upsert(
          rebuilt,
          previousKey: previous?.key,
        );
      } else {
        await store.saveAll(<NovelBookSource>[rebuilt]);
        if (previous != null && previous.key != rebuilt.key) {
          await store.delete(previous.key);
        }
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _status = '已保存，立即生效（${rebuilt.name}）';
      });
      widget.onSaved?.call(rebuilt);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _status = '保存失败：$error';
      });
    }
  }

  /// 打开内置 WebView 登录书源站点，取 Cookie 合并进 `header`。
  ///
  /// 桌面端走应用内页面（不移植 Android 的 WebSocket 服务形态），Android
  /// 复用同一个页面与返回契约；拿到的 Cookie 只写本机书源文件。
  Future<void> _loginForCookie() async {
    if (_mode == NovelSourceEditorMode.raw) {
      final parsed = _parseRawText();
      if (parsed == null) return;
      _raw = parsed;
    } else {
      _syncFormToRaw();
    }
    final loginUrl = readNovelSourceField(_raw, <String>['loginUrl']);
    final sourceUrl = readNovelSourceField(_raw, <String>['bookSourceUrl']);
    final target = loginUrl.trim().isNotEmpty
        ? loginUrl.trim()
        : sourceUrl.trim();
    if (target.isEmpty) {
      setState(() => _status = '先填书源地址或登录地址，才知道去哪登录');
      return;
    }
    final result = await showNovelLoginCookiePage(
      context,
      url: target,
      title: '登录 ${readNovelSourceField(_raw, <String>['bookSourceName'])}',
      webViewBuilder: widget.loginWebViewBuilder,
    );
    if (result == null || !mounted) return;
    if (result.isEmpty) {
      setState(() => _status = '没有取到 Cookie（登录页可能未完成登录）');
      return;
    }
    final header = readNovelSourceField(_raw, <String>['header']);
    final merged = mergeNovelCookieIntoHeader(header, result.cookieHeader);
    if (merged == header && header.trim().isNotEmpty) {
      setState(() => _status = '请求头不是合法 JSON，Cookie 未写入；请先在表单里修正「请求头」');
      return;
    }
    _raw = writeNovelSourceField(_raw, <String>['header'], merged);
    _syncRawToForm();
    _rawController.text = _prettyRaw();
    setState(() {
      _status = '已写入 Cookie（${result.cookieHeader.length} 字符），记得保存';
      _issues = validateNovelSourceRaw(_raw);
    });
  }

  Future<void> _copyJson() async {
    if (_mode == NovelSourceEditorMode.form) _syncFormToRaw();
    await Clipboard.setData(ClipboardData(text: _prettyRaw()));
    if (!mounted) return;
    setState(() => _status = '已复制 JSON 到剪贴板');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final errorCount = _issues.where((issue) => issue.isError).length;
    final warningCount = _issues.where((issue) => !issue.isError).length;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? '新建书源' : '编辑书源'),
        actions: <Widget>[
          IconButton(
            key: const Key('novel-source-edit-validate'),
            tooltip: '校验字段',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: _validate,
          ),
          IconButton(
            key: const Key('novel-source-edit-copy'),
            tooltip: '复制 JSON',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _copyJson,
          ),
          IconButton(
            key: const Key('novel-source-edit-login'),
            tooltip: '登录取 Cookie',
            icon: const Icon(Icons.login),
            onPressed: _loginForCookie,
          ),
          if (widget.onDebug != null)
            IconButton(
              key: const Key('novel-source-edit-debug'),
              tooltip: '调试这条源',
              icon: const Icon(Icons.bug_report_outlined),
              onPressed: () => widget.onDebug?.call(
                _isNew
                    ? novelSourceFromRaw(_raw)
                    : applyNovelSourceRaw(widget.initial!, _raw),
              ),
            ),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: const Key('novel-source-edit-save'),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('保存'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: NovelFillContent(
        maxWidth: 980,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                SegmentedButton<NovelSourceEditorMode>(
                  key: const Key('novel-source-edit-mode'),
                  segments: const <ButtonSegment<NovelSourceEditorMode>>[
                    ButtonSegment<NovelSourceEditorMode>(
                      value: NovelSourceEditorMode.form,
                      label: Text('表单'),
                      icon: Icon(Icons.view_list_outlined, size: 16),
                    ),
                    ButtonSegment<NovelSourceEditorMode>(
                      value: NovelSourceEditorMode.raw,
                      label: Text('原始 JSON'),
                      icon: Icon(Icons.data_object, size: 16),
                    ),
                  ],
                  selected: <NovelSourceEditorMode>{_mode},
                  onSelectionChanged: (value) => _switchMode(value.first),
                ),
                const SizedBox(width: 12),
                if (_mode == NovelSourceEditorMode.raw)
                  OutlinedButton.icon(
                    key: const Key('novel-source-edit-format'),
                    onPressed: _formatRaw,
                    icon: const Icon(Icons.format_align_left, size: 16),
                    label: const Text('格式化'),
                  ),
                const Spacer(),
                if (errorCount > 0)
                  NovelTag(label: '$errorCount 个错误', highlighted: true)
                else if (warningCount > 0)
                  NovelTag(label: '$warningCount 个警告')
                else
                  const NovelTag(label: '字段校验通过'),
              ],
            ),
            if (_status != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _status!,
                key: const Key('novel-source-edit-status'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: errorCount > 0 ? cs.error : cs.primary,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_issues.isNotEmpty) _IssueList(issues: _issues),
            if (_rawError != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _rawError!,
                key: const Key('novel-source-edit-raw-error'),
                style: theme.textTheme.bodySmall?.copyWith(color: cs.error),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: _mode == NovelSourceEditorMode.form
                  ? _buildForm(theme, cs)
                  : _buildRawEditor(theme, cs),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme, ColorScheme cs) {
    return ListView(
      children: <Widget>[
        for (final section in novelSourceFieldSections) ...<Widget>[
          NovelSectionHeader(title: section.title),
          if (section.description.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              section.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 10),
          for (final spec in section.fields) ...<Widget>[
            _FieldInput(
              key: ValueKey<String>('field-${spec.key}'),
              spec: spec,
              controller: _fieldControllers[spec.key]!,
              issue: _issues
                  .where((issue) => issue.field == spec.key && issue.isError)
                  .firstOrNull,
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildRawEditor(ThemeData theme, ColorScheme cs) {
    return TextField(
      key: const Key('novel-source-edit-raw'),
      controller: _rawController,
      maxLines: null,
      expands: true,
      textAlignVertical: TextAlignVertical.top,
      style: theme.textTheme.bodySmall?.copyWith(
        fontFamily: 'Consolas',
        height: 1.5,
      ),
      decoration: const InputDecoration(
        hintText: '{ "bookSourceName": "…", "bookSourceUrl": "…" }',
        alignLabelWithHint: true,
      ),
      onChanged: (_) {
        if (_rawError != null) setState(() => _rawError = null);
      },
    );
  }
}

class _FieldInput extends StatelessWidget {
  const _FieldInput({
    super.key,
    required this.spec,
    required this.controller,
    this.issue,
  });

  final NovelSourceFieldSpec spec;
  final TextEditingController controller;
  final NovelSourceIssue? issue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final multiline = spec.kind == NovelSourceFieldKind.multiline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: controller,
          minLines: multiline ? 3 : 1,
          maxLines: multiline ? 6 : 1,
          keyboardType: spec.kind == NovelSourceFieldKind.integer
              ? TextInputType.number
              : TextInputType.text,
          style: multiline
              ? theme.textTheme.bodySmall?.copyWith(height: 1.5)
              : null,
          decoration: InputDecoration(
            labelText: spec.label,
            hintText: spec.hint.isEmpty ? null : spec.hint,
            errorText: issue?.message,
            isDense: true,
          ),
        ),
      ],
    );
  }
}

class _IssueList extends StatelessWidget {
  const _IssueList({required this.issues});

  final List<NovelSourceIssue> issues;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(MimaoRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final issue in issues.take(6))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    issue.isError
                        ? Icons.error_outline
                        : Icons.warning_amber_outlined,
                    size: 15,
                    color: issue.isError ? cs.error : cs.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      issue.field.isEmpty
                          ? issue.message
                          : '${issue.field}：${issue.message}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: issue.isError ? cs.error : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (issues.length > 6)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '另有 ${issues.length - 6} 条，保存前请逐项检查。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
