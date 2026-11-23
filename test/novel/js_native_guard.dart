/// JS 宿主测试的 native QuickJS 就绪探测（跨平台）。
///
/// - Windows：`flutter build windows` 后拷到仓库根的 `flutter_qjs_plugin.dll`；
/// - Linux/macOS：CI 用插件 CMake 编出的 .so / framework，放到工作目录或
///   `LD_LIBRARY_PATH` 指向的目录。
///
/// CI 里置 `MIMAO_REQUIRE_NATIVE_JS=1`：拿不到 native 库时测试**直接失败**，
/// 而不是静默 skip——否则 JS 回归（post 参数/失败缓存/## 尾注等）在 CI 恒空跑，
/// 门禁全绿但问题照样复发。
library;

import 'dart:io';

/// 跨平台探测已就绪的 QuickJS native 库。
bool hasNativeQuickJs() {
  if (Platform.isWindows) return File('flutter_qjs_plugin.dll').existsSync();
  if (Platform.isLinux) {
    if (File('libflutter_qjs_plugin.so').existsSync()) return true;
    for (final dir
        in Platform.environment['LD_LIBRARY_PATH']?.split(':') ??
            const <String>[]) {
      if (File(
        '${dir.isEmpty ? '.' : dir}/libflutter_qjs_plugin.so',
      ).existsSync()) {
        return true;
      }
    }
    return File('/usr/lib/libflutter_qjs_plugin.so').existsSync() ||
        File('/usr/local/lib/libflutter_qjs_plugin.so').existsSync();
  }
  if (Platform.isMacOS) {
    return File('flutter_qjs.framework/flutter_qjs').existsSync() ||
        File('libflutter_qjs_plugin.dylib').existsSync();
  }
  return false;
}

/// CI 上要求真跑：拿不到 native 库就 fail。
bool get requireNativeQuickJs =>
    Platform.environment['MIMAO_REQUIRE_NATIVE_JS'] == '1';

/// 缺库时按环境返回 skip 原因；strict 模式返回 null（调用方应 fail）。
String? skipReason() =>
    requireNativeQuickJs ? null : '无 native QuickJS（本地可先编译）';

/// strict 模式下的失败说明。
String get missingNativeMessage =>
    'MIMAO_REQUIRE_NATIVE_JS=1 但未找到 native QuickJS 库；'
    '检查 cmake 构建步骤与 LD_LIBRARY_PATH';
