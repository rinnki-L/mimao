/// 歌单库排序端点——EchoMusicNext `crates/echo-api/src/module/playlist_sort.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module）。
///
/// 库内顺序（区别于歌单内曲目顺序）。自建/收藏歌单的位置事实独立保留；
/// 返回的云歌单 id 也独立可缺省（上游注释）。传输走 `cloudlist::encrypted`。
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:mimao/music/api/playlist_add.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/playlist_write_models.dart';

/// 单个歌单的目标位置（playlist_sort.rs `Position`）。
class PlaylistSortPosition {
  const PlaylistSortPosition({
    required this.cloudListId,
    required this.kind,
    required this.position,
  });

  final int cloudListId;
  final MusicPlaylistKind kind;
  final int position;
}

/// 排序入参（playlist_sort.rs `Query`）。
class PlaylistSortQuery {
  const PlaylistSortQuery({
    required this.totalRevision,
    required this.positions,
  });

  final int totalRevision;
  final List<PlaylistSortPosition> positions;
}

/// 歌单库排序（POST /v1/modify_list_sort，cloudlist::encrypted 传输）。
Future<MusicPlaylistOrderChange> fetchPlaylistSort(
  MusicSession session,
  PlaylistSortQuery query, {
  String? seed,
  Random? random,
}) async {
  final identity = await session.ensureDevice();
  requireMusicAccount(identity); // cloudlist::account
  _validate(query);
  final data = <Object?>[
    for (final position in query.positions)
      <String, Object?>{
        'listid': position.cloudListId,
        'type': position.kind.wire,
        'sort': position.position,
      },
  ];
  final bytes = await cloudListEncrypted(
    session,
    identity,
    '/v1/modify_list_sort',
    <String, Object?>{'total_ver': query.totalRevision, 'data': data},
    seed: seed,
    random: random,
  );
  return _convertPlaylistSort(bytes);
}

/// playlist_sort.rs `validate`（顺序逐条对齐）。
void _validate(PlaylistSortQuery query) {
  if (query.positions.isEmpty) {
    throw const KugouApiException('input', '歌单排序数量无效');
  }
  final ids = <int>{};
  final kindPositions = <String>{};
  for (final position in query.positions) {
    validateCloudListId(position.cloudListId);
    final kindKey = '${position.kind.wire}:${position.position}';
    if (!ids.add(position.cloudListId) || !kindPositions.add(kindKey)) {
      throw const KugouApiException('input', '歌单排序 ID 或同类位置重复');
    }
  }
}

/// wire 解析（playlist_sort.rs `convert`：info 是数组，逐项 type→Kind）。
MusicPlaylistOrderChange _convertPlaylistSort(Uint8List bytes) {
  final data = decodeCloudListData(bytes);
  final items = wireList(data['info'], 'info');
  final positions = <MusicPlaylistOrderPosition>[];
  for (final item in items) {
    final wire = wireMap(item);
    if (wire == null) {
      throw const KugouApiException('decode', '云歌单响应 info 项不是 object');
    }
    final kindCode = optionalInt(wire['type']);
    positions.add(
      MusicPlaylistOrderPosition(
        cloudListId: optionalInt(wire['listid']),
        kind: MusicPlaylistKind.fromWire(kindCode),
        kindCode: kindCode,
        position: optionalInt(wire['sort']),
        resourceCode: optionalInt(wire['code']),
      ),
    );
  }
  return MusicPlaylistOrderChange(
    userId: optionalInt(data['userid']),
    previousTotalRevision: optionalInt(data['pre_total_ver']),
    totalRevision: optionalInt(data['total_ver']),
    playlistCount: optionalInt(data['list_count']),
    positions: positions,
  );
}
