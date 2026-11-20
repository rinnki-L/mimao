/// 验证挑战配置端点——EchoMusicNext
/// `crates/echo-api/src/module/get_verify_info.rs` 的逐函数翻译。
///
/// 事件无效时服务端给 `data:null`——那按业务失败处理，而不是拼一个畸形
/// 配置（上游模块注释原样保留）。provider 扩展（show/verify_info/extinfo）
/// 只作结构校验后丢弃，不是可执行 HTML 或任意 URL。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/verify_models.dart';

/// 事件 id 字节长度上限（get_verify_info.rs：`event_id.len() > 4096`）。
const int _verifyEventIdByteLimit = 4096;

/// 查询输入（get_verify_info.rs `Query`：只有 event_id）。
class MusicVerifyInfoQuery {
  const MusicVerifyInfoQuery({required this.eventId});

  final String eventId;

  void validate() {
    // Rust len() 是 UTF-8 字节数；trim 空或超长 → input「验证事件无效」。
    if (eventId.trim().isEmpty ||
        utf8.encode(eventId).length > _verifyEventIdByteLimit) {
      throw const KugouApiException('input', '验证事件无效');
    }
  }
}

/// POST /verifyservice/v3/get_verify_info（网关、无 x-router；普通签名路径，
/// 随当前身份带账号字段）。
Future<MusicVerificationConfiguration> fetchVerifyInfo(
  MusicSession session,
  MusicVerifyInfoQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/verifyservice/v3/get_verify_info',
      method: 'POST',
      // body 键按 serde_json 默认 BTreeMap 字典序编码（签名覆盖 body 字节）：
      // edt, eventid, i, platid, rtype, sid, userid, wasm。
      body: encodeJsonBody(<String, Object?>{
        'edt': '',
        'eventid': query.eventId,
        'i': '',
        'platid': 2,
        'rtype': 1,
        'sid': '',
        'userid': identity.userId,
        'wasm': 1,
      }),
    ),
  );
  return _convertVerifyInfo(response.bytes);
}

/// wire 解析（get_verify_info.rs `convert` + `WireConfiguration`）。
MusicVerificationConfiguration _convertVerifyInfo(Uint8List bytes) {
  // Envelope<Value>：status/error_code 必填标量 + 20018/msg 过期先行
  // （request::decode）→ 业务判定 request::success。
  final envelope = decodeBusinessEnvelope(bytes, context: '验证配置');
  // WireConfiguration：data 必须是 object（from_value 失败 → decode）。
  final wire = requiredWireMap(envelope.data, 'data');

  // serde_json::Map + #[serde(default)]：缺省 → 空 map；出现但不是 object
  // （含显式 null）→ decode。
  final show = _optionalObject(wire, 'show');
  // verify_info / extinfo 是 provider 扩展：校验结构后原样丢弃（上游
  // `let _extensions = (data.verify_info, data.extinfo)`）。
  _optionalObject(wire, 'verify_info');
  _optionalObject(wire, 'extinfo');

  final availableTypes = _wireU32List(wire, 'v_type_list');

  // partnerid_map：BTreeMap<String, i64>（普通反序列化，值严格解码）。
  Map<String, int> partnerStatus = const <String, int>{};
  if (wire.containsKey('partnerid_map')) {
    final map = wireMap(wire['partnerid_map']);
    if (map == null) {
      throw const KugouApiException('decode', '响应字段 partnerid_map 不是 object');
    }
    partnerStatus = <String, int>{
      for (final entry in map.entries)
        entry.key: _requiredI64(entry.value, 'partnerid_map'),
    };
  }

  // sessionid：`optional` + String——缺省/null/非法 → null；数字 → 字符串。
  final sessionId = optionalText(wire['sessionid']);
  final appId = wire.containsKey('txappid')
      ? _requiredScalarText(wire['txappid'], 'txappid')
      : '';
  final url = wire.containsKey('url')
      ? _requiredScalarText(wire['url'], 'url')
      : '';
  final businessId = _optionalU64(wire['business']);
  final verificationType = _requiredU32(wire['v_type'], 'v_type');
  final protocolFlag = _optionalU32(wire['vde']);

  // provider 映射：已知 v_type 优先；tencent 只认**未 trim** url 的
  // `KGCodeTX|` 前缀；其余 unsupported。
  final String provider = switch (verificationType) {
    32 => 'sms',
    34 => 'real_name',
    36 => 'bind_phone',
    38 => 'login',
    51 => 'account_risk',
    _ when url.startsWith('KGCodeTX|') => 'tencent',
    _ => 'unsupported',
  };

  // vendor：trim 后取第一个 `|` 前缀大写；没有 `|`（split_once 失败）或不在
  // 名单 → UNKNOWN。
  final trimmedUrl = url.trim();
  final separator = trimmedUrl.indexOf('|');
  final vendorPrefix = separator < 0
      ? null
      : trimmedUrl.substring(0, separator).toUpperCase();
  final String vendor = switch (vendorPrefix) {
    'KGCODETX' => 'TX',
    'KGCODEGT' => 'GT',
    'KGCODEKG' => 'KG',
    'KGCODEKG2' => 'KG2',
    'KGCODESM' => 'SM',
    'KGCODEYD' => 'YD',
    _ => 'UNKNOWN',
  };

  // show.msg 只认字符串（as_str）：数字/bool 等其它类型 → ''。
  final msg = show['msg'];
  return MusicVerificationConfiguration(
    provider: provider,
    vendor: vendor,
    appId: appId,
    displayMessage: msg is String ? msg : '',
    verificationType: verificationType,
    availableTypes: availableTypes,
    businessId: businessId,
    sessionId: sessionId,
    partnerStatus: partnerStatus,
    protocolFlag: protocolFlag,
  );
}

const int _u32Max = 0xFFFFFFFF;

/// Dart int 是 64 位有符号：u64 的高位段无法表示，按可表示范围封顶
///（id 类字段实际不会触及上限）。
const int _u64Max = 0x7FFFFFFFFFFFFFFF;

/// `exact_unsigned` 的翻译（util/numeric.rs）：整数与整数值浮点可解；负数、
/// 非零小数部分、bool 与复合类型不可解 → null。
int? _exactUnsigned(Object? value, int max) {
  if (value is int) {
    return value >= 0 && value <= max ? value : null;
  }
  if (value is double) {
    if (!value.isFinite || value < 0 || value != value.truncateToDouble()) {
      return null;
    }
    final integral = value.truncate();
    return integral <= max ? integral : null;
  }
  if (value is String) {
    final token = value.trim();
    if (token.isEmpty || token.startsWith('-')) {
      return null;
    }
    final parsed = int.tryParse(token);
    if (parsed == null || parsed < 0 || parsed > max) {
      return null;
    }
    return parsed;
  }
  return null;
}

/// `optional` + u64（response.rs）：缺省/非法 → null。
int? _optionalU64(Object? value) => _exactUnsigned(value, _u64Max);

/// `optional` + u32。
int? _optionalU32(Object? value) => _exactUnsigned(value, _u32Max);

/// `scalar` + u32：缺省/非法 → decode。
int _requiredU32(Object? value, String field) {
  final parsed = _exactUnsigned(value, _u32Max);
  if (parsed == null) {
    throw KugouApiException('decode', '响应字段 $field 缺失或不是标量数字');
  }
  return parsed;
}

/// BTreeMap 值的严格 i64 解码（response.rs `signed`）：不可解 → decode。
int _requiredI64(Object? value, String field) {
  final unsigned = _exactUnsigned(value, _u64Max);
  if (unsigned != null) {
    return unsigned;
  }
  if (value is int) {
    return value;
  }
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.truncate();
  }
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) {
      return parsed;
    }
  }
  throw KugouApiException('decode', '响应字段 $field 不是标量数字');
}

/// `scalar` + String：String/Number 可解；调用方先判 containsKey（缺省走
/// serde default ''）；null/bool/复合 → decode。
String _requiredScalarText(Object? value, String field) {
  final text = optionalText(value);
  if (text == null) {
    throw KugouApiException('decode', '响应字段 $field 缺失或不是标量');
  }
  return text;
}

/// serde_json::Map + `#[serde(default)]`：缺省 → 空 map；出现但不是 object
/// （含显式 null）→ decode。
Map<String, Object?> _optionalObject(Map<String, Object?> wire, String field) {
  if (!wire.containsKey(field)) {
    return const <String, Object?>{};
  }
  final map = wireMap(wire[field]);
  if (map == null) {
    throw KugouApiException('decode', '响应字段 $field 不是 object');
  }
  return map;
}

/// `list` + `Vec<u32>`（response.rs `list`）：null/空 object → 空表；非数组
/// 非空 object → decode；元素按 u32 严格解码。
List<int> _wireU32List(Map<String, Object?> wire, String field) {
  return wireList(
    wire[field],
    field,
  ).map((element) => _requiredU32(element, field)).toList();
}
