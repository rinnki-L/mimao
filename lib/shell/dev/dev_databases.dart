import 'package:drift/drift.dart';

/// `/db` 端点可寻址的 drift 库名 → 实例表（debug-only）。
///
/// 注册时机由各创建方负责：
///   - main.dart 经 startDevHarness(appDb:) 注册 `'app'`
///   - app_registry.dart 注册自建的模块库（`'anime'` / `'comic'` / `'music'`）
///   - 测试可直接读写本表注册内存库
///
/// 类型刻意收窄到 [GeneratedDatabase]（drift 任意生成库的公共基类）：dev 文件
/// 只依赖 drift，不 import 任何模块目录——铁律④（shell 里仅 app_registry.dart
/// 准 import 模块）靠类型收窄天然满足。
final Map<String, GeneratedDatabase> devDatabases =
    <String, GeneratedDatabase>{};

/// 注册（或覆盖同名）一个可经 /db 查询的库。
void devRegisterDatabase(String name, GeneratedDatabase db) {
  devDatabases[name] = db;
}

/// 注销一个库（库被关闭/重置时调用，避免 /db 摸到已关闭连接）。
void devUnregisterDatabase(String name) {
  devDatabases.remove(name);
}

/// 当前已注册的库名（字典序）。
List<String> devDatabaseNames() {
  final names = devDatabases.keys.toList()..sort();
  return names;
}
