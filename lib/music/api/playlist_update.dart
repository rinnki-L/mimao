/// 歌单编辑端点——EchoMusicNext `crates/echo-api/src/module/playlist_update.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module）。
///
/// 账号本地元数据编辑（含服务端观察到的自定义封面引用）。省略
/// cover_reference 即保留服务端封面；空串/路径/URL 猜测一律拒绝（上游注释）。
/// 传输走 `cloudlist::encrypted`（AES-128 信封 + cloud 模式）。
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:mimao/music/api/playlist_add.dart';
import 'package:mimao/music/api/playlist_pic_upload.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/playlist_write_models.dart';

/// 编辑入参（playlist_update.rs `Query`；kind 缺省 Owned）。
class PlaylistUpdateQuery {
  const PlaylistUpdateQuery({
    required this.cloudListId,
    this.kind = MusicPlaylistKind.owned,
    required this.totalRevision,
    required this.sortIndex,
    this.title,
    required this.description,
    required this.tags,
    this.coverReference,
  });

  final int cloudListId;
  final MusicPlaylistKind kind;
  final int totalRevision;
  final int sortIndex;

  /// 缺省时不写 name（保留服务端标题）。
  final String? title;
  final String description;
  final String tags;

  /// `custom/<file_name>` 形态；缺省保留服务端封面。
  final String? coverReference;
}

/// 编辑歌单（POST /v1/modify_list，cloudlist::encrypted 传输）。
Future<MusicPlaylistChange> fetchPlaylistUpdate(
  MusicSession session,
  PlaylistUpdateQuery query, {
  String? seed,
  Random? random,
}) async {
  final identity = await session.ensureDevice();
  requireMusicAccount(identity); // cloudlist::account
  validatePlaylistUpdateQuery(query);
  final body = <String, Object?>{
    'listid': query.cloudListId,
    'total_ver': query.totalRevision,
    'type': query.kind.wire,
    'sort': query.sortIndex,
    'intro': query.description,
    'tags': query.tags,
  };
  if (query.title != null) {
    body['name'] = query.title!;
  }
  if (query.coverReference != null) {
    body['pic'] = query.coverReference!;
  }
  final bytes = await cloudListEncrypted(
    session,
    identity,
    '/v1/modify_list',
    body,
    seed: seed,
    random: random,
  );
  return _convertPlaylistUpdate(bytes);
}

/// playlist_update.rs `validate`（顺序逐条对齐）。
void validatePlaylistUpdateQuery(PlaylistUpdateQuery query) {
  validateCloudListId(query.cloudListId);
  validateCloudListText(query.description, 16384, allowEmpty: true);
  validateCloudListText(query.tags, 4096, allowEmpty: true);
  if (query.title != null) {
    validateCloudListText(query.title!, 1024, allowEmpty: false);
  }
  final cover = query.coverReference;
  if (cover != null) {
    const prefix = 'custom/';
    final base = cover.startsWith(prefix)
        ? cover.substring(prefix.length)
        : null;
    if (base == null || !isValidPlaylistCoverFileName(base)) {
      throw const KugouApiException('input', '封面引用无效');
    }
  }
}

/// wire 解析（playlist_update.rs `convert`：info 是可选 object，带 pic 文本）。
MusicPlaylistChange _convertPlaylistUpdate(Uint8List bytes) {
  final data = decodeCloudListData(bytes);
  final info = wireMap(data['info']);
  int? infoInt(String key) => info == null ? null : optionalInt(info[key]);
  final pic = info == null ? '' : wireText(info['pic']);
  return MusicPlaylistChange(
    userId: optionalInt(data['userid']),
    cloudListId: infoInt('listid'),
    previousTotalRevision: optionalInt(data['pre_total_ver']),
    totalRevision: optionalInt(data['total_ver']),
    playlistCount: optionalInt(data['list_count']),
    providerStatus: infoInt('status'),
    resourceCode: infoInt('code'),
    coverUrl: pic.isEmpty ? null : coverUrl(pic),
  );
}
