import 'package:flutter/widgets.dart';

/// dev `/route` 端点的导航栈追踪器（NavigatorObserver 子类，尽力而为）。
///
/// 现状约束：全部页面都是匿名 `MaterialPageRoute`（无 `settings.name`），栈项
/// 只能如实报 null 名 + 路由运行时类型；「当前在哪个模块」以 shellStore 为准
/// （/state 端点）。栈内容是观察者推算，popUntil 多弹等场景不保证精确——
/// 定位用，不用于严格断言。
final devRouteTracker = DevRouteTracker();

/// 一帧导航栈：[name] 为路由 settings 名（匿名路由为 null），[type] 为路由类名。
class RouteFrame {
  final String? name;
  final String type;

  const RouteFrame({required this.name, required this.type});

  Map<String, Object?> toJson(int index) => <String, Object?>{
    'index': index,
    'name': name,
    'type': type,
  };
}

final class DevRouteTracker extends NavigatorObserver {
  final List<RouteFrame> _frames = <RouteFrame>[];

  /// 栈当前深度（0 = 停在初始页/home）。
  int get depth => _frames.length;

  /// 重置栈（dev harness 启动/热重启时调用——观察者是新 Navigator 的）。
  void reset() => _frames.clear();

  /// 快照，时间正序：index 0 最先压入。
  List<Map<String, Object?>> snapshot() => <Map<String, Object?>>[
    for (var i = 0; i < _frames.length; i++) _frames[i].toJson(i),
  ];

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) {
    _frames.add(_frameOf(route));
  }

  @override
  void didPop(Route<Object?> route, Route<Object?>? previousRoute) {
    if (_frames.isNotEmpty) _frames.removeLast();
  }

  @override
  void didReplace({Route<Object?>? newRoute, Route<Object?>? oldRoute}) {
    if (newRoute == null) return;
    if (_frames.isNotEmpty) {
      _frames[_frames.length - 1] = _frameOf(newRoute);
    } else {
      _frames.add(_frameOf(newRoute));
    }
  }

  @override
  void didRemove(Route<Object?> route, Route<Object?>? previousRoute) {
    // popUntil 一次移除多条时这里逐条回调；只能近似按栈顶逐个弹。
    if (_frames.isNotEmpty) _frames.removeLast();
  }

  RouteFrame _frameOf(Route<Object?> route) =>
      RouteFrame(name: route.settings.name, type: route.runtimeType.toString());
}
