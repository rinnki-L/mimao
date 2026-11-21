// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 风格推荐页（发现页入口网格落位）：标签 chips 多选 + 命中歌曲长条列表。
///
/// 逻辑从发现 tab 的内联 section 原样迁来：
/// - `selected == 1` 的标签按服务端预选；之后以本地选择为准，重取回显不覆盖；
/// - 选中/取消标签即带最新 tagIds 重取；
/// - tagIds 仅 ASCII 字母数字（接口校验约束），脏 id 不渲染、不参与重取；
/// - 请求序号丢弃标签连点的乱序旧响应；
/// - 独立 loading/error/retry，标签重取期间保留旧 chips；
/// - 标签与歌曲全空时显示空态。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/discovery_api.dart';
import 'package:mimao/music/api/everyday_style_recommend.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/pages/music_discovery_list_page.dart';
import 'package:mimao/music/pages/music_discovery_mappers.dart';
import 'package:mimao/music/player/player_ui.dart';
import 'package:mimao/music/widgets/music_song_card.dart';

/// 风格推荐页。
class MusicStyleDiscoveryPage extends StatefulWidget {
  const MusicStyleDiscoveryPage({
    super.key,
    required this.discovery,
    required this.player,
  });

  /// 发现/推荐端点组（风格推荐 everyday_style_recommend）。
  final MusicDiscoveryApi discovery;

  /// 播放 UI：点歌后 playSong 并 push 播放页。
  final MusicPlayerUi player;

  @override
  State<MusicStyleDiscoveryPage> createState() =>
      _MusicStyleDiscoveryPageState();
}

class _MusicStyleDiscoveryPageState extends State<MusicStyleDiscoveryPage> {
  /// 标签 id 的接口约束：仅 ASCII 字母数字（≤32 字节、总数 ≤128，由
  /// [EverydayStyleRecommendQuery.validate] 兜底）；页面用同一规则做防御性
  /// 过滤，脏 id 不渲染、不参与重取。
  static final RegExp _styleTagIdPattern = RegExp(r'^[0-9a-zA-Z]+$');

  bool _loading = false;
  Object? _error;

  /// 最近一次成功响应（标签目录 + 命中歌曲）；标签重取期间保留旧值，
  /// chips 才不会在重取中整块消失。
  MusicStyleRecommendations? _data;

  /// 最近一次请求下发的 tagIds（重试沿用）；首载为空列表。
  List<String> _tagIds = const <String>[];

  /// 本地选中集（chips 选中态与重取 tagIds 的唯一来源）；null 表示还没从
  /// 服务端预选（selected == 1）初始化过——只同步首次成功响应，之后重取的
  /// 回显不覆盖用户操作。
  Set<String>? _selected;

  /// 请求序号：标签连点时丢弃乱序旧响应。
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _load(const <String>[]);
  }

  // ── 数据装载 ──────────────────────────────────────────────────────────

  /// 风格推荐装载（首载 / 选标签重取 / 重试共用）；seq 丢弃乱序旧响应。
  Future<void> _load(List<String> tagIds) async {
    final seq = ++_requestSeq;
    setState(() {
      _loading = true;
      _error = null;
      _tagIds = tagIds;
    });
    try {
      final result = await widget.discovery.everydayStyleRecommend(
        EverydayStyleRecommendQuery(tagIds: _filterStyleTagIds(tagIds)),
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _data = result;
        _loading = false;
        // 预选只按首次成功响应同步（selected == 1 是服务端默认勾选态）；
        // 之后以本地选择为准，重取回显不再覆盖。
        _selected ??= <String>{
          for (final group in result.groups)
            for (final tag in group.child)
              if (tag.selected == 1) tag.id,
        };
      });
    } on Object catch (error) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// 重取前过滤 tagIds：接口只收 ASCII 字母数字且总数 ≤128（validate 会抛
  /// input 错），服务端下发的 id 理应合法，这里兜底过滤避免脏数据把整个
  /// 页面打成错误态。
  List<String> _filterStyleTagIds(List<String> tagIds) {
    final valid = tagIds
        .where((id) => id.isNotEmpty && _styleTagIdPattern.hasMatch(id))
        .toList();
    return valid.length > 128 ? valid.sublist(0, 128) : valid;
  }

  /// 点 / 取消标签：本地集合先行更新（chips 即时反馈），再带最新 tagIds 重取。
  void _toggleStyleTag(String tagId) {
    final next = Set<String>.of(_selected ?? const <String>{});
    if (!next.remove(tagId)) {
      next.add(tagId);
    }
    setState(() => _selected = next);
    _load(next.toList());
  }

  // ── 播放 ──────────────────────────────────────────────────────────────

  /// 点歌：先起播（地址异步解析）再打开播放页——与发现页同一链路。
  void _openSong(MusicSong song) {
    widget.player.playSong(song);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'music/player'),
        builder: (context) => widget.player.buildPlayerPage(context),
      ),
    );
  }

  // ── 骨架 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('风格推荐')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final error = _error;
    if (error != null) {
      // 重试沿用最近一次请求的 tagIds（首载失败则是空标签）。
      return DiscoveryErrorState(
        message: '加载失败：$error',
        onRetry: () => _load(_tagIds),
      );
    }
    final data = _data;
    if (_loading) {
      // 标签重取中：保留旧 chips（选中态由本地集合驱动），歌曲区给占位；
      // 首载则整块占位。
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: data != null && data.groups.isNotEmpty
                ? _buildChips(data)
                : const _ChipPlaceholder(),
          ),
          const SizedBox(height: 8),
          const Expanded(child: _SongListPlaceholder()),
        ],
      );
    }
    if (data == null) return const SizedBox.shrink();
    final hasChips = data.groups.isNotEmpty;
    final hasSongs = data.songs.isNotEmpty;
    if (!hasChips && !hasSongs) {
      return const DiscoveryEmptyState(message: '暂无风格推荐');
    }
    return ListView(
      key: const Key('style-discovery'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        for (final group in data.groups)
          if (group.child.isNotEmpty) _buildGroupChips(group),
        if (hasChips && hasSongs) const SizedBox(height: 8),
        for (final song in data.songs) MusicSongCard(child: _songTile(song)),
      ],
    );
  }

  /// 标签目录 chips：按组渲染；组名缺失只省略标题行；id 不合法（接口校验
  /// 仅 ASCII 字母数字）的标签不渲染，避免「可点但永不生效」的死 chip。
  Widget _buildGroupChips(MusicStyleTagGroup group) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (group.name.isNotEmpty) ...<Widget>[
            Text(group.name, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final tag in group.child)
                if (tag.id.isNotEmpty && _styleTagIdPattern.hasMatch(tag.id))
                  FilterChip(
                    label: Text(tag.name),
                    selected: _selected?.contains(tag.id) ?? false,
                    // 不用勾选图标：勾选占宽 20px 会把 label 中心推进
                    // 框架为「删除按钮」预留的命中区（FilterChip 无
                    // onDeleted 时该区不可命中），点选中 chip 的文字
                    // 会落空；选中态由填充底色表达。
                    showCheckmark: false,
                    onSelected: (_) => _toggleStyleTag(tag.id),
                    visualDensity: VisualDensity.compact,
                  ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChips(MusicStyleRecommendations data) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      for (final group in data.groups)
        if (group.child.isNotEmpty) _buildGroupChips(group),
    ],
  );

  /// 命中歌曲长条：点行走统一播放链路。
  DiscoverySongTile _songTile(MusicDiscoverySong item) {
    final song = discoverySongToMusicSong(item.song);
    return DiscoverySongTile(song: song, onTap: () => _openSong(song));
  }
}

/// chips 区的加载占位：静态灰块（不用 indeterminate 进度条，避免
/// pumpAndSettle 不收敛）。
class _ChipPlaceholder extends StatelessWidget {
  const _ChipPlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final width in const <double>[72, 96, 64, 88])
          Container(
            width: width,
            height: 32,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: MimaoShapes.pill,
            ),
          ),
      ],
    );
  }
}

/// 歌曲长条区的加载占位：静态灰块行（与真实行高接近，不跳版）。
class _SongListPlaceholder extends StatelessWidget {
  const _SongListPlaceholder();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: <Widget>[
        for (final _ in List<int>.generate(5, (index) => index))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              height: 72,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: MimaoShapes.sm,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
