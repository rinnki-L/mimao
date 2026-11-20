/// 歌曲高潮时间端点——EchoMusicNext `crates/echo-api/src/module/song_climax.rs`
/// 的翻译（高潮时刻是十进制串毫秒；未知 hash 可能返回 data: [{}]）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/everyday_recommend.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/discovery_models.dart';

/// song_climax.rs `valid_hash`：32 位 ASCII 十六进制。
bool kugouValidSongHash(String hash) =>
    hash.length == 32 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(hash);

/// GET /v1/audio_climax/audio（climax 主机；data 查询参数携带紧凑 JSON 数组；
/// 固定 kg-* 头与 register_dev 同一套）。
Future<List<MusicSongClimaxSegment>> fetchSongClimax(
  MusicSession session,
  String hash,
) async {
  if (!kugouValidSongHash(hash)) {
    throw const KugouApiException('input', '歌曲hash无效');
  }
  final identity = await session.ensureDevice();
  // serde_json::to_string 紧凑序列化（键序：单键对象无歧义）。
  final data = jsonEncode(<Object?>[
    <String, String>{'hash': hash},
  ]);
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.climax,
      path: '/v1/audio_climax/audio',
      method: 'GET',
      params: <String, String>{'data': data},
      headers: const <(String, String)>[
        ('kg-rc', '1'),
        ('kg-thash', '5d816a0'),
        ('kg-rec', '1'),
        ('kg-rf', 'B9EDA08A64250DEFFBCADDEE00F8F25F'),
      ],
    ),
  );
  return _convertSongClimax(response.bytes);
}

/// Milliseconds（song_climax.rs `TryFrom<Value>`）：字符串按 u64::from_str
/// 解析（**不容忍空白**），数字按 exact_unsigned。
int? _milliseconds(Object? value) {
  if (value is String) {
    if (!RegExp(r'^\+?[0-9]+$').hasMatch(value)) return null;
    return int.tryParse(value);
  }
  return discoveryOptionalUnsigned(value);
}

/// wire 解析（song_climax.rs `convert`）。
List<MusicSongClimaxSegment> _convertSongClimax(Uint8List bytes) {
  final envelope = decodeDiscoveryEnvelope(bytes);
  // song_climax.rs：只判 status != 1——error_code 不参与成功判定。
  if (envelope.status != 1) {
    throw KugouApiException(
      'business',
      '音乐服务返回失败（歌曲高潮）',
      code: envelope.errorCode,
    );
  }
  // data: Option<Vec<Item>> + optional → 缺省/null/非数组 → 空；数组里任一
  // 元素不可解析 → 整个 data 归 None → 空（上游 optional 的 .ok() 语义）。
  final rawItems = envelope.data;
  final items = <Map<String, Object?>>[];
  if (rawItems is List) {
    var valid = true;
    for (final raw in rawItems) {
      final item = wireMap(raw);
      if (item == null) {
        valid = false;
        break;
      }
      items.add(item);
    }
    if (!valid) items.clear();
  }
  final segments = <MusicSongClimaxSegment>[];
  for (final item in items) {
    final startMs = _milliseconds(item['start_time']);
    final endMs = _milliseconds(item['end_time']);
    final itemHash = optionalText(item['hash']);
    // 全空条目（如 data:[{}]）不入表。
    if (startMs != null || endMs != null || itemHash != null) {
      segments.add(
        MusicSongClimaxSegment(startMs: startMs, endMs: endMs, hash: itemHash),
      );
    }
  }
  return segments;
}
