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

/// 非 List → decode 失败；null 与**空 object** → 空 List（`list`：缺省字段
/// 给空表；上游把 `{}` 也视为空集合，例如 top_playlist 的 tags；非空 object
/// 与其它类型错配仍按失败处理，不吞成空表静默通过）。
List<Object?> wireList(Object? value, String field) {
  if (value == null) return const <Object?>[];
  if (value is List) return value;
  if (value is Map && value.isEmpty) return const <Object?>[];
  throw KugouApiException('decode', '响应字段 $field 不是数组');
}

/// 必填 object（`from_value` 到结构体失败 → decode）；null/非 object → decode。
Map<String, Object?> requiredWireMap(Object? value, String field) {
  final map = wireMap(value);
  if (map == null) {
    throw KugouApiException('decode', '响应字段 $field 不是 object');
  }
  return map;
}

/// 展示用 0/1 布尔（util/numeric.rs `boolean`）：0→false、1→true、其它/缺省
/// → null（未知服务码保留未知，不臆造负向事实）。
bool? optionalBool(Object? value) {
  final numeric = optionalInt(value);
  return switch (numeric) {
    0 => false,
    1 => true,
    _ => null,
  };
}

/// 展示用封面 URL：`{size}` 占位符 → [size]（domain.rs `cover_url`）。
String coverUrl(String template, {int size = 240}) =>
    template.replaceAll('{size}', '$size');

/// 请求体 JSON 字节（`request::encode`）。
Uint8List encodeJsonBody(Object? value) =>
    Uint8List.fromList(utf8.encode(jsonEncode(value)));

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
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: context);
  return envelope;
}

/// 业务成功判定（request.rs `success`：status==1 且 code==0）。
void ensureBusinessSuccess(int status, int errorCode, {String context = ''}) {
  if (status == 1 && errorCode == 0) return;
  throw KugouApiException(
    'business',
    '音乐服务返回失败${context.isEmpty ? '' : '（$context）'}'
        '（status=$status）',
    code: errorCode,
  );
}

/// 可配置字段名的信封解码：
/// - `ErrcodeEnvelope` 用 `status` + `errcode`（rank/list 等）；
/// - 歌词端点用 `status` + `error_code`，但成功状态是 200（调用方自行判定）。
///
/// 登录过期语义严格对齐 request.rs `authentication_expiration`：
/// - 只认 `error_code`（`errcode` 等别名不参与，20018 在别名下是 business）；
/// - `msg` 文本含「登录已过期」也算过期（即使没有 error_code）。
WireEnvelope decodeEnvelopeWithFields(
  Uint8List bytes, {
  String statusKey = 'status',
  String errorCodeKey = 'error_code',
  bool mapAuthenticationExpired = true,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  if (decoded is! Map) {
    throw const KugouApiException('decode', '响应信封不是 JSON object');
  }
  if (mapAuthenticationExpired) {
    final message = decoded['msg'];
    final expiredMessage = message is String && message.contains('登录已过期');
    final rawErrorCode = errorCodeKey == 'error_code'
        ? optionalInt(decoded['error_code'])
        : null;
    if (expiredMessage || rawErrorCode == kugouErrorCodeAuthenticationExpired) {
      throw const KugouApiException('authentication', '登录已过期，请重新登录酷狗账号');
    }
  }
  final errorCode = requiredScalarInt(decoded[errorCodeKey], errorCodeKey);
  return WireEnvelope(
    requiredScalarInt(decoded[statusKey], statusKey),
    errorCode,
    decoded['data'],
  );
}

/// 信封解码（不做业务判定——register_dev 有自己的分支语义）。
/// 登录过期码 20018 在这一层统一映射为 authentication（Rust request::decode
/// 语义：即使 HTTP 成功、即使端点层另有分支，也先判过期）。
WireEnvelope decodeEnvelope(Uint8List bytes) => decodeEnvelopeWithFields(bytes);
