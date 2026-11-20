/// 歌单创建/收藏端点——EchoMusicNext `crates/echo-api/src/module/playlist_add.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 普通签名 request：body 是明文 JSON（按 serde_json BTreeMap 字典序编码），
/// 自建分支的 params 是 `cloudlist::write_params`，collection 收藏分支的
/// params 为空、body 里 type/is_pri/source/list_create_* 覆盖。
///
/// 本文件还寄存 `util/cloudlist.rs` 的传输类辅助（unix_seconds /
/// write_params / encrypted）——组内其它写端点共用，本组不能新增共享文件。
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/playlist_write_models.dart';

/// 收藏来源（playlist_add.rs `Collection`）。
class PlaylistAddCollection {
  const PlaylistAddCollection({
    required this.source,
    this.creatorId,
    required this.creatorListId,
    required this.creatorGlobalId,
  });

  final int source;

  /// 可缺省：缺省时不写 list_create_userid。
  final int? creatorId;
  final int creatorListId;
  final String creatorGlobalId;
}

/// 创建/收藏入参（playlist_add.rs `Query`）。
class PlaylistAddQuery {
  const PlaylistAddQuery({
    required this.title,
    required this.isPrivate,
    this.collection,
  });

  final String title;

  /// 自建分支的 `is_pri`（collection 分支恒 0，上游覆盖）。
  final bool isPrivate;
  final PlaylistAddCollection? collection;
}

/// 创建歌单 / 收藏歌单（POST /cloudlist.service/v5/add_list，网关无 router）。
Future<MusicPlaylistChange> fetchPlaylistAdd(
  MusicSession session,
  PlaylistAddQuery query, {
  Random? random,
}) async {
  final identity = await session.ensureDevice();
  requireMusicAccount(identity); // cloudlist::account
  validateCloudListText(query.title, 1024, allowEmpty: false);
  final seconds = cloudListUnixSeconds(session.client);
  final body = <String, Object?>{
    'userid': identity.userId,
    'token': identity.token,
    'total_ver': 0,
    'name': query.title,
    'type': 0,
    'source': 1,
    'is_pri': query.isPrivate ? 1 : 0,
    'list_create_gid': '',
    'from_shupinmv': 0,
  };
  final Map<String, String> params;
  final collection = query.collection;
  if (collection != null) {
    validateCloudListId(collection.creatorListId);
    body['type'] = 1;
    body['is_pri'] = 0;
    body['source'] = collection.source;
    body['list_create_listid'] = collection.creatorListId;
    body['list_create_gid'] = collection.creatorGlobalId;
    if (collection.creatorId != null) {
      body['list_create_userid'] = collection.creatorId!;
    }
    params = const <String, String>{};
  } else {
    params = cloudListWriteParams(identity, seconds);
  }
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/cloudlist.service/v5/add_list',
      method: 'POST',
      params: params,
      body: encodeCloudListJson(body),
    ),
  );
  return _convertPlaylistAdd(response.bytes);
}

/// wire 解析（playlist_add.rs `convert`：info 是可选 object）。
MusicPlaylistChange _convertPlaylistAdd(Uint8List bytes) {
  final data = decodeCloudListData(bytes);
  // info: Option<Info> 带 optional 反序列化器——非 object（含数组/标量）静默
  // 归 None，不是 decode 失败。
  final info = wireMap(data['info']);
  int? infoInt(String key) => info == null ? null : optionalInt(info[key]);
  return MusicPlaylistChange(
    userId: optionalInt(data['userid']),
    cloudListId: infoInt('listid'),
    previousTotalRevision: optionalInt(data['pre_total_ver']),
    totalRevision: optionalInt(data['total_ver']),
    playlistCount: optionalInt(data['list_count']),
    providerStatus: infoInt('status'),
    resourceCode: infoInt('code'),
  );
}

// ---------------------------------------------------------------------------
// util/cloudlist.rs 传输类辅助（组内共享，寄存在本文件）。
// ---------------------------------------------------------------------------

/// `request::unix_seconds`——经客户端注入时钟，测试可固定。
int cloudListUnixSeconds(KugouClient client) =>
    ((client.now?.call() ?? DateTime.now()).millisecondsSinceEpoch) ~/ 1000;

/// `cloudlist::write_params`——明文 JSON 云歌单写端点的四个查询参数。
Map<String, String> cloudListWriteParams(KugouIdentity identity, int seconds) =>
    <String, String>{
      'last_time': '$seconds',
      'last_area': 'gztx',
      'userid': '${identity.userId}',
      'token': identity.token,
    };

/// `cloudlist::encrypted`——AES-128 信封 + cloud 传输（update/sort/tracks_sort
/// 共用）：cloud 模式不注入 token/userid/uuid、不做 Android 签名；响应是
/// 用同一 seed 加密的二进制，先解密再交给端点 convert。
Future<Uint8List> cloudListEncrypted(
  MusicSession session,
  KugouIdentity identity,
  String path,
  Map<String, Object?> body, {
  String? seed,
  Random? random,
}) async {
  final envelope = seed == null
      ? KugouPlaylistEnvelope.random(
          body,
          userId: identity.userId,
          token: identity.token,
          random: random,
        )
      : KugouPlaylistEnvelope.withSeed(
          body,
          userId: identity.userId,
          token: identity.token,
          seed: seed,
        );
  final seconds = cloudListUnixSeconds(session.client);
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: path,
      router: 'cloudlist.service.kugou.com',
      method: 'POST',
      params: <String, String>{
        'clienttime': '$seconds',
        'key': kugouCloudListKeyedTime(seconds),
        'p': envelope.portrait.toUpperCase(),
      },
      body: envelope.body,
      headers: kugouCloudListHeaders,
    ),
    cloud: true,
  );
  // 成功与失效 token 的响应都是密文（上游注释）。
  return envelope.decrypt(response.bytes);
}

/// `cloudlist::encrypted` 的固定头（Content-Type 由客户端从端点头里取）。
const List<(String, String)> kugouCloudListHeaders = <(String, String)>[
  ('Content-Type', 'application/json;charset=utf-8'),
  ('kg-rc', '1'),
  ('kg-thash', '5d816a0'),
  ('kg-rec', '1'),
  ('kg-rf', 'B9EDA08A64250DEFFBCADDEE00F8F25F'),
];
