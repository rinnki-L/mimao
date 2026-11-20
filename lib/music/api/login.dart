/// 密码登录端点——EchoMusicNext `crates/echo-api/src/module/login.rs` 的
/// 逐函数翻译（docs/architecture.md §4.3：`music/api/` ← module）。
///
/// 协议要点：
/// - 请求身份必须匿名化（userid/token/t1 清零，保留 mid/dfid/deviceName）——
///   登录绝不继承旧账号，含直接调用方；
/// - body 里的 `t1/t2/t3` 是固定协议证明常量（上游注释原样保留），**不是**
///   账号续期字段 t1；
/// - 参数信封 `params/pk` 由 `kugouLoginParameterEnvelope` 生成，响应凭证用
///   同一 seed 解密（`kugouDecodeLoginCredentials`）；
/// - 失败文本从 data/error/message/msg 里取第一条有界字符串（只展示文本，
///   永不回显对象或加密信封）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/auth_models.dart';

/// body 的固定协议证明常量（login.rs `T1/T2/T3`，照抄）。
const String kugouLoginProofT1 =
    '562a6f12a6e803453647d16a08f5f0c2ff7eee692cba2ab74cc4c8ab47fc467561a7c6b586ce7dc46a63613b246737c03a1dc8f8d162d8ce1d2c71893d19f1d4b797685a4c6d3d81341cbde65e488c4829a9b4d42ef2df470eb102979fa5adcdd9b4eecfea8b909ff7599abeb49867640f10c3c70fc444effca9d15db44a9a6c907731e2bb0f22cd9b3536380169995693e5f0e2424e3378097d3813186e3fe96bbe7023808a0981b4e2b6135a76faac';
const String kugouLoginProofT2 =
    '31c4daf4cf480169ccea1cb7d4a209295865a9d2b788510301694db229b87807469ea0d41b4d4b9173c2151da7294aeebfc9738df154bbdf11a4e117bb5dff6a3af8ce5ce333e681c1f29a44038f27567d58992eb81283e080778ac77db1400fdf49b7cf7e26be2e5af4da7830cc3be4';
const String kugouLoginProofT3 = 'MCwwLDAsMCwwLDAsMCwwLDA=';

/// 登录输入（login.rs `Query`；敏感字段不参与 toString）。
class MusicLoginQuery {
  const MusicLoginQuery({
    required this.username,
    required this.password,
    this.code = '',
  });

  final String username;
  final String password;

  /// 附加校验串（可选；上游 serde default 空串）。
  final String code;

  void validate() {
    if (utf8.encode(username.trim()).isEmpty ||
        utf8.encode(username).length > 256 ||
        password.isEmpty ||
        utf8.encode(password).length > 256 ||
        utf8.encode(code).length > 128) {
      throw const KugouApiException('input', '账号、密码或设备参数无效');
    }
  }
}

/// /v9/login_by_pwd（网关 + x-router=login.user.kugou.com）。
///
/// `timestampMs`/`seed` 仅供测试注入；生产走系统时钟与随机 seed。
Future<MusicLoginAuthorization> fetchLogin(
  MusicSession session,
  MusicLoginQuery query, {
  int? timestampMs,
  String? seed,
}) async {
  query.validate();
  final identity = await session.ensureDevice();
  if (identity.deviceName.isEmpty) {
    throw const KugouApiException('input', '账号、密码或设备参数无效');
  }
  // 登录绝不继承另一个账号（login.rs execute：userid=0、token/t1 清空）。
  final anonymous = identity.withoutAccount();
  final time = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
  final envelope = kugouLoginParameterEnvelope(
    <String, Object?>{
      'pwd': query.password,
      'code': query.code,
      'clienttime_ms': time,
    },
    time,
    seed: seed,
  );
  // serde_json 默认 BTreeMap：JSON 键按字典序输出，这里按序插入。
  final body = <String, Object?>{
    'clienttime_ms': time,
    'dev': anonymous.deviceName,
    'params': envelope.params,
    'pk': envelope.portrait,
    'plat': 1,
    'support_multi': 1,
    't1': kugouLoginProofT1,
    't2': kugouLoginProofT2,
    't3': kugouLoginProofT3,
    'username': query.username,
  };
  final response = await session.client.sendEndpoint(
    anonymous,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v9/login_by_pwd',
      router: 'login.user.kugou.com',
      method: 'POST',
      body: encodeJsonBody(body),
    ),
  );
  return _convertLogin(response.bytes, envelope.seed);
}

/// wire 解析（login.rs `convert`）。
MusicLoginAuthorization _convertLogin(Uint8List bytes, String seed) {
  final envelope = decodeEnvelope(bytes);
  if (envelope.status != 1 || envelope.errorCode != 0) {
    throw _loginBusinessError(bytes, envelope);
  }
  final data = envelope.data;
  final map = wireMap(data);
  if (map == null) {
    throw const KugouApiException('decode', '登录响应 data 不是 object');
  }
  // login.rs 允许无密文时的明文 token 兜底（手机号/第三方分支各自不同）。
  return loginAuthorizationFromData(map, seed, allowPlaintextToken: true);
}

/// 业务失败文本提取（login.rs convert：data/error/message/msg 依次找第一条
/// trim 非空且 <=1024 字节的字符串；缺省文案与上游 `business()` 一致）。
KugouApiException _loginBusinessError(Uint8List bytes, WireEnvelope envelope) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map) {
      for (final key in const <String>['data', 'error', 'message', 'msg']) {
        final value = decoded[key];
        if (value is String) {
          final text = value.trim();
          if (text.isNotEmpty && utf8.encode(text).length <= 1024) {
            return KugouApiException(
              'business',
              text,
              code: envelope.errorCode,
            );
          }
        }
      }
    }
  } on Object {
    // 信封已解码成功过，这里不可能失败；失败也按无文本处理。
  }
  return KugouApiException('business', '请求失败', code: envelope.errorCode);
}

// ---------------------------------------------------------------------------
// wire 标量原语——response.rs `scalar`（带 serde default）/`optional` 的翻译。
// 与 wire.dart 的区别：scalar 字段「缺失给默认值、存在但不可读按 decode」，
// optional 字段「缺失/null/类型错一律 null（可选 u64 额外拒绝负数）」。
// ---------------------------------------------------------------------------

/// scalar u64 + `#[serde(default)]`：缺失 → 0；null/bool/复合/负数/非整浮点
/// → decode。
int authScalarU64(Map<String, Object?> map, String field) {
  if (!map.containsKey(field)) return 0;
  final parsed = _unsignedScalar(map[field], field);
  if (parsed == null) {
    throw KugouApiException('decode', '响应字段 $field 不是标量数字');
  }
  return parsed;
}

/// scalar u64 无默认（serde 必填字段）：缺失也 decode。
int authRequiredScalarU64(Map<String, Object?> map, String field) {
  final parsed = _unsignedScalar(map[field], field);
  if (parsed == null) {
    throw KugouApiException('decode', '响应字段 $field 缺失或不是标量数字');
  }
  return parsed;
}

/// `request::decode` 的 JSON 语义（provider/解密响应共用）：合法 JSON →
/// 「登录已过期」判定（error_code=20018 或 msg 文本）→ 返回解码值；其余解析
/// 失败 → decode。response.rs 之外的字段由调用方按各自 wire 结构取。
Object? authDecodeProviderJson(List<int> bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  if (decoded is Map) {
    final errorCode = optionalInt(decoded['error_code']);
    final message = decoded['msg'];
    final expiredMessage = message is String && message.contains('登录已过期');
    if (expiredMessage || errorCode == kugouErrorCodeAuthenticationExpired) {
      throw const KugouApiException('authentication', '登录已过期，请重新登录酷狗账号');
    }
  }
  return decoded;
}

/// scalar String + `#[serde(default)]`：缺失 → ''；数字 → 文本；null/bool/复合
/// → decode。
String authScalarText(Map<String, Object?> map, String field) {
  if (!map.containsKey(field)) return '';
  return authRequiredScalarText(map, field);
}

/// scalar String 无默认：缺失也 decode（login_token 的必填字段）。
String authRequiredScalarText(Map<String, Object?> map, String field) {
  final value = map[field];
  if (value is String) return value;
  if (value is num) return '$value';
  throw KugouApiException('decode', '响应字段 $field 不是标量');
}

/// optional u64/u32：缺失/null/bool/复合/负数/非整浮点 → null。
int? authOptionalU64(Object? value) => _unsignedScalar(value, '');

/// unsigned 标量（response.rs `unsigned`）：数字（整数或整值浮点）或数字
/// 字符串；负数/小数/bool/复合 → null。
int? _unsignedScalar(Object? value, String field) {
  final unsigned = switch (value) {
    int v when v >= 0 => v,
    double v when v >= 0 && v == v.truncateToDouble() => v.toInt(),
    String v => () {
      final parsed = int.tryParse(v.trim());
      return parsed != null && parsed >= 0 ? parsed : null;
    }(),
    _ => null,
  };
  if (unsigned == null && field.isNotEmpty) {
    throw KugouApiException('decode', '响应字段 $field 不是标量数字');
  }
  return unsigned;
}

/// optional i64：缺失/null/bool/复合 → null；数字（含负）与数字字符串 → int。
int? authOptionalI64(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

/// 登录凭证转换——login.rs / login_cellphone.rs / login_qq.rs /
/// login_openplat.rs 四处 `authorization(data, seed)` 的共享翻译。
///
/// [allowPlaintextToken]：login.rs 与 login_cellphone.rs 在 `secu_params` 为空
/// 时直接把明文 `token` 当凭证；login_qq.rs / login_openplat.rs **必须**是密文
/// （空串解密失败 → decode）。其余字段语义完全一致。
MusicLoginAuthorization loginAuthorizationFromData(
  Map<String, Object?> data,
  String seed, {
  required bool allowPlaintextToken,
}) {
  final accountUserId = authScalarU64(data, 'userid');
  final accountT1 = optionalText(data['t1']);
  final accountExpires = authOptionalU64(data['t_expire_time']);
  final accountNickname = wireText(data['nickname']);
  final accountPic = wireText(data['pic']);
  final secuParams = authScalarText(data, 'secu_params');
  final accountToken = authScalarText(data, 'token');

  String credentialsToken;
  Map<String, Object?>? credentials;
  if (allowPlaintextToken && secuParams.isEmpty) {
    // 无安全信封时明文 token 原样保留（上游注释）。
    credentialsToken = accountToken;
  } else {
    final secret = kugouDecodeLoginCredentials(secuParams, seed);
    if (secret is String) {
      credentialsToken = secret;
    } else {
      credentials = wireMap(secret);
      if (credentials == null) {
        throw const KugouApiException('decode', '登录凭证结构无效');
      }
      credentialsToken = authRequiredScalarText(credentials, 'token');
    }
  }

  // credentials.* 为 Option：解密对象里缺省/类型错时回退 account.* 字段。
  final userId =
      (credentials == null ? null : authOptionalU64(credentials['userid'])) ??
      accountUserId;
  if (userId == 0 || userId > _i64Max || credentialsToken.isEmpty) {
    throw const KugouApiException('authentication', '服务未返回有效登录凭证');
  }
  final refreshCredential = credentials == null
      ? null
      : optionalText(credentials['t1']);
  final expires = credentials == null
      ? null
      : authOptionalU64(credentials['t_expire_time']);
  return MusicLoginAuthorization(
    userId: userId,
    token: credentialsToken,
    refreshCredential: _nonEmpty(refreshCredential ?? accountT1),
    expiresAtSeconds: _positive(expires ?? accountExpires),
    nickname: credentials == null
        ? accountNickname
        : optionalText(credentials['nickname']) ?? accountNickname,
    avatarUrl: credentials == null
        ? accountPic
        : optionalText(credentials['pic']) ?? accountPic,
  );
}

const int _i64Max = 9223372036854775807;

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;

int? _positive(int? value) => value != null && value > 0 ? value : null;
