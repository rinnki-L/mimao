/// 微信扫码创建端点——EchoMusicNext `crates/echo-api/src/module/login_wx_create.rs`
/// 的逐函数翻译。
///
/// 三段 provider 请求（cgi-bin/token → getticket → qrconnect），签名串为
/// `appid/noncestr/sdk_ticket/timestamp` 的 SHA1；全程 provider 主机白名单，
/// 无酷狗签名/身份。每次创建独立取票据，不做访问令牌缓存（上游注释）。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:mimao/music/api/login.dart';
import 'package:mimao/music/api/login_openplat.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/auth_models.dart';

/// 微信扫码创建（login_wx_create.rs `execute`；不需要酷狗身份）。
///
/// `timestampMs`/`random` 仅供测试注入。
Future<MusicWxSession> fetchLoginWxCreate(
  MusicSession session, {
  int? timestampMs,
  Random? random,
}) async {
  const appid = kWxLiteAppId;
  final tokenResponse = await kugouProviderRequest(
    session.client,
    method: 'GET',
    url: 'https://api.weixin.qq.com/cgi-bin/token',
    params: <String, String>{
      'appid': appid,
      'secret': kWxLiteSecret,
      'grant_type': 'client_credential',
    },
  );
  final tokenMap = wireMap(authDecodeProviderJson(tokenResponse.bytes));
  if (tokenMap == null) {
    throw const KugouApiException('decode', '微信令牌响应不是 object');
  }
  final accessToken = authRequiredScalarText(tokenMap, 'access_token');

  final ticketResponse = await kugouProviderRequest(
    session.client,
    method: 'GET',
    url: 'https://api.weixin.qq.com/cgi-bin/ticket/getticket',
    params: <String, String>{'access_token': accessToken, 'type': '2'},
  );
  final ticketMap = wireMap(authDecodeProviderJson(ticketResponse.bytes));
  if (ticketMap == null) {
    throw const KugouApiException('decode', '微信票据响应不是 object');
  }
  final ticketErrcode = requiredScalarInt(ticketMap['errcode'], 'errcode');
  if (ticketErrcode != 0) {
    throw KugouApiException('business', '请求失败', code: ticketErrcode);
  }
  final ticket = optionalText(ticketMap['ticket']);
  if (ticket == null || ticket.isEmpty) {
    throw const KugouApiException('decode', '微信 SDK 票据缺失');
  }

  final time = (timestampMs ?? DateTime.now().millisecondsSinceEpoch)
      .toString();
  // 随机数与时间戳按次生成；不做持久化票据缓存（上游注释）。
  final source = random ?? Random.secure();
  final nonce = md5.convert(_u64BigEndian(source)).toString();
  final signature = sha1
      .convert(
        utf8.encode(
          'appid=$appid&noncestr=$nonce&sdk_ticket=$ticket&timestamp=$time',
        ),
      )
      .toString();
  final response = await kugouProviderRequest(
    session.client,
    method: 'GET',
    url: 'https://open.weixin.qq.com/connect/sdk/qrconnect',
    params: <String, String>{
      'appid': appid,
      'noncestr': nonce,
      'timestamp': time,
      'scope': 'snsapi_userinfo',
      'signature': signature,
    },
  );
  return _convert(response.bytes);
}

/// wire 解析（login_wx_create.rs `convert`）。
MusicWxSession _convert(Uint8List bytes) {
  final map = wireMap(authDecodeProviderJson(bytes));
  if (map == null) {
    throw const KugouApiException('decode', '微信二维码响应不是 object');
  }
  final errcode = requiredScalarInt(map['errcode'], 'errcode');
  if (errcode != 0) {
    throw KugouApiException('business', '请求失败', code: errcode);
  }
  final key = optionalText(map['uuid']);
  if (key == null || key.isEmpty) {
    throw const KugouApiException('decode', '微信二维码会话缺失');
  }
  final qrcode = wireMap(map['qrcode']);
  if (qrcode == null) {
    throw const KugouApiException('decode', '微信二维码图片缺失');
  }
  final image = authRequiredScalarText(qrcode, 'qrcodebase64');
  return MusicWxSession(
    key: key,
    imageDataUrl: 'data:image/jpeg;base64,$image',
  );
}

/// u64 的大端 8 字节（OsRng.next_u64().to_be_bytes()）。
List<int> _u64BigEndian(Random random) {
  final high = random.nextInt(1 << 32);
  final low = random.nextInt(1 << 32);
  return <int>[
    (high >> 24) & 0xFF,
    (high >> 16) & 0xFF,
    (high >> 8) & 0xFF,
    high & 0xFF,
    (low >> 24) & 0xFF,
    (low >> 16) & 0xFF,
    (low >> 8) & 0xFF,
    low & 0xFF,
  ];
}
