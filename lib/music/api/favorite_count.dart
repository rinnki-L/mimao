/// 收藏计数端点——EchoMusicNext `crates/echo-api/src/module/favorite_count.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// GET `/count/v1/audio/mget_collect`（网关，无 router）。wire 业务码键是
/// `errcode`（且带缺省 0），与共享信封的 `error_code` 键不同——这里按上游
/// `request::decode` 的顺序自解根对象（见文件内注释）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/album_models.dart';

/// 批量收藏计数（favorite_count.rs `execute`；`ids` 无空表校验——空表原样
/// 发送 `mixsongids=`，与上游一致）。
Future<List<MusicAlbumFavoriteCount>> fetchFavoriteCount(
  MusicSession session,
  List<int> ids,
) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/count/v1/audio/mget_collect',
      method: 'GET',
      params: <String, String>{
        'mixsongids': ids.map((id) => id.toString()).join(','),
      },
    ),
  );
  return _convertFavoriteCounts(response.bytes);
}

/// wire 解析（favorite_count.rs `convert`）。
List<MusicAlbumFavoriteCount> _convertFavoriteCounts(Uint8List bytes) {
  final root = _decodeRoot(bytes);
  // Wire.status 必填标量；errcode 缺省 0（serde default），错配 → decode。
  final status = requiredScalarInt(root['status'], 'status');
  final errcode = root['errcode'] == null
      ? 0
      : requiredScalarInt(root['errcode'], 'errcode');
  ensureBusinessSuccess(status, errcode, context: '收藏计数');
  return _convertData(root['data']);
}

/// 根对象解码：request.rs `decode` 在 serde 之前统一判登录过期。
///
/// 注意 `authentication_expiration` 看的是字面 `error_code` 键（不是本端点的
/// wire 键 `errcode`）或 `msg` 含「登录已过期」——因此 `errcode=20018` 在上游
/// 仍是 business 而非 authentication，这里逐字对齐。
Map<String, Object?> _decodeRoot(Uint8List bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  final root = wireMap(decoded);
  if (root == null) {
    throw const KugouApiException('decode', '收藏计数响应不是 JSON object');
  }
  final code = optionalInt(root['error_code']);
  final message = root['msg'];
  final expired = message is String && message.contains('登录已过期');
  if (code == kugouErrorCodeAuthenticationExpired || expired) {
    throw KugouApiException('authentication', '账号认证无效，请重新登录', code: code);
  }
  return root;
}

/// Wire.data 是 object 语义（unwrap_or_default）：data 整体或内部 list 解不动
/// 都静默归空表（上游 Default::default），只有 status/errcode 错配是 decode。
List<MusicAlbumFavoriteCount> _convertData(Object? raw) {
  final data = wireMap(raw);
  if (data == null) return const <MusicAlbumFavoriteCount>[];
  try {
    return wireList(data['list'], 'list').map(_convertCount).toList();
  } on KugouApiException {
    return const <MusicAlbumFavoriteCount>[];
  }
}

/// favorite_count.rs `Count`：mixsongid/count 可选、count_text 文本、其余键
/// 经 `#[serde(flatten)]` 原样旁路捕获。
MusicAlbumFavoriteCount _convertCount(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '收藏计数条目不是 object');
  }
  const consumed = <String>{'mixsongid', 'count', 'count_text'};
  return MusicAlbumFavoriteCount(
    mixsongId: optionalInt(wire['mixsongid']),
    count: optionalInt(wire['count']),
    countText: wireText(wire['count_text']),
    extension: <String, Object?>{
      for (final entry in wire.entries)
        if (!consumed.contains(entry.key)) entry.key: entry.value,
    },
  );
}
