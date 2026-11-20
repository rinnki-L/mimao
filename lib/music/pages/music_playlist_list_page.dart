// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 歌单列表页（U4）：账号云歌单（我创建 / 我收藏）的浏览、新建与删除。
///
/// 只依赖接口（[MusicUserLibraryApi] / [MusicPlaylistReadApi] /
/// [MusicPlaylistWriteApi?] / [MusicPlayerUi]），不 import 任何实现；
/// `write` 为 null 时隐藏新建/删除入口（只读浏览）。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/playlist_add.dart';
import 'package:mimao/music/api/playlist_del.dart';
import 'package:mimao/music/api/playlist_read_api.dart';
import 'package:mimao/music/api/playlist_write_api.dart';
import 'package:mimao/music/api/user_library_api.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:mimao/music/pages/music_playlist_detail_page.dart';
import 'package:mimao/music/player/player_ui.dart';

/// 账号云歌单列表。点击条目进入详情页；write 非空时提供新建（FAB）与
/// 删除（条目菜单，仅 `editable == true` 且 cloudListId 非空）。
class MusicPlaylistListPage extends StatefulWidget {
  const MusicPlaylistListPage({
    super.key,
    required this.library,
    required this.read,
    required this.player,
    this.write,
  });

  final MusicUserLibraryApi library;
  final MusicPlaylistReadApi read;
  final MusicPlayerUi player;

  /// 歌单写端点；null 表示写功能未接线（不显示新建/删除）。
  final MusicPlaylistWriteApi? write;

  @override
  State<MusicPlaylistListPage> createState() => _MusicPlaylistListPageState();
}

enum _Phase { loading, error, ready }

class _MusicPlaylistListPageState extends State<MusicPlaylistListPage> {
  /// user_playlist 的 pageSize 上限 200；50 与云端默认体验一致。
  static const int _pageSize = 50;

  /// 宽窗阈值：超过则两列网格呈现（窄屏保持行列表）。
  static const double _wideBreakpoint = 640;

  List<MusicUserPlaylist> _items = const <MusicUserPlaylist>[];
  int _nextPage = 1;
  bool _hasMore = false;
  bool _loadingMore = false;
  _Phase _phase = _Phase.loading;
  bool _authError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  // ── 数据装配 ────────────────────────────────────────────────────────────

  /// 首屏：phase 级切换（loading/error/ready），错误带重试。
  Future<void> _loadFirst() async {
    setState(() => _phase = _Phase.loading);
    try {
      final result = await widget.library.userPlaylist(
        const MusicUserPlaylistQuery(page: 1, pageSize: _pageSize),
      );
      if (!mounted) return;
      setState(() {
        _items = result.page.items;
        _applyPage(result.page);
        _phase = _Phase.ready;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _authError = _isAuthError(error);
        _errorMessage = _authError ? '请先登录酷狗账号' : _errorText(error);
      });
    }
  }

  /// 下拉刷新 / 删除与新建后的重取：失败保留旧数据（SnackBar 提示）。
  Future<void> _refresh() async {
    try {
      final result = await widget.library.userPlaylist(
        const MusicUserPlaylistQuery(page: 1, pageSize: _pageSize),
      );
      if (!mounted) return;
      setState(() {
        _items = result.page.items;
        _applyPage(result.page);
        _phase = _Phase.ready;
      });
    } on Object catch (error) {
      if (!mounted) return;
      if (_phase != _Phase.ready) {
        setState(() {
          _phase = _Phase.error;
          _authError = _isAuthError(error);
          _errorMessage = _authError ? '请先登录酷狗账号' : _errorText(error);
        });
        return;
      }
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('刷新失败：${_errorText(error)}')));
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.library.userPlaylist(
        MusicUserPlaylistQuery(page: _nextPage, pageSize: _pageSize),
      );
      if (!mounted) return;
      setState(() {
        _items = <MusicUserPlaylist>[..._items, ...result.page.items];
        _applyPage(result.page);
        _loadingMore = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            _isAuthError(error) ? '请先登录酷狗账号' : '加载更多失败：${_errorText(error)}',
          ),
        ),
      );
    }
  }

  /// page/pageSize 是请求回显；total 取 wire `list_count`，缺省时按
  /// 「末页不满一页」推断是否还有更多。
  void _applyPage(MusicPage<MusicUserPlaylist> page) {
    final total = page.total;
    _hasMore = total != null
        ? _items.length < total
        : page.items.length >= _pageSize;
    _nextPage = (page.page ?? 1) + 1;
  }

  // ── 写操作 ──────────────────────────────────────────────────────────────

  bool _isAuthError(Object error) =>
      error is KugouApiException && error.kind == 'authentication';

  String _errorText(Object error) =>
      error is KugouApiException ? error.message : '$error';

  bool _deletable(MusicUserPlaylist playlist) =>
      widget.write != null &&
      playlist.editable == true &&
      playlist.cloudListId != null;

  Future<void> _createPlaylist() async {
    final write = widget.write;
    if (write == null) return;
    final input = await showDialog<_NewPlaylistInput>(
      context: context,
      builder: (_) => const _CreatePlaylistDialog(),
    );
    if (input == null || !mounted) return;
    try {
      await write.playlistAdd(
        PlaylistAddQuery(title: input.title, isPrivate: input.isPrivate),
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('歌单「${input.title}」已创建')));
      await _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            _isAuthError(error) ? '请先登录酷狗账号' : '创建失败：${_errorText(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _deletePlaylist(MusicUserPlaylist playlist) async {
    final write = widget.write;
    final cloudListId = playlist.cloudListId;
    if (write == null || cloudListId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定删除歌单「${playlist.title}」吗？删除后不可恢复。'),
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
    if (confirmed != true || !mounted) return;
    try {
      await write.playlistDel(PlaylistDelQuery(cloudListId: cloudListId));
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('歌单已删除')));
      await _refresh();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            _isAuthError(error) ? '请先登录酷狗账号' : '删除失败：${_errorText(error)}',
          ),
        ),
      );
    }
  }

  Future<void> _openPlaylist(MusicUserPlaylist playlist) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        settings: const RouteSettings(name: 'music/playlist/detail'),
        builder: (_) => MusicPlaylistDetailPage(
          read: widget.read,
          player: widget.player,
          globalId: playlist.globalId,
          cloudListId: playlist.cloudListId,
          title: playlist.title,
          coverUrl: playlist.coverUrl,
          write: widget.write,
          editable: playlist.editable == true,
        ),
      ),
    );
    // 详情页里删掉了歌单（pop(true)）→ 回来刷新列表。
    if (deleted == true && mounted) {
      await _refresh();
    }
  }

  // ── 渲染 ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('歌单')),
      floatingActionButton: widget.write == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _createPlaylist,
              icon: const Icon(Icons.add),
              label: const Text('新建歌单'),
            ),
      body: switch (_phase) {
        _Phase.loading => const Center(child: CircularProgressIndicator()),
        _Phase.error => _ErrorView(
          message: _errorMessage,
          auth: _authError,
          onRetry: _authError ? null : _loadFirst,
        ),
        _Phase.ready => LayoutBuilder(
          builder: (context, constraints) => _buildReady(constraints),
        ),
      },
    );
  }

  Widget _buildReady(BoxConstraints constraints) {
    final wide = constraints.maxWidth >= _wideBreakpoint;
    final Widget content;
    if (_items.isEmpty) {
      content = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          _EmptyHint(text: widget.write == null ? '还没有歌单' : '还没有歌单，点右下角新建一个吧'),
        ],
      );
    } else if (wide) {
      content = GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 360,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 3,
        ),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) return _buildFooter();
          final playlist = _items[index];
          return Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              onTap: () => _openPlaylist(playlist),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: _PlaylistRow(
                  playlist: playlist,
                  deletable: _deletable(playlist),
                  onDelete: () => _deletePlaylist(playlist),
                ),
              ),
            ),
          );
        },
      );
    } else {
      content = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 12),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) return _buildFooter();
          final playlist = _items[index];
          return ListTile(
            key: ValueKey<String>(
              'playlist-$index-${playlist.cloudListId ?? 0}-${playlist.globalId}',
            ),
            leading: _PlaylistCover(url: playlist.coverUrl),
            title: Text(
              playlist.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${playlist.songCount ?? 0}首 · ${playlist.creatorName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: _PlaylistRow.buildTrailing(
              isPrivate: playlist.private,
              deletable: _deletable(playlist),
              onDelete: () => _deletePlaylist(playlist),
            ),
            onTap: () => _openPlaylist(playlist),
          );
        },
      );
    }
    return RefreshIndicator(onRefresh: _refresh, child: content);
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

/// 条目行内容（窄屏 ListTile + 宽屏卡片共用）；trailing 是公开的，
/// 窄屏 ListTile 直接复用（chip + 可选菜单）。
class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.playlist,
    required this.deletable,
    required this.onDelete,
  });

  final MusicUserPlaylist playlist;
  final bool deletable;
  final VoidCallback onDelete;

  static Widget buildTrailing({
    required bool? isPrivate,
    required bool deletable,
    required VoidCallback onDelete,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      _PrivacyChip(isPrivate: isPrivate),
      if (deletable) ...<Widget>[
        const SizedBox(width: 4),
        _PlaylistMenu(onDelete: onDelete),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) {
    final subtitle = '${playlist.songCount ?? 0}首 · ${playlist.creatorName}';
    return Row(
      children: <Widget>[
        _PlaylistCover(url: playlist.coverUrl),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                playlist.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        buildTrailing(
          isPrivate: playlist.private,
          deletable: deletable,
          onDelete: onDelete,
        ),
      ],
    );
  }
}

/// 公开/私有标签。`private` 缺省（服务端没给）时不显示，不臆造公开事实。
class _PrivacyChip extends StatelessWidget {
  const _PrivacyChip({required this.isPrivate});

  /// true：私有；false：公开；null：服务端未给（不显示）。
  final bool? isPrivate;

  @override
  Widget build(BuildContext context) {
    final flag = isPrivate;
    if (flag == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: MimaoShapes.pill,
      ),
      child: Text(
        flag ? '私有' : '公开',
        style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

/// 条目菜单：目前只有删除（可编辑的云歌单才显示入口）。
class _PlaylistMenu extends StatelessWidget {
  const _PlaylistMenu({required this.onDelete});

  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    // 注意 value 不能是 null：PopupMenuButton 只在选中值非 null 时回调
    // onSelected（showMenu 的 then 分支判 null 跳过）。
    return PopupMenuButton<String>(
      tooltip: '歌单操作',
      icon: const Icon(Icons.more_vert),
      itemBuilder: (context) => <PopupMenuItem<String>>[
        const PopupMenuItem<String>(value: 'delete', child: Text('删除')),
      ],
      onSelected: (_) => onDelete(),
    );
  }
}

/// 封面缩略图（列表页固定 56）；无 URL / 加载失败 / 离线测试时回退到
/// 歌单占位图标。详情页另有不同尺寸的同形组件。
class _PlaylistCover extends StatelessWidget {
  const _PlaylistCover({required this.url});

  static const double _size = 56;

  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: MimaoShapes.sm,
      ),
      child: Icon(Icons.library_music, color: cs.primary),
    );
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: MimaoShapes.sm,
      child: Image.network(
        url,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        // 加载中维持占位（与音乐模块页的 loading 模式对齐，不闪空块）。
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

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

/// 新建对话框的回执（pop 带出，页面层执行写端点）。
class _NewPlaylistInput {
  const _NewPlaylistInput({required this.title, required this.isPrivate});

  final String title;
  final bool isPrivate;
}

class _CreatePlaylistDialog extends StatefulWidget {
  const _CreatePlaylistDialog();

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
  late final TextEditingController _controller = TextEditingController();
  bool _private = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建歌单'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: '歌单名称',
              hintText: '输入歌单标题',
            ),
            onSubmitted: (_) => _submit(),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _private,
            onChanged: (value) => setState(() => _private = value),
            title: const Text('私有歌单'),
            subtitle: const Text('仅自己可见'),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        // 标题变化实时驱动创建按钮可用态；空标题不允许创建。
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : _submit,
            child: const Text('创建'),
          ),
        ),
      ],
    );
  }

  void _submit() {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    Navigator.of(
      context,
    ).pop(_NewPlaylistInput(title: title, isPrivate: _private));
  }
}
