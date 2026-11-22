// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 comic 页面同款说明。
/// 音乐模块主页（M4）：左侧栏 + 分区内容 + 迷你播放条。
///
/// 侧栏骨架与漫画模块同款（2026-11-22 对齐，原为底部 NavigationBar）：
/// 导航项 + 底部「设置」项弹底部面板，迷你播放条驻内容列底部，
/// 切分区时播放控制不消失。
///
/// 契约提交后本页只认接口（[MusicPlayerUi]/[MusicCollectApi]/
/// [MusicSearchHistoryApi]），不 import `player/` 实现，也不认识 C 线的
/// 服务类——三条线可各自独立编译。
library;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/library_api.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/user_library_models.dart'
    show MusicUserPlaylist;
import 'package:mimao/music/music_store.dart';
import 'package:mimao/music/player/player_ui.dart';
import 'package:mimao/music/widgets/music_song_card.dart';

/// 搜索框 + 结果列表。embedded=true 时由壳提供顶部「返回 + 标题」。
class MusicModulePage extends StatefulWidget {
  const MusicModulePage({
    super.key,
    required this.store,
    this.embedded = false,
    this.playerUi,
    this.collect,
    this.searchHistory,
    this.favoritesTab,
    this.historyTab,
    this.accountCard,
    this.accountTab,
    this.playlists,
    this.selectedPlaylist,
    this.playlistViewBuilder,
    this.browseTab,
    this.settingsTab,
  });

  final MusicStore store;

  /// true 时由壳提供顶部栏，本页不画 AppBar。
  final bool embedded;

  /// P 线播放 UI；null 时点歌显示占位提示、不渲染迷你播放条。
  final MusicPlayerUi? playerUi;

  /// C 线收藏服务；null 时不显示收藏按钮。
  final MusicCollectApi? collect;

  /// C 线搜索历史；null 时搜索不做记录。
  final MusicSearchHistoryApi? searchHistory;

  /// C 线「我喜欢」页（锁定收藏段的库页）；null 时侧栏不出「我喜欢」入口。
  final Widget? favoritesTab;

  /// C 线「播放历史」页（锁定历史段的库页）；null 时侧栏不出「播放历史」
  /// 入口（2026-11-22 侧栏信息架构升级：原「我的」tab 的两段拆成两个入口）。
  final Widget? historyTab;

  /// 侧栏顶部账号小卡片（展示层，出口装配）；null 时不画卡片，
  /// 也不出「账号」分区入口（[accountTab] 随之不可达）。
  final Widget? accountCard;

  /// 账号中心页（用户资料/等级/会员/历史/已购）；点侧栏账号卡片时
  /// 在内容区展示。null 时卡片无目标。
  final Widget? accountTab;

  /// 侧栏下半部的歌单区（出口装配：云歌单列表 + 「全部」入口）；
  /// null 或窄侧栏时不渲染。
  final Widget? playlists;

  /// 侧栏歌单行的选中桥（出口装配的 ValueNotifier）：侧栏点行写入行
  /// 事实，本页监听后把内容区切到对应内嵌视图；导航行/卡片选中时由本页
  /// 清空（回常规分区）。null 时歌单行保持 push 详情页的旧行为。
  final ValueNotifier<MusicUserPlaylist?>? selectedPlaylist;

  /// 内嵌歌单视图构造器（出口装配，接读端点等出口私有缝）；与
  /// [selectedPlaylist] 配套。null 时选中桥不生效。
  final Widget Function(MusicUserPlaylist playlist)? playlistViewBuilder;

  /// 发现页（搜索扩展 + 推荐）；非空时作为首 tab 并取代独立的搜索 tab
  /// （发现页自身带歌曲搜索）。null 时保持旧的「搜索」首 tab。
  final Widget? browseTab;

  /// 设置面板的内容；由模块出口 buildSettings 注入，收在侧栏底部项
  /// （点击弹底部面板，不再占一个分区）。null 时侧栏不出设置区。
  final Widget? settingsTab;

  @override
  State<MusicModulePage> createState() => _MusicModulePageState();
}

class _MusicModulePageState extends State<MusicModulePage> {
  late final TextEditingController _controller = TextEditingController();

  int _index = 0;

  /// 收藏态缓存（列表批量判断，避免逐行异步查询导致抖动）。
  final Set<String> _collectedIds = <String>{};

  /// 已打开的内嵌歌单视图（按打开顺序缓存）：IndexedStack 保活，切走再
  /// 切回不重拉；键取行 id（listid，收藏行各自唯一）。
  final Map<String, Widget> _playlistViews = <String, Widget>{};

  MusicUserPlaylist? get _focusedPlaylist => widget.selectedPlaylist?.value;

  String _viewKey(MusicUserPlaylist playlist) =>
      'listid:${playlist.cloudListId ?? playlist.globalId}';

  void _onPlaylistFocusChanged() {
    if (!mounted) return;
    final focus = _focusedPlaylist;
    final builder = widget.playlistViewBuilder;
    if (focus != null && builder != null) {
      _playlistViews.putIfAbsent(_viewKey(focus), () => builder(focus));
    }
    setState(() {});
  }

  /// 选中常规分区（导航行/账号卡片）：清掉歌单聚焦，回常规分区内容。
  void _select(int index) {
    if (widget.selectedPlaylist?.value != null) {
      widget.selectedPlaylist!.value = null;
    }
    setState(() => _index = index);
  }

  @override
  void initState() {
    super.initState();
    widget.selectedPlaylist?.addListener(_onPlaylistFocusChanged);
    _loadCollected();
  }

  @override
  void didUpdateWidget(covariant MusicModulePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedPlaylist != oldWidget.selectedPlaylist) {
      oldWidget.selectedPlaylist?.removeListener(_onPlaylistFocusChanged);
      widget.selectedPlaylist?.addListener(_onPlaylistFocusChanged);
    }
  }

  Future<void> _loadCollected() async {
    final collect = widget.collect;
    if (collect == null) return;
    try {
      final ids = await collect.collectedIds();
      if (!mounted) return;
      setState(() {
        _collectedIds
          ..clear()
          ..addAll(ids);
      });
    } on Object {
      // 收藏态加载失败不挡搜索；图标维持未收藏。
    }
  }

  @override
  void dispose() {
    widget.selectedPlaylist?.removeListener(_onPlaylistFocusChanged);
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final keyword = _controller.text.trim();
    if (keyword.isEmpty) return;
    widget.store.search(keyword);
    final searchHistory = widget.searchHistory;
    if (searchHistory != null) {
      searchHistory.record(keyword).catchError((Object _) {});
    }
  }

  Future<void> _toggleCollect(MusicSong song) async {
    final collect = widget.collect;
    if (collect == null) return;
    final id = _songId(song);
    if (id.isEmpty) return;
    final wasCollected = _collectedIds.contains(id);
    setState(() {
      if (wasCollected) {
        _collectedIds.remove(id);
      } else {
        _collectedIds.add(id);
      }
    });
    try {
      if (wasCollected) {
        await collect.remove(id);
      } else {
        await collect.collect(song);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        if (wasCollected) {
          _collectedIds.add(id);
        } else {
          _collectedIds.remove(id);
        }
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(wasCollected ? '取消收藏失败：$error' : '收藏失败：$error')),
      );
    }
  }

  String _songId(MusicSong song) => song.id.isNotEmpty ? song.id : song.hash;

  void _openSong(MusicSong song) {
    final player = widget.playerUi;
    if (player == null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('播放功能随播放器切片接入')));
      return;
    }
    // ── M4-P 播放 ──
    // 先起播（地址异步解析）再打开播放页：页面立刻呈现 loading/错误态，
    // 失败也有「重试」入口，不必回列表再点一次。
    player.playSong(song);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'music/player'),
        builder: (context) => player.buildPlayerPage(context),
      ),
    );
  }

  /// 双击：当前搜索结果整列表替换播放队列，并从 [startIndex] 起播。
  void _openSongList(List<MusicSong> songs, int startIndex) {
    final player = widget.playerUi;
    if (player == null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('播放功能随播放器切片接入')));
      return;
    }
    player.playList(songs, startIndex: startIndex);
  }

  @override
  Widget build(BuildContext context) {
    final searchBody = Column(
      // stretch 与番剧/漫画搜索页同构；SearchBar 默认 maxWidth 800 会被
      // 卡在居中位置，桌面宽窗下不补 stretch 会左右留白。
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          // 与番剧/漫画搜索页同款 MD3 SearchBar（形态走 searchBarTheme），
          // 音乐此前是 MD2 风格直角 TextField，这里统一三模块观感。
          child: SearchBar(
            controller: _controller,
            hintText: '搜索歌曲 / 歌手 / 专辑',
            leading: const Icon(Icons.search),
            trailing: <Widget>[
              IconButton(
                icon: const Icon(Icons.arrow_forward_rounded),
                tooltip: '搜索',
                onPressed: _submit,
              ),
            ],
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submit(),
          ),
        ),
        Expanded(child: Observer(builder: (_) => _buildBody(context))),
      ],
    );

    final favoritesTab = widget.favoritesTab;
    final historyTab = widget.historyTab;
    final accountTab = widget.accountTab;
    final browseTab = widget.browseTab;
    final settingsTab = widget.settingsTab;

    // 侧栏入口列表：发现页（注入时）或旧搜索页恒在首项；「我喜欢」「播放
    // 历史」按注入与否出现；「账号」由顶部卡片进入（2026-11-22 侧栏信息
    // 架构升级：原「我的」tab 拆成两个入口，原「账号」导航行换成卡片）。
    // 设置收在侧栏底部项，点击弹底部面板。
    final destinations = <_MusicSidebarDestination>[];
    final tabs = <Widget>[];
    if (browseTab != null) {
      tabs.add(browseTab);
      destinations.add((
        key: 'music-sidebar-discover',
        icon: Icons.explore_outlined,
        selectedIcon: Icons.explore,
        label: '发现',
      ));
    } else {
      tabs.add(searchBody);
      destinations.add((
        key: 'music-sidebar-search',
        icon: Icons.search_outlined,
        selectedIcon: Icons.search,
        label: '搜索',
      ));
    }
    if (favoritesTab != null) {
      tabs.add(favoritesTab);
      destinations.add((
        key: 'music-sidebar-favorites',
        icon: Icons.favorite_outline,
        selectedIcon: Icons.favorite,
        label: '我喜欢',
      ));
    }
    if (historyTab != null) {
      tabs.add(historyTab);
      destinations.add((
        key: 'music-sidebar-history',
        icon: Icons.history_outlined,
        selectedIcon: Icons.history,
        label: '播放历史',
      ));
    }
    if (accountTab != null) {
      tabs.add(accountTab);
    }
    // 账号分区的目标索引（侧栏顶部卡片进入，不在导航行里）。
    final accountIndex = accountTab == null ? null : tabs.length - 1;
    // 索引防御：favoritesTab/historyTab/accountTab 在两次 build 之间变化时
    // 夹紧，避免越界。
    if (_index >= tabs.length) _index = tabs.length - 1;
    // 内嵌歌单视图（按打开顺序）排在常规分区之后：聚焦侧栏歌单行时内容
    // 区切到对应视图，清焦（点导航行/卡片）回常规分区。IndexedStack 整体
    // 保活——切走再切回不重拉（2026-11-22 侧栏主从化，原为 push 详情页）。
    final focus = _focusedPlaylist;
    final viewKeys = _playlistViews.keys.toList(growable: false);
    final int contentIndex;
    if (focus != null && viewKeys.contains(_viewKey(focus))) {
      contentIndex = tabs.length + viewKeys.indexOf(_viewKey(focus));
    } else {
      contentIndex = _index;
    }
    final content = IndexedStack(
      index: contentIndex,
      children: <Widget>[...tabs, ..._playlistViews.values],
    );
    // 迷你播放条住各页共用区（内容列底部）：切「我的」/「账号」时播放控制
    // 不消失（集成收口修正）。
    // Observer 包住调用：buildMiniPlayer 返回 null 时不渲染，队列变化
    // （点歌入队）由 MobX 驱动重建，不需要页面自己 setState。
    final contentColumn = Column(
      children: <Widget>[
        Expanded(child: content),
        if (widget.playerUi != null)
          Observer(
            builder: (context) =>
                widget.playerUi!.buildMiniPlayer(context) ??
                const SizedBox.shrink(),
          ),
      ],
    );

    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: const Text('音乐')),
      body: Row(
        children: <Widget>[
          _MusicSidebar(
            currentIndex: _index,
            onSelect: _select,
            destinations: destinations,
            accountCard: widget.accountCard,
            accountIndex: accountIndex,
            playlistFocused: focus != null,
            playlists: widget.playlists,
            settingsTab: settingsTab,
            onOpenSettings: _openSettings,
          ),
          Expanded(child: contentColumn),
        ],
      ),
    );
  }

  /// 模块设置面板（底部弹出，与漫画模块同款）：设置内容不再占侧栏分区。
  Future<void> _openSettings() async {
    final settingsTab = widget.settingsTab;
    if (settingsTab == null) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: settingsTab,
        ),
      ),
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
        return MusicSongCard(
          horizontalMargin: 16,
          child: _SongTile(
            song: song,
            isCollected: _collectedIds.contains(_songId(song)),
            onToggleCollect: widget.collect == null
                ? null
                : () => _toggleCollect(song),
            onTap: () => _openSong(song),
            onDoubleTap: () =>
                _openSongList(List<MusicSong>.of(store.results), index),
          ),
        );
      },
    );
  }
}

/// 侧边栏导航项：图标沿用原底部 NavigationBar（selected 用 filled 版本）。
typedef _MusicSidebarDestination = ({
  String key,
  IconData icon,
  IconData selectedIcon,
  String label,
});

/// 模块层左侧边栏（2026-11-22 对齐漫画模块的自绘侧栏，替代原底部
/// NavigationBar；同日信息架构升级：顶部账号卡片 + 导航行 + 歌单区）。
///
/// 结构自上而下：
/// - 账号小卡片（[accountCard]，点按进 [accountIndex] 分区，选中时垫
///   secondaryContainer；null 不渲染）；
/// - 导航行（图标 + 文字横排，选中态为 M3 rail 式选中指示垫：药丸底色
///   只垫在图标后面，文字不笼罩——与漫画/小说模块同款观感）；
/// - 歌单区（[playlists]，占剩余高度自带滚动；null 或窄侧栏不渲染）；
/// - 底部「设置」项（[settingsTab] 为 null 时整块不渲染，含分隔线），
///   点击由 [onOpenSettings] 弹底部面板。
///
/// 窗口宽 ≥ 720 用 240 宽（图标 + 文字）；否则收成 84 宽只留图标，
/// 用 Tooltip 提示名称。右缘 1px outlineVariant 与内容区分隔。
class _MusicSidebar extends StatelessWidget {
  const _MusicSidebar({
    required this.currentIndex,
    required this.onSelect,
    required this.destinations,
    required this.accountIndex,
    required this.playlistFocused,
    required this.settingsTab,
    required this.onOpenSettings,
    this.accountCard,
    this.playlists,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  /// 导航行入口（与 [MusicModulePage] 的 tabs 前段一一对应）。
  final List<_MusicSidebarDestination> destinations;

  /// 侧栏歌单行正被聚焦（内容区展示内嵌歌单视图）：此时导航行与账号卡片
  /// 不再显示选中态，选中指示让给歌单行。
  final bool playlistFocused;

  /// 账号小卡片展示内容；null 不渲染。
  final Widget? accountCard;

  /// 账号分区目标索引；null 时卡片无目标（不可点）。
  final int? accountIndex;

  /// 歌单区内容；null 或窄侧栏不渲染。
  final Widget? playlists;

  /// 模块设置面板内容；null 表示没有设置项，底部设置区（含分隔线）不渲染。
  final Widget? settingsTab;

  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 窗口宽 ≥ 720 走宽形态（图标 + 文字）；否则收窄只留图标。
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final card = accountCard;

    return Container(
      key: const Key('music-sidebar'),
      width: wide ? 240.0 : 84.0,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(right: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        children: <Widget>[
          // 顶部不画模块名：壳层顶栏（embedded）已提供「返回 + 标题」，
          // 侧边栏再画一遍会重复，只留呼吸空隙。
          const SizedBox(height: 12),
          if (card != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _accountCard(
                context,
                child: card,
                selected:
                    !playlistFocused &&
                    accountIndex != null &&
                    currentIndex == accountIndex,
                wide: wide,
              ),
            ),
          for (final (index, destination) in destinations.indexed)
            _destinationRow(
              context: context,
              itemKey: destination.key,
              icon: destination.icon,
              selectedIcon: destination.selectedIcon,
              label: destination.label,
              selected: !playlistFocused && index == currentIndex,
              wide: wide,
              onTap: () => onSelect(index),
            ),
          if (playlists != null && wide)
            Expanded(child: playlists!)
          else
            const Spacer(),
          if (settingsTab != null) ...<Widget>[
            Divider(color: cs.outlineVariant, height: 1),
            // 设置项永不处于选中态；样式与导航项一致。
            _destinationRow(
              context: context,
              itemKey: 'music-sidebar-settings',
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_outlined,
              label: '设置',
              selected: false,
              wide: wide,
              onTap: onOpenSettings,
            ),
          ],
        ],
      ),
    );
  }

  /// 账号卡片外框：圆角卡片（形态走卡片语言：surfaceContainerLow，
  /// 选中垫 secondaryContainer），点按进入账号分区。
  Widget _accountCard(
    BuildContext context, {
    required Widget child,
    required bool selected,
    required bool wide,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.secondaryContainer : cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: MimaoShapes.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: MimaoShapes.md,
        onTap: () {
          final index = accountIndex;
          if (index != null) onSelect(index);
        },
        child: SizedBox(
          height: wide ? 56 : 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  /// 一条导航行：Material 提供水波纹底（透明底才有 ink 效果），圆角药丸
  /// 由 shape + clipBehavior 收住水波纹；行底色与侧边栏同色，选中态的
  /// 高亮只落在图标后面的指示垫上（56×32 药丸，对齐 M3 NavigationRail
  /// 的默认指示垫参数），hover/focus 时药丸形状的 ink 反馈照常出现。
  Widget _destinationRow({
    required BuildContext context,
    required String itemKey,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required bool selected,
    required bool wide,
    required VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    final iconWidget = Icon(
      selected ? selectedIcon : icon,
      size: 24,
      color: fg,
    );
    Widget iconPart = iconWidget;
    if (!wide) iconPart = Tooltip(message: label, child: iconPart);
    return Padding(
      key: Key(itemKey),
      // 悬停/选中的高亮药丸区域保持从 12 起（贴住分隔线的观感不变）；
      // 宽窗下内容在药丸内部再缩进 8（见 Row 前 SizedBox），图标垫落到 20。
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: MimaoShapes.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: MimaoShapes.pill,
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: wide
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: <Widget>[
                // 宽窗：内容相对高亮药丸整体右缩进 8——图标垫落到 x=20
                // （与歌单区封面列对齐），高亮区左缘不动。
                if (wide) const SizedBox(width: 8),
                // M3 rail 式选中指示垫：药丸底色只垫图标，文字留在外面。
                AnimatedContainer(
                  width: 56,
                  height: 32,
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: selected ? cs.secondaryContainer : null,
                    borderRadius: MimaoShapes.pill,
                  ),
                  alignment: Alignment.center,
                  child: iconPart,
                ),
                if (wide) ...<Widget>[
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: textTheme.labelLarge?.copyWith(
                      color: fg,
                      fontWeight: selected
                          ? MimaoFonts.bold
                          : MimaoFonts.regular,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 结果行。封面占位图标——真实封面留待播放页。
class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.song,
    required this.isCollected,
    required this.onTap,
    this.onDoubleTap,
    this.onToggleCollect,
  });

  final MusicSong song;
  final bool isCollected;
  final VoidCallback onTap;

  /// 双击 → 当前搜索结果整列表替换播放队列；与 [onTap] 同一个 InkWell。
  final VoidCallback? onDoubleTap;

  /// null 表示收藏功能未接线（不显示按钮）。
  final VoidCallback? onToggleCollect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: ListTile(
        leading: _SongCover(url: song.coverUrl),
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
        // 收藏按钮用 filledTonal 的选中态：未收藏描边心形，已收藏
        // tonal 实底红心——MD3 的 IconButton 选中形态，一眼可辨。
        trailing: onToggleCollect != null
            ? IconButton.filledTonal(
                tooltip: isCollected ? '取消收藏' : '收藏',
                isSelected: isCollected,
                selectedIcon: const Icon(Icons.favorite),
                icon: const Icon(Icons.favorite_border),
                onPressed: onToggleCollect,
              )
            : Text(
                _formatDuration(song.durationMs),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}

/// 歌曲封面缩略图（44×44，r10）；无 URL / 加载失败回退音符占位。
class _SongCover extends StatelessWidget {
  const _SongCover({required this.url});

  final String url;

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
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: MimaoShapes.sm,
      child: Image.network(
        url,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        // 加载中维持占位（与迷你条/播放页的 loading 模式对齐，不闪空块）。
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
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
