/// wire 解码辅助——EchoMusicNext `crates/echo-api/src/util/response.rs` 的
/// 翻译子集（`scalar`/`text`/`list`/`optional` 解序列化器的 Dart 等价物）。
///
/// 宽容面只对齐 Rust 的宽容面：数字/数字字符串互换（scalar）；其它类型错配
/// 与 Rust 一致按 decode 失败或空值处理（bool 不当文本、非数组不吞成空表）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/client/kugou_error.dart';

/// 数字或数字字符串 → int；缺省/不可解析 → null（`optional`）。
int? optionalInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// 必填标量数字 → int（`scalar`）：缺省或非标量 → decode 失败（Rust 信封的
/// status/error_code 是必填字段）。
int requiredScalarInt(Object? value, String field) {
  final parsed = optionalInt(value);
  if (parsed == null) {
    throw KugouApiException('decode', '响应字段 $field 缺失或不是标量数字');
  }
  return parsed;
}

/// 任意标量 → 文本；缺省/bool/复合类型 → ''（`text`：bool 反序列化失败为空串，
/// 不制造 'true' 这类假值）。
String wireText(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  if (value is num) return '$value';
  return '';
}

/// 数字或数字字符串 → double；缺省/不可解析 → null（`optional<f64>`，
/// tracker 的 volume/volume_peak/volume_gain 用）。
double? optionalDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// 可空文本（`optional` + text 组合）：null → null；bool/复合 → null；
/// 数字 → 字符串形式（Rust ResponseValue 字符串解码）。
String? optionalText(Object? value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is num) return '$value';
  return null;
}

/// 非 List → decode 失败；null → 空 List（`list`：缺省字段给空表，
/// 类型错配与 Rust 一致按失败处理，不吞成空表静默通过）。
List<Object?> wireList(Object? value, String field) {
  if (value == null) return const <Object?>[];
  if (value is List) return value;
  throw KugouApiException('decode', '响应字段 $field 不是数组');
}

/// 非 Map → null。
Map<String, Object?>? wireMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return Map<String, Object?>.from(value);
  }
  return null;
}

/// {status, error_code, data} 信封（Rust `Envelope`：status/error_code 必填）。
class WireEnvelope {
  const WireEnvelope(this.status, this.errorCode, this.data);

  final int status;
  final int errorCode;
  final Object? data;
}

/// 酷狗登录态过期码（request.rs `decode`：20018 → authentication）。
const int kugouErrorCodeAuthenticationExpired = 20018;

/// 解码信封并做业务判定：
/// - status/error_code 缺失或非标量 → decode；
/// - error_code=20018（登录已过期）→ authentication（在 decodeEnvelope 统一判）；
/// - status!=1 或 error_code!=0 → business。
WireEnvelope decodeBusinessEnvelope(Uint8List bytes, {String context = ''}) {
  final envelope = decodeEnvelope(bytes);
  if (envelope.status != 1 || envelope.errorCode != 0) {
    throw KugouApiException(
      'business',
      '音乐服务返回失败${context.isEmpty ? '' : '（$context）'}'
          '（status=${envelope.status}）',
      code: envelope.errorCode,
    );
  }
  return envelope;
}

/// 信封解码（不做业务判定——register_dev 有自己的分支语义）。
/// 登录过期码 20018 在这一层统一映射为 authentication（Rust request::decode
/// 语义：即使 HTTP 成功、即使端点层另有分支，也先判过期）。
WireEnvelope decodeEnvelope(Uint8List bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  if (decoded is! Map) {
    throw const KugouApiException('decode', '响应信封不是 JSON object');
  }
  final errorCode = requiredScalarInt(decoded['error_code'], 'error_code');
  if (errorCode == kugouErrorCodeAuthenticationExpired) {
    throw const KugouApiException('authentication', '登录已过期，请重新登录酷狗账号');
  }
  return WireEnvelope(
    requiredScalarInt(decoded['status'], 'status'),
    errorCode,
    decoded['data'],
  );
}
