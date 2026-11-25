// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明。
/// 本地书导入页：选文件 → 嗅探编码/格式 → 预览目录（可改规则）→ 确认导入。
///
/// 同一个页面兼两个用途：
/// - **新导入**：从书架「添加本地」进来，选一个 TXT / EPUB / Markdown；
/// - **重新定位**：某本书的文件被移动/删除后，从详情页带 `relocateBookId`
///   进来，只让用户重新选文件，导入完把这本书指到新路径（进度、书签保留）。
///
/// 目录预览复用「TXT 目录规则」表：改规则 → 立刻用真实文件重新分章，
/// 看得到前若干章标题与实际章数，再决定是否导入。
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/local/local_book_service.dart';
import 'package:mimao/novel/local/local_epub.dart';
import 'package:mimao/novel/local/local_models.dart';
import 'package:mimao/novel/local/local_source.dart';
import 'package:mimao/novel/local/local_txt.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';

/// 文件选择缝（生产走 file_picker；测试注入内存文件，不碰真实路径）。
abstract interface class NovelLocalFileGate {
  /// 让用户选一个本地书文件；取消返回 null。
  Future<NovelLocalPickedFile?> pick();

  /// 让用户重新选一个文件（重新定位用；提示文案不同）。
  Future<NovelLocalPickedFile?> pickForRelocate(String title);
}

/// 选中的文件：路径 + 已读字节（预览阶段要反复扫，读一次就够）。
class NovelLocalPickedFile {
  const NovelLocalPickedFile({
    required this.name,
    required this.path,
    required this.bytes,
  });

  /// 展示名（文件名）。
  final String name;

  /// 落库路径（Android 上 content:// 时退回展示名）。
  final String path;

  final Uint8List bytes;

  /// 预览用的内存来源：不再读盘，导入时也用它（避免二次读盘拿到不同内容）。
  NovelLocalBytes get source => NovelMemoryFile(path, bytes);
}

/// 生产实现：file_picker 13.x 的静态 API。
class FilePickerNovelLocalFileGate implements NovelLocalFileGate {
  const FilePickerNovelLocalFileGate();

  @override
  Future<NovelLocalPickedFile?> pick() => _pick('选择要导入的本地书');

  @override
  Future<NovelLocalPickedFile?> pickForRelocate(String title) =>
      _pick('重新定位《$title》的文件');

  Future<NovelLocalPickedFile?> _pick(String title) async {
    final file = await FilePicker.pickFile(
      dialogTitle: title,
      type: FileType.custom,
      allowedExtensions: const <String>['txt', 'epub', 'md', 'markdown'],
    );
    if (file == null) return null;
    final path = file.path;
    final bytes = await file.readAsBytes();
    return NovelLocalPickedFile(
      name: file.name,
      path: path == null || path.isEmpty ? file.name : path,
      bytes: bytes,
    );
  }
}

class NovelImportBookPage extends StatefulWidget {
  const NovelImportBookPage({
    super.key,
    this.localBooks,
    this.rules,
    this.fileGate,
    this.collect,
    this.relocateBookId,
    this.initialPath,
    this.onImported,
  });

  /// 本地书门面（探测/导入/重新定位）。null 时页面给能力边界说明。
  final NovelLocalBookStorage? localBooks;

  /// TXT 目录规则仓库（预览时改规则用）。null 时用内置默认规则。
  final NovelTxtRuleStorage? rules;

  /// 文件选择缝；null 时用 file_picker 生产实现。
  final NovelLocalFileGate? fileGate;

  /// 书架收藏门面：导入成功后自动上架（「确认导入 → 进书架」）。
  /// null 时只落本地书表，用户需要自己再收藏。
  final NovelCollectApi? collect;

  /// 非空 = 重新定位模式：把这本书指到新选的文件。
  final String? relocateBookId;

  /// 进页面就预填这个路径并直接探测（跳过系统文件对话框）。
  ///
  /// 用途：系统「用此应用打开 .txt/.epub」传进来的路径，以及 dev 验收脚本
  /// 直接落到目录预览。null = 正常「点按钮选文件」流程。
  final String? initialPath;

  /// 导入/重定位成功后的回调（书架用来刷新列表）。
  final void Function(NovelLocalBook book)? onImported;

  @override
  State<NovelImportBookPage> createState() => _NovelImportBookPageState();
}

enum _Stage { idle, probing, ready }

class _NovelImportBookPageState extends State<NovelImportBookPage> {
  NovelLocalPickedFile? _picked;
  NovelLocalProbe? _probe;
  List<NovelTxtRule> _rules = const <NovelTxtRule>[];
  _Stage _stage = _Stage.idle;
  String? _error;
  double _progress = 0;
  bool _importing = false;

  /// 预览命中的标题样本（改规则后重算）。
  List<String> _matches = const <String>[];

  bool get _relocating => (widget.relocateBookId ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadRules();
    final preset = widget.initialPath?.trim() ?? '';
    if (preset.isNotEmpty) {
      // 系统「用此应用打开」或 dev 验收：直接读这个路径并探测。
      WidgetsBinding.instance.addPostFrameCallback((_) => _probePath(preset));
    } else if (_relocating) {
      // 重新定位模式：直接弹文件选择，少一次点击。
      WidgetsBinding.instance.addPostFrameCallback((_) => _pickFile());
    }
  }

  /// 直接读一个已知路径（跳过系统文件对话框）。
  Future<void> _probePath(String path) async {
    try {
      final source = NovelLocalFile(path);
      final bytes = await source.readAll();
      if (!mounted) return;
      await _probeFile(
        NovelLocalPickedFile(
          name: path.split(RegExp(r'[\\/]')).last,
          path: path,
          bytes: bytes,
        ),
      );
    } on NovelLocalFileMissing catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error\n请确认文件还在原来的位置，或重新选择。');
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '读取文件失败：$error');
    }
  }

  Future<void> _loadRules() async {
    final storage = widget.rules;
    if (storage == null) {
      setState(() => _rules = novelDefaultTxtRules);
      return;
    }
    try {
      final rules = await storage.loadAll();
      if (!mounted) return;
      setState(() {
        _rules = rules.isEmpty ? novelDefaultTxtRules : rules;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _rules = novelDefaultTxtRules);
    }
  }

  Future<void> _pickFile() async {
    final gate = widget.fileGate ?? const FilePickerNovelLocalFileGate();
    final NovelLocalPickedFile? file;
    try {
      file = _relocating
          ? await gate.pickForRelocate(
              (widget.relocateBookId ?? '').isEmpty ? '这本书' : '这本书',
            )
          : await gate.pick();
    } on Object catch (error) {
      if (mounted) setState(() => _error = '打开文件选择器失败：$error');
      return;
    }
    if (file == null || !mounted) return;
    await _probeFile(file);
  }

  Future<void> _probeFile(NovelLocalPickedFile file) async {
    final books = widget.localBooks;
    if (books == null) {
      setState(() => _error = '本地书服务未启用，暂时不能导入。重启应用后再试。');
      return;
    }
    setState(() {
      _picked = file;
      _stage = _Stage.probing;
      _error = null;
      _probe = null;
      _matches = const <String>[];
      _progress = 0;
    });
    try {
      final probed = await books.probe(
        file.source,
        rules: _rules,
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      final samples = await previewNovelTxtMatches(
        source: file.source,
        encoding: probed.encoding ?? NovelTextEncoding.utf8,
        rules: _rules,
      );
      if (!mounted) return;
      setState(() {
        _probe = probed;
        _matches = samples;
        _stage = _Stage.ready;
      });
    } on NovelEpubFormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _error = error.message;
      });
    } on NovelLocalFileMissing catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _error = '$error\n请确认文件还在原来的位置，或重新选择。';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.idle;
        _error = '读取文件失败：$error';
      });
    }
  }

  /// 改规则后重新分章（只对 TXT 有意义；Markdown 按标题分级、EPUB 按 spine）。
  Future<void> _resplit() async {
    final file = _picked;
    if (file == null) return;
    await _probeFile(file);
  }

  Future<void> _openRuleEditor() async {
    final file = _picked;
    if (file == null) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _TxtRuleDialog(
        rules: _rules,
        storage: widget.rules,
        source: file.source,
        encoding: _probe?.encoding ?? NovelTextEncoding.utf8,
      ),
    );
    if (changed == true) {
      await _loadRules();
      await _resplit();
    }
  }

  Future<void> _confirmImport() async {
    final books = widget.localBooks;
    final file = _picked;
    final probed = _probe;
    if (books == null || file == null || probed == null) return;
    setState(() {
      _importing = true;
      _error = null;
      _progress = 0;
    });
    try {
      final relocateId = widget.relocateBookId;
      final book = (relocateId ?? '').isEmpty
          ? await books.importBook(
              file.source,
              rules: _rules,
              onProgress: (value) {
                if (mounted) setState(() => _progress = value);
              },
            )
          : await books.relocate(relocateId!, file.path);
      // 导入后自动上架：书架是唯一入口，「导入成功却不在书架」会让人以为失败。
      // 重新定位时书本来就在书架里，不需要再收藏。
      final collect = widget.collect;
      if ((relocateId ?? '').isEmpty && collect != null) {
        try {
          await collect.collect(
            NovelSummary(
              id: book.id,
              title: book.title,
              author: book.author,
              sourceName: novelLocalSourceName,
              sourceKey: novelLocalSourceKey,
              bookUrl: '$novelLocalSourceUrl/${book.id}',
            ),
          );
        } on Object catch (error) {
          // 上架失败不该把「已导入」整个判失败：文件已经落库，用户可以手动收藏。
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('已导入，但加入书架失败：$error')));
          }
        }
      }
      widget.onImported?.call(book);
      if (!mounted) return;
      setState(() => _importing = false);
      Navigator.of(context).pop(book);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = '导入失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_relocating ? '重新定位文件' : '添加本地书'),
        actions: <Widget>[
          // 探测失败后 _stage 回到 idle，但 _picked 还在——这时仍要能「换一个
          // 文件」，否则错误态就成了死路（只剩重试同一个坏文件）。
          if (_picked != null || _stage != _Stage.idle || _relocating)
            TextButton(
              onPressed: _importing ? null : _pickFile,
              child: Text(_picked == null ? '选择文件' : '换一个文件'),
            ),
        ],
      ),
      body: NovelPageContent(
        maxWidth: 880,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (_error != null) ...<Widget>[
              NovelErrorState(
                message: _error!,
                hint: _picked == null
                    ? '换一个文件试试；支持 TXT / EPUB / Markdown。'
                    : '可以重新选择文件，或调整目录规则后再试。',
                onRetry: _picked == null ? null : _resplit,
              ),
              const SizedBox(height: 16),
            ],
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_stage == _Stage.probing) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const NovelLoadingState(label: '正在识别编码并分章…'),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: LinearProgressIndicator(
              value: _progress <= 0 ? null : _progress,
              minHeight: 6,
            ),
          ),
        ],
      );
    }
    final probed = _probe;
    if (probed == null) {
      return _PickPrompt(
        relocating: _relocating,
        onPick: _pickFile,
        canPick: widget.localBooks != null,
      );
    }
    return ListView(
      children: <Widget>[
        _FileSummaryCard(file: _picked!, probe: probed),
        const SizedBox(height: 16),
        _TocPreviewCard(
          probe: probed,
          matches: _matches,
          rules: _rules,
          canEditRules: probed.format != NovelLocalFormat.epub,
          onEditRules: _openRuleEditor,
          onResplit: _resplit,
          busy: _importing,
        ),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _relocating
                    ? '确认后会把这本书指到新选的文件，阅读进度、书签与划线都会保留。'
                    : '导入后书籍会加入书架，可像在线书一样阅读、加书签、划线、朗读。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              key: const Key('novel-local-confirm-import'),
              onPressed: _importing || probed.toc.isEmpty
                  ? null
                  : _confirmImport,
              icon: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_done),
              label: Text(
                _importing
                    ? '正在导入…'
                    : _relocating
                    ? '确认重新定位'
                    : '导入到书架',
              ),
            ),
          ],
        ),
        if (_importing) ...<Widget>[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _progress <= 0 ? null : _progress,
            minHeight: 6,
          ),
        ],
      ],
    );
  }
}

class _PickPrompt extends StatelessWidget {
  const _PickPrompt({
    required this.relocating,
    required this.onPick,
    required this.canPick,
  });

  final bool relocating;
  final VoidCallback onPick;
  final bool canPick;

  @override
  Widget build(BuildContext context) {
    if (!canPick) {
      return const NovelEmptyState(
        icon: Icons.folder_off_outlined,
        title: '本地书服务未启用',
        message: '当前版本没有加载本地书库，无法导入文件。重启应用后再试。',
      );
    }
    return NovelEmptyState(
      icon: Icons.file_open_outlined,
      title: relocating ? '重新选择文件' : '选择一个本地文件',
      message: relocating
          ? '文件被移动或删除了。找到它现在的位置，重新选中即可恢复阅读（进度与书签保留）。'
          : '支持 TXT（自动识别 UTF-8 / UTF-16 / GBK / GB18030 / Big5）、'
                'EPUB（按 spine 顺序）与 Markdown（按标题分章）。'
                '选好文件后会先显示目录预览，确认后再导入。',
      action: FilledButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.folder_open),
        label: const Text('选择文件'),
      ),
    );
  }
}

class _FileSummaryCard extends StatelessWidget {
  const _FileSummaryCard({required this.file, required this.probe});

  final NovelLocalPickedFile file;
  final NovelLocalProbe probe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sizeText = probe.byteSize >= 1024 * 1024
        ? '${(probe.byteSize / 1024 / 1024).toStringAsFixed(1)} MB'
        : '${(probe.byteSize / 1024).ceil()} KB';
    return NovelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          NovelSectionHeader(
            icon: Icons.insert_drive_file_outlined,
            title: probe.title.isEmpty ? file.name : probe.title,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              NovelTag(label: probe.format.label, highlighted: true),
              if (probe.encoding != null)
                NovelTag(label: probe.encoding!.label),
              NovelTag(label: sizeText),
              NovelTag(label: '${probe.toc.chapters.length} 章'),
              if (probe.author.isNotEmpty) NovelTag(label: probe.author),
              if (probe.lossy) const NovelTag(label: '编码回退'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            file.path,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          if (probe.warning != null) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: .5),
                borderRadius: MimaoShapes.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: cs.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      probe.warning!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TocPreviewCard extends StatelessWidget {
  const _TocPreviewCard({
    required this.probe,
    required this.matches,
    required this.rules,
    required this.canEditRules,
    required this.onEditRules,
    required this.onResplit,
    required this.busy,
  });

  final NovelLocalProbe probe;
  final List<String> matches;
  final List<NovelTxtRule> rules;
  final bool canEditRules;
  final VoidCallback onEditRules;
  final VoidCallback onResplit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final chapters = probe.toc.chapters;
    const previewCount = 30;
    final shown = chapters.take(previewCount).toList();
    final activeRules = rules.where((rule) => rule.enabled).length;
    return NovelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: NovelSectionHeader(
                  icon: Icons.list_alt,
                  title: '目录预览 · ${chapters.length} 章',
                ),
              ),
              if (canEditRules) ...<Widget>[
                TextButton.icon(
                  onPressed: busy ? null : onEditRules,
                  icon: const Icon(Icons.tune, size: 18),
                  label: Text('目录规则（$activeRules 条启用）'),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: '按当前规则重新分章',
                  onPressed: busy ? null : onResplit,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (chapters.isEmpty)
            Text(
              '这个文件里没有分出一章。换一个文件，或调整目录规则后重试。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          else ...<Widget>[
            for (var i = 0; i < shown.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        shown[i].title,
                        style: theme.textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            if (chapters.length > shown.length)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  '…后面还有 ${chapters.length - shown.length} 章',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
          ],
          if (matches.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Text(
              '规则命中示例（前 ${matches.length} 行）',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            for (final line in matches)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  line,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 目录规则编辑：停用/启用、改正则、新建、删自建、恢复默认；底部实时预览。
class _TxtRuleDialog extends StatefulWidget {
  const _TxtRuleDialog({
    required this.rules,
    required this.storage,
    required this.source,
    required this.encoding,
  });

  final List<NovelTxtRule> rules;
  final NovelTxtRuleStorage? storage;
  final NovelLocalBytes source;
  final NovelTextEncoding encoding;

  @override
  State<_TxtRuleDialog> createState() => _TxtRuleDialogState();
}

class _TxtRuleDialogState extends State<_TxtRuleDialog> {
  late List<NovelTxtRule> _rules = List<NovelTxtRule>.of(widget.rules);
  bool _changed = false;
  List<String> _samples = const <String>[];
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _preview();
  }

  Future<void> _preview() async {
    setState(() => _previewing = true);
    final samples = await previewNovelTxtMatches(
      source: widget.source,
      encoding: widget.encoding,
      rules: _rules,
    );
    if (!mounted) return;
    setState(() {
      _samples = samples;
      _previewing = false;
    });
  }

  Future<void> _toggle(NovelTxtRule rule, bool enabled) async {
    final storage = widget.storage;
    try {
      if (storage != null && rule.id != 0) {
        await storage.setEnabled(rule.id, enabled);
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _rules = <NovelTxtRule>[
        for (final item in _rules)
          item.id == rule.id ? item.copyWith(enabled: enabled) : item,
      ];
      _changed = true;
    });
    await _preview();
  }

  Future<void> _edit(NovelTxtRule rule) async {
    final result = await showDialog<NovelTxtRule>(
      context: context,
      builder: (_) => _RuleEditDialog(rule: rule),
    );
    if (result == null) return;
    final storage = widget.storage;
    try {
      if (storage != null) await storage.save(result);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _rules = <NovelTxtRule>[
        for (final item in _rules) item.id == result.id ? result : item,
      ];
      _changed = true;
    });
    await _preview();
  }

  Future<void> _add() async {
    final result = await showDialog<NovelTxtRule>(
      context: context,
      builder: (_) => const _RuleEditDialog(rule: null),
    );
    if (result == null) return;
    final storage = widget.storage;
    NovelTxtRule saved = result;
    try {
      if (storage != null) saved = await storage.save(result);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _rules = <NovelTxtRule>[..._rules, saved];
      _changed = true;
    });
    await _preview();
  }

  Future<void> _delete(NovelTxtRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除规则「${rule.name}」？'),
        content: const Text('删除后可以用「恢复默认」找回内置规则；自建规则删掉就没了。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final storage = widget.storage;
    try {
      if (storage != null && rule.id != 0) await storage.delete(rule.id);
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _rules = _rules.where((item) => item.id != rule.id).toList();
      _changed = true;
    });
    await _preview();
  }

  Future<void> _restore() async {
    final storage = widget.storage;
    try {
      if (storage != null) {
        await storage.restoreDefaults();
        final rules = await storage.loadAll();
        if (!mounted) return;
        setState(() {
          _rules = rules;
          _changed = true;
        });
      } else {
        setState(() {
          _rules = List<NovelTxtRule>.of(novelDefaultTxtRules);
          _changed = true;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('恢复默认失败：$error')));
      }
      return;
    }
    await _preview();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return AlertDialog(
      title: const Text('TXT 目录规则'),
      content: SizedBox(
        width: 620,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '按顺序尝试，命中即分章。规则是正则，对每一行整行匹配；'
              '行太长（超过 $novelTxtTitleMaxLength 字）会被当成正文跳过。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: <Widget>[
                  for (final rule in _rules)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Switch(
                        value: rule.enabled,
                        onChanged: (value) => _toggle(rule, value),
                      ),
                      title: Text(rule.name.isEmpty ? '（未命名规则）' : rule.name),
                      subtitle: Text(
                        rule.pattern,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: rule.isValid ? cs.onSurfaceVariant : cs.error,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          IconButton(
                            tooltip: '编辑',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(rule),
                          ),
                          IconButton(
                            tooltip: '删除',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(rule),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 16),
            Text(
              _previewing
                  ? '正在预览…'
                  : _samples.isEmpty
                  ? '当前规则在前 512 KB 里没有命中任何行。'
                  : '命中示例：${_samples.take(3).join(' / ')}'
                        '${_samples.length > 3 ? ' …' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _samples.isEmpty ? cs.error : cs.onSurfaceVariant,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: _restore, child: const Text('恢复默认')),
        TextButton(onPressed: _add, child: const Text('新建规则')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_changed),
          child: const Text('完成'),
        ),
      ],
    );
  }
}

/// 单条规则编辑：名称 + 正则，实时校验能否编译。
class _RuleEditDialog extends StatefulWidget {
  const _RuleEditDialog({required this.rule});

  /// null = 新建。
  final NovelTxtRule? rule;

  @override
  State<_RuleEditDialog> createState() => _RuleEditDialogState();
}

class _RuleEditDialogState extends State<_RuleEditDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.rule?.name ?? '',
  );
  late final TextEditingController _pattern = TextEditingController(
    text: widget.rule?.pattern ?? '',
  );

  @override
  void dispose() {
    _name.dispose();
    _pattern.dispose();
    super.dispose();
  }

  bool get _valid {
    if (_pattern.text.trim().isEmpty) return false;
    try {
      RegExp(_pattern.text);
      return true;
    } on FormatException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.rule == null ? '新建目录规则' : '编辑目录规则'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: '规则名'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pattern,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '正则表达式',
                hintText: r'^\s*第\s*[0-9一二三四五六七八九十]+\s*章',
                errorText: _pattern.text.trim().isEmpty || _valid
                    ? null
                    : '正则写错了，编译不过',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '对每一行整行匹配；用 `^` 锚定行首、`\$` 锚定行尾更稳。',
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
          onPressed: !_valid
              ? null
              : () {
                  final base =
                      widget.rule ??
                      NovelTxtRule(name: '', pattern: '', enabled: true);
                  Navigator.of(context).pop(
                    base.copyWith(
                      name: _name.text.trim().isEmpty
                          ? '自建规则'
                          : _name.text.trim(),
                      pattern: _pattern.text.trim(),
                    ),
                  );
                },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
