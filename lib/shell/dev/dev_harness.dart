import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:mimao/core/db.dart';
import 'package:mimao/shell/dev/dev_databases.dart';
import 'package:mimao/shell/dev/dev_log.dart';
import 'package:mimao/shell/dev/dev_route.dart';
import 'package:mimao/shell/dev/dev_server.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// dev harness 启动门面——main() 在 kDebugMode 下调用，一次装配全部设施：
///   1. 错误日志环形缓冲钩子（DevLog.install）
///   2. 统一库注册进 /db 可寻址表（'app'）
///   3. 本地 introspection server（写 driver.json 供 skill 侧发现）
///
/// 铁律：任何失败都不打断 app 启动——dev 设施不许拖累本体，所有异常就地吞掉
/// 并记 DevLog（若连 DevLog 都没装上，那就是彻底静默，可接受）。
///
/// 幂等：热重启会重跑 main()，二次调用只重装（钩子幂等）+ 重写 driver.json，
/// 不重复绑定端口。
final DevServer devServer = DevServer();

Future<void> startDevHarness({AppDb? appDb}) async {
  if (!kDebugMode) return;
  try {
    DevLog.install();
    devRouteTracker.reset();
    if (appDb != null) {
      devRegisterDatabase('app', appDb);
    }
    final driverFile = await _defaultDriverFilePath();
    await devServer.start(driverFilePath: driverFile);
  } catch (error, stack) {
    DevLog.error('dev', 'dev harness 启动失败：$error', details: stack);
  }
}

/// driver.json 落点：`MIMAO_DRIVER_FILE` 环境变量可覆盖（并行实例/测试用）；
/// 默认放应用支持目录（与各模块既有 path_provider 用法一致）。
Future<String> _defaultDriverFilePath() async {
  final override = Platform.environment['MIMAO_DRIVER_FILE'];
  if (override != null && override.isNotEmpty) return override;
  final support = await getApplicationSupportDirectory();
  return p.join(support.path, 'driver.json');
}
