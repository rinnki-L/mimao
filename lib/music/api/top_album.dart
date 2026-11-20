/// 新碟榜单端点——EchoMusicNext `crates/echo-api/src/module/top_album.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 一次请求带回全部地区分组（chn/eur/jpn/kor），由应用本地选择地区
/// （上游模块头注释）。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/rank_models.dart';

/// POST /musicadservice/v1/mobile_newalbum_sp（网关；token 写进 body）。
Future<MusicTopAlbums> fetchTopAlbums(MusicSession session) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/musicadservice/v1/mobile_newalbum_sp',
      method: 'POST',
      body: encodeJsonBody(<String, Object?>{
        'apiver': 20,
        'token': identity.token,
        'page': 1,
        'pagesize': 30,
        'withpriv': 1,
      }),
    ),
  );
  return convertTopAlbums(response.bytes);
}

/// wire 解析（top_album.rs `convert`）：`status` + `error_code` 信封。
MusicTopAlbums convertTopAlbums(Uint8List bytes) {
  final envelope = decodeEnvelopeWithFields(bytes);
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '新碟榜单');
  final data = requiredWireMap(envelope.data, 'data');
  final regions = <String, List<MusicTopAlbumCard>>{};
  // BTreeMap 顺序即字典序：chn/eur/jpn/kor。
  for (final key in const <String>['chn', 'eur', 'jpn', 'kor']) {
    regions[key] = wireList(data[key], key).map(_album).toList();
  }
  return MusicTopAlbums(
    regions: regions,
    timestamp: optionalInt(data['timestamp']),
  );
}

/// 专辑条目（top_album.rs `Album`）：albumid 必填标量、trans_param 必填
/// 结构——缺省/不可解析都按 decode 失败（上游无 default）。
MusicTopAlbumCard _album(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '新碟条目不是 object');
  }
  final albumId = optionalInt(wire['albumid']);
  if (albumId == null) {
    throw const KugouApiException('decode', '响应字段 albumid 缺失或不是标量数字');
  }
  final trans = wireMap(wire['trans_param']);
  if (trans == null) {
    throw const KugouApiException('decode', '响应字段 trans_param 不是 object');
  }
  return MusicTopAlbumCard(
    id: '$albumId',
    title: wireText(wire['albumname']),
    creator: wireText(wire['singername']),
    coverUrl: coverUrl(wireText(wire['imgurl'])),
    songCount: optionalInt(wire['songcount']),
    publishedAt: wireText(wire['publishtime']),
    metadata: MusicTopAlbumMetadata(
      artistId: optionalInt(wire['singerid']),
      advertisementId: optionalInt(wire['ad_id']),
      description: wireText(wire['intro']),
      firstReleaseCode: optionalInt(wire['isfirst']),
      privilege: optionalInt(wire['privilege']),
      qualityCode: optionalInt(wire['quality']),
      specialTag: wireText(trans['special_tag']),
    ),
  );
}
