// ignore_for_file: deprecated_member_use — 见同目录 playback_engine.dart 说明。
/// 播放页（M4-P，最小可用）：封面/歌名/歌手/进度条/播放暂停/上一首下一首/
/// 错误态与重试；队列放进底部抽屉（不单独开页）。
///
/// L4 起为 StatefulWidget：持有「当前曲目高潮区间」的页面级状态（不用
/// store 的 @observable，避免 build_runner）；`loadClimax` 为空或 hash
/// 非 32 位时不取，失败静默、无数据不标注。
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/music/api/playback_ext_api.dart';
import 'package:mimao/music/lyric/lyric_models.dart';
import 'package:mimao/music/lyric/lyric_view.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/pages/music_song_info_sheet.dart';
import 'package:mimao/music/player/pages/music_queue_sheet.dart';
import 'package:mimao/music/player/pages/music_wavy_progress.dart';
import 'package:mimao/music/player/player_store.dart';

class MusicPlayerPage extends StatefulWidget {
  const MusicPlayerPage({
    super.key,
    required this.player,
    this.loadClimax,
    this.loadLyric,
    this.playbackExt,
  });

  final MusicPlayerStore player;

  /// 歌曲高潮区间加载缝（集成者传 `discovery.songClimax`）；null 时整段隐藏。
  final Future<List<MusicSongClimaxSegment>> Function(String hash)? loadClimax;

  /// 歌词加载缝（集成者传 registry 组合的两步取词闭包）；null 时显示
  /// 「暂无歌词」且不发任何请求。
  final LoadLyric? loadLyric;

  /// 播放补全接口：非空时提供「歌曲资料」入口（权益/资料/歌手图片）。
  final MusicPlaybackExtApi? playbackExt;

  @override
  State<MusicPlayerPage> createState() => _MusicPlayerPageState();
}

class _MusicPlayerPageState extends State<MusicPlayerPage> {
  /// 已发起过高潮加载的歌曲 key（每首歌只取一次；失败也不重试）。
  String? _climaxSongKey;

  /// 当前歌曲的高潮区间；null = 加载中/无数据/失败（统一不做标注）。
  List<MusicSongClimaxSegment>? _climaxSegments;

  /// 已发起过歌词加载的歌曲 key（每首歌只取一次；失败也不重试）。
  String? _lyricSongKey;

  /// 当前歌曲的歌词；null = 加载中/无歌词/失败（UI 显示「暂无歌词」）。
  ParsedLyric? _lyric;

  /// 拖动中的本地进度（毫秒）；null = 未在拖动，进度跟随引擎快照。
  ///
  /// Slider 是受控组件：拖拽期间引擎位置不会更新，若 value 直接取
  /// snapshot.position，拇指会「钉在原地」不跟手。拖动期间用本地值回填
  /// value 让拇指/波形跟随手指，onChangeEnd 再 seekTo，松手后回到引擎位置。
  double? _dragPositionMs;

  MusicPlayerStore get player => widget.player;

  /// Observer builder 内检测换歌并按需发起高潮加载。
  ///
  /// 为什么在 build 里收口副作用：换歌信号来自 store 的 observable（本页
  /// 不新增 @observable），Observer 每次重建时按歌曲 key 比对一次是最小
  /// 接线；同步部分只改普通字段，结果回来才 setState。
  void _ensureClimax(MusicSong song) {
    final key = song.id.isNotEmpty ? song.id : song.hash;
    if (_climaxSongKey == key) return;
    _climaxSongKey = key;
    _climaxSegments = null; // 换歌丢弃旧结果
    _dragPositionMs = null; // 换歌丢弃上一首歌的拖动残留
    unawaited(_loadClimax(key, song.hash));
  }

  Future<void> _loadClimax(String requestKey, String hash) async {
    final load = widget.loadClimax;
    // 高潮端点只认 32 位 hash（song_climax.rs valid_hash 的长度约束）。
    if (load == null || hash.length != 32) return;
    try {
      final segments = await load(hash);
      // 慢请求期间换歌：按发起时的歌曲 key 比对，不一致就丢弃旧结果。
      if (!mounted || _climaxSongKey != requestKey) return;
      setState(() => _climaxSegments = segments);
    } on Object {
      // 失败静默：保持隐藏，不影响播放。
    }
  }

  /// Observer builder 内检测换歌并按需发起歌词加载（与 [_ensureClimax]
  /// 同款：每首歌只取一次，失败也不重试）。
  void _ensureLyric(MusicSong song) {
    final key = song.id.isNotEmpty ? song.id : song.hash;
    if (_lyricSongKey == key) return;
    _lyricSongKey = key;
    _lyric = null; // 换歌丢弃旧歌词
    unawaited(_loadLyric(key, song));
  }

  Future<void> _loadLyric(String requestKey, MusicSong song) async {
    final load = widget.loadLyric;
    if (load == null) return;
    try {
      final lyric = await load(song);
      // 慢请求期间换歌：按发起时的歌曲 key 比对，不一致就丢弃旧结果。
      if (!mounted || _lyricSongKey != requestKey) return;
      setState(() => _lyric = lyric);
    } on Object {
      // 失败静默：显示「暂无歌词」，不影响播放。
    }
  }

  /// 把高潮区间归一化成 0..1 的 [ClimaxSpan]（交给波浪进度条内部标注）；
  /// 无数据/时长未知/非法区间直接跳过。
  List<ClimaxSpan> _climaxSpans(int durationMs) {
    final spans = <ClimaxSpan>[];
    final segments = _climaxSegments;
    if (segments == null || durationMs <= 0) return spans;
    for (final segment in segments) {
      final startMs = segment.startMs;
      final endMs = segment.endMs;
      if (startMs == null || endMs == null || endMs < startMs) continue;
      spans.add(
        ClimaxSpan(
          start: (startMs / durationMs).clamp(0.0, 1.0),
          end: (endMs / durationMs).clamp(0.0, 1.0),
        ),
      );
    }
    return spans;
  }

  /// 背景层：封面模糊放大铺满 + 暗色遮罩；无封面/加载失败时用主题色渐变
  /// 兜底。整层 [IgnorePointer]，不干扰前景控件的点击。
  Widget _background(String coverUrl, ColorScheme colorScheme) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    colorScheme.primary.withValues(alpha: 0.35),
                    colorScheme.surface,
                  ],
                ),
              ),
            ),
            if (coverUrl.isNotEmpty)
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                child: Image.network(
                  coverUrl,
                  fit: BoxFit.cover,
                  // 无网络/加载失败时透明，露出下面的渐变兜底。
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child : const SizedBox.shrink(),
                ),
              ),
            // 暗色遮罩：压住背景亮度，保证白字/控件清晰可读。
            const ColoredBox(color: Color(0x8A000000)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('正在播放'),
        actions: <Widget>[
          // 歌曲资料（权益/资料/歌手图片）：只有注入播放补全接口时才出现；
          // 面板自己按当前曲目查询，不在这里预取。
          if (widget.playbackExt != null)
            IconButton(
              tooltip: '歌曲资料',
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                final song = player.currentSong;
                if (song == null) return;
                showMusicSongInfoSheet(
                  context,
                  song: song,
                  ext: widget.playbackExt,
                );
              },
            ),
          IconButton(
            tooltip: '播放队列',
            icon: const Icon(Icons.queue_music),
            onPressed: () => showMusicQueueSheet(context, player),
          ),
        ],
      ),
      body: Observer(
        builder: (context) {
          final song = player.currentSong;
          if (song == null) {
            return const Center(child: Text('暂无播放曲目'));
          }
          _ensureClimax(song);
          _ensureLyric(song);
          final snapshot = player.snapshot;
          final failure = player.error;
          final durationMs = snapshot.duration.inMilliseconds;
          final positionMs = durationMs <= 0
              ? 0
              : snapshot.position.inMilliseconds.clamp(0, durationMs);
          // 拖动期间用本地值回填 Slider.value，让拇指/波形跟手；松手后回到
          // 引擎快照驱动的真实位置。duration<=0 时禁用但进度条可见。
          final enabled = durationMs > 0;
          final maxMs = durationMs <= 0 ? 1.0 : durationMs.toDouble();
          final sliderValueMs = (_dragPositionMs ?? positionMs.toDouble())
              .clamp(0.0, maxMs);
          final colorScheme = Theme.of(context).colorScheme;
          final climaxSpans = _climaxSpans(durationMs);
          // 歌词开关/模式来自本地设置；未注入设置时按默认（显示、原文）。
          final settings = player.settings;
          final lyricEnabled = settings?.lyricEnabled ?? true;
          final lyricMode = settings?.lyricMode ?? LyricMode.original;

          Widget slider = SliderTheme(
            data: WavySliderTheme(
              activeColor: colorScheme.primary,
              inactiveColor: colorScheme.onSurfaceVariant.withValues(
                alpha: 0.2,
              ),
              climaxSpans: climaxSpans,
            ),
            child: Slider(
              key: const Key('player-wavy-progress'),
              value: sliderValueMs,
              max: maxMs,
              onChanged: enabled
                  ? (value) => setState(() => _dragPositionMs = value)
                  : null,
              onChangeEnd: enabled
                  ? (value) {
                      setState(() => _dragPositionMs = null);
                      player.seekTo(Duration(milliseconds: value.round()));
                    }
                  : null,
            ),
          );
          // 高潮已内化进进度条：仅在有时段时挂一个语义标签，便于无障碍与
          // 测试断言「进度条包含高潮区间」。
          if (climaxSpans.isNotEmpty) {
            slider = Semantics(label: '含高潮区间', child: slider);
          }

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _background(song.coverUrl, colorScheme),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Center(
                    child: ConstrainedBox(
                      // 放宽内容宽度：左侧唱片 + 右侧歌词在桌面宽屏下都要有
                      // 空间；手机竖屏由外层 padding 与 Expanded 自适应。
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: Column(
                        children: <Widget>[
                          // 顶部区域：唱片居左、垂直居中；右侧一列放歌名/歌手
                          // 与歌词（歌词占满剩余高度并内部滚动）。
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(
                                top: 8,
                                bottom: 16,
                              ),
                              child: Row(
                                // 封面（左）与右侧文字列垂直居中对齐。
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: <Widget>[
                                  _Cover(
                                    url: song.coverUrl,
                                    playing: snapshot.playing,
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      // 关闭歌词时列高收缩到文字高度，唱片与
                                      // 歌名/歌手仍按 Row 的 center 对齐。
                                      mainAxisSize: lyricEnabled
                                          ? MainAxisSize.max
                                          : MainAxisSize.min,
                                      children: <Widget>[
                                        Text(
                                          _displayTitle(song.title),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(color: Colors.white),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          song.artistText,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(color: Colors.white70),
                                        ),
                                        if (lyricEnabled) ...<Widget>[
                                          const SizedBox(height: 12),
                                          Expanded(
                                            child: LyricView(
                                              lyric: _lyric,
                                              position: snapshot.position,
                                              mode: lyricMode,
                                              // 点歌词跳到该行起始时间；
                                              // position 变化后高亮/滚动由
                                              // Observer 重建自动跟上。
                                              onLineTap: (line) => unawaited(
                                                player.seekTo(line.start),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // 底部一整组：错误/重试 + 传输控件 + 进度条 + 时间。
                          if (failure != null) ...<Widget>[
                            Text(
                              failure,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: Colors.red),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: player.retry,
                              icon: const Icon(Icons.refresh),
                              label: const Text('重试'),
                            ),
                            const SizedBox(height: 12),
                          ],
                          // 传输控件（上一首/播放暂停/下一首）位于进度条上方。
                          if (player.isResolving)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(),
                            )
                          else
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                IconButton.filledTonal(
                                  tooltip: '上一首',
                                  iconSize: 32,
                                  icon: const Icon(Icons.skip_previous),
                                  onPressed: player.previous,
                                ),
                                const SizedBox(width: 16),
                                IconButton.filled(
                                  tooltip: snapshot.playing ? '暂停' : '播放',
                                  iconSize: 40,
                                  icon: Icon(
                                    snapshot.playing
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                  ),
                                  onPressed: player.toggle,
                                ),
                                const SizedBox(width: 16),
                                IconButton.filledTonal(
                                  tooltip: '下一首',
                                  iconSize: 32,
                                  icon: const Icon(Icons.skip_next),
                                  onPressed: player.next,
                                ),
                              ],
                            ),
                          const SizedBox(height: 16),
                          // 波浪进度条：保留 Slider 语义/点击 seek/无障碍，拖动跟手；
                          // 高潮区间通过 theme 的 climaxSpans 直接画在轨道上。
                          // 外包 SliderTheme 只影响本条，不改全局主题。
                          slider,
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                _formatDuration(snapshot.position),
                                style: const TextStyle(color: Colors.white70),
                              ),
                              Text(
                                _formatDuration(snapshot.duration),
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 圆形「黑胶唱片」封面：播放时旋转（12 秒一圈），暂停时静止。
///
/// 盘面叠了一道非对称反光（两道相对扇形高光 + 边缘标记点），否则同心对称
/// 的封面图案转起来和静止几乎没有区别。旋转用 [AnimationController.repeat]
/// 无限动画，而 widget 测试里的 `pumpAndSettle` 永远等不到收敛。因此在测试
/// 绑定下完全不启动动画（只显示静止封面）；真机按 [playing] 起停。dispose
/// 必须释放控制器。
class _Cover extends StatefulWidget {
  const _Cover({required this.url, required this.playing});

  /// 唱片在 Row 中占的布局边长（逻辑像素）。
  ///
  /// 盘面实际绘制比它大（[size]），但布局占位保持此值，保证 Row 里的
  /// 中心点不因放大而右移。
  static const double layoutSize = 200;

  /// 唱片实际绘制直径（逻辑像素）；以中心为锚溢出布局占位。
  static const double size = 260;

  final String url;
  final bool playing;

  @override
  State<_Cover> createState() => _CoverState();
}

class _CoverState extends State<_Cover> with SingleTickerProviderStateMixin {
  /// 测试绑定下禁用无限旋转（否则 pumpAndSettle 会超时）。
  static final bool _isWidgetTest = WidgetsBinding.instance.runtimeType
      .toString()
      .contains('TestWidgetsFlutterBinding');

  /// 12 秒一圈：比之前 5 秒更慢更接近真实黑胶的从容感，同时仍能一眼
  /// 看出在转。
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );

  @override
  void initState() {
    super.initState();
    _syncSpin();
  }

  @override
  void didUpdateWidget(covariant _Cover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playing != widget.playing) _syncSpin();
  }

  void _syncSpin() {
    if (widget.playing && !_isWidgetTest) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const size = _Cover.size;

    final Widget fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.music_note, size: size * 0.4, color: cs.primary),
    );
    // widget 测试无网络：errorBuilder/loadingBuilder 缺一个都会抛异常。
    final Widget artwork = widget.url.isEmpty
        ? fallback
        : Image.network(
            widget.url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => fallback,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : SizedBox(
                    width: size,
                    height: size,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
          );

    final Widget disc = RotationTransition(
      turns: _spin,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
            width: 2,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              artwork,
              // 非对称反光：两道相对的扇形高光 + 边缘标记点，全部放在
              // RotationTransition 内部随盘面一起转。封面本身可能是同心对称
              // 图案（转起来和静止一样），这层反光是「看得出在转」的关键。
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: SweepGradient(
                      colors: <Color>[
                        Color(0x00FFFFFF),
                        Color(0x2EFFFFFF),
                        Color(0x00FFFFFF),
                        Color(0x00FFFFFF),
                        Color(0x1FFFFFFF),
                        Color(0x00FFFFFF),
                      ],
                      stops: <double>[0.0, 0.07, 0.16, 0.5, 0.57, 0.66],
                    ),
                  ),
                ),
              ),
              Align(
                alignment: const Alignment(0, -0.82),
                child: IgnorePointer(
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
              // 用户要求去掉中间凹进/打孔的唱片轴孔，只保留圆形封面本身
              // 与非对称反光（反光随盘面旋转，让旋转可见）。
            ],
          ),
        ),
      ),
    );

    // 布局占位固定为 [layoutSize]（Row 里的中心点不因放大而右移），盘面
    // 按 [size] 以中心为锚向四周溢出绘制。
    return SizedBox(
      width: _Cover.layoutSize,
      height: _Cover.layoutSize,
      child: OverflowBox(
        minWidth: size,
        maxWidth: size,
        minHeight: size,
        maxHeight: size,
        child: disc,
      ),
    );
  }
}

/// 展示层剥掉复杂搜索的 `<em>` 高亮标签。
String _displayTitle(String raw) =>
    raw.replaceAll('<em>', '').replaceAll('</em>', '');

String _formatDuration(Duration duration) {
  final seconds = duration.inSeconds;
  if (seconds <= 0) return '0:00';
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
