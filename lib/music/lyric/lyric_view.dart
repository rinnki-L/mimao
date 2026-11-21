// ignore_for_file: deprecated_member_use — Flutter 3.50 起 material.dart 被标记废弃，
// 与仓库其它页面一致继续沿用 Material 库，待全仓迁移 material_ui 时统一处理。
/// 歌词显示组件：按播放位置高亮当前行，并随播放自动滚动到可视区中央。
///
/// 设计约束：
/// - 适配播放页暗色模糊背景，原文统一白色系；当前行用主题主色加粗；
/// - 按 [LyricMode] 决定是否在原文下方追加翻译/音译小字，缺失时不留空壳；
/// - 初始/跨行滚动使用 `Scrollable.ensureVisible(duration: Duration.zero)`
///   （等价 jumpTo），不使用无限动画，测试里 `pumpAndSettle` 不会卡死；
/// - 用户手动滚动后暂停自动复位，松手满 3 秒才带动画回到当前行，
///   避免播放推进把用户正在看的歌词抢走；复位动画带阻尼振荡，呈现
///   「果冻」回弹质感；
/// - 歌词行只在**双击**时跳转播放进度，单击是空操作，避免误触；
/// - [LyricView] 本身保持 `StatelessWidget` 契约，内部滚动状态由私有
///   StatefulWidget 承担。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mimao/music/lyric/lyric_models.dart';

/// 歌词视图。
class LyricView extends StatelessWidget {
  const LyricView({
    super.key,
    required this.lyric,
    required this.position,
    required this.mode,
    this.onLineTap,
  });

  /// null 表示没有歌词。
  final ParsedLyric? lyric;

  /// 当前播放位置，用于高亮当前行。
  final Duration position;

  /// 显示模式。
  final LyricMode mode;

  /// 双击某一行歌词时回调（用于跳转播放进度）；null 表示不可交互。
  final void Function(LyricLine line)? onLineTap;

  @override
  Widget build(BuildContext context) {
    final lines = lyric?.lines ?? const <LyricLine>[];
    if (lines.isEmpty) {
      return const Center(
        child: Text(
          '暂无歌词',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      );
    }
    return _LyricScrollBody(
      lines: lines,
      position: position,
      mode: mode,
      onLineTap: onLineTap,
    );
  }
}

/// 承载滚动控制器与当前行索引的内部组件。
class _LyricScrollBody extends StatefulWidget {
  const _LyricScrollBody({
    required this.lines,
    required this.position,
    required this.mode,
    this.onLineTap,
  });

  final List<LyricLine> lines;
  final Duration position;
  final LyricMode mode;
  final void Function(LyricLine line)? onLineTap;

  @override
  State<_LyricScrollBody> createState() => _LyricScrollBodyState();
}

class _LyricScrollBodyState extends State<_LyricScrollBody> {
  /// 用户松手后等待多久再带动画复位到当前行。
  static const Duration _resetDelay = Duration(seconds: 3);

  /// 复位动画时长；有限动画，`pumpAndSettle` 能收敛。550ms 配合果冻
  /// 曲线让「吸附回当前行」的回弹看得清。
  static const Duration _resetDuration = Duration(milliseconds: 550);

  final ScrollController _controller = ScrollController();
  late List<GlobalKey> _lineKeys;
  int _currentIndex = -1;

  /// 用户正在拖动、或刚松手仍在 [_resetDelay] 等待期内：期间忽略所有
  /// 自动滚动请求，把视图留给用户。
  bool _autoScrollSuspended = false;

  /// 松手后的复位计时器；再次拖动会取消并重新计时。
  Timer? _resetTimer;

  @override
  void initState() {
    super.initState();
    _lineKeys = _createKeys(widget.lines.length);
    _currentIndex = _indexAt(widget.position);
    _scheduleScroll();
  }

  @override
  void didUpdateWidget(covariant _LyricScrollBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lines, widget.lines)) {
      _lineKeys = _createKeys(widget.lines.length);
      _currentIndex = _indexAt(widget.position);
      _scheduleScroll();
      return;
    }
    final index = _indexAt(widget.position);
    if (index != _currentIndex) {
      _currentIndex = index;
      _scheduleScroll();
    }
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  List<GlobalKey> _createKeys(int count) =>
      List<GlobalKey>.generate(count, (_) => GlobalKey());

  /// 当前行：position 落在 `[start, end)` 内；不在任何行内返回 -1。
  int _indexAt(Duration position) {
    for (var i = 0; i < widget.lines.length; i++) {
      final line = widget.lines[i];
      if (position >= line.start && position < line.end) return i;
    }
    return -1;
  }

  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 用户滚动中/等待复位期间不抢视图；高亮仍由 build 正常更新。
      if (_autoScrollSuspended) return;
      _scrollToCurrent();
    });
  }

  /// 用户松手后复位用的「果冻」曲线；常量实例，避免每帧重建。
  static const Curve _jellyCurve = _JellyCurve();

  /// 把当前行滚到视口中央。
  ///
  /// 常规跟随用零时长（等价 jumpTo，不影响测试收敛）；用户松手满
  /// [_resetDelay] 后的复位用 [_resetDuration] 的果冻曲线。
  void _scrollToCurrent({bool animate = false}) {
    if (!mounted) return;
    final index = _currentIndex;
    if (index < 0 || index >= _lineKeys.length) return;
    final targetContext = _lineKeys[index].currentContext;
    if (targetContext == null) return;

    Curve curve = Curves.ease;
    if (animate) {
      curve = _jellyCurve;
      // 首/末行的居中目标会被滚动物理 clamp 到 min/max，过冲在边界上
      // 只会被截断、表现为边缘抽动，这时退回平滑的 easeOut。
      if (_isTargetNearScrollEdge(targetContext)) {
        curve = Curves.easeOut;
      }
    }

    Scrollable.ensureVisible(
      targetContext,
      alignment: 0.5,
      duration: animate ? _resetDuration : Duration.zero,
      curve: curve,
    );
  }

  /// 目标行居中后的偏移是否已贴在 min/max 滚动边界（2px 内）。
  bool _isTargetNearScrollEdge(BuildContext targetContext) {
    if (!_controller.hasClients) return false;
    final renderObject = targetContext.findRenderObject();
    if (renderObject == null || !renderObject.attached) return false;
    final position = _controller.position;
    final targetOffset = RenderAbstractViewport.of(
      renderObject,
    ).getOffsetToReveal(renderObject, 0.5).offset;
    const tolerance = 2.0;
    return (targetOffset - position.minScrollExtent).abs() <= tolerance ||
        (targetOffset - position.maxScrollExtent).abs() <= tolerance;
  }

  /// 用户开始拖动：立刻暂停自动复位，并取消上一次的松手计时。
  void _beginUserScroll() {
    _resetTimer?.cancel();
    _resetTimer = null;
    _autoScrollSuspended = true;
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _beginUserScroll();
    } else if (notification is ScrollEndNotification && _autoScrollSuspended) {
      // 松手后再等 [_resetDelay] 才复位；期间若再次拖动会在
      // [_beginUserScroll] 里取消并重新计时。
      _resetTimer?.cancel();
      _resetTimer = Timer(_resetDelay, () {
        _resetTimer = null;
        if (!mounted) return;
        _autoScrollSuspended = false;
        _scrollToCurrent(animate: true);
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: SingleChildScrollView(
        controller: _controller,
        // 首尾留白，让第一行/最后一行也能滚到视口中央。
        padding: const EdgeInsets.symmetric(vertical: 140, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var i = 0; i < widget.lines.length; i++)
              KeyedSubtree(
                key: _lineKeys[i],
                child: _LyricLineTile(
                  line: widget.lines[i],
                  mode: widget.mode,
                  highlighted: i == _currentIndex,
                  primary: primary,
                  onDoubleTap: widget.onLineTap == null
                      ? null
                      : () => widget.onLineTap!(widget.lines[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 单行歌词：原文 +（按模式）翻译/音译小字。
class _LyricLineTile extends StatelessWidget {
  const _LyricLineTile({
    required this.line,
    required this.mode,
    required this.highlighted,
    required this.primary,
    this.onDoubleTap,
  });

  final LyricLine line;
  final LyricMode mode;
  final bool highlighted;
  final Color primary;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final auxiliary = switch (mode) {
      LyricMode.original => null,
      LyricMode.originalWithTranslation => line.translation,
      LyricMode.originalWithTransliteration => line.transliteration,
    };
    final hasAuxiliary = auxiliary != null && auxiliary.trim().isNotEmpty;

    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: <Widget>[
          Text(
            line.original,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: highlighted ? primary : Colors.white,
              fontSize: 20,
              fontWeight: highlighted ? FontWeight.bold : FontWeight.normal,
              height: 1.3,
            ),
          ),
          if (hasAuxiliary)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                auxiliary,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.2,
                ),
              ),
            ),
        ],
      ),
    );

    final doubleTap = onDoubleTap;
    if (doubleTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 只挂 onDoubleTap：单击是空操作。若同时挂 onTap，单击会在双击
      // 判定窗口过期后被识别，误触问题依旧存在。
      onDoubleTap: doubleTap,
      child: content,
    );
  }
}

/// 复位用的「果冻」曲线：阻尼正弦给出小幅过冲与 1.5 次回摆。
///
/// `1 - e^(-6.5t)·cos(8t)` 在 t=0 处为 0、约 t=0.31 处过冲 ~10.5%，
/// 随后在 1 附近做一次轻微回摆；末尾用端点归一化，保证
/// `transform(1) == 1`，动画结束正好落在目标位置，残留偏移为 0。
/// 振幅刻意小于 `Curves.elasticOut` 的 25%，避免被滚动边界 clamp
/// 成「断头」动画。
class _JellyCurve extends Curve {
  const _JellyCurve();

  /// 阻尼系数：越大越快收敛。
  static const double _damping = 6.5;

  /// 振荡角频率：约 1.5 个周期。
  static const double _frequency = 8;

  static final double _endValue =
      1 - math.exp(-_damping) * math.cos(_frequency);

  @override
  double transformInternal(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    final raw = 1 - math.exp(-_damping * t) * math.cos(_frequency * t);
    return raw / _endValue;
  }
}
