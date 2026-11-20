/// 微信扫码轮询端点——EchoMusicNext `crates/echo-api/src/module/login_wx_check.rs`
/// 的逐函数翻译。
///
/// 长轮询（上游建议响应超时 45 秒，节奏由调用方控制）；状态码 408/404/402/403/
/// 405 之外一律 provider 失败；provider_code 只在授权码非空且有界时成立。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/login.dart';
import 'package:mimao/music/api/login_openplat.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/auth_models.dart';

/// 微信扫码轮询（login_wx_check.rs `execute`；不需要酷狗身份）。
Future<MusicWxCheckResult> fetchLoginWxCheck(
  MusicSession session,
  String key,
) async {
  if (key.isEmpty || utf8.encode(key).length > 256) {
    throw const KugouApiException('input', '微信二维码会话无效');
  }
  final response = await kugouProviderRequest(
    session.client,
    method: 'GET',
    url: 'https://long.open.weixin.qq.com/connect/l/qrconnect',
    params: <String, String>{'f': 'json', 'uuid': key},
  );
  return _convert(response.bytes);
}

/// wire 解析（login_wx_check.rs `convert`）。
MusicWxCheckResult _convert(Uint8List bytes) {
  final map = wireMap(authDecodeProviderJson(bytes));
  if (map == null) {
    throw const KugouApiException('decode', '微信扫码状态响应不是 object');
  }
  final errcode = requiredScalarInt(map['wx_errcode'], 'wx_errcode');
  final code = wireText(map['wx_code']);
  final String state;
  switch (errcode) {
    case 408:
      state = MusicWxCheckResult.stateWaiting;
    case 404:
      state = MusicWxCheckResult.stateScanned;
    case 402 || 403:
      state = MusicWxCheckResult.stateExpired;
    case 405 when code.isNotEmpty && utf8.encode(code).length <= 4096:
      state = MusicWxCheckResult.stateProviderCode;
    default:
      throw const KugouApiException('provider', '微信扫码状态异常，请重新获取二维码');
  }
  return MusicWxCheckResult(
    state: state,
    code: state == MusicWxCheckResult.stateProviderCode ? code : null,
  );
}
