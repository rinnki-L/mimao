/// 推荐榜单端点——EchoMusicNext `crates/echo-api/src/module/rank_top.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/models/rank_models.dart';

/// /mobileservice/api/v5/rank/rec_rank_list（网关；无端点参数）。
Future<List<MusicRank>> fetchRankTop(MusicSession session) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    const KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/mobileservice/api/v5/rank/rec_rank_list',
      method: 'GET',
    ),
  );
  return convertRankTop(response.bytes);
}

/// wire 解析（rank_top.rs `convert`）：`status` + `errcode` 信封，data.list
/// 条目与 rank_list 同为 rank_catalog.rs `WireRank`。
List<MusicRank> convertRankTop(Uint8List bytes) {
  final envelope = decodeEnvelopeWithFields(bytes, errorCodeKey: 'errcode');
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '推荐榜单');
  final data = requiredWireMap(envelope.data, 'data');
  return wireList(data['list'], 'list').map(musicRankFromWire).toList();
}
