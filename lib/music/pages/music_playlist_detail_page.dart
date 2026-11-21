// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 歌单详情页（U4）：头部信息 + 曲目分页 + 播放。
///
/// - 云歌单（[MusicPlaylistDetailPage.cloudListId] 非空）走
///   `playlistTrackAllNew`，头部用构造传入的 title/coverUrl；
/// - 公开歌单走 `playlistDetail`（头部）+ `playlistTrackAll`（曲目），
///   头部缺失/失败时用传入占位，不挡曲目。
///
/// 写能力（仅云歌单 + editable + write 非空）：编辑信息 / 更换封面 /
/// 曲目管理（多选删除 + 上移下移排序）/ 添加歌曲。编辑与封面写
/// `playlistUpdate` 需要 `totalRevision`（取 playlistTrackAllNew 返回的
/// revision，缺省用构造传入）与 `sortIndex`（构造传入）；两者缺失时入口
/// 置灰并说明「缺少云端版本信息」。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/playlist_del.dart';
import 'package:mimao/music/api/playlist_detail.dart';
import 'package:mimao/music/api/playlist_pic_upload.dart';
import 'package:mimao/music/api/playlist_read_api.dart';
import 'package:mimao/music/api/playlist_track_all.dart';
import 'package:mimao/music/api/playlist_track_all_new.dart';
import 'package:mimao/music/api/playlist_tracks_add.dart';
import 'package:mimao/music/api/playlist_tracks_del.dart';
import 'package:mimao/music/api/playlist_tracks_sort.dart';
import 'package:mimao/music/api/playlist_update.dart';
import 'package:mimao/music/api/playlist_write_api.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playlist_models.dart';
import 'package:mimao/music/models/playlist_write_models.dart';
import 'package:mimao/music/pages/music_playlist_add_songs_page.dart';
import 'package:mimao/music/pages/music_playlist_edit_sheet.dart';
import 'package:mimao/music/pages/music_playlist_image_picker.dart';
import 'package:mimao/music/player/player_ui.dart';
import 'package:mimao/music/widgets/music_song_card.dart';

/// 歌单详情。`globalId` 是公开歌单标识（云歌单可传空串）；`cloudListId`
/// 非空时优先走云歌单曲目端点。`editable` 由列表页传入：true 且 write
/// 非空时提供删除歌单与曲目写操作。
class MusicPlaylistDetailPage extends StatefulWidget {
  const MusicPlaylistDetailPage({
    super.key,
    required this.read,
    required this.player,
    required this.globalId,
    this.cloudListId,
    this.title,
    this.coverUrl,
    this.write,
    this.editable,
    this.revision,
    this.sortIndex,
    this.kind,
    this.description,
    this.tags,
    this.searchSongs,
    this.imagePicker,
  });

  final MusicPlaylistReadApi read;
  final MusicPlayerUi player;

  /// 公开歌单标识；云歌单可传空串。
  final String globalId;

  /// 云歌单 id；非空时优先走 playlistTrackAllNew。
  final int? cloudListId;
  final String? title;
  final String? coverUrl;

  /// 歌单写端点；null 表示写功能未接线（不显示任何写入口）。
  final MusicPlaylistWriteApi? write;

  /// 列表页回传的 editable 事实；null 视为不可编辑（写入口隐藏）。
  final bool? editable;

  /// 云歌单版本（wire list_ver）。写操作的兜底：playlistTrackAllNew 返回
  /// 的 revision 优先，缺失时才用这里传入的值。
  final int? revision;

  /// 歌单在账号云歌单库里的排序位（wire sort，可为负）。playlistUpdate
  /// 必传；缺失时编辑信息/更换封面入口置灰。
  final int? sortIndex;

  /// 歌单归属种类；缺失按 owned 处理（与 PlaylistUpdateQuery 缺省一致）。
  final MusicPlaylistKind? kind;

  /// 列表页透传的歌单简介/标签（cloudlist 文本，可为空串）。
  final String? description;
  final String? tags;

  /// 搜索歌曲的注入缝（集成者传 discovery 的搜索端点）；null 时隐藏
  /// 「添加歌曲」入口。
  final MusicSongSearch? searchSongs;

  /// 封面图片选择缝；null 时首次使用构造默认 file_picker 实现（懒构造，
  /// 不在 build 里碰插件）。测试注入 fake 固定字节。
  final MusicPlaylistImagePicker? imagePicker;

  @override
  State<MusicPlaylistDetailPage> createState() =>
      _MusicPlaylistDetailPageState();
}

enum _Phase { loading, error, ready }

class _MusicPlaylistDetailPageState extends State<MusicPlaylistDetailPage> {
  /// 公开歌单 1..=200、云歌单 1..=300；50 对两端点都合法。
  static const int _pageSize = 50;

  /// 宽窗下正文收窄居中，避免长行拉满整屏。
  static const double _wideBreakpoint = 720;

  MusicPlaylistDetail? _detail;
  List<MusicPlaylistTrack> _tracks = const <MusicPlaylistTrack>[];
  int _total = 0;
  int _nextPage = 1;
  bool _hasMore = false;
  bool _loadingMore = false;
  bool _deleting = false;
  _Phase _phase = _Phase.loading;
  bool _authError = false;
  String _errorMessage = '';

  /// playlistTrackAllNew 观察到的最新版本；比构造传入的 revision 新。
  int? _cloudRevision;

  /// 写成功后的本地展示覆盖（远端刷新是异步的，先给即时反馈）。
  String? _titleOverride;
  String? _descriptionOverride;
  String? _tagsOverride;
  String? _coverOverride;

  /// 通用写忙标志：编辑/封面/加歌/删歌/排序共用，防重复提交。
  bool _writing = false;

  /// 曲目管理模式（多选删除 + 上移下移排序）。
  bool _selectionMode = false;
  final Set<int> _selectedFileIds = <int>{};

  /// 默认图片选择器（懒构造：不在 build 里碰 file_picker 插件）。
  MusicPlaylistImagePicker? _lazyImagePicker;

  bool get _isCloud => widget.cloudListId != null;

  /// 删除歌单（仅可编辑云歌单 + 写端点已接线）。
  bool get _canDelete =>
      _isCloud && widget.write != null && widget.editable == true;

  /// 曲目/信息写入口（比删除少了版本信息要求：删歌/加歌不需要 revision）。
  bool get _canWrite =>
      _isCloud && widget.write != null && widget.editable == true;

  /// playlistUpdate 必需的版本事实：revision（云端优先）+ sortIndex（构造）。
  int? get _latestRevision => _cloudRevision ?? widget.revision;

  bool get _hasVersionInfo =>
      _latestRevision != null && widget.sortIndex != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── 数据装配 ────────────────────────────────────────────────────────────

  /// 首屏：曲目失败 = 整页错误（可重试）；公开歌单头部失败静默降级为占位。
  Future<void> _load() async {
    setState(() => _phase = _Phase.loading);
    // 公开歌单头部与曲目并行取：头部慢/失败都不挡曲目浏览。
    if (!_isCloud && widget.globalId.isNotEmpty) {
      unawaited(_loadHeader());
    }
    try {
      final tracks = await _fetchTracks(page: 1);
      if (!mounted) return;
      setState(() {
        _tracks = tracks.items;
        _applyPage(tracks);
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

  Future<MusicPage<MusicPlaylistTrack>> _fetchTracks({
    required int page,
  }) async {
    final cloudListId = widget.cloudListId;
    if (cloudListId != null) {
      final result = await widget.read.playlistTrackAllNew(
        MusicPlaylistTrackAllNewQuery(
          cloudListId: cloudListId,
          page: page,
          pageSize: _pageSize,
        ),
      );
      // 云端返回的 list_ver 是最新版本；编辑/排序提交要用它当 totalRevision。
      _cloudRevision = result.revision ?? _cloudRevision;
      return result.page;
    }
    return widget.read.playlistTrackAll(
      MusicPlaylistTrackAllQuery(
        globalId: widget.globalId,
        page: page,
        pageSize: _pageSize,
      ),
    );
  }

  /// 公开歌单头部；失败/缺失不挡曲目（用传入 title/coverUrl 占位）。
  Future<void> _loadHeader() async {
    if (_isCloud || widget.globalId.isEmpty) return;
    try {
      final details = await widget.read.playlistDetail(
        MusicPlaylistDetailQuery(globalIds: <String>[widget.globalId]),
      );
      if (!mounted) return;
      setState(() => _detail = details.isEmpty ? null : details.first);
    } on Object {
      // 头部是锦上添花：失败保持占位，不打断曲目浏览。
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final tracks = await _fetchTracks(page: _nextPage);
      if (!mounted) return;
      setState(() {
        _tracks = <MusicPlaylistTrack>[..._tracks, ...tracks.items];
        _applyPage(tracks);
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

  /// total 缺省时按「末页不满一页」推断是否还有更多。
  void _applyPage(MusicPage<MusicPlaylistTrack> page) {
    final total = page.total;
    _total = total ?? _tracks.length;
    _hasMore = total != null
        ? _tracks.length < total
        : page.items.length >= _pageSize;
    _nextPage = (page.page ?? 1) + 1;
  }

  /// 写操作成功后的轻量刷新：失败保留旧列表（SnackBar 提示），不清空。
  Future<void> _refreshTracks() async {
    try {
      final tracks = await _fetchTracks(page: 1);
      if (!mounted) return;
      setState(() {
        _tracks = tracks.items;
        _applyPage(tracks);
        _loadingMore = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('刷新失败：${_errorText(error)}')));
    }
  }

  // ── 交互 ────────────────────────────────────────────────────────────────

  bool _isAuthError(Object error) =>
      error is KugouApiException && error.kind == 'authentication';

  String _errorText(Object error) =>
      error is KugouApiException ? error.message : '$error';

  String get _displayTitle {
    final fromOverride = _titleOverride;
    if (fromOverride != null && fromOverride.isNotEmpty) return fromOverride;
    final fromDetail = _detail?.title ?? '';
    if (fromDetail.isNotEmpty) return fromDetail;
    final fromArg = widget.title ?? '';
    return fromArg.isNotEmpty ? fromArg : '歌单详情';
  }

  String get _displayCover {
    final override = _coverOverride;
    if (override != null && override.isNotEmpty) return override;
    final detail = _detail;
    final fromDetail = detail?.coverUrl ?? '';
    if (fromDetail.isNotEmpty) return fromDetail;
    return widget.coverUrl ?? '';
  }

  /// 简介/标签：本地覆盖 → 构造传入 → 公开详情。都没有时按空串展示。
  String get _displayDescription =>
      _descriptionOverride ?? widget.description ?? _detail?.description ?? '';

  String get _displayTags =>
      _tagsOverride ?? widget.tags ?? _detail?.tags ?? '';

  void _play(MusicPlaylistTrack track) {
    // 先起播再打开播放页（与音乐模块页同款时序）：页面立刻呈现 loading/错误态。
    widget.player.playSong(track.song);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'music/player'),
        builder: (_) => widget.player.buildPlayerPage(context),
      ),
    );
  }

  /// 双击：已加载的整个歌单替换播放队列，并从 [index] 起播（不跳播放页）。
  void _playList(int index) {
    if (_tracks.isEmpty) return;
    widget.player.playList(<MusicSong>[
      for (final track in _tracks) track.song,
    ], startIndex: index);
  }

  Future<void> _confirmDelete() async {
    final write = widget.write;
    final cloudListId = widget.cloudListId;
    if (write == null || cloudListId == null || _deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除歌单'),
        content: Text('确定删除歌单「$_displayTitle」吗？删除后不可恢复。'),
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
    setState(() => _deleting = true);
    try {
      await write.playlistDel(PlaylistDelQuery(cloudListId: cloudListId));
      if (!mounted) return;
      // pop(true) 告诉列表页「歌单已被删除」→ 列表自动刷新。
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            _isAuthError(error) ? '请先登录酷狗账号' : '删除失败：${_errorText(error)}',
          ),
        ),
      );
    }
  }

  // ── 歌单信息写 ──────────────────────────────────────────────────────────

  /// 编辑信息：sheet 收集 → playlistUpdate（title/intro/tags + 最新版本）。
  Future<void> _editInfo() async {
    final write = widget.write;
    final cloudListId = widget.cloudListId;
    final revision = _latestRevision;
    final sortIndex = widget.sortIndex;
    if (write == null ||
        cloudListId == null ||
        revision == null ||
        sortIndex == null ||
        _writing) {
      return;
    }
    final result = await showMusicPlaylistEditSheet(
      context,
      initialTitle: _displayTitle,
      initialDescription: _displayDescription,
      initialTags: _displayTags,
    );
    if (result == null || !mounted) return;
    setState(() => _writing = true);
    try {
      await write.playlistUpdate(
        PlaylistUpdateQuery(
          cloudListId: cloudListId,
          kind: widget.kind ?? MusicPlaylistKind.owned,
          totalRevision: revision,
          sortIndex: sortIndex,
          title: result.title,
          description: result.description,
          tags: result.tags,
        ),
      );
      if (!mounted) return;
      setState(() {
        _writing = false;
        _titleOverride = result.title;
        _descriptionOverride = result.description;
        _tagsOverride = result.tags;
      });
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('歌单信息已更新')));
      await _refreshTracks();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _writing = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            _isAuthError(error) ? '请先登录酷狗账号' : '保存失败：${_errorText(error)}',
          ),
        ),
      );
    }
  }

  /// 更换封面：选 PNG → playlistPicUpload（本地日历日校验和）→ 拿 fileName
  /// 拼 `custom/<fileName>` → playlistUpdate(coverReference:) → 刷新头部。
  Future<void> _changeCover() async {
    final write = widget.write;
    final cloudListId = widget.cloudListId;
    final revision = _latestRevision;
    final sortIndex = widget.sortIndex;
    if (write == null ||
        cloudListId == null ||
        revision == null ||
        sortIndex == null ||
        _writing) {
      return;
    }
    final picker =
        widget.imagePicker ??
        (_lazyImagePicker ??= const FilePickerPlaylistImagePicker());
    Uint8List? png;
    try {
      png = await picker.pickPng();
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('选择图片失败：${_errorText(error)}')));
      return;
    }
    if (png == null || !mounted) return;
    // 与端点同域的前置校验：非 PNG 在上传前拦下（端点仍会复核）。
    final invalid = validatePlaylistCoverPng(png);
    if (invalid != null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(invalid)));
      return;
    }
    setState(() => _writing = true);
    try {
      // 校验和按本地日历日（不是 UTC），格式 yyyyMMdd。
      final now = DateTime.now();
      final localDate =
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      final cover = await write.playlistPicUpload(
        PlaylistPicUploadQuery(png: png, localDate: localDate),
      );
      // playlist_update 的 cover_reference 入参形态是 `custom/<file_name>`
      //（与端点回执 reference 同形，这里按约定重新拼装）。
      final change = await write.playlistUpdate(
        PlaylistUpdateQuery(
          cloudListId: cloudListId,
          kind: widget.kind ?? MusicPlaylistKind.owned,
          totalRevision: revision,
          sortIndex: sortIndex,
          title: _titleOverride ?? widget.title,
          description: _displayDescription,
          tags: _displayTags,
          coverReference: 'custom/${cover.fileName}',
        ),
      );
      if (!mounted) return;
      setState(() {
        _writing = false;
        _coverOverride = change.coverUrl ?? _coverOverride;
      });
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('封面已更新')));
      await _refreshTracks();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _writing = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            _isAuthError(error) ? '请先登录酷狗账号' : '封面上传失败：${_errorText(error)}',
          ),
        ),
      );
    }
  }

  // ── 曲目写 ──────────────────────────────────────────────────────────────

  /// 添加歌曲：加歌页搜索多选 → playlistTracksAdd → 刷新 + SnackBar。
  Future<void> _addSongs() async {
    final write = widget.write;
    final cloudListId = widget.cloudListId;
    final searchSongs = widget.searchSongs;
    if (write == null ||
        cloudListId == null ||
        searchSongs == null ||
        _writing) {
      return;
    }
    final songs = await Navigator.of(context).push<List<MusicSong>>(
      MaterialPageRoute<List<MusicSong>>(
        settings: const RouteSettings(name: 'music/playlist/add-songs'),
        builder: (_) => MusicPlaylistAddSongsPage(searchSongs: searchSongs),
      ),
    );
    if (songs == null || songs.isEmpty || !mounted) return;
    // PlaylistTrackInput 需要 int 型专辑/歌曲 id；缺失关键信息的跳过。
    final inputs = <PlaylistTrackInput>[];
    for (final song in songs) {
      final albumId = int.tryParse(song.albumId);
      final songId = int.tryParse(song.id);
      if (song.hash.isEmpty || albumId == null || songId == null) continue;
      inputs.add(
        PlaylistTrackInput(
          title: song.title,
          hash: song.hash,
          albumId: albumId,
          songId: songId,
        ),
      );
    }
    if (inputs.isEmpty) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('所选歌曲缺少必要信息，未能添加')));
      return;
    }
    setState(() => _writing = true);
    try {
      await write.playlistTracksAdd(
        PlaylistTracksAddQuery(cloudListId: cloudListId, tracks: inputs),
      );
      if (!mounted) return;
      setState(() => _writing = false);
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('已添加 ${inputs.length} 首歌曲')));
      await _refreshTracks();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _writing = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            _isAuthError(error) ? '请先登录酷狗账号' : '添加失败：${_errorText(error)}',
          ),
        ),
      );
    }
  }

  void _enterSelection() {
    setState(() {
      _selectionMode = true;
      _selectedFileIds.clear();
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedFileIds.clear();
    });
  }

  void _toggleTrackSelection(MusicPlaylistTrack track) {
    final fileId = track.fileId;
    if (fileId == null) return;
    setState(() {
      if (!_selectedFileIds.add(fileId)) {
        _selectedFileIds.remove(fileId);
      }
    });
  }

  /// 多选删除：fileId 来自新鲜的曲目读取（不是 mixsongid，上游注释）。
  Future<void> _confirmDeleteTracks() async {
    final write = widget.write;
    final cloudListId = widget.cloudListId;
    if (write == null ||
        cloudListId == null ||
        _writing ||
        _selectedFileIds.isEmpty) {
      return;
    }
    final count = _selectedFileIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除歌曲'),
        content: Text('将把选中的 $count 首歌曲从歌单中移除，确定继续吗？'),
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
    setState(() => _writing = true);
    try {
      await write.playlistTracksDel(
        PlaylistTracksDelQuery(
          cloudListId: cloudListId,
          fileIds: _selectedFileIds.toList(),
        ),
      );
      if (!mounted) return;
      setState(() {
        _writing = false;
        _selectedFileIds.clear();
      });
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('已删除 $count 首歌曲')));
      await _refreshTracks();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _writing = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            _isAuthError(error) ? '请先登录酷狗账号' : '删除失败：${_errorText(error)}',
          ),
        ),
      );
    }
  }

  /// 上移/下移：本地先换位给即时反馈，playlistTracksSort(revision, positions)
  /// 提交后刷新对齐服务端顺序（失败也刷新回滚，不清空列表）。
  Future<void> _moveTrack(int index, int delta) async {
    final write = widget.write;
    final cloudListId = widget.cloudListId;
    final revision = _latestRevision;
    if (write == null || cloudListId == null || revision == null || _writing) {
      return;
    }
    if (_tracks[index].fileId == null) return;
    final target = index + delta;
    if (target < 0 || target >= _tracks.length) return;
    final reordered = <MusicPlaylistTrack>[..._tracks];
    final moved = reordered.removeAt(index);
    reordered.insert(target, moved);
    // positions 覆盖所有带 fileId 的行：按新的展示顺序 0 起始连续编号
    //（端点要求 fileId 与位置都不得重复）。
    final positions = <PlaylistTrackSortPosition>[];
    var position = 0;
    for (final row in reordered) {
      final fileId = row.fileId;
      if (fileId == null) continue;
      positions.add(
        PlaylistTrackSortPosition(fileId: fileId, position: position),
      );
      position++;
    }
    setState(() {
      _writing = true;
      _tracks = reordered;
    });
    try {
      await write.playlistTracksSort(
        PlaylistTracksSortQuery(
          cloudListId: cloudListId,
          revision: revision,
          positions: positions,
        ),
      );
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              _isAuthError(error) ? '请先登录酷狗账号' : '排序失败：${_errorText(error)}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _writing = false);
    }
    if (mounted) await _refreshTracks();
  }

  // ── 渲染 ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selectionMode ? _buildSelectionAppBar() : _buildNormalAppBar(),
      body: switch (_phase) {
        _Phase.loading => const Center(child: CircularProgressIndicator()),
        _Phase.error => _ErrorView(
          message: _errorMessage,
          auth: _authError,
          onRetry: _authError ? null : _load,
        ),
        _Phase.ready => LayoutBuilder(
          builder: (context, constraints) => _buildReady(constraints),
        ),
      },
    );
  }

  AppBar _buildNormalAppBar() {
    return AppBar(
      title: Text(_displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: <Widget>[
        if (_canWrite)
          PopupMenuButton<String>(
            tooltip: '歌单管理',
            icon: _writing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.more_vert),
            itemBuilder: (context) => <PopupMenuItem<String>>[
              PopupMenuItem<String>(
                value: 'info',
                enabled: _hasVersionInfo && !_writing,
                child: _menuTile(
                  '编辑信息',
                  note: _hasVersionInfo ? null : '缺少云端版本信息',
                ),
              ),
              PopupMenuItem<String>(
                value: 'cover',
                enabled: _hasVersionInfo && !_writing,
                child: _menuTile(
                  '更换封面',
                  note: _hasVersionInfo ? null : '缺少云端版本信息',
                ),
              ),
              if (widget.searchSongs != null)
                PopupMenuItem<String>(
                  value: 'add',
                  enabled: !_writing,
                  child: const Text('添加歌曲'),
                ),
              PopupMenuItem<String>(
                value: 'manage',
                enabled: !_writing,
                child: const Text('管理曲目'),
              ),
            ],
            onSelected: (value) => switch (value) {
              'info' => _editInfo(),
              'cover' => _changeCover(),
              'add' => _addSongs(),
              'manage' => _enterSelection(),
              _ => null,
            },
          ),
        if (_canDelete)
          IconButton(
            tooltip: '删除歌单',
            icon: _deleting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.delete_outline),
            onPressed: _deleting ? null : _confirmDelete,
          ),
      ],
    );
  }

  /// 曲目管理模式的顶栏：选中计数 + 删除/取消。
  AppBar _buildSelectionAppBar() {
    return AppBar(
      title: Text('已选 ${_selectedFileIds.length} 首'),
      leading: IconButton(
        tooltip: '退出选择',
        icon: const Icon(Icons.close),
        onPressed: _writing ? null : _exitSelection,
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _selectedFileIds.isEmpty || _writing
              ? null
              : _confirmDeleteTracks,
          child: const Text('删除'),
        ),
        TextButton(
          onPressed: _writing ? null : _exitSelection,
          child: const Text('取消'),
        ),
      ],
    );
  }

  /// 菜单条目：主文案 + 可选说明（版本信息缺失时置灰展示原因）。
  Widget _menuTile(String title, {String? note}) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(title),
      if (note != null)
        Text(
          note,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
    ],
  );

  Widget _buildReady(BoxConstraints constraints) {
    final wide = constraints.maxWidth >= _wideBreakpoint;
    final empty = _tracks.isEmpty;
    final itemCount = 1 + (empty ? 1 : _tracks.length + (_hasMore ? 1 : 0));
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: wide ? _wideBreakpoint : constraints.maxWidth,
        ),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: itemCount,
          itemBuilder: (context, index) {
            if (index == 0) return _buildHeader(context);
            if (empty) return const _EmptyHint(text: '歌单里还没有歌曲');
            final trackIndex = index - 1;
            if (trackIndex < _tracks.length) {
              return MusicSongCard(child: _buildTrackRow(context, trackIndex));
            }
            return _buildFooter();
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final detail = _detail;
    final creator = detail?.creatorName ?? '';
    final description = _displayDescription;
    final songCount = detail?.songCount ?? _total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            _PlaylistCover(url: _displayCover, size: 96),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _displayTitle,
                    style: theme.textTheme.titleLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (creator.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      '创建者：$creator',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (songCount > 0) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      '共 $songCount 首',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (description.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 8),
        Divider(height: 1, color: cs.outlineVariant),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildTrackRow(BuildContext context, int index) {
    final track = _tracks[index];
    final song = track.song;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final selectable = track.fileId != null;
    final selected = selectable && _selectedFileIds.contains(track.fileId);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: <Widget>[
          if (_selectionMode) ...<Widget>[
            // fileId 为空的行不可选（fileId 必须来自新鲜读取才能删/排）。
            Checkbox(
              value: selected,
              onChanged: selectable && !_writing
                  ? (_) => _toggleTrackSelection(track)
                  : null,
            ),
            const SizedBox(width: 4),
          ],
          SizedBox(
            width: 28,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _PlaylistCover(url: song.coverUrl, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  song.artistText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (_selectionMode) ...<Widget>[
            IconButton(
              tooltip: '上移',
              icon: const Icon(Icons.arrow_upward, size: 20),
              onPressed: selectable && !_writing && index > 0
                  ? () => _moveTrack(index, -1)
                  : null,
            ),
            IconButton(
              tooltip: '下移',
              icon: const Icon(Icons.arrow_downward, size: 20),
              onPressed: selectable && !_writing && index < _tracks.length - 1
                  ? () => _moveTrack(index, 1)
                  : null,
            ),
          ] else ...<Widget>[
            const SizedBox(width: 8),
            Text(
              _formatDuration(song.durationMs),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
    return InkWell(
      key: ValueKey<String>('track-$index-${song.id}-${song.hash}'),
      onTap: () {
        if (_selectionMode) {
          _toggleTrackSelection(track);
        } else {
          _play(track);
        }
      },
      // 多选管理下双击无意义（单击用于勾选），禁用整列表播放。
      onDoubleTap: _selectionMode ? null : () => _playList(index),
      child: row,
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

String _formatDuration(int? durationMs) {
  if (durationMs == null || durationMs <= 0) return '';
  final seconds = durationMs ~/ 1000;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// 封面缩略图；无 URL / 加载失败 / 离线测试时回退到歌单占位图标。
class _PlaylistCover extends StatelessWidget {
  const _PlaylistCover({required this.url, this.size = 56});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
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
        width: size,
        height: size,
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
