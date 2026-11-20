/// 云歌单曲目排序端点——EchoMusicNext
/// `crates/echo-api/src/module/playlist_tracks_sort.rs` 的翻译
/// （docs/architecture.md §4.3：`music/api/` ← module）。
///
/// 加密云协议。返回的 fileid/sort 对独立于请求顺序保留；最终展示顺序由
/// 后续读取同步（上游注释）。传输走 `cloudlist::encrypted`。
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:mimao/music/api/playlist_add.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/playlist_write_models.dart';

/// 单个文件的目标位置（playlist_tracks_sort.rs `Position`）。
class PlaylistTrackSortPosition {
  const PlaylistTrackSortPosition({
    required this.fileId,
    required this.position,
  });

  final int fileId;
  final int position;
}

/// 排序入参（playlist_tracks_sort.rs `Query`）。
class PlaylistTracksSortQuery {
  const PlaylistTracksSortQuery({
    required this.cloudListId,
    required this.revision,
    required this.positions,
  });

  final int cloudListId;
  final int revision;
  final List<PlaylistTrackSortPosition> positions;
}

/// 云歌单曲目排序（POST /v1/modify_song_sort，cloudlist::encrypted 传输）。
Future<MusicCloudTrackChange> fetchPlaylistTracksSort(
  MusicSession session,
  PlaylistTracksSortQuery query, {
  String? seed,
  Random? random,
}) async {
  final identity = await session.ensureDevice();
  requireMusicAccount(identity); // cloudlist::account
  validateCloudListId(query.cloudListId);
  _validate(query);
  final data = <Object?>[
    for (final position in query.positions)
      <String, Object?>{'fileid': position.fileId, 'sort': position.position},
  ];
  final bytes = await cloudListEncrypted(
    session,
    identity,
    '/v1/modify_song_sort',
    <String, Object?>{
      'listid': query.cloudListId,
      'list_ver': query.revision,
      'type': 0,
      'data': data,
    },
    seed: seed,
    random: random,
  );
  return _convertTracksSort(bytes);
}

/// playlist_tracks_sort.rs `validate`：列表可跨页，拒绝空输入/重复/非法 id，
/// 不设页大小上限（上游注释；execute 与测试共用）。
void _validate(PlaylistTracksSortQuery query) {
  if (query.positions.isEmpty) {
    throw const KugouApiException('input', '排序数量无效');
  }
  final ids = <int>{};
  final positions = <int>{};
  for (final position in query.positions) {
    validateCloudListId(position.fileId);
    if (!ids.add(position.fileId) || !positions.add(position.position)) {
      throw const KugouApiException('input', '排序 ID 或位置重复');
    }
  }
}

/// wire 解析（playlist_tracks_sort.rs `convert`：info 是数组）。
MusicCloudTrackChange _convertTracksSort(Uint8List bytes) {
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
        position: optionalInt(wire['sort']),
        fileId: optionalInt(wire['fileid']),
        songId: null,
        resourceCode: optionalInt(wire['code']),
      ),
    );
  }
  return MusicCloudTrackChange(
    userId: optionalInt(data['userid']),
    cloudListId: optionalInt(data['listid']),
    providerStatus: optionalInt(data['status']),
    previousRevision: optionalInt(data['pre_list_ver']),
    revision: optionalInt(data['list_ver']),
    songCount: optionalInt(data['count']),
    outcomes: outcomes,
    replacedFileIds: null,
  );
}
