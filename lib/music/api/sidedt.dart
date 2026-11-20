/// sidedt 端点——EchoMusicNext `crates/echo-api/src/module/sidedt.rs` 的翻译
/// （docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// sidedt = 本地生成 SID/EDT 指纹（`util/generate_simulate.rs`）+ 以
/// verify_user_info 协议提交（`module/verify_user_info.rs`）。指纹是本地模拟
/// 的人类操作轨迹，不是签发的凭证（上游注释：绝不写日志）。
///
/// 两个组件在共享底座 kugou_crypto.dart 的骨架期还没有对应原语（裸 RSA 画像/
/// 显式 key+iv 的 AES/2048 位 OAEP 公钥），按规格先在本文件自包含实现；
/// 集成者后续可与 kugouUserPortrait / kugouAes256Hex 合并去重。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/search_models.dart';
import 'package:pointycastle/export.dart';

/// sidedt 输入（verify_user_info.rs `Query`）。
class MusicSideDtQuery {
  const MusicSideDtQuery({
    required this.eventId,
    required this.verifyType,
    required this.proof,
  });

  final String eventId;

  /// 只接受 23（普通验证）与 32（短信/验证码验证）。
  final int verifyType;
  final String proof;

  void validate() {
    if (eventId.trim().isEmpty ||
        eventId.length > 4096 ||
        proof.trim().isEmpty ||
        proof.length > 16384) {
      throw const KugouApiException('input', '验证事件或验证码无效');
    }
    if (verifyType != 23 && verifyType != 32) {
      throw const KugouApiException('input', '此验证类型不能提交验证码');
    }
  }
}

/// 本地指纹（generate_simulate.rs `Fingerprint`）：sid 是 RSA-OAEP 包裹的
/// AES 密钥，edt 是 AES-CBC 加密的轨迹明文。
class KugouSidedtFingerprint {
  const KugouSidedtFingerprint(this.sid, this.edt);

  final String sid;
  final String edt;
}

/// POST https://verifyservice.kugou.com/v4/verify_user_info（sidedt.rs 组装）。
///
/// `random`/`now` 仅供测试注入（确定性重放）；生产用安全随机与系统时钟。
Future<MusicSideDtAcknowledgement> fetchSideDt(
  MusicSession session,
  MusicSideDtQuery query, {
  Random? random,
  DateTime Function()? now,
}) async {
  query.validate();
  final identity = await session.ensureDevice();
  final source = random ?? Random.secure();
  final fingerprint = generateSidedtFingerprint(
    identity,
    random: source,
    now: now ?? DateTime.now,
  );
  // verify_type==32 时信封带 code，否则空对象（verify_user_info.rs）。
  final (pk, params) = kugouSidedtVerificationEnvelope(
    query.verifyType == 32
        ? <String, Object?>{'code': query.proof}
        : <String, Object?>{},
    random: source,
  );
  // serde_json 默认 Map 是 BTreeMap：请求体键按字典序输出（与 kugou_crypto
  // 注释同一约定）；body 键序进入签名覆盖的字节流，顺序不能乱。
  final body = <String, Object?>{};
  if (query.verifyType == 32) {
    body['code'] = query.proof;
  }
  body['edt'] = fingerprint.edt;
  body['eventid'] = query.eventId;
  body['i'] = '';
  body['params'] = params;
  body['pk'] = pk;
  body['platid'] = 2;
  body['sid'] = fingerprint.sid;
  body['v_type'] = query.verifyType;
  body['userid'] = identity.userId;
  if (query.verifyType != 32) {
    body['verifycode'] = query.proof;
  }
  body['wasm'] = 1;
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.verification,
      path: '/v4/verify_user_info',
      method: 'POST',
      params: const <String, String>{'clientver': '11510'},
      body: encodeJsonBody(body),
    ),
  );
  return _convertSideDt(response.bytes);
}

/// 本地指纹生成（generate_simulate.rs `generate`）。
///
/// 轨迹事件串是反爬语义的本地模拟：哨兵值 + 贝塞尔光标点，算法逐行对照上游。
KugouSidedtFingerprint generateSidedtFingerprint(
  KugouIdentity identity, {
  required Random random,
  required DateTime Function() now,
}) {
  int between(int min, int max) => min + random.nextInt(max - min + 1);
  double jitter(double scale) =>
      (random.nextInt(4294967296) / 4294967295.0 - 0.5) * scale;

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
  events.add(
    '3,$elapsed,1,${(ex + jitter(10.0)).round()},${(ey + jitter(10.0)).round()}'
    ':3,$sentinel,1,${ex.round()},${ey.round()}',
  );

  // 上游：render_fingerprint 为空时随机 u64；否则沿用身份里的渲染指纹。
  final fingerprint = identity.renderFingerprint.isEmpty
      ? _randomUint64String(random)
      : identity.renderFingerprint;
  final plaintext = sidedtFingerprintPlaintext(
    identity,
    fingerprint: fingerprint,
    events: events,
    nowMilliseconds: now().millisecondsSinceEpoch,
  );

  // AES-128 密钥 = md5(16 随机字节) 的 32 位小写 hex 的**前 16 个 ASCII 字符**，
  // IV 固定 'kugousecurity123'（generate_simulate.rs）。
  final entropy = Uint8List.fromList(
    List<int>.generate(16, (_) => random.nextInt(256)),
  );
  final digest = md5.convert(entropy).toString();
  final key = utf8.encode(digest.substring(0, 16));
  final edt = base64Encode(
    kugouSidedtAesCbcPkcs7(utf8.encode(plaintext), key, kugouSidedtAesIv),
  );
  final sid = base64Encode(_rsaOaepSha256Encrypt(key));
  return KugouSidedtFingerprint(sid, edt);
}

/// 指纹明文（generate_simulate.rs 的 format! 模板）：测试黄金对拍用。
String sidedtFingerprintPlaintext(
  KugouIdentity identity, {
  required String fingerprint,
  required List<String> events,
  required int nowMilliseconds,
}) =>
    'mid=${identity.mid};userid=${identity.userId};dfid=${identity.dfid}'
    ';webgl=$fingerprint;webdriver=0;ts=$nowMilliseconds;data=${events.join(':')}';

/// 指纹 AES 的固定 IV（上游字节常量）。
final Uint8List kugouSidedtAesIv = Uint8List.fromList(
  utf8.encode('kugousecurity123'),
);

/// AES-CBC + PKCS7（key 长度决定 AES-128/256；generate_simulate 与
/// verification_envelope 共用）。
Uint8List kugouSidedtAesCbcPkcs7(List<int> plain, List<int> key, List<int> iv) {
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
  return cipher.process(Uint8List.fromList(plain));
}

/// verification 信封（crypto.rs `verification_envelope` →
/// `parameter_envelope_with_seed(seed, None)`）：seed 是 8 随机字节的 hex。
/// 返回 (pk, params)：pk 是裸 RSA 画像 hex（小写），params 是 AES-256 hex。
(String, String) kugouSidedtVerificationEnvelope(
  Map<String, Object?> envelope, {
  required Random random,
}) {
  final seed = List<int>.generate(
    8,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return kugouSidedtVerificationEnvelopeWithSeed(envelope, seed);
}

/// 种子注入版信封（上游 `parameter_envelope_with_seed` 的 timestamp=None 分支）。
///
/// key/iv 都取 md5(seed) 的 32 位小写 hex 的 ASCII 字节（key 全 32 字节、
/// iv 取后 16 字节）；画像 `{"key":seed}` 用 lite 公钥裸 RSA 后**转小写**。
(String, String) kugouSidedtVerificationEnvelopeWithSeed(
  Map<String, Object?> envelope,
  String seed,
) {
  final digest = md5.convert(utf8.encode(seed)).toString();
  final keyBytes = Uint8List.fromList(utf8.encode(digest));
  final params = kugouSidedtAesCbcPkcs7(
    utf8.encode(jsonEncode(envelope)),
    keyBytes,
    keyBytes.sublist(16),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  final portrait = kugouSidedtRawRsaPortrait(
    utf8.encode('{"key":"$seed"}'),
  ).toLowerCase();
  return (portrait, params);
}

/// 裸 RSA 画像（crypto.rs `user_portrait`）：明文放在 128 字节大端整数高位、
/// 低位补零，modpow 后输出 256 位大写 hex。**不要**拿它做通用加密。
String kugouSidedtRawRsaPortrait(List<int> plaintext) {
  const keySize = 128;
  if (plaintext.length > keySize) {
    throw const KugouApiException('input', '账号凭证长度超出协议限制');
  }
  final padded = Uint8List(keySize)..setRange(0, plaintext.length, plaintext);
  final modulus = _bytesToBigInt(padded).modPow(_kLiteExponent, _kLiteModulus);
  return _bigIntToHex(modulus, keySize);
}

/// 2048 位验证公钥（crypto.rs include_str!("verification-public-key.pem")）
/// 拆出的参数；模数提取见 sidedt_test.dart 注释。
const String _kVerificationModulusHex =
    'a16dbe625a3c00b78f4904cfd31045945984387bc10fdb52facec30657ca12ed'
    'd1cf3bd94da5f526d61b5f8f80554aa3e80473f0833e08a072a8616f6c737f5b'
    'ae17c4d23eabbcf7e9a8c22f75532765b91bd302262b5cea819b8ab7b83507e1'
    '684ab49c2fa1c41590bc26c815f940d88b6b2d46d253bcf56c703f6be8e5426e'
    '0e5af63e20a9d3af23894cfb93d7234e5636c9f3004b2b2d83810afda4fa963e'
    '6110b46a51e4833d57c29aa3a3da49d29839619b5f78b6f91cc82a1bd9531c6d'
    '2707556ea3e50cf956f61e3fc4805ce7a2e0bebe1a225f2716dc1b8f85095544'
    'c5b86aecd2d63d1ffb57bd9db675408ab86c56fe05bb645fa05f3eaf1ed61aad';
const String _kVerificationExponentHex = '010001';

final BigInt _kVerificationModulus = BigInt.parse(
  _kVerificationModulusHex,
  radix: 16,
);
final BigInt _kVerificationExponent = BigInt.parse(
  _kVerificationExponentHex,
  radix: 16,
);

/// RSA-OAEP-SHA256（generate_simulate.rs：`Oaep::new::<Sha256>()`——hash 与
/// MGF1 同用 SHA-256），包裹 16 字节 AES 密钥。
Uint8List _rsaOaepSha256Encrypt(List<int> plain) {
  final engine = OAEPEncoding.withSHA256(RSAEngine());
  engine.init(
    true,
    PublicKeyParameter<RSAPublicKey>(
      RSAPublicKey(_kVerificationModulus, _kVerificationExponent),
    ),
  );
  return engine.process(Uint8List.fromList(plain));
}

/// verification 信封用的 lite 公钥（与 kugou_crypto.dart 的 LITE 公钥同源；
/// 那边是私有常量，此处按文件所有权约定就地复制，集成时可合并）。
const String _kLiteModulusHex =
    '00c40a2d0da76511f3bb1cc2bbd3afbd8bea83b4d6b05b6c13eb8920c53f1af7679b32ba0d'
    '0edb843240ef1b836efed3ee240734c14c1399fd6594d16af22f52525d14d72e0155c6dcc8'
    '638d4f7bb94f3a0b1f4c29f991972f2a160a25eb0a9e724336be7f69bbd319ffab1c6dd847'
    '0b021dc434f3faba89f4a2a01b33bdbdd08b';
const String _kLiteExponentHex = '010001';

final BigInt _kLiteModulus = BigInt.parse(_kLiteModulusHex, radix: 16);
final BigInt _kLiteExponent = BigInt.parse(_kLiteExponentHex, radix: 16);

/// 上游 OsRng.next_u64().to_string()：无符号 64 位整数十进制串。
String _randomUint64String(Random random) {
  final high = BigInt.from(random.nextInt(4294967296));
  final low = BigInt.from(random.nextInt(4294967296));
  return ((high << 32) | low).toString();
}

BigInt _bytesToBigInt(Uint8List bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

/// 定宽大端 hex（不足左侧补 0）。
String _bigIntToHex(BigInt value, int byteLength) {
  var text = value.toRadixString(16);
  if (text.length.isOdd) text = '0$text';
  return text.padLeft(byteLength * 2, '0').toUpperCase();
}

/// wire 解析（verify_user_info.rs `convert`）。
///
/// status 是必填 WireNumber（整数或整数字符串）；error_code/err_code/errcode
/// 是 strict_optional——提供了但读不出来必须 decode 失败，不吞成成功。
MusicSideDtAcknowledgement _convertSideDt(Uint8List bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  final root = wireMap(decoded);
  if (root == null) {
    throw const KugouApiException('decode', '验证响应不是 JSON object');
  }
  // request.rs decode 前置：根上 error_code=20018 → authentication。
  if (optionalInt(root['error_code']) == kugouErrorCodeAuthenticationExpired) {
    throw const KugouApiException('authentication', '登录已过期，请重新登录酷狗账号');
  }
  final status = _wireNumber(root['status'], 'status');
  final code = _sideDtErrorCode(root);
  if (status != 1 || code != 0) {
    throw KugouApiException('business', '验证服务返回失败', code: code);
  }
  return const MusicSideDtAcknowledgement(acknowledged: true);
}

/// verify_user_info.rs `WireNumber`：JSON 整数或 trim 后可解析的整数字符串。
int _wireNumber(Object? value, String field) {
  if (value is int) return value;
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return parsed;
  }
  throw KugouApiException('decode', '响应字段 $field 缺失或不是标量数字');
}

/// 三个错误键按序取第一个非空者；缺省/明写 null → 0（unwrap_or(0)）。
int _sideDtErrorCode(Map<String, Object?> root) {
  for (final key in const <String>['error_code', 'err_code', 'errcode']) {
    if (!root.containsKey(key)) continue;
    final value = root[key];
    if (value == null) continue;
    if (value is int) return value;
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      if (parsed != null) return parsed;
    }
    throw KugouApiException('decode', '响应字段 $key 缺失或不是标量数字');
  }
  return 0;
}
