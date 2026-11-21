// ignore_for_file: deprecated_member_use — 见同目录 playback_engine.dart 说明。
/// Material 3 Expressive「波浪」播放进度条（M4-P）。
///
/// 把进度条拆成两层可复用能力：
///
/// * [_WavyProgressPainter]：纯 [CustomPainter]，只按 progress 画一条波形轨道，
///   不持有任何控制器、不注册帧回调。迷你条用它做「只画不管手势」的细条。
/// * [WavySliderTrackShape]：把同一套波形画法接到 [Slider] 的 track 上，保留
///   Slider 的点击 seek / 拖拽 / 语义 / `find.byType(Slider)` 测试能力。
/// * [_WavyThumbShape]：播放页拖动时跟随手指的小圆点。
///
/// 关键约束：**绝对不创建无限循环的 AnimationController**。波形相位由当前
/// progress 直接推导（`progress * 6π`），播放推进 → progress 变化 → painter
/// 重建 → 波形自然流动；拖动/静止时没有动画在跑，`pumpAndSettle` 能收敛。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 高潮区间在进度条轨道上的位置，start/end 都是 0..1 的归一化值。
@immutable
class ClimaxSpan {
  const ClimaxSpan({required this.start, required this.end});

  final double start;
  final double end;
}

/// 未播放波形的振幅（逻辑像素，峰-峰值约 5px）。
const double kWavyAmplitude = 2.5;

/// 波形波长（一个完整正弦周期的水平长度，逻辑像素）。
const double kWavyWavelength = 18;

/// 波形描边宽度；端帽用 round，形成连贯的圆头波浪。
const double kWavyStrokeWidth = 5;

/// 轨道（未播放段）高度。
const double kWavyTrackHeight = 4;

/// 相位系数：progress 从 0→1 时相位推进 6π（3 个完整波）。
const double kWavyPhaseTurns = 6 * math.pi;

/// 画一条波浪进度所需的全部视觉参数；迷你条与 Slider track 共用。
@immutable
class WavyProgressStyle {
  const WavyProgressStyle({
    required this.activeColor,
    required this.inactiveColor,
    this.amplitude = kWavyAmplitude,
    this.wavelength = kWavyWavelength,
    this.strokeWidth = kWavyStrokeWidth,
    this.trackHeight = kWavyTrackHeight,
  });

  final Color activeColor;

  /// 未播放轨道颜色，调用方通常传入带低透明度（如 20%）的 onSurfaceVariant。
  final Color inactiveColor;
  final double amplitude;
  final double wavelength;
  final double strokeWidth;
  final double trackHeight;

  /// 由当前主题的 [ColorScheme] 生成 MD3 配色：active=primary，
  /// inactive=onSurfaceVariant @20%。
  factory WavyProgressStyle.fromColorScheme(ColorScheme cs) =>
      WavyProgressStyle(
        activeColor: cs.primary,
        inactiveColor: cs.onSurfaceVariant.withValues(alpha: 0.2),
      );
}

/// 纯绘制：[progress] 为 0..1，只画波形，不接管任何手势。
///
/// 用于迷你条的细条形态。被放进 [IgnorePointer] 后整卡点击仍可穿透到
/// 外层 [InkWell]（CustomPaint 默认 hitTestBehavior 为 deferToChild，自身
/// 不产生命中）。
class MiniWavyProgress extends StatelessWidget {
  const MiniWavyProgress({
    super.key,
    required this.progress,
    this.style,
    this.height = 12,
  });

  /// 0..1，外部按 position/duration 自行 clamp。
  final double progress;
  final WavyProgressStyle? style;
  final double height;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle =
        style ??
        WavyProgressStyle.fromColorScheme(Theme.of(context).colorScheme);
    return IgnorePointer(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: WavyProgressPainter(
            progress: progress,
            style: effectiveStyle,
          ),
        ),
      ),
    );
  }
}

/// 波形绘制核心：未播放段是低透明度正弦波，已播放段是 active 色直线。
///
/// [progress] 是直线与波浪的分界点：直线画到 left + progress * width，
/// 波浪从该点延伸到右端；相位 = progress * 6π，播放推进时波浪被向左「拉直」。
class WavyProgressPainter extends CustomPainter {
  WavyProgressPainter({required this.progress, required this.style});

  final double progress;
  final WavyProgressStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final p = progress.clamp(0.0, 1.0);
    final midY = size.height / 2;
    final endX = p * size.width;
    final stroke = style.strokeWidth;

    // 水平方向向右多留半个描边，让右端圆帽完整可见；纵向仍按画布高度。
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width + stroke / 2, size.height));

    // 已播放段：active 色直线（progress=0 时不画，整条都是波浪）。
    if (p > 0) {
      final activePaint = Paint()
        ..color = style.activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      canvas.drawLine(Offset(0, midY), Offset(endX, midY), activePaint);
    }

    // 未播放段：inactive 色低透明度正弦波（progress=1 时不画，整条都是直线）。
    if (p < 1) {
      final wavePaint = Paint()
        ..color = style.inactiveColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;
      final path = _buildWavePath(
        startX: endX,
        endX: size.width,
        midY: midY,
        amplitude: style.amplitude,
        wavelength: style.wavelength,
        phase: p * kWavyPhaseTurns,
      );
      canvas.drawPath(path, wavePaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant WavyProgressPainter old) =>
      old.progress != progress || old.style != style;
}

/// 把波形接到 [Slider] 上的 track shape。
///
/// 继承 [SliderTrackShape] 并混入 [BaseSliderTrackShape] 复用 Flutter 默认的
/// track 布局计算（左右按 thumb/overlay 宽度收口）。绘制时复用
/// [_drawWaveOnTrack] 的同一套算法，因此与迷你条视觉一致。
class WavySliderTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const WavySliderTrackShape({this.climaxSpans = const []});

  /// 需要标在轨道上的高潮区间（默认空，不影响迷你条等现有调用方）。
  final List<ClimaxSpan> climaxSpans;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 0;
    if (trackHeight <= 0) return;

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (trackRect.isEmpty) return;

    final activeColor = ColorTween(
      begin: sliderTheme.disabledActiveTrackColor,
      end: sliderTheme.activeTrackColor,
    ).evaluate(enableAnimation);
    final inactiveColor = ColorTween(
      begin: sliderTheme.disabledInactiveTrackColor,
      end: sliderTheme.inactiveTrackColor,
    ).evaluate(enableAnimation);
    if (activeColor == null || inactiveColor == null) return;

    // 把 thumbCenter 换算成 0..1 的 progress（LTR 左→右，RTL 右→左）。
    final double visual = (thumbCenter.dx - trackRect.left) / trackRect.width;
    final progress = textDirection == TextDirection.rtl ? 1 - visual : visual;

    _drawWaveOnTrack(
      context.canvas,
      trackRect,
      progress.clamp(0.0, 1.0),
      activeColor,
      inactiveColor,
      climaxSpans: climaxSpans,
    );
  }
}

/// 覆盖默认的 [RoundedRectSliderTrackShape] + [RoundSliderThumbShape]：
/// 轨道画正弦波，thumb 画一个 primary 小圆点，拖动时跟随手指。
///
/// 拖拽跟手的关键：Slider 本体是 controlled widget——拖动的每一帧都要由
/// 外部把 [onChanged] 的新值回填到 [value]，拇指才会跟着手指移动。播放页用
/// 本地 State 暂存拖拽值实现这一点（见 music_player_page.dart）。
class WavySliderTheme extends SliderThemeData {
  WavySliderTheme({
    required Color activeColor,
    required Color inactiveColor,
    Color? thumbColor,
    this.climaxSpans = const [],
  }) : super(
         trackHeight: kWavyTrackHeight,
         activeTrackColor: activeColor,
         inactiveTrackColor: inactiveColor,
         disabledActiveTrackColor: activeColor.withValues(alpha: 0.4),
         disabledInactiveTrackColor: inactiveColor,
         thumbColor: thumbColor ?? activeColor,
         disabledThumbColor: (thumbColor ?? activeColor).withValues(alpha: 0.4),
         trackShape: WavySliderTrackShape(climaxSpans: climaxSpans),
         thumbShape: const _WavyThumbShape(),
         overlayShape: SliderComponentShape.noOverlay,
         valueIndicatorShape: SliderComponentShape.noOverlay,
         showValueIndicator: ShowValueIndicator.never,
         // 让轨道从 Slider 盒子左缘一直延伸到右缘，不留默认 padding。
         padding: EdgeInsets.zero,
       );

  /// 透传给 [WavySliderTrackShape] 的高潮区间（默认空列表）。
  final List<ClimaxSpan> climaxSpans;
}

class _WavyThumbShape extends SliderComponentShape {
  const _WavyThumbShape();

  static const double _radius = 7;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(_radius * 2, _radius * 2);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final color = ColorTween(
      begin: sliderTheme.disabledThumbColor,
      end: sliderTheme.thumbColor,
    ).evaluate(enableAnimation);
    if (color == null) return;
    // 拖动时轻微放大，给出「跟手/按压」反馈；无隐式动画，帧数可收敛。
    final radius = _radius + activationAnimation.value * 2;
    context.canvas.drawCircle(center, radius, Paint()..color = color);
  }
}

/// 在给定轨道矩形内画进度：与 [WavyProgressPainter.paint] 同款算法，
/// 区别只是坐标由 trackRect 提供（Slider 场景）。
///
/// 已播放段是 active 色直线，未播放段是 inactive 色低透明度波浪；高潮区间
/// 只在 start/end 两端各画一个暖橙色圆点，且画在最上层。
void _drawWaveOnTrack(
  Canvas canvas,
  Rect trackRect,
  double progress,
  Color activeColor,
  Color inactiveColor, {
  double amplitude = kWavyAmplitude,
  double wavelength = kWavyWavelength,
  double strokeWidth = kWavyStrokeWidth,
  List<ClimaxSpan> climaxSpans = const [],
}) {
  final midY = trackRect.center.dy;
  final endX = trackRect.left + progress * trackRect.width;

  // 关键：不能用 trackRect 本身裁剪——它只有 kWavyTrackHeight(4) 高，
  // 会把振幅 2.5 + 半描边 2.5 的波峰纵向切掉，只剩一条抖动细线。
  // 向外撑开 amplitude+strokeWidth，给波峰和两端圆帽留足空间。
  canvas.save();
  canvas.clipRect(trackRect.inflate(amplitude + strokeWidth));

  // 已播放段：active 色直线（progress=0 时不画，整条都是波浪）。
  if (progress > 0) {
    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawLine(
      Offset(trackRect.left, midY),
      Offset(endX, midY),
      activePaint,
    );
  }

  // 未播放段：inactive 色低透明度波浪（progress=1 时不画，整条都是直线）。
  // 相位随 progress 推进，波浪像被从右往左「吃掉」，逐步拉直成直线。
  if (progress < 1) {
    final wavePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final path = _buildWavePath(
      startX: endX,
      endX: trackRect.right,
      midY: midY,
      amplitude: amplitude,
      wavelength: wavelength,
      phase: progress * kWavyPhaseTurns,
    );
    canvas.drawPath(path, wavePaint);
  }

  // 高潮区间标记：start/end 两端各一个暖橙色圆点（半径比拇指 7px 小），
  // 不画长条/连线，叠在直线与波浪之上。默认空列表 → 不做任何绘制。
  for (final span in climaxSpans) {
    final start = span.start.clamp(0.0, 1.0);
    final end = span.end.clamp(0.0, 1.0);
    final low = math.min(start, end);
    final high = math.max(start, end);
    final dotPaint = Paint()
      ..color = const Color(0xFFFFB74D)
      ..isAntiAlias = true;
    canvas.drawCircle(
      Offset(trackRect.left + low * trackRect.width, midY),
      3,
      dotPaint,
    );
    canvas.drawCircle(
      Offset(trackRect.left + high * trackRect.width, midY),
      3,
      dotPaint,
    );
  }

  canvas.restore();
}

/// 在 [startX, endX] 区间按正弦函数采样并构造一条 Path。
///
/// 相位从区间左端开始向右累加，因此相位增大时波峰会向左移动；配合
/// progress 推导的相位，未播放波浪会呈现被向左「吃掉/拉直」的流动感。
/// [endX] 不大于 [startX] 时返回空 Path（progress=1 不画波浪）。
Path _buildWavePath({
  required double startX,
  required double endX,
  required double midY,
  required double amplitude,
  required double wavelength,
  required double phase,
}) {
  final path = Path();
  if (endX <= startX) return path;
  final step = math.max(wavelength / 12, 1.0);
  path.moveTo(startX, midY + amplitude * math.sin(phase));
  for (double x = startX + step; x < endX; x += step) {
    final distance = x - startX;
    final y =
        midY +
        amplitude * math.sin(phase + (distance / wavelength) * 2 * math.pi);
    path.lineTo(x, y);
  }
  // 严格落在轨道右端，保证圆头端帽对齐精确边缘。
  final endDistance = endX - startX;
  path.lineTo(
    endX,
    midY +
        amplitude * math.sin(phase + (endDistance / wavelength) * 2 * math.pi),
  );
  return path;
}
