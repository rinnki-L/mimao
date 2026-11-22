// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 用户中心页（U5）：资料头 / 会员 / 听歌等级 / 听歌历史 / 已购专辑 /
/// 已购单曲 / 我的歌单。
///
/// 只依赖 [MusicUserProfileApi] / [MusicUserLibraryApi] / [MusicPlayerUi]
/// 三个接口（与 API 组、P 线保持编译隔离）；各分区独立 loading/错误/重试/
/// 空态，整页下拉刷新，宽屏两栏、窄屏单列。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/user_library_api.dart';
import 'package:mimao/music/api/user_profile_api.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:mimao/music/models/user_models.dart';
import 'package:mimao/music/pages/music_preference_page.dart';
import 'package:mimao/music/pages/music_profile_edit_page.dart';
import 'package:mimao/music/pages/music_profile_image_picker.dart';
import 'package:mimao/music/player/player_ui.dart';

/// 分页请求的每页条数（听歌历史/已购分区共用）。
const int _kPageSize = 20;

/// 我的歌单分区最多展示的条数（入口页只列前若干条）。
const int _kPlaylistDisplayLimit = 10;

/// 宽屏两栏布局的最小宽度（以下按单列）。
const double _kTwoColumnBreakpoint = 720;

/// 用户中心页。回调为空时点击只提示「未接线」，不抛异常。
class MusicAccountCenterPage extends StatefulWidget {
  const MusicAccountCenterPage({
    super.key,
    required this.profile,
    required this.library,
    required this.player,
    this.onOpenAlbum,
    this.onOpenPlaylist,
    this.imagePicker,
    this.authEpoch,
    this.loadPreferenceTagGroups,
    this.showAppBar = true,
  });

  /// 用户资料组接口（资料头/会员/等级）。
  final MusicUserProfileApi profile;

  /// 用户库组接口（历史/已购/歌单）。
  final MusicUserLibraryApi library;

  /// P 线播放 UI；点歌只调用 [MusicPlayerUi.playSong]，不开播放页。
  final MusicPlayerUi player;

  /// 打开专辑详情（已购专辑卡片点击；专辑 id 非空时才回调）。
  final ValueChanged<int>? onOpenAlbum;

  /// 打开歌单（我的歌单行点击）。
  final ValueChanged<MusicUserPlaylist>? onOpenPlaylist;

  /// 头像图片选择缝（L3）：null 时在触发「更换头像」的瞬间惰性构造
  /// file_picker 生产实现；widget 测试注入 fake，绝不真调插件。
  final MusicProfileImagePicker? imagePicker;

  /// 登录态变化信号：登录/登出后自动重拉全部账号分区（资料/会员/等级/
  /// 历史/已购/歌单），用户不必再手动点重试。null 时保持旧行为。
  final ValueListenable<int>? authEpoch;

  /// 音乐偏好页的官方标签候选注入缝（透传给 [MusicPreferencePage] 的
  /// `loadTagGroups`）：生产由入口页把发现组的
  /// `everydayStyleRecommend` 标签组接进来。null 时候选区静默隐藏，
  /// 不影响偏好的读取与保存。
  final Future<List<MusicStyleTagGroup>> Function()? loadPreferenceTagGroups;

  /// false 时由模块层侧栏/壳顶栏提供标题，本页不再画 AppBar
  /// （模块层侧栏化后分区页不再自带标题，与漫画分区页同款）。
  final bool showAppBar;

  @override
  State<MusicAccountCenterPage> createState() => _MusicAccountCenterPageState();
}

class _MusicAccountCenterPageState extends State<MusicAccountCenterPage> {
  // ── 资料头：userDetail 与 userInfo 两个独立请求，任一失败不挡另一块 ──
  MusicUserProfile? _detail;
  Object? _detailError;
  bool _detailLoading = true;

  /// 头像上传两步流程进行中（防重复提交、期间禁用入口）。
  bool _avatarBusy = false;

  MusicUserIdentityTags? _tags;
  Object? _tagsError;
  bool _tagsLoading = true;

  final _Section<MusicUserVipMemberships> _vip =
      _Section<MusicUserVipMemberships>();
  final _Section<MusicUserGradeInfo> _grade = _Section<MusicUserGradeInfo>();
  final _Section<MusicUserPlaylists> _playlists =
      _Section<MusicUserPlaylists>();
  final _PagedSection<MusicHistoryItem> _history =
      _PagedSection<MusicHistoryItem>();
  final _PagedSection<MusicPurchasedAlbum> _albums =
      _PagedSection<MusicPurchasedAlbum>();
  final _PagedSection<MusicPurchasedSong> _songs =
      _PagedSection<MusicPurchasedSong>();

  @override
  void initState() {
    super.initState();
    widget.authEpoch?.addListener(_onAuthChanged);
    unawaited(_refreshAll());
  }

  @override
  void dispose() {
    widget.authEpoch?.removeListener(_onAuthChanged);
    super.dispose();
  }

  /// 登录/登出事件：整页重拉。首次进入时的匿名加载失败会在这里被登录后的
  /// 刷新覆盖，不再需要用户手动点「重试」。
  void _onAuthChanged() {
    if (!mounted) return;
    unawaited(_refreshAll());
  }

  @override
  void didUpdateWidget(covariant MusicAccountCenterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authEpoch != widget.authEpoch) {
      oldWidget.authEpoch?.removeListener(_onAuthChanged);
      widget.authEpoch?.addListener(_onAuthChanged);
    }
    // 换了接口实例（如重新登录后换 session）就整页重拉。
    if (oldWidget.profile != widget.profile ||
        oldWidget.library != widget.library) {
      unawaited(_refreshAll());
    }
  }

  // ── 加载逻辑 ─────────────────────────────────────────────────────────

  /// 整页刷新（下拉刷新与首次进入共用）：各分区并行、互不阻塞。
  Future<void> _refreshAll() {
    return Future.wait(<Future<void>>[
      _loadDetail(),
      _loadTags(),
      _loadVip(),
      _loadGrade(),
      _loadHistoryFirstPage(),
      _loadAlbumsFirstPage(),
      _loadSongsFirstPage(),
      _loadPlaylists(),
    ]);
  }

  Future<void> _loadDetail() async {
    setState(() {
      _detailLoading = true;
      _detailError = null;
    });
    try {
      final data = await widget.profile.userDetail();
      if (!mounted) return;
      setState(() {
        _detail = data;
        _detailLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _detailError = error;
        _detailLoading = false;
      });
    }
  }

  Future<void> _loadTags() async {
    setState(() {
      _tagsLoading = true;
      _tagsError = null;
    });
    try {
      final data = await widget.profile.userInfo();
      if (!mounted) return;
      setState(() {
        _tags = data;
        _tagsLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _tagsError = error;
        _tagsLoading = false;
      });
    }
  }

  Future<void> _loadVip() =>
      _loadSection(section: _vip, fetch: widget.profile.userVipDetail);

  Future<void> _loadGrade() => _loadSection(
    section: _grade,
    fetch: () => widget.profile.userGradeInfo(null),
  );

  Future<void> _loadPlaylists() => _loadSection(
    section: _playlists,
    fetch: () => widget.library.userPlaylist(
      const MusicUserPlaylistQuery(page: 1, pageSize: _kPageSize),
    ),
  );

  /// 单值分区的通用装载：成功/失败都落在本分区状态里，互不影响。
  Future<void> _loadSection<T>({
    required _Section<T> section,
    required Future<T> Function() fetch,
  }) async {
    setState(section.reset);
    try {
      final data = await fetch();
      if (!mounted) return;
      setState(() {
        section.data = data;
        section.loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        section.error = error;
        section.loading = false;
      });
    }
  }

  Future<void> _loadHistoryFirstPage() async {
    setState(_history.reset);
    try {
      final page = await widget.library.userHistory(
        const MusicUserHistoryQuery(),
      );
      if (!mounted) return;
      setState(() {
        _applyHistoryPage(page);
        _history.loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _history.error = error;
        _history.loading = false;
      });
    }
  }

  Future<void> _loadMoreHistory() async {
    final section = _history;
    if (section.loadingMore || !section.hasMore) return;
    final bp = section.cursor;
    if (bp == null || bp.isEmpty) return;
    setState(() {
      section.loadingMore = true;
      section.moreError = null;
    });
    try {
      final page = await widget.library.userHistory(
        MusicUserHistoryQuery(bp: bp),
      );
      if (!mounted) return;
      setState(() {
        _applyHistoryPage(page);
        section.loadingMore = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        section.moreError = error;
        section.loadingMore = false;
      });
    }
  }

  /// 追加一页历史；游标与 has_more/finished 决定能否继续「加载更多」。
  void _applyHistoryPage(MusicHistoryPage page) {
    final section = _history;
    section.items.addAll(page.items);
    section.cursor = page.cursor;
    final bool hasMore = page.hasMore ?? false;
    final bool hasCursor = page.cursor != null && page.cursor!.isNotEmpty;
    section.hasMore = hasMore && hasCursor;
  }

  Future<void> _loadAlbumsFirstPage() => _loadPurchasedFirstPage(
    section: _albums,
    fetch: widget.library.userPurchasedAlbums,
  );

  Future<void> _loadSongsFirstPage() => _loadPurchasedFirstPage(
    section: _songs,
    fetch: widget.library.userPurchasedSongs,
  );

  Future<void> _loadMoreAlbums() => _loadMorePurchased(
    section: _albums,
    fetch: widget.library.userPurchasedAlbums,
  );

  Future<void> _loadMoreSongs() => _loadMorePurchased(
    section: _songs,
    fetch: widget.library.userPurchasedSongs,
  );

  /// 已购分区的通用首页装载（专辑/单曲同为 MusicPage 分页）。
  Future<void> _loadPurchasedFirstPage<T>({
    required _PagedSection<T> section,
    required Future<MusicPage<T>> Function(MusicUserPagedQuery) fetch,
  }) async {
    setState(section.reset);
    try {
      final page = await fetch(
        const MusicUserPagedQuery(page: 1, pageSize: _kPageSize),
      );
      if (!mounted) return;
      setState(() {
        _applyPurchasedPage(section, page);
        section.loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        section.error = error;
        section.loading = false;
      });
    }
  }

  Future<void> _loadMorePurchased<T>({
    required _PagedSection<T> section,
    required Future<MusicPage<T>> Function(MusicUserPagedQuery) fetch,
  }) async {
    if (section.loadingMore || !section.hasMore) return;
    final int page = section.nextPage;
    setState(() {
      section.loadingMore = true;
      section.moreError = null;
    });
    try {
      final result = await fetch(
        MusicUserPagedQuery(page: page, pageSize: _kPageSize),
      );
      if (!mounted) return;
      setState(() {
        _applyPurchasedPage(section, result);
        section.loadingMore = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        section.moreError = error;
        section.loadingMore = false;
      });
    }
  }

  /// 追加一页已购；total 缺省时按「整页返回」猜测还有下一页。
  void _applyPurchasedPage<T>(_PagedSection<T> section, MusicPage<T> page) {
    section.items.addAll(page.items);
    final int? total = page.total;
    section.total = total ?? section.total;
    section.hasMore = total != null
        ? section.items.length < total
        : page.items.length >= _kPageSize;
    section.nextPage += 1;
  }

  // ── 展示辅助 ─────────────────────────────────────────────────────────

  /// 错误文案：匿名/未登录（authentication）统一翻译成登录引导。
  String _errorText(Object error) {
    if (error is KugouApiException && error.kind == 'authentication') {
      return '请先登录酷狗账号';
    }
    return '$error';
  }

  void _showSnack(String message) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  // ── 资料写入口（L3） ─────────────────────────────────────────────────

  /// 打开资料编辑页；保存成功（pop(true)）后重拉资料头。
  Future<void> _openProfileEditor() async {
    final MusicUserProfile? detail = _detail;
    if (detail == null) return;
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            MusicProfileEditPage(profile: widget.profile, initial: detail),
      ),
    );
    if (saved == true && mounted) unawaited(_loadDetail());
  }

  /// 打开音乐偏好页（偏好不在账号中心展示，返回无需刷新）。
  Future<void> _openPreference() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MusicPreferencePage(
          library: widget.library,
          loadTagGroups: widget.loadPreferenceTagGroups,
        ),
      ),
    );
  }

  /// 更换头像：选图 → 前置校验 → base64 上传 → 提交引用 → 刷新资料。
  ///
  /// 两步接口：`userAvatarUpload` 上传图片拿文件引用，`userUpdateAvatar`
  /// 提交引用（后者可能返回「审核中」回执 34236——已提交待发布，不算失败）。
  Future<void> _changeAvatar() async {
    if (_avatarBusy) return;
    // 可注入缝：测试注入 fake；生产在此惰性构造 file_picker 实现（不在
    // build 里构造插件）。
    final MusicProfileImagePicker picker =
        widget.imagePicker ?? const FilePickerProfileImagePicker();
    setState(() => _avatarBusy = true);
    try {
      final Uint8List? bytes = await picker.pickImage();
      if (!mounted) return;
      if (bytes == null) return; // 用户取消选择
      final String? invalid = validateAvatarImageBytes(bytes);
      if (invalid != null) {
        _showSnack(invalid);
        return;
      }
      final upload = await widget.profile.userAvatarUpload(
        imageBase64: base64.encode(bytes),
        localDate: _localDateToday(),
      );
      final update = await widget.profile.userUpdateAvatar(upload.fileName);
      if (!mounted) return;
      _showSnack(update.reviewPending ? '头像审核中' : '头像已更新');
      unawaited(_loadDetail());
    } on Object catch (error) {
      if (!mounted) return;
      _showSnack('头像更新失败：$error');
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  /// 头像上传要求的 localDate：本地日期 `yyyyMMdd`。
  String _localDateToday() {
    final DateTime now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}';
  }

  MusicSong _songFromHistory(MusicHistoryItem item) => MusicSong(
    id: item.songId,
    audioId: item.audioId == null ? null : int.tryParse(item.audioId!),
    hash: item.hash,
    title: item.name,
    artists: <MusicArtistRef>[
      if (item.artist.isNotEmpty) MusicArtistRef(name: item.artist),
    ],
    albumId: item.albumId ?? '',
    albumTitle: item.album,
    durationMs: item.durationMs,
    coverUrl: item.cover ?? '',
  );

  MusicSong _songFromPurchased(MusicSongSummary song) => MusicSong(
    id: song.id,
    hash: song.hash,
    title: song.title,
    artists: song.artists,
    albumId: song.albumId,
    albumTitle: song.albumTitle ?? '',
    durationMs: song.durationMs,
    coverUrl: song.coverUrl,
    privilege: song.privilege,
  );

  String _formatDuration(int? durationMs) {
    if (durationMs == null || durationMs <= 0) return '';
    final int seconds = durationMs ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String _listeningText(int? seconds) {
    if (seconds == null || seconds < 0) return '—';
    if (seconds < 3600) return '$seconds 秒';
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    return minutes == 0 ? '$hours 小时' : '$hours 小时 $minutes 分钟';
  }

  String _playTimeText(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final DateTime time = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  String _locationText(MusicUserProfile profile) {
    if (profile.ipLocation.isNotEmpty) return profile.ipLocation;
    final String region = (profile.province + profile.city).trim();
    return region;
  }

  // ── 组装 ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 模块层侧栏化后，embedded 的分区页不自带标题（与漫画分区页同款）。
      appBar: widget.showAppBar ? AppBar(title: const Text('用户中心')) : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool wide = constraints.maxWidth >= _kTwoColumnBreakpoint;
          return RefreshIndicator(
            onRefresh: _refreshAll,
            child: wide ? _buildWideContent() : _buildNarrowContent(),
          );
        },
      ),
    );
  }

  Widget _buildNarrowContent() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        _buildProfileCard(),
        _buildVipSection(),
        _buildGradeSection(),
        _buildHistorySection(),
        _buildAlbumsSection(),
        _buildSongsSection(),
        _buildPlaylistsSection(),
      ],
    );
  }

  /// 宽屏布局：
  /// 1. 第一行是通栏资料卡，会员作为资料卡内部右侧的一栏（共用同一张卡）；
  /// 2. 第二行是听歌等级 + 已购专辑并排、等高；
  /// 3. 其下听歌历史 / 已购单曲 / 我的歌单作通栏大卡片依次排列。
  Widget _buildWideContent() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildProfileCard(withInlineVip: true),
          // 等高：IntrinsicHeight 先取两卡较高的固有高度，再由 stretch
          // 把两个 Expanded 拉伸到同一高度（内容少的专辑卡不再塌陷）。
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: _buildGradeSection()),
                const SizedBox(width: 12),
                Expanded(child: _buildAlbumsSection()),
              ],
            ),
          ),
          _buildHistorySection(),
          _buildSongsSection(),
          _buildPlaylistsSection(),
        ],
      ),
    );
  }

  /// 分区卡片骨架：标题 + 可选角标 + 内容。
  Widget _sectionCard({
    required Key key,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleMedium),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }

  /// 分区体的通用三态（loading/错误/空态），错误行带重试。
  ///
  /// [content] 用回调惰性构造：只有数据就绪才会求值（`data!` 不能在
  /// loading/空态被提前解引用）。
  Widget _sectionBody({
    required bool loading,
    Object? error,
    required VoidCallback onRetry,
    required bool isEmpty,
    required String emptyText,
    required Widget Function() content,
  }) {
    if (loading) return const _LoadingRow();
    if (error != null) {
      return _SectionError(message: _errorText(error), onRetry: onRetry);
    }
    if (isEmpty) return _EmptyRow(text: emptyText);
    return content();
  }

  /// 分页分区的尾部：加载更多 / 追加失败重试 / 没有更多。
  Widget _pagedFooter({
    required _PagedSection<Object?> section,
    required VoidCallback onLoadMore,
    required String moreKey,
  }) {
    if (section.loadingMore) return const _LoadingRow();
    final Object? moreError = section.moreError;
    if (moreError != null) {
      return _SectionError(message: _errorText(moreError), onRetry: onLoadMore);
    }
    if (section.hasMore) {
      return Center(
        child: TextButton.icon(
          key: ValueKey<String>(moreKey),
          onPressed: onLoadMore,
          icon: const Icon(Icons.expand_more),
          label: const Text('加载更多'),
        ),
      );
    }
    return const _EndRow(text: '没有更多了');
  }

  // ── 资料头 ───────────────────────────────────────────────────────────

  /// [withInlineVip] 为 true 时（仅宽屏），登录态下把会员块并进同一张
  /// 资料卡：左侧资料内容占满剩余宽度，右侧固定宽度放会员，中间一条竖线。
  Widget _buildProfileCard({bool withInlineVip = false}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final Widget body;
    if (_detailLoading) {
      body = const _LoadingRow();
    } else if (_detailError != null) {
      // 匿名/未登录等错误：整块降级为登录引导 + 重试。
      body = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.account_circle_outlined,
                size: 40,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                _errorText(_detailError!),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _loadDetail,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    } else if (withInlineVip) {
      // 登录态：资料内容 + 竖分隔线 + 内联会员，共用同一张卡片背景。
      body = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: _buildProfileBody(_detail!)),
            const SizedBox(width: 16),
            Container(width: 1, color: cs.outlineVariant),
            const SizedBox(width: 16),
            // 会员块固定宽度：宽屏下资料内容占满其余空间。
            SizedBox(width: 260, child: _buildVipInline()),
          ],
        ),
      );
    } else {
      body = _buildProfileBody(_detail!);
    }
    return Padding(
      key: const ValueKey<String>('account-profile'),
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(padding: const EdgeInsets.all(16), child: body),
      ),
    );
  }

  Widget _buildProfileBody(MusicUserProfile detail) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final children = <Widget>[
      Row(
        children: <Widget>[
          // 点头像同样进入更换头像流程（资料卡只在登录态渲染，入口天然
          // 只对登录态生效）。
          GestureDetector(
            key: const ValueKey<String>('account-avatar'),
            onTap: _avatarBusy ? null : _changeAvatar,
            child: _Avatar(url: detail.avatarUrl),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  detail.nickname.isEmpty ? '酷狗用户' : detail.nickname,
                  style: theme.textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'ID：${detail.id} · Lv.${detail.grade ?? '—'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (detail.biography.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    detail.biography,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ];

    // 身份/标签（userInfo；独立请求，失败不挡资料头主体）。
    if (_tagsLoading) {
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (_tagsError != null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '身份标签加载失败：${_errorText(_tagsError!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(onPressed: _loadTags, child: const Text('重试')),
            ],
          ),
        ),
      );
    } else {
      final tags = _tags;
      final chips = <String>[
        if (detail.identity.singer) '歌手',
        if (detail.identity.actor) '演员',
        if (detail.identity.star) '明星',
        if (detail.identity.business) '机构',
        if (tags != null && tags.studentSchool.isNotEmpty)
          '学生 · ${tags.studentSchool}',
        if (tags != null) ...tags.tags,
      ];
      if (chips.isNotEmpty) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final chip in chips)
                  Chip(
                    label: Text(chip),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ),
        );
      }
    }

    // 粉丝/关注/听歌分钟/属地等统计行。
    final location = _locationText(detail);
    final stats = <String>[
      if (detail.follows != null) '关注 ${detail.follows}',
      if (detail.fans != null) '粉丝 ${detail.fans}',
      if (detail.listeningMinutes != null) '听歌 ${detail.listeningMinutes} 分钟',
      if (location.isNotEmpty) '属地 $location',
    ];
    if (stats.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            stats.join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // 写入口（登录态）：编辑资料 / 更换头像 / 音乐偏好。
    children.add(
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            TextButton.icon(
              key: const ValueKey<String>('account-edit-profile'),
              onPressed: _openProfileEditor,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('编辑资料'),
            ),
            TextButton.icon(
              key: const ValueKey<String>('account-change-avatar'),
              onPressed: _avatarBusy ? null : _changeAvatar,
              icon: const Icon(Icons.photo_outlined, size: 18),
              label: const Text('更换头像'),
            ),
            TextButton.icon(
              key: const ValueKey<String>('account-preference'),
              onPressed: _openPreference,
              icon: const Icon(Icons.tune, size: 18),
              label: const Text('音乐偏好'),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  // ── 会员 ─────────────────────────────────────────────────────────────

  /// 宽屏资料卡内联的会员块：无 Card 外壳，只保留标题 + 三态内容，
  /// 与资料内容共用外层卡片背景。key 沿用 `account-vip` 以兼容定位/重试。
  Widget _buildVipInline() {
    final theme = Theme.of(context);
    final data = _vip.data;
    return Column(
      key: const ValueKey<String>('account-vip'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('会员', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _sectionBody(
          loading: _vip.loading,
          error: _vip.error,
          onRetry: _loadVip,
          isEmpty: _isVipEmpty(data),
          emptyText: '暂无会员信息',
          content: () => _buildVipContent(data!),
        ),
      ],
    );
  }

  Widget _buildVipSection() {
    final data = _vip.data;
    return _sectionCard(
      key: const ValueKey<String>('account-vip'),
      title: '会员',
      child: _sectionBody(
        loading: _vip.loading,
        error: _vip.error,
        onRetry: _loadVip,
        isEmpty: _isVipEmpty(data),
        emptyText: '暂无会员信息',
        content: () => _buildVipContent(data!),
      ),
    );
  }

  bool _isVipEmpty(MusicUserVipMemberships? data) {
    if (data == null) return true;
    final bool hasWindow =
        (data.deluxeExpiresAt?.isNotEmpty ?? false) ||
        (data.superExpiresAt?.isNotEmpty ?? false);
    return !hasWindow && data.products.isEmpty;
  }

  Widget _buildVipContent(MusicUserVipMemberships vip) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final children = <Widget>[];
    if (vip.deluxeExpiresAt?.isNotEmpty ?? false) {
      children.add(
        _VipRow(
          icon: Icons.workspace_premium_outlined,
          text: '豪华会员 · 至 ${vip.deluxeExpiresAt}',
        ),
      );
    }
    if (vip.superExpiresAt?.isNotEmpty ?? false) {
      children.add(
        _VipRow(
          icon: Icons.diamond_outlined,
          text: '超级会员 · 至 ${vip.superExpiresAt}',
        ),
      );
    }
    for (final product in vip.products) {
      children.add(
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            product.active == true ? Icons.verified : Icons.card_membership,
            color: cs.primary,
          ),
          title: Text(
            product.product.isNotEmpty ? product.product : product.business,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: product.expiresAt?.isNotEmpty ?? false
              ? Text('到期：${product.expiresAt}')
              : null,
          trailing: Text(
            switch (product.active) {
              true => '生效中',
              false => '未生效',
              null => '未知',
            },
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  // ── 听歌等级 ─────────────────────────────────────────────────────────

  Widget _buildGradeSection() {
    final data = _grade.data;
    return _sectionCard(
      key: const ValueKey<String>('account-grade'),
      title: '听歌等级',
      child: _sectionBody(
        loading: _grade.loading,
        error: _grade.error,
        onRetry: _loadGrade,
        isEmpty: data == null,
        emptyText: '暂无等级信息',
        content: () => _buildGradeContent(data!),
      ),
    );
  }

  Widget _buildGradeContent(MusicUserGradeInfo grade) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final int? current = grade.currentPoints;
    final int? next = grade.nextGradePoints;
    final int floor = grade.gradePoints ?? 0;
    // 本级进度：p_current_point 相对 [p_grade_point, p_next_grade_point] 区间。
    double? progress;
    if (current != null && next != null && next > floor) {
      progress = ((current - floor) / (next - floor)).clamp(0.0, 1.0);
    }
    final remaining = (current != null && next != null)
        ? (next - current).clamp(0, next - floor)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              'Lv.${grade.grade ?? '—'}',
              style: theme.textTheme.titleLarge?.copyWith(color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '当前积分 ${current ?? '—'}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '累计听歌 ${_listeningText(grade.listeningSeconds)}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        if (progress != null) ...<Widget>[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: MimaoShapes.pill,
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            grade.nextGrade != null && remaining != null && remaining > 0
                ? '距 Lv.${grade.nextGrade} 还需 $remaining 积分'
                : '成长积分已满足下一等级',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  // ── 听歌历史 ─────────────────────────────────────────────────────────

  Widget _buildHistorySection() {
    return _sectionCard(
      key: const ValueKey<String>('account-history'),
      title: '听歌历史',
      child: _sectionBody(
        loading: _history.loading,
        error: _history.error,
        onRetry: _loadHistoryFirstPage,
        isEmpty: _history.items.isEmpty,
        emptyText: '暂无听歌记录',
        content: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final item in _history.items) _buildHistoryTile(item),
            _pagedFooter(
              section: _history,
              onLoadMore: _loadMoreHistory,
              moreKey: 'account-history-more',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTile(MusicHistoryItem item) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final String subtitle = item.album.isEmpty
        ? item.artist
        : '${item.artist} · ${item.album}';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: _CoverThumb(url: item.cover),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(
            item.playCount == null ? '—' : '播放 ${item.playCount} 次',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          Text(
            _playTimeText(item.lastPlayedAt),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
      onTap: () => unawaited(widget.player.playSong(_songFromHistory(item))),
    );
  }

  // ── 已购专辑 ─────────────────────────────────────────────────────────

  Widget _buildAlbumsSection() {
    return _sectionCard(
      key: const ValueKey<String>('account-albums'),
      title: '已购专辑',
      subtitle: _albums.total == null ? null : '共 ${_albums.total} 张',
      child: _sectionBody(
        loading: _albums.loading,
        error: _albums.error,
        onRetry: _loadAlbumsFirstPage,
        isEmpty: _albums.items.isEmpty,
        emptyText: '暂无已购专辑',
        content: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              height: 164,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _albums.items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final album = _albums.items[index].album;
                  return _PurchasedAlbumCard(
                    album: album,
                    onTap: () => _openPurchasedAlbum(album),
                  );
                },
              ),
            ),
            _pagedFooter(
              section: _albums,
              onLoadMore: _loadMoreAlbums,
              moreKey: 'account-albums-more',
            ),
          ],
        ),
      ),
    );
  }

  void _openPurchasedAlbum(MusicAlbumSummary album) {
    final callback = widget.onOpenAlbum;
    final int? id = album.id;
    if (callback == null) {
      _showSnack('打开专辑功能未接线');
      return;
    }
    // id 为空（wire 不可解析）时不回调，避免上层打开无效详情。
    if (id == null) return;
    callback(id);
  }

  // ── 已购单曲 ─────────────────────────────────────────────────────────

  Widget _buildSongsSection() {
    return _sectionCard(
      key: const ValueKey<String>('account-songs'),
      title: '已购单曲',
      subtitle: _songs.total == null ? null : '共 ${_songs.total} 首',
      child: _sectionBody(
        loading: _songs.loading,
        error: _songs.error,
        onRetry: _loadSongsFirstPage,
        isEmpty: _songs.items.isEmpty,
        emptyText: '暂无已购单曲',
        content: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final item in _songs.items) _buildPurchasedSongTile(item),
            _pagedFooter(
              section: _songs,
              onLoadMore: _loadMoreSongs,
              moreKey: 'account-songs-more',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchasedSongTile(MusicPurchasedSong item) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final song = item.song;
    final String artistText = song.artists
        .map((artist) => artist.name)
        .where((name) => name.isNotEmpty)
        .join(' / ');
    final String subtitle = song.albumTitle == null || song.albumTitle!.isEmpty
        ? artistText
        : artistText.isEmpty
        ? song.albumTitle!
        : '$artistText · ${song.albumTitle}';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: _CoverThumb(url: song.coverUrl),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        _formatDuration(song.durationMs),
        style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      onTap: () => unawaited(widget.player.playSong(_songFromPurchased(song))),
    );
  }

  // ── 我的歌单 ─────────────────────────────────────────────────────────

  Widget _buildPlaylistsSection() {
    final data = _playlists.data;
    return _sectionCard(
      key: const ValueKey<String>('account-playlists'),
      title: '我的歌单',
      subtitle: data?.page.total == null ? null : '共 ${data!.page.total} 个',
      child: _sectionBody(
        loading: _playlists.loading,
        error: _playlists.error,
        onRetry: _loadPlaylists,
        isEmpty: data == null || data.page.items.isEmpty,
        emptyText: '暂无歌单',
        content: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final playlist in data!.page.items.take(
              _kPlaylistDisplayLimit,
            ))
              _buildPlaylistTile(playlist),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistTile(MusicUserPlaylist playlist) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: _CoverThumb(url: playlist.coverUrl),
      title: Text(
        playlist.title.isEmpty ? '未命名歌单' : playlist.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${playlist.songCount ?? 0} 首'),
      trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
      onTap: () => _openPlaylist(playlist),
    );
  }

  void _openPlaylist(MusicUserPlaylist playlist) {
    final callback = widget.onOpenPlaylist;
    if (callback == null) {
      _showSnack('打开歌单功能未接线');
      return;
    }
    callback(playlist);
  }
}

// ── 私有展示组件 ─────────────────────────────────────────────────────────

/// 单值分区状态（loading/数据/错误三选一）。
class _Section<T> {
  T? data;
  Object? error;
  bool loading = true;

  void reset() {
    data = null;
    error = null;
    loading = true;
  }
}

/// 分页分区状态：首页 loading/错误 + 追加页 loadingMore/错误 + 游标/页码。
class _PagedSection<T> {
  final List<T> items = <T>[];
  Object? error;
  bool loading = true;
  bool loadingMore = false;
  Object? moreError;
  bool hasMore = false;

  /// 服务端回显的总数（wire `total`；缺省 null）。
  int? total;

  /// 听歌历史的 bp 游标（null=首页）。
  String? cursor;

  /// 已购分区的下一个请求页码（首页为 1，装载成功后自增）。
  int nextPage = 1;

  void reset() {
    items.clear();
    error = null;
    loading = true;
    loadingMore = false;
    moreError = null;
    hasMore = false;
    total = null;
    cursor = null;
    nextPage = 1;
  }
}

/// 会员/等级行前的装饰行。
class _VipRow extends StatelessWidget {
  const _VipRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 分区行内错误 + 重试。
class _SectionError extends StatelessWidget {
  const _SectionError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

/// 分区加载中。
class _LoadingRow extends StatelessWidget {
  const _LoadingRow();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

/// 分区空态。
class _EmptyRow extends StatelessWidget {
  const _EmptyRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 分页末尾提示。
class _EndRow extends StatelessWidget {
  const _EndRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 头像（56×56 圆形；无 URL/加载失败回退人形占位）。
class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Widget fallback = CircleAvatar(
      radius: 28,
      backgroundColor: cs.surfaceContainerHighest,
      child: Icon(Icons.person, size: 30, color: cs.primary),
    );
    if (url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        url,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

/// 封面缩略图（44×44，r10）；无 URL/加载失败/加载中回退音符占位。
class _CoverThumb extends StatelessWidget {
  const _CoverThumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: MimaoShapes.sm,
      ),
      child: Icon(Icons.music_note, color: cs.primary),
    );
    final coverUrl = url;
    if (coverUrl == null || coverUrl.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: MimaoShapes.sm,
      child: Image.network(
        coverUrl,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

/// 已购专辑卡片（横向列表项；封面 116×116 + 标题 + 歌手）。
class _PurchasedAlbumCard extends StatelessWidget {
  const _PurchasedAlbumCard({required this.album, required this.onTap});

  final MusicAlbumSummary album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final Widget fallback = Container(
      width: 116,
      height: 116,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: MimaoShapes.sm,
      ),
      child: Icon(Icons.album_outlined, color: cs.primary),
    );
    final cover = album.coverUrl.isEmpty
        ? fallback
        : ClipRRect(
            borderRadius: MimaoShapes.sm,
            child: Image.network(
              album.coverUrl,
              width: 116,
              height: 116,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : fallback,
            ),
          );
    return InkWell(
      borderRadius: MimaoShapes.sm,
      onTap: onTap,
      child: SizedBox(
        width: 116,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            cover,
            const SizedBox(height: 6),
            Text(
              album.title,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              album.artistText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
