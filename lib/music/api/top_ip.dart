/// IP 榜单端点——EchoMusicNext `crates/echo-api/src/module/top_ip.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 列表条目保留供给方身份；只有歌单条目（type==1）可导航，任意深链与
/// web URL 不暴露（上游模块头注释）。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/rank_models.dart';

/// POST /v1/daily_recommend（网关 + x-router=musicadservice.kugou.com；
/// 固定 clientver=12349 / area_code=1 / body {"tags":{}}）。
Future<List<MusicRankPlaylistCard>> fetchTopIps(MusicSession session) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v1/daily_recommend',
      router: 'musicadservice.kugou.com',
      method: 'POST',
      params: const <String, String>{'clientver': '12349', 'area_code': '1'},
      body: encodeJsonBody(const <String, Object?>{
        'tags': <String, Object?>{},
      }),
    ),
  );
  return convertTopIps(response.bytes);
}

/// wire 解析（top_ip.rs `convert`）：`status` + `errcode` 信封；list 先按
/// kind==1 过滤再转卡片，卡片结构复用 top_playlist.rs 的 PlaylistCard。
List<MusicRankPlaylistCard> convertTopIps(Uint8List bytes) {
  final envelope = decodeEnvelopeWithFields(bytes, errorCodeKey: 'errcode');
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: 'IP 榜单');
  final data = requiredWireMap(envelope.data, 'data');
  return wireList(
    data['list'],
    'list',
  ).map(_item).whereType<MusicRankPlaylistCard>().toList();
}

/// 条目转换：非歌单条目（type != 1）按上游 filter 直接丢弃。
MusicRankPlaylistCard? _item(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', 'IP 榜单条目不是 object');
  }
  final kind = optionalInt(wire['type']);
  if (kind != 1) {
    return null;
  }
  final extra = wireMap(wire['extra']) ?? const <String, Object?>{};
  return MusicRankPlaylistCard(
    id: optionalText(extra['global_collection_id']) ?? '',
    title: wireText(wire['title']),
    creator: '',
    coverUrl: coverUrl(wireText(wire['sizable_image_url'])),
    metadata: MusicRankPlaylistMetadata(
      publicId: optionalInt(extra['specialid']),
      alternateGlobalId: optionalText(extra['global_special_id']),
      creatorId: optionalInt(extra['suid']),
      playCount: optionalInt(extra['play_count']),
      kindCode: kind,
    ),
  );
}
