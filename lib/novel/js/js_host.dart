/// flutter_qjs 宿主窄接口（M5 骨架）：只执行书源 JSON 内嵌的 JS 片段，语义冻结于
/// docs/architecture.md §4.4；本阶段不 import 任何 JS 引擎包、零实现。
library;

abstract class JsHost {
  Future<String?> run(
    String snippet, {
    Map<String, Object?> context = const {},
  });
  void dispose();
}
