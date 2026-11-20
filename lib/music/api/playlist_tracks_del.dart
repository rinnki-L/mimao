/// 云歌单删歌端点——EchoMusicNext
/// `crates/echo-api/src/module/playlist_tracks_del.rs` 的翻译
/// （docs/architecture.md §4.3：`music/api/` ← module）。
///
/// 文件 id 必须来自新鲜的曲目读取，不是 mixsongid/公开歌曲 id（上游注释）。
/// 传输是普通签名 request：params 为空表（只有客户端默认参数 + 签名），
/// body 是明文 JSON，router=cloudlist.service.kugou.com。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/playlist_write_models.dart';

/// 删歌入参（playlist_tracks_del.rs `Query`）。
class PlaylistTracksDelQuery {
  const PlaylistTracksDelQuery({
    required this.cloudListId,
    required this.fileIds,
  });

  final int cloudListId;
  final List<int> fileIds;
}

/// 云歌单删歌（POST /v4/delete_songs，网关 + x-router）。
Future<MusicCloudTrackChange> fetchPlaylistTracksDel(
  MusicSession session,
  PlaylistTracksDelQuery query,
) async {
  final identity = await session.ensureDevice();
  requireMusicAccount(identity); // cloudlist::account
  validateCloudListId(query.cloudListId);
  if (query.fileIds.isEmpty || query.fileIds.length > 300) {
    throw const KugouApiException('input', '删歌数量无效');
  }
  final seen = <int>{};
  for (final fileId in query.fileIds) {
    validateCloudListId(fileId);
    if (!seen.add(fileId)) {
      throw const KugouApiException('input', '文件 ID 重复');
    }
  }
  final data = <Object?>[
    for (final fileId in query.fileIds) <String, Object?>{'fileid': fileId},
  ];
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v4/delete_songs',
      router: 'cloudlist.service.kugou.com',
      method: 'POST',
      // 上游传空表：鉴权全部在默认参数与 body 里。
      params: const <String, String>{},
      body: encodeCloudListJson(<String, Object?>{
        'userid': identity.userId,
        'token': identity.token,
        'listid': query.cloudListId,
        'list_ver': 0,
        'type': 0,
        'data': data,
      }),
    ),
  );
  return _convertTracksDel(response.bytes);
}

/// wire 解析（playlist_tracks_del.rs `convert`：无 info 项，outcomes 恒 null）。
MusicCloudTrackChange _convertTracksDel(Uint8List bytes) {
  final data = decodeCloudListData(bytes);
  return MusicCloudTrackChange(
    userId: optionalInt(data['userid']),
    cloudListId: optionalInt(data['listid']),
    providerStatus: optionalInt(data['status']),
    previousRevision: optionalInt(data['pre_list_ver']),
    revision: optionalInt(data['list_ver']),
    songCount: optionalInt(data['count']),
    outcomes: null,
    replacedFileIds: null,
  );
}
