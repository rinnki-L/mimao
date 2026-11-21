// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 添加歌曲页：搜索歌曲 → 多选 → pop 带回选中列表。playlistTracksAdd 写
/// 端点由详情页执行（页面只做选择，与「对话框只收集、页面层写」的模式
/// 一致）。
///
/// 搜索通过构造注入的 [MusicPlaylistAddSongsPage.searchSongs]（集成者传
/// discovery 的搜索端点），页面不依赖任何搜索实现。
library;

import 'package:flutter/material.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';

/// 搜索歌曲的注入缝类型：keyword 非空、page 1 起始。
typedef MusicSongSearch =
    Future<MusicPage<MusicSong>> Function(
      String keyword, {
      int page,
      int pageSize,
    });

/// 添加歌曲页。完成时 `Navigator.pop(context, List<MusicSong>)` 带回选中
/// 歌曲（保持结果展示顺序）；返回/取消时 pop null。
class MusicPlaylistAddSongsPage extends StatefulWidget {
  const MusicPlaylistAddSongsPage({super.key, required this.searchSongs});

  final MusicSongSearch searchSongs;

  @override
  State<MusicPlaylistAddSongsPage> createState() =>
      _MusicPlaylistAddSongsPageState();
}

enum _Phase { idle, loading, error, ready }

class _MusicPlaylistAddSongsPageState extends State<MusicPlaylistAddSongsPage> {
  /// 搜索端点单页上限各异；30 与发现页搜索的默认体验一致。
  static const int _pageSize = 30;

  final TextEditingController _keywordController = TextEditingController();

  List<MusicSong> _songs = const <MusicSong>[];
  final Set<String> _selectedIds = <String>{};
  _Phase _phase = _Phase.idle;
  bool _authError = false;
  String _errorMessage = '';
  int _nextPage = 1;
  bool _hasMore = false;
  bool _loadingMore = false;

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  // ── 数据装配 ────────────────────────────────────────────────────────────

  Future<void> _search() async {
    final keyword = _keywordController.text.trim();
    if (keyword.isEmpty) return;
    setState(() {
      _phase = _Phase.loading;
      _songs = const <MusicSong>[];
      _selectedIds.clear();
      _errorMessage = '';
    });
    try {
      final result = await widget.searchSongs(
        keyword,
        page: 1,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _songs = result.items;
        _applyPage(result);
        _phase = _Phase.ready;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _authError =
            error is KugouApiException && error.kind == 'authentication';
        _errorMessage = error is KugouApiException ? error.message : '$error';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final keyword = _keywordController.text.trim();
    if (keyword.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.searchSongs(
        keyword,
        page: _nextPage,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _songs = <MusicSong>[..._songs, ...result.items];
        _applyPage(result);
        _loadingMore = false;
      });
    } on Object {
      if (!mounted) return;
      // 追加失败保留已加载内容，仅恢复按钮状态。
      setState(() => _loadingMore = false);
    }
  }

  /// total 缺省时按「末页不满一页」推断是否还有更多。
  void _applyPage(MusicPage<MusicSong> page) {
    final total = page.total;
    _hasMore = total != null
        ? _songs.length < total
        : page.items.length >= _pageSize;
    _nextPage = (page.page ?? 1) + 1;
  }

  void _toggle(MusicSong song) {
    setState(() {
      if (!_selectedIds.add(song.id)) {
        _selectedIds.remove(song.id);
      }
    });
  }

  /// pop 带回选中的歌曲（按结果展示顺序，不按勾选先后）。
  void _finish() {
    final selected = <MusicSong>[
      for (final song in _songs)
        if (_selectedIds.contains(song.id)) song,
    ];
    if (selected.isEmpty) return;
    Navigator.of(context).pop(selected);
  }

  // ── 渲染 ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('添加歌曲'),
        actions: <Widget>[
          TextButton(
            // 未选中任何歌曲时禁用；选中后带回列表。
            onPressed: _selectedIds.isEmpty ? null : _finish,
            child: Text('完成(${_selectedIds.length})'),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _keywordController,
              decoration: InputDecoration(
                labelText: '搜索歌曲',
                hintText: '输入歌名或歌手',
                suffixIcon: IconButton(
                  tooltip: '搜索',
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          Expanded(
            child: switch (_phase) {
              _Phase.idle => const _Hint(text: '输入关键词搜索要添加的歌曲'),
              _Phase.loading => const Center(
                child: CircularProgressIndicator(),
              ),
              _Phase.error => _ErrorView(
                message: _errorMessage,
                auth: _authError,
                onRetry: _authError ? null : _search,
              ),
              _Phase.ready =>
                _songs.isEmpty
                    ? const _Hint(text: '没有找到相关歌曲')
                    : _buildResults(),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    return ListView.builder(
      itemCount: _songs.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _songs.length) return _buildFooter();
        final song = _songs[index];
        return CheckboxListTile(
          key: ValueKey<String>('add-song-${song.id}'),
          value: _selectedIds.contains(song.id),
          onChanged: (_) => _toggle(song),
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${song.artistText} · ${song.albumTitle}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: _loadingMore
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : OutlinedButton.icon(
                onPressed: _loadMore,
                icon: const Icon(Icons.expand_more),
                label: const Text('加载更多'),
              ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 错误态：认证类不显示重试（重试也不会成功），其余带重试按钮。
class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.auth, this.onRetry});

  final String message;
  final bool auth;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              auth ? Icons.account_circle_outlined : Icons.error_outline,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
