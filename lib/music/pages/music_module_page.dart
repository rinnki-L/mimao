// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 comic 页面同款说明。
/// 音乐模块主页（M4 骨架）：搜索 + 结果列表。
///
/// 模块内部导航骨架期只有这一层；歌单/播放页随播放器切片加入时换成
/// NavigationBar + IndexedStack（对齐 comic_module_page 的模式）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_store.dart';

/// 搜索框 + 结果列表。embedded=true 时由壳提供顶部「返回 + 标题」。
class MusicModulePage extends StatefulWidget {
  const MusicModulePage({
    super.key,
    required this.store,
    this.embedded = false,
  });

  final MusicStore store;

  /// true 时由壳提供顶部栏，本页不画 AppBar。
  final bool embedded;

  @override
  State<MusicModulePage> createState() => _MusicModulePageState();
}

class _MusicModulePageState extends State<MusicModulePage> {
  late final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    widget.store.search(keyword);
  }

  @override
  Widget build(BuildContext context) {
    final body = Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: '搜索歌曲 / 歌手 / 专辑',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                tooltip: '搜索',
                onPressed: _submit,
              ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Expanded(child: Observer(builder: (_) => _buildBody(context))),
      ],
    );
    if (widget.embedded) {
      return Scaffold(body: body);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('音乐')),
      body: body,
    );
  }

  Widget _buildBody(BuildContext context) {
    final store = widget.store;
    if (store.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = store.error;
    if (error != null) {
      return _ErrorState(message: error, onRetry: _submit);
    }
    if (store.results.isEmpty) {
      return _EmptyState(hasSearched: store.searched);
    }
    return ListView.builder(
      itemCount: store.results.length,
      itemBuilder: (context, index) {
        final song = store.results[index];
        return _SongTile(song: song);
      },
    );
  }
}

/// 结果行。封面占位图标——真实封面/点播进播放器随播放器切片接。
class _SongTile extends StatelessWidget {
  const _SongTile({required this.song});

  final MusicSong song;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(Icons.music_note, color: theme.colorScheme.primary),
      title: Text(
        _displayTitle(song.title),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${song.artistText}${song.albumTitle.isEmpty ? '' : ' · ${song.albumTitle}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        _formatDuration(song.durationMs),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      // 点播为占位——播放链路（song_auth → tracker → media_kit）随后续切片接。
      onTap: () {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('播放功能随播放器切片接入')));
      },
    );
  }
}

/// wire 的 SongName 可能带 `<em>` 高亮标签（复杂搜索的命中高亮），
/// 展示层统一剥掉；模型层保持上游 api 的原样语义。
String _displayTitle(String raw) =>
    raw.replaceAll('<em>', '').replaceAll('</em>', '');

String _formatDuration(int? durationMs) {
  if (durationMs == null || durationMs <= 0) return '';
  final seconds = durationMs ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasSearched});

  final bool hasSearched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        hasSearched ? '没有找到相关歌曲' : '输入关键词开始搜索',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
