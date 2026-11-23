/// 全局路由观察者：模块页需要在「被上层路由遮住又返回」时刷新本地数据
/// （阅读回来后的最近阅读/书架进度）。挂在壳的 MaterialApp 上，模块页面
/// 以 [RouteAware] 订阅即可，不引入模块 → 壳的反向依赖。
library;

import 'package:flutter/widgets.dart';

/// 根导航观察者（与 `MimaoApp.navigatorObservers` 同源）。
final RouteObserver<PageRoute<dynamic>> mimaoRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
