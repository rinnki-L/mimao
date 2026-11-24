// 墨水屏整页刷新：每隔 N 页闪一次黑/白，减轻残影。
//
// 移植自 Venera-Next `eink_refresh_controller.dart` / `eink_refresh.dart`：
// 控制器只管"该不该刷、刷多久、什么样式"，闪屏动画在 overlay 里做。
// 本仓只在翻页模式启用（连续/瀑布整页闪会打断滚动）。

import 'dart:async';

import 'package:flutter/widgets.dart';

/// 闪屏样式。
enum EInkRefreshStyle {
  black('black'),
  white('white'),
  whiteThenBlack('whiteThenBlack');

  const EInkRefreshStyle(this.key);

  final String key;

  static EInkRefreshStyle fromKey(String? key) => values.firstWhere(
    (style) => style.key == key,
    orElse: () => EInkRefreshStyle.black,
  );
}

/// 一次刷新请求（id 自增，overlay 用它丢弃迟到的定时器）。
class EInkRefreshRequest {
  const EInkRefreshRequest({
    required this.id,
    required this.durationMilliseconds,
    required this.style,
  });

  final int id;
  final int durationMilliseconds;
  final EInkRefreshStyle style;
}

/// 翻页计数 → 刷新请求。纯逻辑，可单测。
class EInkRefreshController extends ChangeNotifier {
  EInkRefreshRequest? _request;
  int _pageChangeCount = 0;
  int? _interval;

  EInkRefreshRequest? get request => _request;

  /// 记录一次翻页；需要闪屏时返回 true 并产生新请求。
  bool onPageChanged({
    required int interval,
    required int durationMilliseconds,
    required EInkRefreshStyle style,
  }) {
    final normalizedInterval = interval.clamp(1, 10);
    if (_interval != normalizedInterval) {
      _interval = normalizedInterval;
      _pageChangeCount = 0;
    }
    final shouldRefresh = _pageChangeCount % normalizedInterval == 0;
    _pageChangeCount++;
    if (!shouldRefresh) return false;

    _request = EInkRefreshRequest(
      id: (_request?.id ?? 0) + 1,
      durationMilliseconds: durationMilliseconds.clamp(100, 1500),
      style: style,
    );
    notifyListeners();
    return true;
  }

  void reset() {
    _pageChangeCount = 0;
    _interval = null;
  }
}

/// 闪屏覆盖层：按请求闪黑/白/白后黑，结束自动清空。
class EInkRefreshOverlay extends StatefulWidget {
  const EInkRefreshOverlay({super.key, required this.controller});

  final EInkRefreshController controller;

  @override
  State<EInkRefreshOverlay> createState() => _EInkRefreshOverlayState();
}

class _EInkRefreshOverlayState extends State<EInkRefreshOverlay> {
  Timer? _timer;
  Color? _color;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleRefreshRequest);
  }

  @override
  void didUpdateWidget(covariant EInkRefreshOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleRefreshRequest);
      widget.controller.addListener(_handleRefreshRequest);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleRefreshRequest);
    _timer?.cancel();
    super.dispose();
  }

  void _handleRefreshRequest() {
    final request = widget.controller.request;
    if (request == null) return;

    _timer?.cancel();
    final generation = ++_generation;
    final duration = request.durationMilliseconds;

    if (request.style == EInkRefreshStyle.whiteThenBlack) {
      final firstPhase = duration ~/ 2;
      _setColor(const Color(0xFFFFFFFF));
      _timer = Timer(Duration(milliseconds: firstPhase), () {
        if (!mounted || generation != _generation) return;
        _setColor(const Color(0xFF000000));
        _timer = Timer(Duration(milliseconds: duration - firstPhase), () {
          if (mounted && generation == _generation) _setColor(null);
        });
      });
      return;
    }

    _setColor(
      request.style == EInkRefreshStyle.black
          ? const Color(0xFF000000)
          : const Color(0xFFFFFFFF),
    );
    _timer = Timer(Duration(milliseconds: duration), () {
      if (mounted && generation == _generation) _setColor(null);
    });
  }

  void _setColor(Color? color) {
    if (_color == color) return;
    setState(() => _color = color);
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: _color == null
            ? const SizedBox.expand()
            : ColoredBox(color: _color!),
      ),
    );
  }
}
