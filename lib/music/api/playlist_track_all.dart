/// 公开歌单曲目端点——EchoMusicNext `crates/echo-api/src/module/playlist_track_all.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 公开列表的 timelen 是毫秒；name 保留为传输文件名（展示标题按
/// util/playlist_song.rs 的 display 规则切分），list_info 在末页之后是 {}。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playlist_models.dart';

/// 输入（playlist_track_all.rs `Query`）。
class MusicPlaylistTrackAllQuery {
  const MusicPlaylistTrackAllQuery({
    required this.globalId,
    required this.page,
    required this.pageSize,
  });

  final String globalId;

  /// 1 起始页码。
  final int page;
  final int pageSize;

  /// 页码 0、分页不在 1..=200、global_id 为空或超 256 字符 → input。
  void validate() {
    if (page < 1 ||
        pageSize < 1 ||
        pageSize > 200 ||
        globalId.isEmpty ||
        globalId.length > 256) {
      throw const KugouApiException('input', '公开歌单或分页参数无效');
    }
  }
}

/// GET /pubsongs/v2/get_other_list_file_nofilt（网关，无 router）。
Future<MusicPage<MusicPlaylistTrack>> fetchPlaylistTrackAll(
  MusicSession session,
  MusicPlaylistTrackAllQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/pubsongs/v2/get_other_list_file_nofilt',
      method: 'GET',
      params: <String, String>{
        'area_code': '1',
        'begin_idx': ((query.page - 1) * query.pageSize).toString(),
        'plat': '1',
        'type': '1',
        'mode': '1',
        'personal_switch': '1',
        'extend_fields': 'abtags,hot_cmt,popularization',
        'pagesize': query.pageSize.toString(),
        'global_collection_id': query.globalId,
      },
    ),
  );
  return convertPlaylistTrackAll(response.bytes, query.page, query.pageSize);
}

/// wire 解析（playlist_track_all.rs `convert`）。
MusicPage<MusicPlaylistTrack> convertPlaylistTrackAll(
  Uint8List bytes,
  int page,
  int pageSize,
) {
  final envelope = decodeEnvelope(bytes);
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '歌单曲目');
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '歌单曲目响应 data 不是 object');
  }
  final count = optionalInt(data['count']);
  final songs = wireList(data['songs'], 'songs');
  return MusicPage<MusicPlaylistTrack>(
    page: page,
    pageSize: pageSize,
    total: count,
    items: <MusicPlaylistTrack>[for (final song in songs) _convertTrack(song)],
  );
}

MusicPlaylistTrack _convertTrack(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '歌单曲目行不是 object');
  }
  final name = wireText(wire['name']);
  final hash = wireText(wire['hash']);
  final singers = wireList(
    wire['singerinfo'],
    'singerinfo',
  ).map(_convertSinger).toList();
  final durationMs = optionalInt(wire['timelen']);
  final album = wireMap(wire['albuminfo']);

  final metadata = convertMusicPlaylistFacts(
    facts: MusicPlaylistTrackFacts.of(wire),
    hash: hash,
    title: name,
    durationMs: durationMs,
    singers: singers,
    // relate_goods / download 走 `optional`——整体解析失败归空表，不让行失败。
    related: _relatedList(wire['relate_goods']),
    downloads: _downloadList(wire['download']),
    paymentType: null,
    failureCode: null,
    publicationCode: null,
    accompanimentCode: optionalInt(wire['has_obbligato']),
    albumDetailsId: album == null ? null : optionalInt(album['id']),
  );
  return MusicPlaylistTrack(
    song: MusicSong(
      id: wireText(wire['mixsongid']),
      hash: hash,
      title: musicPlaylistDisplayTitle(name),
      artists: musicPlaylistDisplayArtists(name, singers),
      albumId: wireText(wire['album_id']),
      // 公开列表恒保留专辑名（空串也是 Some）。
      albumTitle: album == null ? '' : wireText(album['name']),
      durationMs: durationMs,
      coverUrl: coverUrl(wireText(wire['cover'])),
      privilege: optionalInt(wire['privilege']),
    ),
    metadata: metadata,
    fileId: optionalInt(wire['fileid']),
    sortIndex: optionalInt(wire['sort']),
    collectedAtSeconds: optionalInt(wire['collecttime']),
  );
}

MusicPlaylistSinger _convertSinger(Object? raw) {
  final map = wireMap(raw);
  if (map == null) {
    throw const KugouApiException('decode', '歌单曲目歌手行不是 object');
  }
  return MusicPlaylistSinger(
    id: optionalInt(map['id']),
    name: wireText(map['name']),
    avatar: optionalText(map['avatar']),
    publish: optionalInt(map['publish']),
  );
}

/// wire `relate_goods`（`Option<Vec<RelatedResource>>` + optional）：
/// null/非数组/含非 object 条目 → 空表。
List<MusicPlaylistRelatedResource> _relatedList(Object? value) {
  if (value is! List) return const <MusicPlaylistRelatedResource>[];
  final result = <MusicPlaylistRelatedResource>[];
  for (final item in value) {
    final map = wireMap(item);
    if (map == null) return const <MusicPlaylistRelatedResource>[];
    result.add(
      MusicPlaylistRelatedResource(
        hash: wireText(map['hash']),
        size: optionalInt(map['size']),
        bitrate: optionalInt(map['bitrate']),
        privilege: optionalInt(map['privilege']),
        level: optionalInt(map['level']),
      ),
    );
  }
  return result;
}

/// wire `download`（`Option<Vec<Download>>` + optional）：同 relate_goods 宽容。
List<MusicPlaylistDownload> _downloadList(Object? value) {
  if (value is! List) return const <MusicPlaylistDownload>[];
  final result = <MusicPlaylistDownload>[];
  for (final item in value) {
    final map = wireMap(item);
    if (map == null) return const <MusicPlaylistDownload>[];
    result.add(
      MusicPlaylistDownload(
        hash: wireText(map['hash']),
        status: optionalInt(map['status']),
        payType: optionalInt(map['pay_type']),
        failProcess: optionalInt(map['fail_process']),
      ),
    );
  }
  return result;
}
