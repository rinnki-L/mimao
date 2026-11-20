/// 歌单删除端点——EchoMusicNext `crates/echo-api/src/module/playlist_del.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module）。
///
/// 传输是**普通签名 request**（不是 cloud 模式）：query 带 uuid/token/userid
/// 默认值 + `clienttime/key/last_area/last_time/p`，body 是信封密文的
/// base64 文本；响应用同一 seed 解密后再解码。
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:mimao/music/api/playlist_add.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/models/playlist_write_models.dart';

/// 删除入参（playlist_del.rs `Query`）。
class PlaylistDelQuery {
  const PlaylistDelQuery({required this.cloudListId});

  final int cloudListId;
}

/// 删除歌单（POST /v2/delete_list，网关 + x-router=cloudlist.service.kugou.com）。
/// 新建 type=0 的歌单删除时也用 type=1（上游注释）。
Future<MusicPlaylistChange> fetchPlaylistDel(
  MusicSession session,
  PlaylistDelQuery query, {
  String? seed,
  Random? random,
}) async {
  final identity = await session.ensureDevice();
  requireMusicAccount(identity); // cloudlist::account
  validateCloudListId(query.cloudListId);
  final envelope = seed == null
      ? KugouPlaylistEnvelope.random(
          <String, Object?>{
            'listid': query.cloudListId,
            'total_ver': 0,
            'type': 1,
          },
          userId: identity.userId,
          token: identity.token,
          random: random,
        )
      : KugouPlaylistEnvelope.withSeed(
          <String, Object?>{
            'listid': query.cloudListId,
            'total_ver': 0,
            'type': 1,
          },
          userId: identity.userId,
          token: identity.token,
          seed: seed,
        );
  final seconds = cloudListUnixSeconds(session.client);
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v2/delete_list',
      router: 'cloudlist.service.kugou.com',
      method: 'POST',
      params: <String, String>{
        'clienttime': '$seconds',
        'key': kugouCloudListKeyedTime(seconds),
        'last_area': 'gztx',
        'last_time': '$seconds',
        'p': envelope.portrait.toUpperCase(),
      },
      body: envelope.base64Body(),
    ),
  );
  return _convertPlaylistDel(
    envelope.decrypt(response.bytes),
    query.cloudListId,
  );
}

/// wire 解析（playlist_del.rs `convert`：info 是数组，取首项）。
MusicPlaylistChange _convertPlaylistDel(Uint8List bytes, int listId) {
  final data = decodeCloudListData(bytes);
  final items = wireList(data['info'], 'info');
  Map<String, Object?>? first;
  if (items.isNotEmpty) {
    final wire = wireMap(items.first);
    if (wire == null) {
      throw const KugouApiException('decode', '云歌单响应 info 项不是 object');
    }
    first = wire;
  }
  int? firstInt(String key) => first == null ? null : optionalInt(first[key]);
  return MusicPlaylistChange(
    userId: optionalInt(data['userid']),
    // 返回的 listid 缺省时回退请求 id（上游 unwrap_or(list_id)，恒 Some）。
    cloudListId: firstInt('listid') ?? listId,
    previousTotalRevision: optionalInt(data['pre_total_ver']),
    totalRevision: optionalInt(data['total_ver']),
    playlistCount: optionalInt(data['list_count']),
    providerStatus: firstInt('status'),
    resourceCode: firstInt('code'),
  );
}
