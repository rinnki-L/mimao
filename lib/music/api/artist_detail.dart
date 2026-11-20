/// 歌手详情端点——EchoMusicNext `crates/echo-api/src/module/artist_detail.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// /artist/detail 映射 /kmr/v3/author（网关 POST，x-router=openapi.kugou.com，
/// kg-tid=36）：标量计数 + long_intro 数组；可选事实未知时不阻塞页面，
/// data 缺省/空 object → null（上游 convert 的 Option 语义），不算失败。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/artist_models.dart';

/// 歌手详情（id 为 u64 输入域；负数在 Rust 侧是反序列化失败）。
Future<MusicArtistDetail?> fetchArtistDetail(
  MusicSession session,
  int id,
) async {
  if (id < 0) {
    throw const KugouApiException('input', '歌手 id 无效');
  }
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/kmr/v3/author',
      router: 'openapi.kugou.com',
      method: 'POST',
      body: encodeJsonBody(<String, Object?>{'author_id': id}),
      headers: const <(String, String)>[('kg-tid', '36')],
    ),
  );
  return _convertArtistDetail(response.bytes);
}

/// wire 解析（artist_detail.rs `convert`）。
MusicArtistDetail? _convertArtistDetail(Uint8List bytes) {
  final envelope = decodeBusinessEnvelope(bytes, context: '歌手详情');
  final data = envelope.data;
  // data 缺省（serde default → Null）或空 object → 没有数据，不是错误。
  if (data == null) return null;
  final map = wireMap(data);
  if (map != null && map.isEmpty) return null;
  if (map == null) {
    throw const KugouApiException('decode', '歌手详情响应 data 不是 object');
  }
  // long_intro：list 反序列化——元素不是 object 时整条解码失败（Rust 一致）。
  final introContents = <String>[];
  for (final entry in wireList(map['long_intro'], 'long_intro')) {
    final intro = wireMap(entry);
    if (intro == null) {
      throw const KugouApiException('decode', '歌手详情响应 long_intro 元素不是 object');
    }
    introContents.add(wireText(intro['content']));
  }
  return MusicArtistDetail(
    id: _parseAuthorId(wireText(map['author_id'])),
    name: wireText(map['author_name']),
    avatarUrl: coverUrl(wireText(map['sizable_avatar'])),
    description: introContents
        .where((content) => content.isNotEmpty)
        .join('\n\n'),
    birthday: wireText(map['birthday']),
    fans: optionalInt(map['fansnums']),
    albumCount: optionalInt(map['album_count']),
    mvCount: optionalInt(map['mv_count']),
    published: optionalBool(map['is_publish']),
  );
}

/// `author_id.parse::<u64>()`：仅纯数字文本可解析（无符号、无空白宽容），
/// 其余回 null。
int? _parseAuthorId(String text) {
  if (text.isEmpty || !RegExp(r'^\d+$').hasMatch(text)) return null;
  return int.tryParse(text);
}
