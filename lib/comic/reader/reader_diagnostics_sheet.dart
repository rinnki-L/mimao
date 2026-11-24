// 阅读诊断对话框：开始/停止采集、预览、复制、保存完整 JSON。
//
// 采集本身在 [ReaderDiagnostics] 里；本文件只做展示与文件导出。报告不含
// 漫画内容/标题/路径/URL/账号/脚本/错误正文（见导出 JSON 的 privacy 字段）。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'reader_diagnostics.dart';
import 'reader_view_mode.dart';

/// 诊断报告里记录的版本号；与 `pubspec.yaml` 的 version 保持一致。
///
/// 不引 package_info_plus（多一个平台插件只为读一个字符串不划算）；
/// 升级版本时同步改这里，格式不合规时诊断会写成 unknown。
const String kReaderDiagnosticsAppVersion = '0.1.0';

/// 诊断面板。
class ReaderDiagnosticsSheet extends StatefulWidget {
  const ReaderDiagnosticsSheet({
    super.key,
    required this.diagnostics,
    this.mode = ReaderViewMode.waterfallTopToBottom,
    this.appVersion = '0.0.0',
    this.refreshRate = 60,
  });

  final ReaderDiagnostics diagnostics;

  /// 采集时记录当前阅读模式，便于对照不同模式的报告。
  final ReaderViewMode mode;
  final String appVersion;
  final double refreshRate;

  @override
  State<ReaderDiagnosticsSheet> createState() => _ReaderDiagnosticsSheetState();
}

class _ReaderDiagnosticsSheetState extends State<ReaderDiagnosticsSheet> {
  String? _message;

  ReaderDiagnostics get _diagnostics => widget.diagnostics;

  static ReaderDiagnosticMode _modeFor(ReaderViewMode mode) {
    if (mode.isGallery) return ReaderDiagnosticMode.paged;
    if (mode.isWaterfall) return ReaderDiagnosticMode.waterfall;
    return ReaderDiagnosticMode.continuous;
  }

  @override
  void initState() {
    super.initState();
    _diagnostics.addListener(_onChanged);
  }

  @override
  void dispose() {
    _diagnostics.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _copyReport() async {
    final report = _diagnostics.exportJson();
    await Clipboard.setData(ClipboardData(text: report));
    if (mounted) setState(() => _message = '已复制（${report.length} 字符）');
  }

  Future<void> _saveReport() async {
    final report = _diagnostics.exportJson(complete: true);
    try {
      final directory = await getApplicationSupportDirectory();
      final stamp = DateTime.now().toIso8601String().replaceAll(
        RegExp(r'[:.]'),
        '-',
      );
      final fallback = File(
        p.join(directory.path, 'reader-diagnostics-$stamp.json'),
      );
      final uri = await FilePicker.saveFile(
        fileName: 'reader-diagnostics-$stamp.json',
        bytes: utf8.encode(report),
        mimeType: 'application/json',
        dialogTitle: '保存阅读诊断报告',
      );
      if (!mounted) return;
      if (uri == null) {
        // 用户取消保存对话框时，仍落到应用支持目录，避免白丢一次采集。
        await fallback.writeAsString(report);
        if (mounted) setState(() => _message = '已保存到 ${fallback.path}');
        return;
      }
      setState(() => _message = '已保存：${uri.toString()}');
    } on Object catch (error) {
      if (mounted) setState(() => _message = '保存失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recording = _diagnostics.isRecording;
    final hasCapture = _diagnostics.hasCapture;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text('阅读诊断', style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    key: const Key('reader-diagnostics-close'),
                    icon: const Icon(Icons.close),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: <Widget>[
                  Text(
                    '采集本机阅读过程 45 秒：图片读取/解码等待、帧时间、翻页事件。'
                    '报告只含数值与匿名图片编号，不含漫画内容、标题、路径、'
                    '网址、账号或错误正文。仅在本次阅读器内存中保留，不自动写盘。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      FilledButton.icon(
                        key: const Key('reader-diagnostics-toggle'),
                        onPressed: () {
                          if (recording) {
                            _diagnostics.stop(ReaderDiagnosticStop.review);
                          } else {
                            _diagnostics.start(
                              mode: _modeFor(widget.mode),
                              appVersion: widget.appVersion,
                              refreshRate: widget.refreshRate,
                            );
                          }
                          setState(() => _message = null);
                        },
                        icon: Icon(
                          recording ? Icons.stop : Icons.fiber_manual_record,
                        ),
                        label: Text(recording ? '停止采集' : '开始新的 45 秒采集'),
                      ),
                      const SizedBox(width: 12),
                      if (hasCapture)
                        TextButton(
                          key: const Key('reader-diagnostics-clear'),
                          onPressed: () {
                            _diagnostics.clear();
                            setState(() => _message = null);
                          },
                          child: const Text('清除'),
                        ),
                    ],
                  ),
                  if (_message != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(_message!, style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 16),
                  if (hasCapture) ...<Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('reader-diagnostics-copy'),
                            onPressed: () => unawaited(_copyReport()),
                            icon: const Icon(Icons.copy_all_outlined),
                            label: const Text('复制报告'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('reader-diagnostics-save'),
                            onPressed: () => unawaited(_saveReport()),
                            icon: const Icon(Icons.save_alt),
                            label: const Text('保存完整 JSON'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          _diagnostics.exportJson(),
                          key: const Key('reader-diagnostics-preview'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'Consolas',
                          ),
                        ),
                      ),
                    ),
                  ] else
                    Text(
                      '还没有采集结果。点上面的按钮开始，然后在阅读器里翻几页。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
