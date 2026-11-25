// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他小说页面同款说明。
/// 「我的 → 阅读主题包」：把阅读设置（区 1 那套 `NovelReaderSettings`）导出成
/// 带版本号与预览图的 JSON 包，也能导入/分享别人的包。
///
/// 导入时先校验 `format` + `version`：包版本高于当前支持版本的直接拒绝并说明
/// 原因，不做「尽力猜」的降级；应用前给差异摘要，用户能看清会改哪些项。
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/file_gate.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/reader/novel_keyboard_assist.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';
import 'package:mimao/novel/theme/novel_theme_package.dart';
import 'package:mimao/novel/theme/novel_theme_package_service.dart';
import 'package:mimao/novel/theme/novel_theme_preview.dart';

class NovelThemeImportPage extends StatefulWidget {
  const NovelThemeImportPage({
    super.key,
    required this.store,
    required this.settingsStore,
    this.keyboardStore,
    this.fileGate,
  });

  final NovelThemePackageStorage store;
  final NovelReaderSettingsStore settingsStore;

  /// 键位映射存储；null = 导入时不处理键位。
  final NovelKeyboardAssistStore? keyboardStore;

  /// 文件选择/保存缝；null = 只支持粘贴/复制文本。
  final NovelJsonFileGate? fileGate;

  @override
  State<NovelThemeImportPage> createState() => _NovelThemeImportPageState();
}

class _NovelThemeImportPageState extends State<NovelThemeImportPage> {
  final GlobalKey _previewKey = GlobalKey();
  bool _loading = true;
  String? _error;
  NovelReaderSettings _current = const NovelReaderSettings();
  List<NovelThemePackageRecord> _packages = const <NovelThemePackageRecord>[];
  bool _busy = false;

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
      final settings = await widget.settingsStore.load();
      final packages = await widget.store.loadAll();
      if (!mounted) return;
      setState(() {
        _current = settings;
        _packages = packages;
        _loading = false;
      });
    } on Object catch (error) {
      debugPrint('novel: 读取主题包失败: $error');
      if (!mounted) return;
      setState(() {
        _error = '读取主题包失败：本地库暂时打不开。';
        _loading = false;
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 把预览样张抓成 PNG（失败返回 null，包仍能导出，只是没有嵌图）。
  Future<ui.Image?> _capturePreview() async {
    try {
      final boundary =
          _previewKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      return await boundary.toImage(pixelRatio: 1.5);
    } on Object {
      return null;
    }
  }

  Future<List<int>?> _previewPngBytes() async {
    final image = await _capturePreview();
    if (image == null) return null;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data?.buffer.asUint8List();
      if (bytes == null || bytes.isEmpty) return null;
      // 包体别被预览图撑爆：超过 ~400KB 就当没图（导入端会现场渲染）。
      if (bytes.length > 400 * 1024) return null;
      return bytes;
    } on Object {
      return null;
    } finally {
      image.dispose();
    }
  }

  NovelKeyboardConfig? _loadedKeyboardConfig;

  Future<NovelKeyboardConfig?> _keyboardConfig() async {
    final store = widget.keyboardStore;
    if (store == null) return null;
    _loadedKeyboardConfig ??= await store.load();
    return _loadedKeyboardConfig;
  }

  Future<NovelThemePackage?> _buildPackage(
    String name,
    bool includeKeys,
  ) async {
    final config = includeKeys ? await _keyboardConfig() : null;
    final previewBytes = await _previewPngBytes();
    return NovelThemePackage(
      name: name,
      settings: _current,
      keyBindings: config?.bindings ?? const <NovelKeyboardBinding>[],
      previewPng: previewBytes == null
          ? null
          : Uint8List.fromList(previewBytes),
    );
  }

  Future<void> _exportCurrent({required bool toFile}) async {
    if (_busy) return;
    final options = await showDialog<_ExportOptions>(
      context: context,
      builder: (_) => _ExportOptionsDialog(
        defaultName: '我的阅读主题',
        canIncludeKeys: widget.keyboardStore != null,
        toFile: toFile,
      ),
    );
    if (options == null) return;
    setState(() => _busy = true);
    try {
      final package = await _buildPackage(options.name, options.includeKeys);
      if (package == null) return;
      final json = package.encode();
      if (!mounted) return;
      if (toFile) {
        final gate = widget.fileGate;
        if (gate == null) {
          await _showJsonDialog(package.name, json);
          return;
        }
        final path = await gate.save(
          '${_fileSafe(package.name)}.json',
          Uint8List.fromList(utf8.encode(json)),
          dialogTitle: '导出主题包',
        );
        if (path == null) return;
        _toast('已导出到 $path');
      } else {
        await widget.store.save(package);
        await _reload();
        _toast('已保存到「我的主题」');
      }
    } on Object catch (error) {
      _toast('导出失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _fileSafe(String raw) =>
      raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();

  Future<void> _showJsonDialog(String name, String json) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$name · 主题包 JSON'),
        content: SizedBox(
          width: 620,
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    json,
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '当前环境没有文件保存器：全选复制即可分享。',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
              if (mounted) _toast('主题包 JSON 已复制');
            },
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _importFromFile() async {
    final gate = widget.fileGate;
    if (gate == null) {
      _toast('当前环境没有文件选择器；用「粘贴 JSON」导入。');
      return;
    }
    try {
      final file = await gate.pick(dialogTitle: '选择主题包 JSON');
      if (file == null || !mounted) return;
      await _importText(file.text, sourceName: file.name);
    } on Object catch (error) {
      _toast('读取文件失败：$error');
    }
  }

  Future<void> _importFromClipboard() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _PasteThemeDialog(),
    );
    if (text == null || text.trim().isEmpty) return;
    await _importText(text);
  }

  Future<void> _importText(String text, {String? sourceName}) async {
    final NovelThemePackage package;
    try {
      package = NovelThemePackage.decode(text);
    } on NovelThemePackageException catch (error) {
      await _showImportError(error);
      return;
    }
    if (!mounted) return;
    final choice = await showDialog<_ImportChoice>(
      context: context,
      builder: (_) => _ImportPreviewDialog(
        package: package,
        current: _current,
        sourceName: sourceName,
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final record = await widget.store.save(package);
      if (choice == _ImportChoice.apply) {
        await widget.settingsStore.save(package.settings);
        if (package.keyBindings.isNotEmpty) {
          final store = widget.keyboardStore;
          if (store != null) {
            final existing = await store.load();
            await store.save(existing.copyWith(bindings: package.keyBindings));
          }
        }
        await widget.store.markApplied(record.id);
      }
      await _reload();
      _toast(choice == _ImportChoice.apply ? '已应用主题；重新打开阅读页生效' : '已保存到「我的主题」');
    } on Object catch (error) {
      _toast('导入失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showImportError(NovelThemePackageException error) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        final title = switch (error.error) {
          NovelThemePackageError.notJson => '文件不是 JSON',
          NovelThemePackageError.notTheme => '不是 mimao 主题包',
          NovelThemePackageError.versionTooNew => '主题包版本不兼容',
          NovelThemePackageError.versionTooOld => '主题包版本无效',
          NovelThemePackageError.corrupt => '主题包内容不完整',
        };
        return AlertDialog(
          title: Text(title),
          content: SelectableText(
            error.message,
            style: Theme.of(
              dialogContext,
            ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _applyRecord(NovelThemePackageRecord record) async {
    final package = record.decode();
    if (package == null) {
      _toast('这个主题包已损坏：删掉后重新导入一份。');
      return;
    }
    final confirmed = await showDialog<_ImportChoice>(
      context: context,
      builder: (_) => _ImportPreviewDialog(
        package: package,
        current: _current,
        appliedFromList: true,
      ),
    );
    if (confirmed != _ImportChoice.apply) return;
    setState(() => _busy = true);
    try {
      await widget.settingsStore.save(package.settings);
      if (package.keyBindings.isNotEmpty) {
        final store = widget.keyboardStore;
        if (store != null) {
          final existing = await store.load();
          await store.save(existing.copyWith(bindings: package.keyBindings));
        }
      }
      await widget.store.markApplied(record.id);
      await _reload();
      _toast('已应用「${package.name}」；重新打开阅读页生效');
    } on Object catch (error) {
      _toast('应用失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportRecord(NovelThemePackageRecord record) async {
    final package = record.decode();
    if (package == null) {
      _toast('这个主题包已损坏，无法导出。');
      return;
    }
    final gate = widget.fileGate;
    if (gate == null) {
      await _showJsonDialog(package.name, record.json);
      return;
    }
    try {
      final path = await gate.save(
        '${_fileSafe(package.name)}.json',
        Uint8List.fromList(utf8.encode(record.json)),
        dialogTitle: '导出主题包',
      );
      if (path == null) return;
      _toast('已导出到 $path');
    } on Object catch (error) {
      _toast('导出失败：$error');
    }
  }

  Future<void> _deleteRecord(NovelThemePackageRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除主题「${record.name}」？'),
        content: const Text('只删掉保存的包，已经应用到你阅读设置里的效果不会回退。'),
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
    try {
      await widget.store.delete(record.id);
      await _reload();
    } on Object catch (error) {
      _toast('删除失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读主题包'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: NovelPageContent(
        maxWidth: 960,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: _loading
            ? const NovelLoadingState(label: '正在读取主题包…')
            : _error != null
            ? NovelErrorState(
                message: _error!,
                hint: '可以重试一次；反复失败就退出应用重启，让本地库重新打开。',
                onRetry: _reload,
              )
            : ListView(
                children: <Widget>[
                  _buildCurrentCard(context),
                  const SizedBox(height: 18),
                  _buildImportCard(context),
                  const SizedBox(height: 22),
                  _buildSavedSection(context),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }

  Widget _buildCurrentCard(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NovelCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 620;
          final preview = RepaintBoundary(
            key: _previewKey,
            child: NovelThemePreview(settings: _current),
          );
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('当前阅读设置', style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                '字号 ${_current.fontSize.round()} · 行距 '
                '${_current.lineHeight.toStringAsFixed(1)} · '
                '${_current.pageMode == NovelPageMode.page ? '左右翻页' : '上下滚动'} · '
                '背景 ${_current.background.name}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '导出的是「阅读页右上角」那套全局设置（字号/字体/背景/排版/翻页）。'
                '每本书的独立覆盖不跟着走，换机后仍按每书的差异生效。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    key: const Key('novel-theme-export-file'),
                    onPressed: _busy
                        ? null
                        : () => _exportCurrent(toFile: true),
                    icon: const Icon(Icons.save_alt, size: 18),
                    label: const Text('导出为文件'),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('novel-theme-save'),
                    onPressed: _busy
                        ? null
                        : () => _exportCurrent(toFile: false),
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    label: const Text('保存到我的主题'),
                  ),
                ],
              ),
            ],
          );
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Center(child: preview),
                const SizedBox(height: 14),
                info,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              preview,
              const SizedBox(width: 20),
              Expanded(child: info),
            ],
          );
        },
      ),
    );
  }

  Widget _buildImportCard(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NovelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('导入主题包', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '主题包是 JSON 文件（含格式版本与预览图）。导入前会先校验版本，'
            '再给「会修改哪些项」的摘要；确认后才写入你的阅读设置。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.tonalIcon(
                key: const Key('novel-theme-import-file'),
                onPressed: _busy ? null : _importFromFile,
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text('从文件导入'),
              ),
              OutlinedButton.icon(
                key: const Key('novel-theme-import-paste'),
                onPressed: _busy ? null : _importFromClipboard,
                icon: const Icon(Icons.content_paste, size: 18),
                label: const Text('粘贴 JSON'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSavedSection(BuildContext context) {
    final theme = Theme.of(context);
    if (_packages.isEmpty) {
      return NovelEmptyState(
        icon: Icons.collections_bookmark_outlined,
        title: '还没有保存的主题',
        message:
            '把当前设置「保存到我的主题」后，这里会列出可一键应用/导出的主题包；'
            '也可以直接从文件或剪贴板导入别人分享的包。',
        action: FilledButton.tonalIcon(
          onPressed: _busy ? null : () => _exportCurrent(toFile: false),
          icon: const Icon(Icons.bookmark_add_outlined, size: 18),
          label: const Text('把当前设置存为第一个主题'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('我的主题  ${_packages.length}', style: theme.textTheme.titleMedium),
        const SizedBox(height: 10),
        for (final record in _packages)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildRecordCard(context, record),
          ),
      ],
    );
  }

  Widget _buildRecordCard(
    BuildContext context,
    NovelThemePackageRecord record,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final package = record.decode();
    final previewBytes = record.previewPng;
    Widget preview;
    if (previewBytes != null) {
      preview = ClipRRect(
        borderRadius: MimaoShapes.sm,
        child: Image.memory(
          previewBytes,
          width: 120,
          height: 160,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox(width: 120, height: 160),
        ),
      );
    } else if (package != null) {
      preview = NovelThemePreview(
        settings: package.settings,
        width: 120,
        height: 160,
      );
    } else {
      preview = Container(
        width: 120,
        height: 160,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: MimaoShapes.sm,
        ),
        child: Text(
          '包已损坏',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onErrorContainer,
          ),
        ),
      );
    }
    return NovelCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          preview,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        record.name,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    NovelTag(label: 'v${record.version}'),
                    if (record.appliedAt != null) ...<Widget>[
                      const SizedBox(width: 6),
                      const NovelTag(label: '已应用', highlighted: true),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  package == null
                      ? '包 JSON 解析失败：删掉后重新导入。'
                      : '导入于 ${_formatTime(record.importedAt)}'
                            '${record.appliedAt == null ? '' : '· 应用于 ${_formatTime(record.appliedAt!)}'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (package != null &&
                    package.keyBindings.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    '含 ${package.keyBindings.length} 条键位映射',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    FilledButton.tonal(
                      key: const Key('novel-theme-record-apply'),
                      onPressed: _busy || package == null
                          ? null
                          : () => _applyRecord(record),
                      child: const Text('应用'),
                    ),
                    TextButton(
                      onPressed: package == null
                          ? null
                          : () => _exportRecord(record),
                      child: const Text('导出'),
                    ),
                    TextButton(
                      onPressed: () => _deleteRecord(record),
                      style: TextButton.styleFrom(foregroundColor: cs.error),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime time) =>
      '${time.year}-${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')} '
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

/// 导出选项（名称 + 是否带键位）。
class _ExportOptions {
  const _ExportOptions({required this.name, required this.includeKeys});

  final String name;
  final bool includeKeys;
}

class _ExportOptionsDialog extends StatefulWidget {
  const _ExportOptionsDialog({
    required this.defaultName,
    required this.canIncludeKeys,
    required this.toFile,
  });

  final String defaultName;
  final bool canIncludeKeys;
  final bool toFile;

  @override
  State<_ExportOptionsDialog> createState() => _ExportOptionsDialogState();
}

class _ExportOptionsDialogState extends State<_ExportOptionsDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.defaultName,
  );
  late bool _includeKeys = widget.canIncludeKeys;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.toFile ? '导出主题包' : '存为我的主题'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: '主题名'),
            ),
            const SizedBox(height: 8),
            if (widget.canIncludeKeys)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeKeys,
                onChanged: (value) =>
                    setState(() => _includeKeys = value ?? false),
                title: const Text('带上键盘键位映射'),
                subtitle: const Text('别人导入后可直接用同一套按键；不带则只同步外观。'),
              ),
            const SizedBox(height: 6),
            Text(
              '包格式 v$novelThemePackageVersion · 含背景/字号/行距/边距/翻页/菜单外观，'
              '不含每书覆盖与背景图原图。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
          key: const Key('novel-theme-export-confirm'),
          onPressed: _name.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  _ExportOptions(
                    name: _name.text.trim(),
                    includeKeys: widget.canIncludeKeys && _includeKeys,
                  ),
                ),
          child: Text(widget.toFile ? '导出' : '保存'),
        ),
      ],
    );
  }
}

enum _ImportChoice { apply, saveOnly }

/// 导入预览：预览图（或现场渲染）+ 版本 + 差异摘要。
class _ImportPreviewDialog extends StatelessWidget {
  const _ImportPreviewDialog({
    required this.package,
    required this.current,
    this.sourceName,
    this.appliedFromList = false,
  });

  final NovelThemePackage package;
  final NovelReaderSettings current;
  final String? sourceName;
  final bool appliedFromList;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final previewBytes = package.previewPng;
    final preview = previewBytes != null
        ? ClipRRect(
            borderRadius: MimaoShapes.sm,
            child: Image.memory(
              previewBytes,
              width: 220,
              height: 294,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  NovelThemePreview(settings: package.settings),
            ),
          )
        : NovelThemePreview(settings: package.settings);
    final differences = describeNovelThemeDifferences(
      current,
      package.settings,
    );
    return AlertDialog(
      title: Row(
        children: <Widget>[
          Expanded(child: Text(package.name)),
          NovelTag(label: 'v${package.version}'),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              preview,
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      package.settings.darkBackground ? '深色背景' : '浅色背景',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('会修改这些项', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 6),
                    if (differences.isEmpty)
                      Text(
                        '与当前设置完全一致，应用后没有可见变化。',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: <Widget>[
                          for (final item in differences) NovelTag(label: item),
                        ],
                      ),
                    const SizedBox(height: 10),
                    if (package.keyBindings.isNotEmpty)
                      Text(
                        '包含 ${package.keyBindings.length} 条键位映射'
                        '${package.keyBindings.isEmpty ? '' : '：${package.keyBindings.map((b) => b.keys).take(4).join('、')}'
                                  '${package.keyBindings.length > 4 ? '…' : ''}'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    if (sourceName != null && sourceName!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '来源文件：$sourceName',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      appliedFromList
                          ? '应用后写入你的全局阅读设置；重新打开阅读页生效。'
                          : '应用会写入全局阅读设置并保存到「我的主题」；'
                                '只保存则先放进列表、稍后再应用。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消'),
        ),
        if (appliedFromList)
          FilledButton(
            key: const Key('novel-theme-apply-confirm'),
            onPressed: () => Navigator.of(context).pop(_ImportChoice.apply),
            child: const Text('应用'),
          )
        else ...<Widget>[
          OutlinedButton(
            key: const Key('novel-theme-save-only'),
            onPressed: () => Navigator.of(context).pop(_ImportChoice.saveOnly),
            child: const Text('仅保存'),
          ),
          FilledButton(
            key: const Key('novel-theme-apply-confirm'),
            onPressed: () => Navigator.of(context).pop(_ImportChoice.apply),
            child: const Text('应用并保存'),
          ),
        ],
      ],
    );
  }
}

/// 粘贴主题包 JSON。
class _PasteThemeDialog extends StatefulWidget {
  const _PasteThemeDialog();

  @override
  State<_PasteThemeDialog> createState() => _PasteThemeDialogState();
}

class _PasteThemeDialogState extends State<_PasteThemeDialog> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('粘贴主题包 JSON'),
      content: SizedBox(
        width: 620,
        child: TextField(
          controller: _text,
          minLines: 10,
          maxLines: 16,
          decoration: const InputDecoration(
            labelText: '主题包 JSON',
            hintText: '以 {"format":"mimao-novel-reader-theme",...} 开头',
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_text.text),
          child: const Text('继续'),
        ),
      ],
    );
  }
}
