/// 验证码提交端点——EchoMusicNext `crates/echo-api/src/module/verify_user_info.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 内部 /sidedt 确认回执：**不授予账号授权**；`data.msg` 只是描述文案，
/// 不是验收条件。SID/EDT 是本地模拟的协议指纹（util/generate_simulate.rs），
/// 不是服务端签发的凭证，也绝不写日志。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:pointycastle/export.dart';

/// 验证码提交请求（verify_user_info.rs `Query`）。
class MusicVerifyUserInfoQuery {
  const MusicVerifyUserInfoQuery({
    required this.eventId,
    required this.verifyType,
    required this.proof,
  });

  /// 服务端下发的验证事件 id（trim 后非空，字节长度 ≤4096）。
  final String eventId;

  /// 只允许 23/32（其它验证类型不走本地提交）。
  final int verifyType;

  /// 用户输入的验证码（trim 后非空，字节长度 ≤16384）。
  final String proof;

  void validate() {
    if (eventId.trim().isEmpty ||
        utf8.encode(eventId).length > 4096 ||
        proof.trim().isEmpty ||
        utf8.encode(proof).length > 16384) {
      throw const KugouApiException('input', '验证事件或验证码无效');
    }
    if (verifyType != 23 && verifyType != 32) {
      throw const KugouApiException('input', '此验证类型不能提交验证码');
    }
  }
}

/// POST /v4/verify_user_info（verifyservice.kugou.com；匿名身份也可提交）。
///
/// `fingerprint` 缺省时本地生成（util/generate_simulate.rs）；`seed`/`random`/
/// `now` 仅供测试注入，生产走系统熵与时钟。
Future<MusicVerifyAcknowledgement> fetchVerifyUserInfo(
  MusicSession session,
  MusicVerifyUserInfoQuery query, {
  MusicVerifyFingerprint? fingerprint,
  String? seed,
  Random? random,
  DateTime Function()? now,
}) async {
  query.validate();
  final identity = await session.ensureDevice();
  final actualFingerprint =
      fingerprint ??
      kugouGenerateVerifyFingerprint(identity, random: random, now: now);
  // verify_type=32 才把验证码放进加密 envelope；23 的 envelope 是空对象。
  final envelope = query.verifyType == 32
      ? <String, Object?>{'code': query.proof}
      : <String, Object?>{};
  final verification = kugouVerificationEnvelope(
    envelope,
    seed: seed,
    random: random,
  );
  final body = encodeJsonBody(<String, Object?>{
    // Rust json! 宏经 BTreeMap 序列化：键按字典序输出（'u' < 'v'：
    // code 在最前，verifycode 在 userid 与 wasm 之间）。
    if (query.verifyType == 32) 'code': query.proof,
    'edt': actualFingerprint.edt,
    'eventid': query.eventId,
    'i': '',
    'params': verification.params,
    'pk': verification.portrait,
    'platid': 2,
    'sid': actualFingerprint.sid,
    'v_type': query.verifyType,
    'userid': identity.userId,
    if (query.verifyType != 32) 'verifycode': query.proof,
    'wasm': 1,
  });
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.verification,
      path: '/v4/verify_user_info',
      method: 'POST',
      params: <String, String>{'clientver': '11510'},
      body: body,
    ),
  );
  return _convertVerifyAcknowledgement(response.bytes);
}

/// wire 解析（verify_user_info.rs `convert`）。
///
/// status 可为数字或数字字符串；error_code/err_code/errcode 三键回退，且
/// 「存在但不可读」必须 decode 失败（strict_optional），不能静默当成功。
MusicVerifyAcknowledgement _convertVerifyAcknowledgement(Uint8List bytes) {
  final root = _decodeVerifyRoot(bytes);
  if (!root.containsKey('status')) {
    throw const KugouApiException('decode', '验证回执缺少 status');
  }
  final status = _strictWireNumber(root['status'], 'status');
  var code = 0;
  for (final key in const <String>['error_code', 'err_code', 'errcode']) {
    final raw = root[key];
    if (raw == null) continue;
    code = _strictWireNumber(raw, key);
    break;
  }
  // 参考实现：status=1 且无非零错误码即恢复原请求；data.msg 不参与判定。
  if (status != 1 || code != 0) {
    throw KugouApiException('business', '请求失败', code: code);
  }
  return const MusicVerifyAcknowledgement(acknowledged: true);
}

/// verify_user_info 的响应信封没有必填 error_code（三键可选），不能用共享
/// decodeEnvelope；这里只保留 request::decode 的公共语义：JSON object +
/// 登录过期（error_code==20018 / msg 文本）先行判定。
Map<String, Object?> _decodeVerifyRoot(Uint8List bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  if (decoded is! Map) {
    throw const KugouApiException('decode', '验证回执响应不是 JSON object');
  }
  final message = decoded['msg'];
  final expiredMessage = message is String && message.contains('登录已过期');
  if (expiredMessage ||
      optionalInt(decoded['error_code']) ==
          kugouErrorCodeAuthenticationExpired) {
    throw const KugouApiException('authentication', '登录已过期，请重新登录酷狗账号');
  }
  return Map<String, Object?>.from(decoded);
}

/// verify_user_info.rs `WireNumber::integer`：整数原样；文本 trim 后按 i64
/// 解析；其它（浮点/bool/复合）→ decode（untagged 两分支都失败）。
int _strictWireNumber(Object? value, String field) {
  if (value is int) return value;
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return parsed;
  }
  throw KugouApiException('decode', '响应字段 $field 不是合法状态数字');
}

/// SID/EDT 协议指纹（generate_simulate.rs `Fingerprint`）。SID 是 AES 密钥
/// 的 OAEP 密文，EDT 是行为序列的 AES 密文；内容为本地模拟，不是凭证。
class MusicVerifyFingerprint {
  const MusicVerifyFingerprint({required this.sid, required this.edt});

  final String sid;
  final String edt;
}

/// generate_simulate.rs `aes_cbc` 的原语：AES-128-CBC + PKCS7 → base64。
/// 公开为协议原语，测试用它对拍上游 AES 黄金向量。
String kugouSimulateAesCbcBase64(
  List<int> plaintext,
  List<int> key,
  List<int> iv,
) {
  final cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    CBCBlockCipher(AESEngine()),
  );
  cipher.init(
    true,
    PaddedBlockCipherParameters<CipherParameters?, CipherParameters?>(
      ParametersWithIV<KeyParameter>(
        KeyParameter(Uint8List.fromList(key)),
        Uint8List.fromList(iv),
      ),
      null,
    ),
  );
  return base64Encode(cipher.process(Uint8List.fromList(plaintext)));
}

/// OAEP-SHA256 加密（generate_simulate.rs 的 SID 半边；与 Rust
/// `Oaep::new::<Sha256>()` 同参：编码哈希与 MGF1 都用 SHA-256）。
/// 公开为原语，测试用临时 RSA 密钥对做可解性回环。
Uint8List kugouVerifyOaepSha256Encrypt(
  List<int> plaintext,
  RSAPublicKey publicKey,
) {
  final cipher = OAEPEncoding.withSHA256(RSAEngine());
  cipher.init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
  return cipher.process(Uint8List.fromList(plaintext));
}

/// verification 公钥（util/verification-public-key.pem）拆出的参数：
/// 2048-bit 模数；e = 0x010001（65537）。
const String _kVerificationModulusHex =
    'a16dbe625a3c00b78f4904cfd31045945984387bc10fdb52facec30657ca12edd1cf3bd94d'
    'a5f526d61b5f8f80554aa3e80473f0833e08a072a8616f6c737f5bae17c4d23eabbcf7e9a'
    '8c22f75532765b91bd302262b5cea819b8ab7b83507e1684ab49c2fa1c41590bc26c815f9'
    '40d88b6b2d46d253bcf56c703f6be8e5426e0e5af63e20a9d3af23894cfb93d7234e5636c'
    '9f3004b2b2d83810afda4fa963e6110b46a51e4833d57c29aa3a3da49d29839619b5f78b6'
    'f91cc82a1bd9531c6d2707556ea3e50cf956f61e3fc4805ce7a2e0bebe1a225f2716dc1b8'
    'f85095544c5b86aecd2d63d1ffb57bd9db675408ab86c56fe05bb645fa05f3eaf1ed61aad';
const String _kVerificationExponentHex = '010001';

final BigInt _verificationModulus = BigInt.parse(
  _kVerificationModulusHex,
  radix: 16,
);
final BigInt _verificationExponent = BigInt.parse(
  _kVerificationExponentHex,
  radix: 16,
);
final RSAPublicKey _verificationPublicKey = RSAPublicKey(
  _verificationModulus,
  _verificationExponent,
);

/// 本地生成 SID/EDT（generate_simulate.rs `generate`）：行为事件序列 →
/// 明文 `mid=…;userid=…;dfid=…;webgl=…;webdriver=0;ts=…;data=…` →
/// AES-128-CBC（key=md5(16 随机字节) hex 前 16、iv="kugousecurity123"）为
/// EDT；同一 key 经 OAEP-SHA256(verification 公钥) 为 SID。
MusicVerifyFingerprint kugouGenerateVerifyFingerprint(
  KugouIdentity identity, {
  Random? random,
  DateTime Function()? now,
}) {
  final source = random ?? Random.secure();
  // OsRng.next_u32 的等价来源；两次 16 位组合保证 VM/Web 一致。
  int nextU32() => (source.nextInt(1 << 16) << 16) | source.nextInt(1 << 16);
  int between(int min, int max) => min + nextU32() % (max - min + 1);
  double jitter(double scale) => (nextU32() / 4294967295.0 - 0.5) * scale;

  final sentinel = 4294967295 - between(0, 19);
  final events = <String>['5,0,0:5,$sentinel,0:5,0,0:5,$sentinel,0'];
  var elapsed = between(5, 20);
  var index = 0;
  events.add('6,$elapsed,$index,750,500:6,$sentinel,$index,750,500');
  index += 1;
  for (var round = 0; round < 3; round++) {
    elapsed += between(80, 600);
    events.add('5,$elapsed,$index:5,$sentinel,$index');
    index += 1;
  }
  final points = between(30, 60);
  final sx = between(200, 600).toDouble();
  final sy = between(200, 500).toDouble();
  final ex = between(500, 700).toDouble();
  final ey = between(80, 150).toDouble();
  final c1x = sx + (ex - sx) * 0.3 + jitter(160.0);
  final c1y = sy + (ey - sy) * 0.2 + jitter(120.0);
  final c2x = sx + (ex - sx) * 0.7 + jitter(120.0);
  final c2y = sy + (ey - sy) * 0.8 + jitter(80.0);
  for (var i = 0; i <= points; i++) {
    final t = i / points;
    final u = 1.0 - t;
    final scale = max(3.0 - t * 2.5, 0.5);
    // Rust f64 Display 对整值浮点输出不带小数点；round() 后直接按整数格式化。
    final x =
        (u * u * u * sx +
                3.0 * u * u * t * c1x +
                3.0 * u * t * t * c2x +
                t * t * t * ex +
                jitter(scale))
            .round();
    final y =
        (u * u * u * sy +
                3.0 * u * u * t * c1y +
                3.0 * u * t * t * c2y +
                t * t * t * ey +
                jitter(scale))
            .round();
    elapsed += between(8, 50);
    final subindex = i % 2;
    events.add('3,$elapsed,$subindex,$x,$y:3,$sentinel,$subindex,$x,$y');
    if (i > 0 && i % 12 == 0) {
      elapsed += between(20, 60);
      events.add('5,$elapsed,$index:5,$sentinel,$index');
      index += 1;
    }
  }
  elapsed += between(5, 30);
  final endX = (ex + jitter(10.0)).round();
  final endY = (ey + jitter(10.0)).round();
  events.add(
    '3,$elapsed,1,$endX,$endY:3,$sentinel,1,${ex.round()},${ey.round()}',
  );

  // render_fingerprint 缺省 → 随机 u64 的十进制串（保持无符号位宽）。
  final fingerprint = identity.renderFingerprint.isEmpty
      ? ((BigInt.from(nextU32()) << 32) | BigInt.from(nextU32())).toString()
      : identity.renderFingerprint;
  final timestampMs = (now?.call() ?? DateTime.now()).millisecondsSinceEpoch;
  final plaintext =
      'mid=${identity.mid};userid=${identity.userId};dfid=${identity.dfid};'
      'webgl=$fingerprint;webdriver=0;ts=$timestampMs;data=${events.join(':')}';

  final entropy = Uint8List.fromList(
    List<int>.generate(16, (_) => source.nextInt(256)),
  );
  final digest = md5.convert(entropy).toString();
  final key = utf8.encode(digest.substring(0, 16));
  final edt = kugouSimulateAesCbcBase64(
    utf8.encode(plaintext),
    key,
    utf8.encode('kugousecurity123'),
  );
  final sid = base64Encode(
    kugouVerifyOaepSha256Encrypt(key, _verificationPublicKey),
  );
  return MusicVerifyFingerprint(sid: sid, edt: edt);
}
