/// dev 能力注册表：/eval 端点可调用的调试能力（debug-only）。
///
/// 与 [devDatabases] 同款模式：模块能力在 shell 的唯一模块装配点
/// （app_registry.dart）注册进 dev 层，dev 文件自身不 import 模块目录——
/// 铁律④靠「闭包捕获模块对象 + 类型收窄」满足。
///
/// 能力签名刻意收敛为 JSON 进出：入参是解码后的 JSON Map，返回值经
/// jsonEncode（不可编码对象 toString 兜底）。复杂对象先在闭包里整理成
/// Map/List/标量再返回。
typedef DevCapability = Future<Object?> Function(Map<String, Object?> args);

final Map<String, DevCapability> devCapabilities = <String, DevCapability>{};

/// 注册（或覆盖同名）一个能力。
void devRegisterCapability(String name, DevCapability capability) {
  devCapabilities[name] = capability;
}

/// 注销一个能力（模块装配失败/重置时调用）。
void devUnregisterCapability(String name) {
  devCapabilities.remove(name);
}

/// 当前已注册能力名（字典序）。
List<String> devCapabilityNames() {
  final names = devCapabilities.keys.toList()..sort();
  return names;
}
