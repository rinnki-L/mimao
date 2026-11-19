/// 歌曲级授权端点——EchoMusicNext `crates/echo-api/src/module/song_auth.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 用 user_verify 的授权串换「这首歌」的授权（含 open_time）；歌曲授权与
/// tracker 地址元数据刻意分开，不混进同一个模型。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

/// 上行参数键（tracker 链路里同名的协议键）。
const String authParamName = 'authorization';

/// 歌曲级授权（song_auth.rs `SongAuthorization`）。
class SongAuthorization {
  const SongAuthorization({required this.authorization, required this.opensAt});

  /// 歌曲授权串（tracker 的 `auth` 参数）。
  final String authorization;

  /// 授权开启时间（tracker 的 `open_time` 参数；上游原样透传）。
  final int opensAt;
}

/// GET /v1/authorization（网关 + x-router=trackercdngz.kugou.com）。
Future<SongAuthorization> songAuthorize(
  KugouClient client,
  KugouIdentity identity, {
  required String hash,
  required int songId,
  required String userAuth,
}) async {
  final response = await client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v1/authorization',
      router: 'trackercdngz.kugou.com',
      method: 'GET',
      params: <String, String>{
        authParamName: userAuth,
        'module_id': '51',
        'album_audio_id': songId.toString(),
        'clientver': '11561',
        'hash': hash.toLowerCase(),
      },
    ),
  );
  return _convertSongAuthorization(response.bytes);
}

/// wire 解析（song_auth.rs `convert`）。
SongAuthorization _convertSongAuthorization(Uint8List bytes) {
  final envelope = decodeBusinessEnvelope(bytes, context: '歌曲授权');
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '歌曲授权响应 data 不是 object');
  }
  final authText = wireText(data['auth']);
  if (authText.isEmpty) {
    throw const KugouApiException('authentication', '无法取得歌曲授权');
  }
  return SongAuthorization(
    authorization: authText,
    opensAt: requiredScalarInt(data['open_time'], 'open_time'),
  );
}
