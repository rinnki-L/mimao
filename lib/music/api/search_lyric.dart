/// 歌词候选搜索端点——EchoMusicNext `crates/echo-api/src/module/search_lyric.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 走 lyrics.kugou.com 直连主机 + `request_lyric_search`（clearDefaults）：
/// 只签端点自己的 8 个参数，不注入任何默认身份字段，但保留 Android 签名
/// （request.rs 注释：Lyric search clears device/account URL defaults but
/// retains the Android parameter signature）。候选顺序保持服务端原序。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/search_models.dart';

/// 歌词候选搜索的输入（search_lyric.rs `Query` 的 Hash/Keywords 两个变体）。
///
/// 上游是 `#[serde(untagged)]` 枚举且两变体都 `deny_unknown_fields`——构造器
/// 分别对应两个变体，hash/keywords 互斥。
class MusicSearchLyricQuery {
  const MusicSearchLyricQuery._({
    required this.hash,
    required this.songId,
    required this.keywords,
    required this.durationMs,
    required this.allCandidates,
  });

  /// Hash 变体：按文件 hash 精确匹配。
  const MusicSearchLyricQuery.hash({
    required String hash,
    required int songId,
    required int durationMs,
    required bool allCandidates,
  }) : this._(
         hash: hash,
         songId: songId,
         keywords: '',
         durationMs: durationMs,
         allCandidates: allCandidates,
       );

  /// Keywords 变体：按关键词模糊匹配（params 阶段 trim）。
  const MusicSearchLyricQuery.keywords({
    required String keywords,
    required int durationMs,
    required bool allCandidates,
  }) : this._(
         hash: '',
         songId: 0,
         keywords: keywords,
         durationMs: durationMs,
         allCandidates: allCandidates,
       );

  final String hash;
  final int songId;
  final String keywords;
  final int durationMs;
  final bool allCandidates;

  /// search_lyric.rs `Query::params`（8 个键一个不能少，键序由 BTreeMap 决定）。
  Map<String, String> params() => <String, String>{
    'album_audio_id': songId.toString(),
    'appid': '3116',
    'clientver': '11440',
    'duration': durationMs.toString(),
    'hash': hash,
    'keyword': keywords.trim(),
    'lrctxt': '1',
    'man': allCandidates ? 'yes' : 'no',
  };
}

/// GET https://lyrics.kugou.com/v1/search（clearDefaults 语义）。
Future<List<MusicLyricCandidate>> fetchSearchLyric(
  MusicSession session,
  MusicSearchLyricQuery query,
) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.lyrics,
      path: '/v1/search',
      method: 'GET',
      params: query.params(),
    ),
    // Rust request_lyric_search → send_endpoint(clear_defaults=true)。
    clearDefaults: true,
  );
  return _convertSearchLyric(response.bytes);
}

/// wire 解析（search_lyric.rs `convert`；根上只有 status + candidates）。
List<MusicLyricCandidate> _convertSearchLyric(Uint8List bytes) {
  final root = _decodeLyricRoot(bytes);
  final status = requiredScalarInt(root['status'], 'status');
  final candidates = _lyricCandidates(root['candidates']);
  // 404 且 candidates 恰为空表 → 无候选（不是错误）；其余非 200 → business。
  if (status == 404 && candidates != null && candidates.isEmpty) {
    return const <MusicLyricCandidate>[];
  }
  if (status != 200) {
    throw const KugouApiException('business', '歌词搜索失败');
  }
  // candidates 缺省/非法（optional 失败）→ 空表，不抛 decode。
  return candidates?.map(_convertCandidate).toList() ??
      const <MusicLyricCandidate>[];
}

/// 根对象解码（request.rs `decode`：20018 → authentication 前置）。
Map<String, Object?> _decodeLyricRoot(Uint8List bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  final root = wireMap(decoded);
  if (root == null) {
    throw const KugouApiException('decode', '歌词搜索响应不是 JSON object');
  }
  if (optionalInt(root['error_code']) == kugouErrorCodeAuthenticationExpired) {
    throw const KugouApiException('authentication', '登录已过期，请重新登录酷狗账号');
  }
  return root;
}

/// `optional<Vec<WireCandidate>>`：null/缺省/非数组/含非法项 → null。
///
/// 与 Rust 一致：候选表里任何一项的 text 字段出现 bool/复合值，整表解码失败
/// 回 None（不是 decode 错误）——服务端把这类异常当「无候选」处理。
List<Object?>? _lyricCandidates(Object? value) {
  if (value == null || value is! List) return null;
  for (final item in value) {
    final wire = wireMap(item);
    if (wire == null) return null;
    for (final key in const <String>[
      'id',
      'accesskey',
      'singer',
      'nickname',
      'song',
      'product_from',
      'language',
    ]) {
      if (!_lyricTextOk(wire, key)) return null;
    }
  }
  return value;
}

/// text 字段语义：键缺省 → ''（serde default）；null/bool/复合 → 整表失败。
bool _lyricTextOk(Map<String, Object?> wire, String key) {
  if (!wire.containsKey(key)) return true;
  final value = wire[key];
  return value is String || value is num;
}

MusicLyricCandidate _convertCandidate(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '歌词候选项不是 object');
  }
  final krctype = optionalInt(wire['krctype']);
  final contentType = optionalInt(wire['contenttype']);
  return MusicLyricCandidate(
    sourceId: wireText(wire['id']),
    accessKey: wireText(wire['accesskey']),
    artist: wireText(wire['singer']),
    nickname: wireText(wire['nickname']),
    title: wireText(wire['song']),
    // 候选表的 duration 本身就是毫秒，原样透传（不乘 1000）。
    durationMs: optionalInt(wire['duration']),
    sourceLabel: wireText(wire['product_from']),
    language: wireText(wire['language']),
    wordTimed: switch (krctype) {
      1 => true,
      2 => false,
      _ => null,
    },
    score: optionalInt(wire['score']),
    scrollable: switch (contentType) {
      0 || 1 => true,
      2 => false,
      _ => null,
    },
    sourceFormatCode: krctype,
    contentTypeCode: contentType,
  );
}
