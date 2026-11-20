/// 专辑动态封面端点——EchoMusicNext `crates/echo-api/src/module/album_dycover.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// **特殊主机裸传输**（request.rs `album_dynamic_cover`）：无账号头、无 kg-*
/// 默认参数、无 lite 签名——走 `KugouClient.sendRaw`，URL/参数/头/签名全部
/// 由本端点逐字提供，身份完全不参与（上游 `execute(client, query)` 无 identity）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/signature.dart';
import 'package:mimao/music/models/album_models.dart';

/// 动态封面固定主机（request.rs `album_dynamic_cover` 的 GET URL）。
const String kugouAlbumDycoverUrl =
    'https://kmrcdn.service.kugou.com/v2/album/audio';

/// 动态封面查询（album_dycover.rs `Query`：album_audio_id 必填、album_id 缺省 0）。
class AlbumDycoverQuery {
  const AlbumDycoverQuery({required this.albumAudioId, this.albumId = 0});

  final int albumAudioId;
  final int albumId;
}

/// 专辑动态封面（album_dycover.rs `execute`）。
///
/// 返回 null 表示「无可用动态封面」（空 data / 无 dycover / 无合法 URL），
/// 与业务失败是两条路。
Future<MusicAlbumDynamicCover?> fetchAlbumDycover(
  MusicSession session,
  AlbumDycoverQuery query,
) async {
  if (query.albumAudioId == 0 && query.albumId == 0) {
    throw const KugouApiException('input', '缺少专辑资源');
  }
  // request.rs：album_id > 0 才带（0/缺省只发 album_audio_id）。
  final item = <String, Object?>{'album_audio_id': query.albumAudioId};
  if (query.albumId > 0) {
    item['album_id'] = query.albumId;
  }
  final params = <String, String>{
    'appid': '1005',
    'clientver': '20489',
    'data': jsonEncode(<Object?>[item]),
    'isCdn': '1',
    'query': 'audioPlay',
  };
  // 签名只覆盖这 5 个参数（album_cover salt），signature 随后并入 query。
  params['signature'] = kugouSignatureAlbumCover(params);
  final response = await session.client.sendRaw(
    url: kugouAlbumDycoverUrl,
    method: 'GET',
    params: params,
    headers: <String, String>{
      'dfid': '-',
      'mid': 'undefined',
      'clienttime': _unixSeconds().toString(),
    },
  );
  return _convertAlbumDycover(response.bytes, query.albumId);
}

/// wire 解析（album_dycover.rs `convert`）。
MusicAlbumDynamicCover? _convertAlbumDycover(Uint8List bytes, int albumId) {
  // request::decode 链路：20018（error_code 键）在这层统一映射 authentication。
  final envelope = decodeEnvelope(bytes);
  // 上游只判 status != 1（与 request::success 的 status&&code 双判定刻意不同）。
  if (envelope.status != 1) {
    throw KugouApiException(
      'business',
      '音乐服务返回失败（动态封面）（status=${envelope.status}）',
      code: envelope.errorCode,
    );
  }
  final data = wireList(envelope.data, 'data');
  if (data.isEmpty) return null;
  final item = wireMap(data.first);
  if (item == null) {
    throw const KugouApiException('decode', '动态封面条目不是 object');
  }
  // base/dycover 都是 optional：缺省/null/非 object → 无该部分，不挡行。
  final video = wireMap(item['dycover']);
  if (video == null) return null;
  final base = wireMap(item['base']);
  final resolvedAlbum = base == null
      ? albumId
      : (optionalInt(base['album_id']) ?? albumId);

  // Prefer widely decoded H.264; keep signed URLs verbatim in ephemeral memory.
  // （上游注释）h264_url 先、h264_backup_url 后；空串跳过；非 http/https 或
  // 无 host 跳过；字符串原样去重。
  final rawBackup = video['h264_backup_url'];
  final backups = rawBackup is List && rawBackup.every((e) => e is String)
      ? List<String>.from(rawBackup)
      : const <String>[];
  final urls = <String>[];
  for (final url in <String?>[optionalText(video['h264_url']), ...backups]) {
    if (url == null || url.isEmpty) continue;
    final parsed = Uri.tryParse(url);
    if (parsed == null) continue;
    final scheme = parsed.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') continue;
    if (parsed.host.isEmpty) continue;
    if (!urls.contains(url)) urls.add(url);
  }
  if (urls.isEmpty) return null;
  return MusicAlbumDynamicCover(albumId: resolvedAlbum.toString(), urls: urls);
}

int _unixSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;
