/// 云歌单加歌端点——EchoMusicNext
/// `crates/echo-api/src/module/playlist_tracks_add.rs` 的翻译
/// （docs/architecture.md §4.3：`music/api/` ← module）。
///
/// 顶层成功也可能内嵌逐项 code=206/fileid=0。重复加歌会替换文件 id：
/// 保留 del_fileids 事实，绝不自动重放本次写（上游注释）。
/// 传输是普通签名 request + `cloudlist::write_params`，body 明文 JSON。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/playlist_add.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/playlist_write_models.dart';

/// 待加入的单曲（playlist_tracks_add.rs `Track`）。
class PlaylistTrackInput {
  const PlaylistTrackInput({
    required this.title,
    required this.hash,
    required this.albumId,
    required this.songId,
  });

  final String title;

  /// 32 位 hex（大小写原样上送）。
  final String hash;
  final int albumId;
  final int songId;
}

/// 加歌入参（playlist_tracks_add.rs `Query`）。
class PlaylistTracksAddQuery {
  const PlaylistTracksAddQuery({
    required this.cloudListId,
    required this.tracks,
  });

  final int cloudListId;
  final List<PlaylistTrackInput> tracks;
}

/// 云歌单加歌（POST /cloudlist.service/v6/add_song，网关无 router）。
Future<MusicCloudTrackChange> fetchPlaylistTracksAdd(
  MusicSession session,
  PlaylistTracksAddQuery query,
) async {
  final identity = await session.ensureDevice();
  requireMusicAccount(identity); // cloudlist::account
  validateCloudListId(query.cloudListId);
  if (query.tracks.isEmpty || query.tracks.length > 300) {
    throw const KugouApiException('input', '加歌数量无效');
  }
  final data = <Object?>[];
  for (final track in query.tracks) {
    validateCloudListText(track.title, 4096, allowEmpty: false);
    if (track.hash.length != 32 || !_isAsciiHex(track.hash)) {
      throw const KugouApiException('input', '歌曲 hash 无效');
    }
    data.add(<String, Object?>{
      'number': 1,
      'name': track.title,
      'hash': track.hash,
      'size': 0,
      'sort': 0,
      'timelen': 0,
      'bitrate': 0,
      'album_id': track.albumId,
      'mixsongid': track.songId,
    });
  }
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/cloudlist.service/v6/add_song',
      method: 'POST',
      params: cloudListWriteParams(
        identity,
        cloudListUnixSeconds(session.client),
      ),
      body: encodeCloudListJson(<String, Object?>{
        'userid': identity.userId,
        'token': identity.token,
        'listid': query.cloudListId,
        'list_ver': 0,
        'type': 0,
        'slow_upload': 1,
        'scene': 'false;null',
        'data': data,
      }),
    ),
  );
  return _convertTracksAdd(response.bytes);
}

bool _isAsciiHex(String value) {
  for (final code in value.codeUnits) {
    final isDigit = code >= 0x30 && code <= 0x39;
    final isLower = code >= 0x61 && code <= 0x66;
    final isUpper = code >= 0x41 && code <= 0x46;
    if (!isDigit && !isLower && !isUpper) {
      return false;
    }
  }
  return true;
}

/// wire 解析（playlist_tracks_add.rs `convert`）。嵌套 status 不是第二重
/// 错误码：原样保留，不设固定值门槛（上游注释）；逐项 code 交给调用方。
MusicCloudTrackChange _convertTracksAdd(Uint8List bytes) {
  final data = decodeCloudListData(bytes);
  final items = wireList(data['info'], 'info');
  final outcomes = <MusicTrackWriteOutcome>[];
  for (final item in items) {
    final wire = wireMap(item);
    if (wire == null) {
      throw const KugouApiException('decode', '云歌单响应 info 项不是 object');
    }
    outcomes.add(
      MusicTrackWriteOutcome(
        position: null,
        fileId: optionalInt(wire['fileid']),
        songId: optionalInt(wire['mixsongid']),
        resourceCode: optionalInt(wire['code']),
      ),
    );
  }
  // del_fileids 是原始 Value：数组 → 逐项 u64（不可解析项为 null）；
  // 其它形态 → null（替换元数据缺省是未知，绝不是失败——上游注释）。
  final rawReplaced = data['del_fileids'];
  List<int?>? replaced;
  if (rawReplaced is List) {
    replaced = <int?>[for (final id in rawReplaced) optionalInt(id)];
  }
  return MusicCloudTrackChange(
    userId: optionalInt(data['userid']),
    cloudListId: optionalInt(data['listid']),
    providerStatus: optionalInt(data['status']),
    previousRevision: optionalInt(data['pre_list_ver']),
    revision: optionalInt(data['list_ver']),
    songCount: optionalInt(data['count']),
    outcomes: outcomes,
    replacedFileIds: replaced,
  );
}
