/// 热搜榜端点——EchoMusicNext `crates/echo-api/src/module/search_hot.rs` 的
/// 翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 契约参考上游 fixtures/search_hot/success.json 的 hot_tab 采样。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/search_models.dart';

/// GET /api/v3/search/hot_tab（网关 + x-router=msearch.kugou.com）。
Future<List<MusicHotSearchGroup>> fetchSearchHot(MusicSession session) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/api/v3/search/hot_tab',
      router: 'msearch.kugou.com',
      method: 'GET',
      params: const <String, String>{'navid': '1', 'plat': '2'},
    ),
  );
  return _convertSearchHot(response.bytes);
}

/// wire 解析（search_hot.rs `convert`：ErrcodeEnvelope + Data.list）。
List<MusicHotSearchGroup> _convertSearchHot(Uint8List bytes) {
  // 与 search_default 同款：errcode 键的 20018 走 business，不映射 authentication。
  final envelope = decodeEnvelopeWithFields(
    bytes,
    errorCodeKey: 'errcode',
    mapAuthenticationExpired: false,
  );
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '热搜榜');
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '热搜榜响应 data 不是 object');
  }
  return wireList(data['list'], 'list').map(_convertHotGroup).toList();
}

MusicHotSearchGroup _convertHotGroup(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '热搜榜分组项不是 object');
  }
  return MusicHotSearchGroup(
    title: wireText(wire['name']),
    keywords: wireList(
      wire['keywords'],
      'keywords',
    ).map(_convertHotKeyword).toList(),
  );
}

MusicHotKeyword _convertHotKeyword(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '热搜榜关键词项不是 object');
  }
  return MusicHotKeyword(
    keyword: wireText(wire['keyword']),
    reason: wireText(wire['reason']),
    kind: optionalInt(wire['type']),
    icon: optionalInt(wire['icon']),
    jumpUrl: wireText(wire['jumpurl']),
    jsonUrl: wireText(wire['json_url']),
  );
}
