/// 排行榜总目录端点——EchoMusicNext `crates/echo-api/src/module/rank_list.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/models/rank_models.dart';

/// /ocean/v6/rank/list（网关；plat=2 + withsong=1 + parentid=0 固定三参）。
Future<List<MusicRank>> fetchRankList(MusicSession session) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    const KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/ocean/v6/rank/list',
      method: 'GET',
      params: <String, String>{'plat': '2', 'withsong': '1', 'parentid': '0'},
    ),
  );
  return convertRankList(response.bytes);
}

/// wire 解析（rank_list.rs `convert`）：`status` + `errcode` 信封，data.info
/// 为榜单目录；条目转换在 rank_models（rank_catalog.rs `WireRank`）。
List<MusicRank> convertRankList(Uint8List bytes) {
  final envelope = decodeEnvelopeWithFields(bytes, errorCodeKey: 'errcode');
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '排行榜目录');
  final data = requiredWireMap(envelope.data, 'data');
  return wireList(data['info'], 'info').map(musicRankFromWire).toList();
}
