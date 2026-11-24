// 连续/瀑布模式的滚动锚点：图片异步测量后尺寸变化时，保持读者正在看的位置。
//
// 移植自 Venera-Next `lib/features/reader/continuous_scroll.dart`（上游同款
// 思路：通过公开的 ScrollPosition 与 scrollable_positioned_list 发布的可见项
// 边界，把"布局后图片变高/变矮"造成的位移在下一帧绘制前修正掉）。
//
// 为什么需要：本仓图片先按编码头尺寸占位，但首张图在尺寸测出前仍会从估算
// 宽高比切到真实宽高比；列表总高度一变，ScrollPosition 会把内容整体推走。
// 用每个列表项挂一个锚点，记录它的屏幕位置，尺寸变化时反算滚动偏移。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// 观察可见项边界，并在异步尺寸变化后修正滚动位置。
class ReaderContinuousScrollController extends ScrollController {
  ReaderContinuousScrollController(
    this.items, {
    required this.onPositionChanged,
    this.canAnchor,
  }) : super(keepScrollOffset: false) {
    items.addListener(syncPosition);
  }

  final ValueListenable<Iterable<ItemPosition>> items;
  final VoidCallback onPositionChanged;

  /// 哪些项可以作为锚点（哨兵/章节分隔条不参与）。
  final bool Function(int index)? canAnchor;

  final Set<_ReaderContinuousScrollAnchorState> _anchors =
      <_ReaderContinuousScrollAnchorState>{};
  bool _scheduled = false;
  bool _disposed = false;
  bool _layoutChanged = false;
  ({
    _ReaderContinuousScrollAnchorState item,
    ScrollPosition position,
    RenderBox viewport,
    double leading,
    double pixels,
    double extent,
  })?
  _layoutAnchor;

  void resetLayoutAnchor() {
    _layoutAnchor = null;
    _layoutChanged = false;
  }

  void _onExtentChanged(ScrollPosition? owner) {
    final anchor = _layoutAnchor;
    if (_disposed ||
        anchor == null ||
        !identical(owner, anchor.position) ||
        !anchor.position.hasPixels) {
      return;
    }
    _layoutChanged = true;
    // 总高度没变也可能发生两次等量反向变化，仍要纠正一次。
    anchor.position.correctBy(0);
  }

  ({RenderBox viewport, double leading, double trailing, double extent})?
  _geometry(
    _ReaderContinuousScrollAnchorState anchor,
    ScrollPosition position,
  ) {
    if (!anchor.mounted) return null;
    final box = anchor.context.findRenderObject();
    if (box is! _RenderReaderAnchorLayout ||
        !box.attached ||
        box.previousSize == null) {
      return null;
    }
    final RenderObject? viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport is! RenderBox || !viewport.hasSize) return null;
    // 反向列表在布局期间拿不到 paint transform，但 layout offset 可用。
    RenderBox item = box;
    while (item.parent is RenderBox) {
      item = item.parent! as RenderBox;
    }
    final sliver = item.parent;
    if (sliver is! RenderSliverMultiBoxAdaptor || sliver.geometry == null) {
      return null;
    }
    final offset = sliver.childScrollOffset(item);
    if (offset == null) return null;
    final size = box.previousSize!;
    final vertical = sliver.constraints.axis == Axis.vertical;
    var leading = offset - sliver.constraints.scrollOffset;
    final direction = applyGrowthDirectionToAxisDirection(
      sliver.constraints.axisDirection,
      sliver.constraints.growthDirection,
    );
    if (axisDirectionIsReversed(direction)) {
      leading =
          sliver.geometry!.paintExtent -
          leading -
          (vertical ? size.height : size.width);
    }
    final bounds = MatrixUtils.transformRect(
      sliver.getTransformTo(viewport),
      (vertical ? Offset(0, leading) : Offset(leading, 0)) & size,
    );
    if (!bounds.isFinite) return null;
    final extent = vertical ? viewport.size.height : viewport.size.width;
    final reversed = axisDirectionIsReversed(position.axisDirection);
    return (
      viewport: viewport,
      extent: extent,
      leading: reversed
          ? extent - (vertical ? bounds.bottom : bounds.right)
          : (vertical ? bounds.top : bounds.left),
      trailing: reversed
          ? extent - (vertical ? bounds.top : bounds.left)
          : (vertical ? bounds.bottom : bounds.right),
    );
  }

  void _captureLayoutAnchor(ScrollPosition? position) {
    resetLayoutAnchor();
    if (position == null) return;
    for (final anchor in _anchors) {
      if (!anchor.mounted ||
          anchor.widget.index <= 0 ||
          canAnchor?.call(anchor.widget.index) == false ||
          !identical(Scrollable.maybeOf(anchor.context)?.position, position)) {
        continue;
      }
      final geometry = _geometry(anchor, position);
      if (geometry == null ||
          geometry.trailing <= 0 ||
          geometry.leading >= geometry.extent ||
          (_layoutAnchor != null &&
              _layoutAnchor!.item.widget.index < anchor.widget.index)) {
        continue;
      }
      _layoutAnchor = (
        item: anchor,
        position: position,
        viewport: geometry.viewport,
        leading: geometry.leading,
        pixels: position.pixels,
        extent: geometry.extent,
      );
    }
  }

  double? _correctLayout(ScrollMetrics metrics) {
    if (!_layoutChanged) return null;
    _layoutChanged = false;
    final anchor = _layoutAnchor;
    if (anchor == null ||
        !hasClients ||
        !identical(position, anchor.position) ||
        metrics.viewportDimension != anchor.extent) {
      return null;
    }
    final geometry = _geometry(anchor.item, anchor.position);
    if (geometry == null || !identical(geometry.viewport, anchor.viewport)) {
      return null;
    }
    // 保留用户在这一帧里的真实滑动量，不用 jumpTo 打断惯性。
    final correction =
        geometry.leading - anchor.leading + metrics.pixels - anchor.pixels;
    if (!correction.isFinite || correction.abs() < 0.01) return null;
    return (metrics.pixels + correction).clamp(
      metrics.minScrollExtent,
      metrics.maxScrollExtent,
    );
  }

  void _register(_ReaderContinuousScrollAnchorState anchor) {
    _anchors.add(anchor);
    _scheduleSync();
  }

  void _unregister(_ReaderContinuousScrollAnchorState anchor) {
    _anchors.remove(anchor);
    _scheduleSync();
  }

  void _scheduleSync() {
    if (_disposed || _scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      syncPosition();
    }, debugLabel: 'reader continuous scroll position');
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  /// 把控制器挂到当前真正活着的 ScrollPosition 上。
  void syncPosition() {
    if (_disposed) return;
    final expected = <int, ItemPosition>{
      for (final item in items.value) item.index: item,
    };
    final matches = <ScrollPosition, int>{};
    final live = <ScrollPosition>{};
    for (final anchor in _anchors) {
      if (!anchor.mounted) continue;
      final scroll = Scrollable.maybeOf(anchor.context)?.position;
      if (scroll == null) continue;
      live.add(scroll);
      final item = expected[anchor.widget.index];
      if (item == null || !scroll.hasContentDimensions) continue;
      final box = anchor.context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final RenderObject? viewport = RenderAbstractViewport.maybeOf(box);
      if (viewport is! RenderBox || !viewport.hasSize) continue;
      final bounds = MatrixUtils.transformRect(
        box.getTransformTo(viewport),
        Offset.zero & box.size,
      );
      final vertical =
          axisDirectionToAxis(scroll.axisDirection) == Axis.vertical;
      final extent = vertical ? viewport.size.height : viewport.size.width;
      if (!bounds.isFinite || extent <= 0) continue;
      var leading = (vertical ? bounds.top : bounds.left) / extent;
      var trailing = (vertical ? bounds.bottom : bounds.right) / extent;
      if (axisDirectionIsReversed(scroll.axisDirection)) {
        (leading, trailing) = (1 - trailing, 1 - leading);
      }
      if ((leading - item.itemLeadingEdge).abs() < 0.0001 &&
          (trailing - item.itemTrailingEdge).abs() < 0.0001) {
        matches.update(scroll, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final current = hasClients ? position : null;
    var selected = current;
    var best = matches[current] ?? 0;
    for (final entry in matches.entries) {
      if (entry.value > best) {
        selected = entry.key;
        best = entry.value;
      }
    }
    if (selected != null && !live.contains(selected)) selected = null;
    // 只有一条活列表时没有歧义；两条（长距离动画）时靠可见项边界判定。
    if (selected == null && live.length == 1) selected = live.single;
    _captureLayoutAnchor(selected);
    if (identical(selected, current)) return;
    if (current != null) detach(current);
    if (selected != null) attach(selected);
    onPositionChanged();
    notifyListeners();
  }

  /// 按像素滚动（自动阅读、点击/键盘翻屏共用）。
  Future<void> scrollBy(double offset, {Duration? duration}) {
    if (_disposed || !hasClients) return Future<void>.value();
    final target = (position.pixels + offset).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.5) return Future<void>.value();
    if (duration == null) {
      position.jumpTo(target);
      return Future<void>.value();
    }
    return position.animateTo(
      target,
      duration: duration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    resetLayoutAnchor();
    items.removeListener(syncPosition);
    _anchors.clear();
    for (final position in positions.toList()) {
      detach(position);
    }
    // ScrollPosition 归官方列表所有，这里只退订。
    super.dispose();
  }
}

/// 尺寸变化后先修正 ScrollPosition，再交给父级物理。
class ReaderContinuousLayoutPhysics extends ScrollPhysics {
  const ReaderContinuousLayoutPhysics({required this.controller, super.parent});

  final ReaderContinuousScrollController controller;

  @override
  ReaderContinuousLayoutPhysics applyTo(ScrollPhysics? ancestor) =>
      ReaderContinuousLayoutPhysics(
        controller: controller,
        parent: buildParent(ancestor),
      );

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) =>
      controller._correctLayout(newPosition) ??
      super.adjustPositionForNewDimensions(
        oldPosition: oldPosition,
        newPosition: newPosition,
        isScrolling: isScrolling,
        velocity: velocity,
      );
}

/// 列表项包装：向滚动控制器注册自己，并报告尺寸变化。
class ReaderContinuousScrollAnchor extends StatefulWidget {
  const ReaderContinuousScrollAnchor({
    super.key,
    required this.controller,
    required this.index,
    required this.child,
  });

  final ReaderContinuousScrollController controller;
  final int index;
  final Widget child;

  @override
  State<ReaderContinuousScrollAnchor> createState() =>
      _ReaderContinuousScrollAnchorState();
}

class _ReaderContinuousScrollAnchorState
    extends State<ReaderContinuousScrollAnchor> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 先建立对 Scrollable 的依赖，再注册锚点。
    Scrollable.maybeOf(context);
    widget.controller._register(this);
  }

  @override
  void didUpdateWidget(ReaderContinuousScrollAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller._unregister(this);
    }
    widget.controller._register(this);
  }

  @override
  void dispose() {
    widget.controller._unregister(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ReaderAnchorLayout(controller: widget.controller, child: widget.child);
}

class _ReaderAnchorLayout extends SingleChildRenderObjectWidget {
  const _ReaderAnchorLayout({required this.controller, required super.child});

  final ReaderContinuousScrollController controller;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReaderAnchorLayout(
        controller,
        Scrollable.maybeOf(context)?.position,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReaderAnchorLayout renderObject,
  ) {
    renderObject.controller = controller;
    renderObject.position = Scrollable.maybeOf(context)?.position;
  }
}

class _RenderReaderAnchorLayout extends RenderProxyBox {
  _RenderReaderAnchorLayout(this.controller, this.position);

  ReaderContinuousScrollController controller;
  ScrollPosition? position;
  Size? previousSize;

  @override
  void performLayout() {
    super.performLayout();
    if (previousSize != null && previousSize != size) {
      controller._onExtentChanged(position);
    }
    previousSize = size;
  }
}
