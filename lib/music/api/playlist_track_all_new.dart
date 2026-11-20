/// 云歌单曲目端点——EchoMusicNext `crates/echo-api/src/module/playlist_track_all_new.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 账号云歌单用 listid（不是 specialid/global_collection_id）；privilege 字段
/// 是 media_privilege，与公开曲目契约彼此独立。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playlist_models.dart';

/// 输入（playlist_track_all_new.rs `Query`）。
class MusicPlaylistTrackAllNewQuery {
  const MusicPlaylistTrackAllNewQuery({
    required this.cloudListId,
    required this.page,
    required this.pageSize,
  });

  /// 账号云歌单 id（wire `listid`）。
  final int cloudListId;

  /// 1 起始页码。
  final int page;
  final int pageSize;

  /// cloud_list_id=0、页码 0、分页不在 1..=300 → input。
  void validate() {
    if (cloudListId == 0 || page < 1 || pageSize < 1 || pageSize > 300) {
      throw const KugouApiException('input', '云歌单分页参数无效');
    }
  }
}

/// POST /v4/get_list_all_file_v3（网关 + x-router=cloudlist.service.kugou.com）。
/// 必须账号：匿名直接 authentication（上游 execute 的 identity 前置校验）。
Future<MusicCloudPlaylistTracks> fetchPlaylistTrackAllNew(
  MusicSession session,
  MusicPlaylistTrackAllNewQuery query,
) async {
  final identity = await session.ensureDevice();
  requireMusicAccount(identity);
  query.validate();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v4/get_list_all_file_v3',
      router: 'cloudlist.service.kugou.com',
      method: 'POST',
      body: encodeJsonBody(<String, Object?>{
        'listid': query.cloudListId,
        'userid': identity.userId,
        'type': 0,
        'page': query.page,
        'pagesize': query.pageSize,
        'area_code': 1,
        'allplatform': 1,
        'show_cover': 1,
        'token': identity.token,
      }),
    ),
  );
  return convertPlaylistTrackAllNew(response.bytes);
}

/// wire 解析（playlist_track_all_new.rs `convert`）。
MusicCloudPlaylistTracks convertPlaylistTrackAllNew(Uint8List bytes) {
  final envelope = decodeEnvelope(bytes);
  // 云歌单的专属过期码：status!=1 且 error_code=20017 → authentication。
  if (envelope.status != 1 && envelope.errorCode == 20017) {
    throw const KugouApiException(
      'authentication',
      '账号认证无效，请重新登录',
      code: 20017,
    );
  }
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '云歌单');
  final data = requiredWireMap(envelope.data, '云歌单响应 data');
  // info 缺省（null）→ 空表；非数组（含空 object）→ decode。
  final info = data['info'];
  final List<Object?> songs;
  if (info == null) {
    songs = const <Object?>[];
  } else if (info is List) {
    songs = info;
  } else {
    throw const KugouApiException('decode', '云歌单响应 info 不是数组');
  }
  final items = <MusicPlaylistTrack>[];
  for (var row = 0; row < songs.length; row++) {
    items.add(_convertTrack(songs[row], row));
  }
  return MusicCloudPlaylistTracks(
    page: MusicPage<MusicPlaylistTrack>(
      page: optionalInt(data['page']),
      pageSize: optionalInt(data['pagesize']),
      total: optionalInt(data['count']),
      items: items,
    ),
    userId: optionalInt(data['userid']),
    cloudListId: optionalInt(data['listid']),
    revision: optionalInt(data['list_ver']),
  );
}

/// 单行解析（playlist_track_all_new.rs 的 request::decode_value Song 分支；
/// 行级失败带「云歌单第 N 首」前缀）。
MusicPlaylistTrack _convertTrack(Object? raw, int row) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw KugouApiException('decode', '云歌单第${row + 1}首：条目不是 object');
  }
  final name = wireText(wire['name']);
  final hash = wireText(wire['hash']);
  final List<MusicPlaylistSinger> singers;
  try {
    singers = wireList(
      wire['singerinfo'],
      'singerinfo',
    ).map(_convertSinger).toList();
  } on KugouApiException catch (error) {
    throw KugouApiException('decode', '云歌单第${row + 1}首：${error.message}');
  }
  final durationMs = optionalInt(wire['timelen']);
  final album = wireMap(wire['albuminfo']);

  final metadata = convertMusicPlaylistFacts(
    facts: MusicPlaylistTrackFacts.of(wire),
    hash: hash,
    title: name,
    durationMs: durationMs,
    singers: singers,
    related: const <MusicPlaylistRelatedResource>[],
    downloads: const <MusicPlaylistDownload>[],
    paymentType: optionalInt(wire['media_pay_type']),
    failureCode: optionalInt(wire['media_fail_process']),
    publicationCode: optionalInt(wire['is_publish']),
    accompanimentCode: null,
    albumDetailsId: album == null ? null : optionalInt(album['id']),
  );
  return MusicPlaylistTrack(
    song: MusicSong(
      id: wireText(wire['mixsongid']),
      hash: hash,
      title: musicPlaylistDisplayTitle(name),
      artists: musicPlaylistDisplayArtists(name, singers),
      // 主专辑 id 与空 albuminfo 可以并存——独立身份字段原样保留。
      albumId: wireText(wire['album_id']),
      albumTitle: album == null ? '' : wireText(album['name']),
      durationMs: durationMs,
      coverUrl: coverUrl(wireText(wire['cover'])),
      privilege: optionalInt(wire['media_privilege']),
    ),
    metadata: metadata,
    fileId: optionalInt(wire['fileid']),
    sortIndex: optionalInt(wire['sort']),
    fileSortIndex: optionalInt(wire['fsort']),
    collectedAtSeconds: optionalInt(wire['collecttime']),
  );
}

MusicPlaylistSinger _convertSinger(Object? raw) {
  final map = wireMap(raw);
  if (map == null) {
    throw const KugouApiException('decode', '云歌单歌手行不是 object');
  }
  return MusicPlaylistSinger(
    id: optionalInt(map['id']),
    name: wireText(map['name']),
    avatar: optionalText(map['avatar']),
    publish: optionalInt(map['publish']),
  );
}
