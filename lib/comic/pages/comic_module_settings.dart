// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/comic_cover.dart 同款说明。
import 'package:flutter/material.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/engine/engine.dart' show ComicSourceCatalog;
import 'package:mimao/comic/pages/comic_source_page.dart';
import 'package:mimao/comic/search_history_service.dart';

/// 漫画模块在设置抽屉里的最小可用面板（closure-02 §5）：
/// 打开源管理 + 清除搜索历史。不过度设计，只依赖注入的仓库/服务。
class ComicModuleSettings extends StatefulWidget {
  const ComicModuleSettings({
    super.key,
    required this.sourceRepository,
    required this.searchHistory,
    this.sourceCatalog,
    this.onImportSource,
    this.onDeleteSource,
  });

  final ComicSourceRepository sourceRepository;
  final ComicSearchHistoryService searchHistory;

  /// 源仓库目录，打开源管理时透传；null 时源管理页不显示仓库区块。
  final ComicSourceCatalog? sourceCatalog;

  /// 源管理页的写操作回调，透传给源管理页；模块层用它触发执行池对账
  /// （与 ComicModulePage 的同名回调语义一致，两条入口路径行为对齐）。
  final ValueChanged<String>? onImportSource;
  final ValueChanged<ComicSourceInfo>? onDeleteSource;

  @override
  State<ComicModuleSettings> createState() => _ComicModuleSettingsState();
}

class _ComicModuleSettingsState extends State<ComicModuleSettings> {
  bool _clearing = false;

  Future<void> _clearHistory() async {
    if (_clearing) return;
    setState(() => _clearing = true);
    try {
      await widget.searchHistory.clear();
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('搜索历史已清除')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('清除失败：$e')));
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  void _openSources() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'comic/sources'),
        builder: (_) => ComicSourcePage(
          repository: widget.sourceRepository,
          catalog: widget.sourceCatalog,
          onImport: widget.onImportSource,
          onDelete: widget.onDeleteSource,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        OutlinedButton.icon(
          key: const Key('comic-settings-open-sources'),
          onPressed: _openSources,
          icon: const Icon(Icons.source_outlined),
          label: const Text('打开源管理'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('comic-settings-clear-history'),
          onPressed: _clearing ? null : _clearHistory,
          icon: const Icon(Icons.history_rounded),
          label: Text(_clearing ? '清除中…' : '清除搜索历史'),
        ),
      ],
    );
  }
}
