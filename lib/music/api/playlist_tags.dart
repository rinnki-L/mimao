/// 歌单标签端点——EchoMusicNext `crates/echo-api/src/module/playlist_tags.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 分组标签保留字符串 id 与服务端顺序；children 只递归一层。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/playlist_models.dart';

/// POST /pubsongs/v1/get_tags_by_type（网关，无 router；固定采集类标签体）。
Future<List<MusicPlaylistTagCategory>> fetchPlaylistTags(
  MusicSession session,
) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/pubsongs/v1/get_tags_by_type',
      method: 'POST',
      body: encodeJsonBody(<String, Object?>{
        'tag_type': 'collection',
        'tag_id': 0,
        'source': 3,
      }),
    ),
  );
  return convertPlaylistTags(response.bytes);
}

/// wire 解析（playlist_tags.rs `convert`，走 request::decode_envelope）。
List<MusicPlaylistTagCategory> convertPlaylistTags(Uint8List bytes) {
  try {
    return _parse(bytes);
  } on KugouApiException catch (error) {
    if (error.kind != 'decode') rethrow;
    // request.rs decode_envelope 兜底：整包结构解析失败时，若 error_code
    // 非零或 status=0，仍按业务失败上报（错误字段名固定 error_code）。
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on Object {
      rethrow;
    }
    if (decoded is! Map) rethrow;
    final code = optionalInt(decoded['error_code']);
    final rejected = optionalInt(decoded['status']) == 0;
    if ((code != null && code != 0) || rejected) {
      throw KugouApiException('business', '请求失败', code: code ?? 0);
    }
    rethrow;
  }
}

List<MusicPlaylistTagCategory> _parse(Uint8List bytes) {
  final envelope = decodeEnvelopeWithFields(bytes);
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '歌单标签');
  final groups = wireList(envelope.data, 'data');
  return <MusicPlaylistTagCategory>[
    for (final group in groups) _convertGroup(group),
  ];
}

MusicPlaylistTagCategory _convertGroup(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '歌单标签分组不是 object');
  }
  return MusicPlaylistTagCategory(
    id: wireText(wire['tag_id']),
    name: wireText(wire['tag_name']),
    parentId: wireText(wire['parent_id']),
    position: _decimal(wireText(wire['sort'])),
    children: <MusicPlaylistTagCategory>[
      for (final child in wireList(wire['son'], 'son')) _convertChild(child),
    ],
  );
}

MusicPlaylistTagCategory _convertChild(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '歌单标签子项不是 object');
  }
  return MusicPlaylistTagCategory(
    id: wireText(wire['tag_id']),
    name: wireText(wire['tag_name']),
    parentId: wireText(wire['parent_id']),
    position: _decimal(wireText(wire['sort'])),
    children: const <MusicPlaylistTagCategory>[],
  );
}

/// recommendation_song.rs `decimal`：u64::from_str 精确解析——可选「+」、
/// 纯数字、无空白（解析失败 → null，不抛）。
int? _decimal(String value) {
  if (!RegExp(r'^\+?[0-9]+$').hasMatch(value)) return null;
  return int.tryParse(value);
}
