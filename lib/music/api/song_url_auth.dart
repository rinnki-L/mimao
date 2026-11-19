/// 播放地址端点——EchoMusicNext `crates/echo-api/src/module/song_url_auth.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 走**网关**（上游 `request()` 固定 `Origin::Gateway`；`Origin::Tracker` 在
/// `util/request.rs` 里只是主机表常量、无调用点——不要"修"客户端），
/// 完整 24 个参数与上游逐键对齐，`key` 由 `tracker_key` 现算。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/song_auth.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';
import 'package:mimao/music/models/music_models.dart';

/// `ppage_id` 默认值（song_url_auth_merge.rs `default_origin`）。
const String kugouDefaultOriginPage = '356753938,823673182,967485191';

/// 音质 → tracker 的 `quality` 值（song_url_auth.rs `tracker_quality`）。
/// automatic 在上游注释里是「原 hash 回退」，wire 上由 references 归一成 128。
String trackerQuality(MusicQuality quality) => switch (quality) {
  MusicQuality.standard => '128',
  MusicQuality.higher => '320',
  MusicQuality.flac => 'flac',
  MusicQuality.hiRes => 'high',
  MusicQuality.viperTape => 'viper_tape',
  MusicQuality.viperClear => 'viper_clear',
  MusicQuality.viperAtmos => 'viper_atmos',
  MusicQuality.automatic => '128',
};

/// GET /tracker/v5/url（网关主机；24 个键一个都不能少）。
Future<MusicPlaybackSource> resolveSongUrl(
  KugouClient client,
  KugouIdentity identity, {
  required String hash,
  required int albumId,
  required int songId,
  required MusicQuality quality,
  required SongAuthorization songAuth,
  String originPage = kugouDefaultOriginPage,
}) async {
  final normalizedHash = hash.toLowerCase();
  final wireQuality = trackerQuality(quality);
  final response = await client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/tracker/v5/url',
      method: 'GET',
      params: <String, String>{
        'album_id': albumId.toString(),
        'area_code': '1',
        'module': '',
        'hash': normalizedHash,
        'need_m': '0',
        'ssa_flag': 'is_fromtrack',
        'version': '11430',
        'open_time': songAuth.opensAt.toString(),
        'ptype': '0',
        'need_ogg': '1',
        'page_id': '967177915',
        'auth': songAuth.authorization,
        'mtype': '0',
        'quality': wireQuality,
        'album_audio_id': songId.toString(),
        'behavior': 'play',
        'pid': '411',
        'module_id': '51',
        'cmd': '26',
        'ppage_id': originPage,
        'clientver': '11561',
        'pidversion': '3001',
        'cdnBackup': '1',
        'key': kugouTrackerKey(normalizedHash, identity.mid, identity.userId),
      },
    ),
  );
  return _convertPlaybackSource(response.bytes);
}

/// wire 解析（song_url_auth.rs `convert`）。
///
/// 响应是**平铺**结构（hash/url/... 在根上），不是信封里的 data；`status`
/// 必填标量、`error_code` 可缺省（上游局部 `Status` 用 optional）。
MusicPlaybackSource _convertPlaybackSource(Uint8List bytes) {
  final root = _decodeRoot(bytes);
  final status = requiredScalarInt(root['status'], 'status');
  if (status != 1) {
    // 只保留协议计数与错误码，绝不带 msg/data/URL/auth。
    throw KugouApiException(
      'business',
      '音乐服务未返回播放地址',
      code: optionalInt(root['error_code']),
    );
  }
  final urls = _stringList(root['url'], 'url');
  // 产品约束（非上游语义）：上游会原样返回空 PlaybackSource，这里提前失败，
  // 避免播放器打开空地址。
  if (urls.isEmpty) {
    throw const KugouApiException('business', '音乐服务未返回播放地址');
  }
  final timeLengthSeconds = optionalInt(root['timeLength']);
  return MusicPlaybackSource(
    hash: wireText(root['hash']),
    urls: urls,
    backupUrls: _stringList(root['backupUrl'], 'backupUrl'),
    fileSizeBytes: optionalInt(root['fileSize']),
    bitRateBps: optionalInt(root['bitRate']),
    durationMs: timeLengthSeconds == null ? null : timeLengthSeconds * 1000,
    // std_hash_time 本来就是毫秒，原样透传（不乘 1000）。
    standardDurationMs: optionalInt(root['std_hash_time']),
    extension: wireText(root['extName']),
    fileName: wireText(root['fileName']),
    fileHead: optionalInt(root['fileHead']),
    loudness: optionalDouble(root['volume']),
    peak: optionalDouble(root['volume_peak']),
    gain: optionalDouble(root['volume_gain']),
  );
}

/// 根对象解码：status/error_code 之前先判登录过期码（request.rs `decode`
/// 在 serde 之前统一映射 20018）。
Map<String, Object?> _decodeRoot(Uint8List bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  final root = wireMap(decoded);
  if (root == null) {
    throw const KugouApiException('decode', '播放地址响应不是 JSON object');
  }
  if (optionalInt(root['error_code']) == kugouErrorCodeAuthenticationExpired) {
    throw const KugouApiException('authentication', '登录已过期，请重新登录酷狗账号');
  }
  return root;
}

/// 文本数组（上游 `list<String>`）；非文本项按 decode 失败，不静默丢弃。
List<String> _stringList(Object? value, String field) {
  final items = wireList(value, field);
  final result = <String>[];
  for (final item in items) {
    final text = optionalText(item);
    if (text == null) {
      throw KugouApiException('decode', '响应字段 $field 含非文本项');
    }
    result.add(text);
  }
  return result;
}
