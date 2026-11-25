/// 本机设备标识：阅读记录的多设备维度种子（为区 11 的同步打底）。
///
/// 首次启动时生成一个 UUID v4 存进模块 kv（[novelPrefDeviceId]），之后每次
/// 读取都返回同一个值。不引入 `uuid` 包：它现在只是 transitive 依赖，为一个
/// 32 行就能写完的 v4 生成再往 pubspec 里加直接依赖不划算（依赖精简约束）。
library;

import 'dart:math';

/// 模块 kv 键：本机设备 ID。
const String novelPrefDeviceId = 'device_id';

/// 生成 UUID v4（随机 122 bit；版本/变体位按 RFC 4122 写死）。
///
/// 每次调用都返回新值——持久化由调用方（[NovelDb.ensureDeviceId]）负责，
/// 这里保持纯函数，便于单测格式与唯一性。
String generateNovelDeviceId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

/// UUID v4 文本格式（8-4-4-4-12，小写十六进制）。
final RegExp novelDeviceIdPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
