/// 歌单详情端点——EchoMusicNext `crates/echo-api/src/module/playlist_detail.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 公开详情暴露的是创作者歌单 id（global_collection_id），不是账号云歌单 id；
/// `creator_list_id` 只是只读的评论身份元数据。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/models/playlist_models.dart';

/// 输入（playlist_detail.rs `Query`）。
class MusicPlaylistDetailQuery {
  const MusicPlaylistDetailQuery({required this.globalIds});

  final List<String> globalIds;

  /// 空、超过 100 个、或任一为空/超 256 字符/含逗号 → input。
  void validate() {
    if (globalIds.isEmpty ||
        globalIds.length > 100 ||
        globalIds.any(
          (id) => id.isEmpty || id.length > 256 || id.contains(','),
        )) {
      throw const KugouApiException('input', '公开歌单标识无效');
    }
  }
}

/// POST /v3/get_list_info（网关 + x-router=pubsongs.kugou.com，普通带签名请求）。
Future<List<MusicPlaylistDetail>> fetchPlaylistDetail(
  MusicSession session,
  MusicPlaylistDetailQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v3/get_list_info',
      router: 'pubsongs.kugou.com',
      method: 'POST',
      body: encodeJsonBody(<String, Object?>{
        'data': <Object?>[
          for (final id in query.globalIds)
            <String, Object?>{'global_collection_id': id},
        ],
        'userid': identity.userId,
        'token': identity.token,
      }),
    ),
  );
  return convertPlaylistDetail(response.bytes);
}

/// wire 解析（playlist_detail.rs `convert`）。
List<MusicPlaylistDetail> convertPlaylistDetail(Uint8List bytes) {
  final envelope = decodeEnvelope(bytes);
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '歌单详情');
  final data = envelope.data;
  // 采样的缺失合集：data 是空 object → 空列表（data 缺省/非数组仍是 decode）。
  if (data is Map && data.isEmpty) {
    return const <MusicPlaylistDetail>[];
  }
  if (data is! List) {
    throw const KugouApiException('decode', '歌单详情响应 data 不是数组');
  }
  return <MusicPlaylistDetail>[for (final item in data) _convertItem(item)];
}

MusicPlaylistDetail _convertItem(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '歌单详情条目不是 object');
  }
  return MusicPlaylistDetail(
    globalId: wireText(wire['global_collection_id']),
    publicId: optionalInt(wire['specialid']),
    title: wireText(wire['name']),
    description: wireText(wire['intro']),
    coverUrl: coverUrl(wireText(wire['pic'])),
    creatorId: optionalInt(wire['list_create_userid']),
    creatorListId: optionalInt(wire['list_create_listid']),
    creatorName: wireText(wire['list_create_username']),
    creatorAvatarUrl: coverUrl(wireText(wire['create_user_pic'])),
    songCount: optionalInt(wire['count']),
    revision: optionalInt(wire['list_ver']),
    publishedAt: wireText(wire['publish_date']),
    collectionCount: optionalInt(wire['collect_total']),
    private: optionalBool(wire['is_pri']),
    privateCode: optionalInt(wire['is_pri']),
    published: optionalBool(wire['is_publish']),
    publicationCode: optionalInt(wire['is_publish']),
    tags: optionalText(wire['tags']),
    createdAtSeconds: optionalInt(wire['create_time']),
    updatedAtSeconds: optionalInt(wire['update_time']),
    creatorGlobalId: optionalText(wire['list_create_gid']),
    sourceCode: optionalInt(wire['source']),
    customCover: optionalBool(wire['is_custom_pic']),
    customCoverCode: optionalInt(wire['is_custom_pic']),
    defaultKind: optionalInt(wire['is_def']),
    musicTags: _musicTags(wire['musiclib_tags']),
  );
}

/// wire `musiclib_tags`：`Option<Vec<WireTag>>` 走 `optional`——null/非数组/
/// 含非 object 条目都整体归 null（不抛 decode）。
List<MusicPlaylistSongTag>? _musicTags(Object? value) {
  if (value is! List) return null;
  final tags = <MusicPlaylistSongTag>[];
  for (final item in value) {
    final map = wireMap(item);
    if (map == null) return null;
    tags.add(
      MusicPlaylistSongTag(
        id: optionalInt(map['tag_id'])?.toString(),
        name: wireText(map['tag_name']),
        parentId: optionalInt(map['parent_id'])?.toString(),
      ),
    );
  }
  return tags;
}
