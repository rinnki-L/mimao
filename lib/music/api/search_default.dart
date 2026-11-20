/// 默认搜索词端点——EchoMusicNext `crates/echo-api/src/module/search_default.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 采样结构：推广位（ads）+ 未建模的 fallback 扩展。上游注释：非空 fallback
/// 尚未采样建模，**绝不**把它重新解读成搜索词。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/search_models.dart';

/// POST /searchnofocus/v1/search_no_focus_word（网关；无 x-router）。
///
/// 请求体是上游 execute 里 `format!` 拼出的**精确字节**（键序/间距原样）：
/// Android 签名覆盖的就是这些字节，不能换成 jsonEncode 重排。
String kugouSearchDefaultBody(int userId) =>
    '{"plat":0,"userid":$userId,"tags":"{}","vip_type":65530,"m_type":0,'
    '"own_ads":{},"ability":"3","sources":[],"bitmap":2,"mode":"normal"}';

/// 默认搜索词（无输入参数）。
Future<MusicSearchDefault> fetchSearchDefault(MusicSession session) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/searchnofocus/v1/search_no_focus_word',
      method: 'POST',
      params: const <String, String>{'clientver': '12329'},
      body: utf8.encode(kugouSearchDefaultBody(identity.userId)),
    ),
  );
  return _convertSearchDefault(response.bytes);
}

/// wire 解析（search_default.rs `convert`：ErrcodeEnvelope + Data）。
MusicSearchDefault _convertSearchDefault(Uint8List bytes) {
  // ErrcodeEnvelope 用 errcode 键；request.rs authentication_expiration 只认
  // 根上的 error_code——本端点的 20018 走 business，不映射 authentication。
  final envelope = decodeEnvelopeWithFields(
    bytes,
    errorCodeKey: 'errcode',
    mapAuthenticationExpired: false,
  );
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '默认搜索词');
  // Data 结构体从 Null/非 object 解码都失败（Rust from_value → decode）。
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '默认搜索词响应 data 不是 object');
  }
  final promotions = wireList(
    data['ads'],
    'ads',
  ).map(_convertPromotion).toList();
  return MusicSearchDefault(
    promotions: promotions,
    // optional<Value>：null/缺省 → null；其余原样保留。
    fallbackExtension: data['fallback'],
  );
}

MusicSearchPromotion _convertPromotion(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '默认搜索词广告项不是 object');
  }
  return MusicSearchPromotion(
    id: optionalInt(wire['id']),
    title: wireText(wire['title']),
    mainTitle: wireText(wire['main_title']),
    subtitle: wireText(wire['sub_title']),
    jumpType: wireText(wire['jumpType']),
    encodedDestination: wireText(wire['unifiedUrl']),
  );
}
