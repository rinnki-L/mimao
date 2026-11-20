/// 账号云歌单端点——EchoMusicNext `crates/echo-api/src/module/user_playlist.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 云歌单 id（`listid`）与公共合集 id（`global_collection_id`）是两套主键，
/// 全页样本 32 张里 28 张是收藏——两种计数永不合并。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/user_library_models.dart';

/// 云歌单请求（user_playlist.rs `Query`：page/page_size）。
class MusicUserPlaylistQuery {
  const MusicUserPlaylistQuery({required this.page, required this.pageSize});

  /// 1 起始页码（u32，0 无效）。
  final int page;

  /// 1..=200。
  final int pageSize;

  void validate() {
    if (page == 0 || pageSize < 1 || pageSize > 200) {
      throw const KugouApiException('input', '歌单分页参数无效');
    }
  }
}

/// POST /v7/get_all_list（网关 + x-router=cloudlist.service.kugou.com；
/// 需要账号）。query 上显式携带 plat/userid/token（上游 BTreeMap::from）。
Future<MusicUserPlaylists> fetchUserPlaylist(
  MusicSession session,
  MusicUserPlaylistQuery query,
) async {
  final identity = await session.ensureDevice();
  requireMusicAccount(identity);
  query.validate();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v7/get_all_list',
      router: 'cloudlist.service.kugou.com',
      method: 'POST',
      params: <String, String>{
        'plat': '1',
        'userid': identity.userId.toString(),
        'token': identity.token,
      },
      // Rust 是具名 struct（serde 按字段声明序输出，非 BTreeMap 字典序）。
      body: encodeJsonBody(<String, Object?>{
        'userid': identity.userId,
        'token': identity.token,
        'total_ver': 979,
        'type': 2,
        'page': query.page,
        'pagesize': query.pageSize,
      }),
    ),
  );
  return _convertUserPlaylists(response.bytes, query.page, query.pageSize);
}

/// wire 解析（user_playlist.rs `convert`）。
MusicUserPlaylists _convertUserPlaylists(
  Uint8List bytes,
  int page,
  int pageSize,
) {
  final envelope = decodeEnvelope(bytes);
  if (envelope.status != 1 && envelope.errorCode == 20017) {
    throw KugouApiException(
      'authentication',
      '账号认证无效，请重新登录',
      code: envelope.errorCode,
    );
  }
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '云歌单');
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '云歌单响应 data 不是 object');
  }
  // info：null/缺省 → 无返回行；非空数组逐条转 item；其它形态 → decode
  // 失败（空 object 也不是合法列表，上游 from_value::<Vec<Item>> 同样失败）。
  final rawInfo = data['info'];
  final rawItems = <Object?>[];
  if (rawInfo != null) {
    if (rawInfo is! List) {
      throw const KugouApiException('decode', '云歌单响应 info 不是数组');
    }
    rawItems.addAll(rawInfo);
  }
  final items = rawItems.map(_convertUserPlaylist).toList();
  return MusicUserPlaylists(
    // page/pageSize 回显请求值（上游 Page::page/page_size 填请求参数）。
    page: MusicPage<MusicUserPlaylist>(
      page: page,
      pageSize: pageSize,
      total: musicWireUnsigned(data['list_count']),
      items: items,
    ),
    userId: musicWireUnsigned(data['userid']),
    totalRevision: musicWireUnsigned(data['total_ver']),
    collectionCount: musicWireUnsigned(data['collect_count']),
    albumCount: musicWireUnsigned(data['album_count']),
  );
}

MusicUserPlaylist _convertUserPlaylist(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '云歌单条目不是 object');
  }
  final kindCode = musicWireU32(wire['type']);
  // intro/tags 只在键存在且可读时算「有值」；null → 没给（不造空选择）。
  final intro = optionalText(wire['intro']);
  final tags = optionalText(wire['tags']);
  return MusicUserPlaylist(
    cloudListId: musicWireUnsigned(wire['listid']),
    globalId: wireText(wire['global_collection_id']),
    creatorGlobalId: wireText(wire['list_create_gid']),
    title: wireText(wire['name']),
    descriptionPresent: intro != null,
    tagsPresent: tags != null,
    description: intro ?? '',
    tags: tags ?? '',
    coverUrl: coverUrl(wireText(wire['pic'])),
    creatorId: musicWireUnsigned(wire['list_create_userid']),
    creatorName: wireText(wire['list_create_username']),
    creatorListId: musicWireUnsigned(wire['list_create_listid']),
    songCount: musicWireUnsigned(wire['count']),
    revision: musicWireUnsigned(wire['list_ver']),
    sortIndex: musicWireUnsigned(wire['sort']),
    sourceCode: musicWireU32(wire['source']),
    kindCode: kindCode,
    kind: switch (kindCode) {
      0 => MusicCloudPlaylistKind.owned,
      1 => MusicCloudPlaylistKind.collected,
      _ => MusicCloudPlaylistKind.unknown,
    },
    editable: musicWireFlag(wire['is_edit']),
    private: musicWireFlag(wire['is_pri']),
    published: musicWireFlag(wire['is_publish']),
    deleted: musicWireFlag(wire['is_del']),
    dropped: musicWireFlag(wire['is_drop']),
    customCover: musicWireFlag(wire['is_custom_pic']),
    // is_def 是原样码（default_kind），不做布尔投影。
    defaultKind: musicWireU32(wire['is_def']),
    flagCodes: MusicPlaylistFlagCodes(
      editable: musicWireU32(wire['is_edit']),
      private: musicWireU32(wire['is_pri']),
      published: musicWireU32(wire['is_publish']),
      deleted: musicWireU32(wire['is_del']),
      dropped: musicWireU32(wire['is_drop']),
      customCover: musicWireU32(wire['is_custom_pic']),
    ),
    createdAtSeconds: musicWireUnsigned(wire['create_time']),
    updatedAtSeconds: musicWireUnsigned(wire['update_time']),
  );
}
