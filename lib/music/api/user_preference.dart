/// 偏好读取端点——EchoMusicNext `crates/echo-api/src/module/user_preference.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 传输装配走 util/preference_protocol.rs（get/update 共用），在本文件以
/// [kugouSendPreferenceProtocol] 落地；六个 UI 字段都是字符串（含 JSON 编码
/// 的权重），未知 id 与非法编码原样保留——绝不把远端不可编辑的值变成空选择。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';
import 'package:mimao/music/models/user_library_models.dart';

/// 偏好协议传输（preference_protocol.rs `send`）——get_user_conf 与
/// update_user_conf 共用：require_account → 秒级 time → `preference_envelope`
/// （token 单独 AES 加密、画像走 PKCS#1 v1.5 RSA、portrait 小写）→ body
/// `{data?, p, params, plat, userid}` → 显式参数 + 端点自算签名 →
/// `request_grade`（cloud + clearDefaults：URL 上只有显式列出的键）。
///
/// [fields] 非空即 update 写入；`seed`/`random`/`now` 仅供测试注入（与
/// register_dev 的可注入缝同款式），生产全走系统熵。
Future<Uint8List> kugouSendPreferenceProtocol(
  KugouClient client,
  KugouIdentity identity, {
  Map<String, String>? fields,
  String? seed,
  Random? random,
  DateTime Function()? now,
}) async {
  // preference_protocol.rs send 开头的 require_account。
  requireMusicAccount(identity);
  final seconds =
      ((now?.call() ?? DateTime.now()).millisecondsSinceEpoch) ~/ 1000;
  final envelope = kugouPreferenceEnvelope(
    identity.token,
    seconds,
    seed: seed,
    random: random,
  );
  // Rust json! 宏经 BTreeMap 序列化：body 键按字典序（data < p < params <
  // plat < userid）；data 的字段表也是 BTreeMap → 键序排序。
  final sortedFields = fields == null
      ? null
      : <String, String>{
          for (final key in fields.keys.toList()..sort()) key: fields[key]!,
        };
  final update = fields != null;
  final body = encodeJsonBody(<String, Object?>{
    if (update) 'data': sortedFields,
    'p': envelope.portrait,
    'params': envelope.params,
    'plat': 1,
    'userid': identity.userId,
  });
  final params = <String, String>{
    'appid': '3116',
    'clientver': '11440',
    'clienttime': seconds.toString(),
    'mid': identity.mid,
    'dfid': identity.dfid,
    'uuid': identity.uuid,
  };
  // 上游在端点层自算 Android 签名（request_grade 不注入）。
  params['signature'] = kugouSignatureAndroid(params, body);
  return (await client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: update
          ? '/userpreferservice/v1/update_user_conf'
          : '/userpreferservice/v1/get_user_conf',
      method: 'POST',
      params: params,
      body: body,
      headers: <(String, String)>[
        ('Content-Type', 'application/json'),
        ('KG-Rec', '1'),
        ('KG-RC', '1'),
        ('User-Agent', kugouPreferenceUserAgent(update: update)),
      ],
    ),
    cloud: true,
    clearDefaults: true,
  )).bytes;
}

/// preference 端点的固定 UA（preference_protocol.rs headers）。
String kugouPreferenceUserAgent({required bool update}) => update
    ? 'Android15-1070-11440-201-0-update_user_conf-wifi'
    : 'Android15-1070-11440-201-0-get_user_conf-wifi';

/// GET /userpreferservice/v1/get_user_conf（需要账号）。
Future<MusicPreferences> fetchUserPreference(
  MusicSession session, {
  String? seed,
  Random? random,
  DateTime Function()? now,
}) async {
  final identity = await session.ensureDevice();
  final bytes = await kugouSendPreferenceProtocol(
    session.client,
    identity,
    seed: seed,
    random: random,
    now: now,
  );
  return _convertPreferences(bytes);
}

/// wire 解析（user_preference.rs `convert`）。
MusicPreferences _convertPreferences(Uint8List bytes) {
  final envelope = decodeEnvelope(bytes);
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '偏好');
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '偏好响应 data 不是 object');
  }
  return MusicPreferences(
    recommendationMode: _preferenceText(data['mode']),
    gender: _preferenceText(data['gender']),
    age: _preferenceText(data['age']),
    languages: _weightPreference(data['lang']),
    styles: _weightPreference(data['style']),
    recommendation: _weightPreference(data['song_lang']),
  );
}

/// `from_value::<String>.ok()`：字符串原样、数字取字面量；其它 → null。
String? _preferenceText(Object? value) {
  if (value is String) return value;
  if (value is num) return '$value';
  return null;
}

/// WeightPreference::new：String → 原样；object → 紧凑 JSON（BTreeMap 键序）；
/// 其它 → encoded/weights 双 null（原值仍留在 raw）。
MusicWeightPreference _weightPreference(Object? raw) {
  String? encoded;
  if (raw is String) {
    encoded = raw;
  } else if (raw is Map) {
    encoded = jsonEncode(_sortedValue(raw));
  }
  return MusicWeightPreference(
    encoded: encoded,
    weights: _weightsOf(encoded),
    raw: raw,
  );
}

/// encoded 非空时解 `Map<String, double>`；空串 → 空表；解析失败或含不可读
/// 值 → null（不上抛——远端值不因此被丢弃）。
Map<String, double>? _weightsOf(String? encoded) {
  if (encoded == null) return null;
  if (encoded.isEmpty) return <String, double>{};
  Object? parsed;
  try {
    parsed = jsonDecode(encoded);
  } on Object {
    return null;
  }
  final map = wireMap(parsed);
  if (map == null) return null;
  final weights = <String, double>{};
  for (final entry in map.entries) {
    final weight = optionalDouble(entry.value);
    if (weight == null) return null;
    weights[entry.key] = weight;
  }
  return weights;
}

/// serde_json 默认 Map 是 BTreeMap：`Value::to_string()` 按 key 字典序输出
/// （嵌套同理）——object 型偏好的 encoded 与上游字符串逐字节一致。
Object? _sortedValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _sortedValue(value[key]),
    };
  }
  if (value is List) {
    return <Object?>[for (final item in value) _sortedValue(item)];
  }
  return value;
}
