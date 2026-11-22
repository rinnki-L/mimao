// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 侧栏下半部的「歌单」区（2026-11-22 侧栏信息架构升级）。
///
/// 列当前账号的云歌单（首页分页）；头部「全部」进歌单管理页（新建/导入
/// 都在那里）。窄侧栏不渲染本区（模块层控制）。
///
/// 点行行为由 [selected] 分岔（2026-11-22 侧栏主从化）：提供 [selected]
/// 时为**内嵌模式**——点行把行事实写入 selected，模块层在内容区切出对应
/// 内嵌视图并高亮本行；未提供时保持旧行为，点行走 [onOpenPlaylist]
/// push 详情页。
///
/// 登录态变化（[authEpoch]）自动重拉；未登录画「登录后同步云歌单」提示，
/// 其他失败给紧凑重试——不假装空列表。
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/user_library_api.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/user_library_models.dart';

/// 侧栏歌单区；由模块出口装配，选中态/滚动容器由模块层侧栏提供。
class MusicSidebarPlaylists extends StatefulWidget {
  const MusicSidebarPlaylists({
    super.key,
    required this.library,
    this.onOpenPlaylist,
    this.selected,
    this.onOpenAll,
    this.authEpoch,
  });

  /// 用户库接口（user_playlist 云歌单分页）。
  final MusicUserLibraryApi library;

  /// 点歌单行 → 打开详情（push；仅未提供 [selected] 的旧形态使用）。
  final ValueChanged<MusicUserPlaylist>? onOpenPlaylist;

  /// 内嵌模式的选中桥：点行写入行事实，模块层据此在内容区切视图；
  /// 行高亮也读它（按 listid 对比，重拉后对象换新仍能对上）。
  final ValueNotifier<MusicUserPlaylist?>? selected;

  /// 头部「全部」→ 歌单管理页；null 时不显示（管理能力未接线）。
  final VoidCallback? onOpenAll;

  /// 登录态变化信号：登录/切号后自动重拉。
  final ValueListenable<int>? authEpoch;

  @override
  State<MusicSidebarPlaylists> createState() => _MusicSidebarPlaylistsState();
}

class _MusicSidebarPlaylistsState extends State<MusicSidebarPlaylists> {
  /// 首页条数：侧栏只列常用歌单，全部清单走「全部」入口。
  static const int _pageSize = 30;

  List<MusicUserPlaylist>? _playlists;

  /// true = 鉴权失败（未登录/掉登录）：画「登录后同步」提示而不是报错。
  bool _authFailed = false;

  /// 其他失败：紧凑重试行（不吞成空列表）。
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    widget.authEpoch?.addListener(_reload);
    widget.selected?.addListener(_onSelectionChanged);
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant MusicSidebarPlaylists oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.authEpoch != oldWidget.authEpoch) {
      oldWidget.authEpoch?.removeListener(_reload);
      widget.authEpoch?.addListener(_reload);
      unawaited(_reload());
    }
    if (widget.selected != oldWidget.selected) {
      oldWidget.selected?.removeListener(_onSelectionChanged);
      widget.selected?.addListener(_onSelectionChanged);
    }
  }

  @override
  void dispose() {
    widget.authEpoch?.removeListener(_reload);
    widget.selected?.removeListener(_onSelectionChanged);
    super.dispose();
  }

  void _onSelectionChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _reload() async {
    try {
      final page = await widget.library.userPlaylist(
        const MusicUserPlaylistQuery(page: 1, pageSize: _pageSize),
      );
      if (!mounted) return;
      setState(() {
        _playlists = page.page.items;
        _authFailed = false;
        _failed = false;
      });
    } on KugouApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _authFailed = error.kind == 'authentication';
        _failed = !_authFailed;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _authFailed = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
          child: Row(
            children: <Widget>[
              Text(
                '歌单',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: MimaoFonts.bold,
                ),
              ),
              const Spacer(),
              if (widget.onOpenAll != null)
                TextButton(
                  onPressed: widget.onOpenAll,
                  child: const Text('全部'),
                ),
            ],
          ),
        ),
        Expanded(child: _buildBody(theme, cs)),
      ],
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme cs) {
    if (_playlists == null) {
      if (_authFailed) {
        return _hint(theme, '登录后同步云歌单');
      }
      if (_failed) {
        return _hint(theme, '歌单加载失败，点击重试', onTap: _reload);
      }
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    final playlists = _playlists!;
    if (playlists.isEmpty) return _hint(theme, '还没有云歌单');
    final focusedId = widget.selected?.value?.cloudListId;
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      itemCount: playlists.length,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        final isSelected =
            focusedId != null && playlist.cloudListId == focusedId;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Material(
            // 内嵌模式下选中行垫 secondaryContainer（M3 语言，与导航项一致）。
            color: isSelected ? theme.colorScheme.secondaryContainer : null,
            shape: RoundedRectangleBorder(borderRadius: MimaoShapes.sm),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                final selected = widget.selected;
                if (selected != null) {
                  // 内嵌模式：把行事实写回选中桥，模块层切视图；重复点同行
                  // 不回切（回分区走导航行/卡片）。
                  selected.value = playlist;
                  return;
                }
                widget.onOpenPlaylist?.call(playlist);
              },
              child: SizedBox(
                height: 44,
                child: Row(
                  children: <Widget>[
                    const SizedBox(width: 12),
                    _CoverThumb(url: playlist.coverUrl),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        playlist.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${playlist.songCount}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _hint(ThemeData theme, String message, {VoidCallback? onTap}) {
    final child = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    if (onTap == null) return child;
    return InkWell(onTap: onTap, child: child);
  }
}

/// 歌单封面缩略图（32×32，r10）；无 URL/加载失败回退音符占位
/// （模块页 _SongCover 同款缩小版）。
class _CoverThumb extends StatelessWidget {
  const _CoverThumb({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: MimaoShapes.sm,
      ),
      child: Icon(Icons.queue_music, size: 18, color: cs.primary),
    );
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: MimaoShapes.sm,
      child: Image.network(
        url,
        width: 32,
        height: 32,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}
