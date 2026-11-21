/// 听歌历史端点——EchoMusicNext `crates/echo-api/src/module/user_history.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 网关返回一页 100 条 `songs` 与一个不透明的 `bp` 游标；64 位业务 id
/// （`mxid`/`album_id`/`audio_id`）一律保持十进制字符串，避免跨端取整丢位。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/user_library_models.dart';

/// 游标是不透明的上游令牌，回传前限制长度（user_history.rs
/// `MAX_CURSOR_BYTES`）。
const int kugouHistoryMaxCursorBytes = 4096;

/// 听歌历史请求（user_history.rs `Query`：仅 `bp` 可选）。
class MusicUserHistoryQuery {
  const MusicUserHistoryQuery({this.bp});

  /// 上一次响应给的翻页游标；首页不带。
  final String? bp;

  void validate() {
    final bp = this.bp;
    if (bp != null && utf8.encode(bp).length > kugouHistoryMaxCursorBytes) {
      throw const KugouApiException('input', '听歌历史分页游标无效');
    }
  }
}

/// POST /playhistory/v1/get_songs（网关；需要账号，匿名直接 authentication）。
Future<MusicHistoryPage> fetchUserHistory(
  MusicSession session,
  MusicUserHistoryQuery query,
) async {
  // Rust execute：先 require_account，再校验游标（匿名 + 超长游标 → authentication）。
  final identity = await session.ensureDevice();
  requireMusicAccount(identity);
  query.validate();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/playhistory/v1/get_songs',
      method: 'POST',
      // Rust json! 宏经 serde_json BTreeMap 序列化：键按字典序输出。
      body: encodeJsonBody(<String, Object?>{
        if (query.bp != null) 'bp': query.bp,
        'source_classify': 'app',
        'to_subdivide_sr': 1,
        'token': identity.token,
        'userid': identity.userId,
      }),
    ),
  );
  return _convertHistoryPage(response.bytes);
}

/// wire 解析（user_history.rs `convert`）。
MusicHistoryPage _convertHistoryPage(Uint8List bytes) {
  // request::decode：先统一判登录过期（20018 / msg 文本），再进端点分支。
  final envelope = decodeEnvelope(bytes);
  // 20017 在 success() 之前单列：status!=1 且 error_code==20017 → 认证失败。
  if (envelope.status != 1 && envelope.errorCode == 20017) {
    throw KugouApiException(
      'authentication',
      '账号认证无效，请重新登录',
      code: envelope.errorCode,
    );
  }
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '听歌历史');
  // 成功响应的 data 必须是 object（Rust Data::from_value(Null) → decode 失败）。
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '听歌历史响应 data 不是 object');
  }
  final items = wireList(
    data['songs'],
    'songs',
  ).map(_convertHistoryItem).toList();
  final hasMore = musicWireFlag(data['has_more']);
  return MusicHistoryPage(
    // 完结只由 has_more 推导；`bp_finished` 是另一种游标形态，不是完结标志。
    finished: hasMore == null ? null : !hasMore,
    hasMore: hasMore,
    cursor: optionalText(data['bp']),
    userId: wireText(data['userid']),
    items: items,
  );
}

MusicHistoryItem _convertHistoryItem(Object? raw) {
  final row = wireMap(raw);
  if (row == null) {
    throw const KugouApiException('decode', '听歌历史结果项不是 object');
  }
  // info 缺省/null/不可读 → 空 info（Rust `unwrap_or_default`）。
  final info = wireMap(row['info']) ?? const <String, Object?>{};
  // song_id：mxid 优先，空串回退 info.mixsongid；都保持字符串。
  final mxid = wireText(row['mxid']);
  return MusicHistoryItem(
    songId: mxid.isEmpty ? wireText(info['mixsongid']) : mxid,
    name: wireText(info['name']),
    artist: wireText(info['singername']),
    album: wireText(wireMap(info['albuminfo'])?['name']),
    albumId: optionalText(info['album_id']),
    audioId: optionalText(info['audio_id']),
    hash: wireText(info['hash']),
    cover: _historyCover(info),
    durationMs: musicWireUnsigned(info['timelen']),
    bitrate: musicWireU32(info['bitrate']),
    playCount: musicWireUnsigned(row['pc']),
    lastPlayedAt: musicWireUnsigned(row['ot']),
  );
}

/// 历史封面：wire 是带 `{size}` 占位的模板（如
/// `http://imge.kugou.com/stdmusic/{size}/...`），必须套 [coverUrl] 换成
/// 实际尺寸，否则 `Image.network` 拿到带花括号的 URL 直接失败、列表只剩
/// 占位图标。cover 缺失时回退 `trans_param.union_cover`（同样套模板）。
String? _historyCover(Map<String, Object?> info) {
  final cover = optionalText(info['cover']);
  if (cover != null && cover.isNotEmpty) return coverUrl(cover);
  final union = optionalText(wireMap(info['trans_param'])?['union_cover']);
  if (union != null && union.isNotEmpty) return coverUrl(union);
  return null;
}
