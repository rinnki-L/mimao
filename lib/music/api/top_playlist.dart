/// 推荐歌单端点——EchoMusicNext `crates/echo-api/src/module/top_playlist.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 成功分类响应可能只有 OlexpIds 而没有 special_list；song count 在
/// data.special_list 缺席时保持未知（上游模块头注释）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/rank_models.dart';

/// 推荐歌单输入（top_playlist.rs `Query { category_id }`）。
class MusicTopPlaylistQuery {
  const MusicTopPlaylistQuery({required this.categoryId});

  /// 来源 IPC 会把 query 值字符串化后再走模块默认；"0" 保持 0 而不是被
  /// 当成 1（上游注释）——本端点的 categoryid 只做字符串透传。
  final String categoryId;

  void validate() {
    // 上游 recommendation_song.rs `decimal`：category_id 必须是十进制 u64
    // （Rust parse 接受前导 + 与前导零；拒绝空白/负号/小数/溢出）。
    if (!RegExp(r'^\+?[0-9]+$').hasMatch(categoryId) ||
        int.tryParse(categoryId) == null) {
      throw const KugouApiException('input', '推荐歌单分类无效');
    }
  }
}

/// body key 签名的固定盐（top_playlist.rs `request_body`）。
const String _kKeySalt = '3116LnT6xpN3khm36zse0QzvmgTZ3waWdRSA11440';

/// POST /v2/special_recommend（网关 + x-router=specialrec.service.kugou.com；
/// 完整 JSON body，key=md5(salt+clienttime)）。
Future<List<MusicRankPlaylistCard>> fetchTopPlaylists(
  MusicSession session,
  MusicTopPlaylistQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  // 上游 execute 用 request::unix_seconds 现取秒级时间戳；测试经 client.now 注入。
  final now =
      ((session.client.now?.call() ?? DateTime.now()).millisecondsSinceEpoch ~/
      1000);
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v2/special_recommend',
      router: 'specialrec.service.kugou.com',
      method: 'POST',
      body: encodeJsonBody(<String, Object?>{
        'appid': 3116,
        'mid': identity.mid,
        'clientver': 11440,
        'platform': 'android',
        'clienttime': '$now',
        'userid': identity.userId,
        'module_id': 1,
        'page': 1,
        'pagesize': 30,
        'key': md5.convert(utf8.encode('$_kKeySalt$now')).toString(),
        'special_recommend': <String, Object?>{
          // withtag/withsong 上游刻意发字符串（IPC 序列化保真），其余是数字。
          'withtag': '1',
          'withsong': '0',
          'sort': 1,
          'ugc': 1,
          'is_selected': 0,
          'withrecommend': 1,
          'area_code': 1,
          'categoryid': query.categoryId,
        },
        'req_multi': 1,
        'retrun_min': 5,
        'return_special_falg': 1,
      }),
    ),
  );
  return convertTopPlaylists(response.bytes);
}

/// wire 解析（top_playlist.rs `convert`）：`status` + `error_code` 信封。
List<MusicRankPlaylistCard> convertTopPlaylists(Uint8List bytes) {
  final envelope = decodeEnvelopeWithFields(bytes);
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '推荐歌单');
  final data = requiredWireMap(envelope.data, 'data');
  return wireList(data['special_list'], 'special_list').map(_playlist).toList();
}

/// 歌单条目（top_playlist.rs `Playlist` → `PlaylistCard`）。
MusicRankPlaylistCard _playlist(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '推荐歌单条目不是 object');
  }
  return MusicRankPlaylistCard(
    id: wireText(wire['global_collection_id']),
    title: wireText(wire['specialname']),
    creator: wireText(wire['nickname']),
    coverUrl: coverUrl(wireText(wire['imgurl'])),
    metadata: MusicRankPlaylistMetadata(
      publicId: optionalInt(wire['specialid']),
      creatorId: optionalInt(wire['suid']),
      creatorAvatarUrl: coverUrl(wireText(wire['pic'])),
      description: wireText(wire['intro']),
      tags: wireList(wire['tags'], 'tags').map(_tag).toList(),
      playCount: optionalInt(wire['play_count']),
      collectionCount: optionalInt(wire['collectcount']),
      publishedAt: wireText(wire['publishtime']),
      sourceCode: optionalInt(wire['from']),
      kindCode: optionalInt(wire['type']),
      alternateCoverUrl: optionalText(wire['flexible_cover']) == null
          ? null
          : coverUrl(wireText(wire['flexible_cover'])),
    ),
  );
}

/// 标签条目（top_playlist.rs `Tag`）：tag_id 缺省归空串（上游
/// unwrap_or_default），tag_name 走文本。
MusicPlaylistTag _tag(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '推荐歌单标签条目不是 object');
  }
  final tagId = optionalInt(wire['tag_id']);
  return MusicPlaylistTag(
    id: tagId == null ? '' : '$tagId',
    name: wireText(wire['tag_name']),
  );
}
