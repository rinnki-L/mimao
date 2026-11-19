import 'dart:io' show HttpStatus;

import 'package:mimao/core/contract.dart';
import 'package:mimao/shell/app.dart';
import 'package:mimao/shell/dev/dev_route.dart';
import 'package:mimao/shell/dev/dev_state.dart';
import 'package:mimao/shell/shell_store.dart';

/// `/navigate` 端点：壳级导航意图（debug-only）。
///
/// 只覆盖「能到页面」所需的最低限：模块切换与壳层页走 [shellStore]（app 的
/// 模块切换本就不经过 Navigator），出栈走根 [MimaoApp.navigatorKey] 的
/// `maybePop`。**不做**任意路由跳转——详情页参数是模型对象而非 JSON，做了
/// 就要给每个模块造 JSON→模型适配层；要进详情页用 /tap 点列表项即可（与
/// 人类同款路径）。
///
/// 返回（HTTP 状态码, 响应体）；body 里带 [devStateSnapshot] 让 agent 立刻
/// 确认落点，省一次 /state 往返。
Future<(int, Map<String, Object?>)> devNavigate(
  Map<String, Object?> body,
) async {
  final action = body['action']?.toString() ?? '';
  switch (action) {
    case 'home':
      shellStore.goHome();
    case 'library':
      shellStore.openLibrary();
    case 'settings':
      shellStore.openSettings();
    case 'closeSettings':
      shellStore.closeSettings();
    case 'module':
      final name = body['name']?.toString() ?? '';
      MediaType? type;
      for (final MediaType t in MediaType.values) {
        if (t.name == name) {
          type = t;
          break;
        }
      }
      if (type == null) {
        return (
          HttpStatus.badRequest,
          <String, Object?>{
            'ok': false,
            'error':
                '未知模块 "$name"；可用：'
                '${MediaType.values.map((t) => t.name).join(', ')}',
          },
        );
      }
      shellStore.openModule(type);
    case 'back':
      final navigator = MimaoApp.navigatorKey.currentState;
      if (navigator == null) {
        return (
          HttpStatus.conflict,
          <String, Object?>{
            'ok': false,
            'error': '根 Navigator 尚未就绪（app 还没跑到 runApp 之后）',
          },
        );
      }
      final popped = await navigator.maybePop();
      return (
        HttpStatus.ok,
        <String, Object?>{
          'ok': true,
          'action': action,
          'popped': popped,
          'routeDepth': devRouteTracker.depth,
          'state': devStateSnapshot(),
        },
      );
    default:
      return (
        HttpStatus.badRequest,
        <String, Object?>{
          'ok': false,
          'error':
              '未知 action "$action"；可用：home / library / settings / '
              'closeSettings / module(+name) / back',
        },
      );
  }
  return (
    HttpStatus.ok,
    <String, Object?>{
      'ok': true,
      'action': action,
      'routeDepth': devRouteTracker.depth,
      'state': devStateSnapshot(),
    },
  );
}
