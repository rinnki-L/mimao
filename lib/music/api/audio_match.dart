/// 听歌识曲端点——EchoMusicNext `crates/echo-api/src/module/audio_match.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 指纹识别不上 JSON：PCM 原始字节直接作为 POST body（`content-type:
/// application/octet-stream` + KuGou UA 固定头）；候选按 confidence 降序，
/// 每个候选完整保留 SongSummary + CatalogSongFacts（discovery.rs）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playback_ext_models.dart';

/// 识曲输入（audio_match.rs `Query`）：10 秒以内单声道 PCM 的标准 base64。
class AudioMatchQuery {
  const AudioMatchQuery({required this.pcmBase64});

  final String pcmBase64;
}

/// 识曲候选（audio_match.rs `execute`）：
/// - PCM 走 STANDARD base64 严格解码（非法字符/缺 canonical padding → input）；
/// - 非空、≤160000 字节、长度为偶数（≤10 秒单声道 16-bit）；
/// - `fpid` 取当前毫秒（[now] 仅供测试注入时钟，生产走系统时间）。
Future<List<MusicRecognitionMatch>> fetchAudioMatch(
  MusicSession session,
  AudioMatchQuery query, {
  DateTime Function()? now,
}) async {
  Uint8List pcm;
  try {
    // Rust STANDARD 引擎要求 canonical padding；Dart 解码器对缺 padding 宽容，
    // 先按 4 的倍数补上 canonical 校验（空串合法，落到下面的 PCM 校验）。
    if (query.pcmBase64.length % 4 != 0) {
      throw const FormatException('base64 长度非 canonical');
    }
    pcm = Uint8List.fromList(base64Decode(query.pcmBase64));
  } on FormatException {
    throw const KugouApiException('input', '识曲音频编码无效');
  }
  if (pcm.isEmpty || pcm.length > 160000 || pcm.length % 2 != 0) {
    throw const KugouApiException('input', '识曲音频须为十秒以内的单声道 PCM');
  }
  final identity = await session.ensureDevice();
  final fpid = (now?.call() ?? DateTime.now()).millisecondsSinceEpoch
      .toString();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/fingerprint.service/v1/music_trackid_mulit',
      method: 'POST',
      params: <String, String>{
        'fpid': fpid,
        'area_code': '1',
        'include_unpublish': '1',
        // 上游键名就是 useid（不是 userid 的拼写修正，原样保留）。
        'useid': identity.userId.toString(),
        'multi_result': '1',
      },
      body: pcm,
      headers: const <(String, String)>[
        ('Content-Type', 'application/octet-stream'),
        ('User-Agent', 'KuGou/11490 (Android)'),
        ('kg-rc', '1'),
        ('kg-thash', '5d816a0'),
        ('kg-rec', '1'),
        ('kg-rf', 'B9EDA08A64250DEFFBCADDEE00F8F25F'),
      ],
    ),
  );
  return convertRecognitionMatches(response.bytes);
}

/// audio_match.rs `text(raw, key)`：String 原样；Number → 文本；其它 → null。
String? _rawText(Object? value) => optionalText(value);

/// audio_match.rs `number(raw, key)`：text 后解析 u64；非整数文本 → null。
int? _rawNumber(Object? value) {
  final text = _rawText(value);
  if (text == null) return null;
  return int.tryParse(text);
}

/// audio_match.rs `convert`。
List<MusicRecognitionMatch> convertRecognitionMatches(Uint8List bytes) {
  // request::decode：登录过期探测 → Wire{status 必填, error_code 缺省 0,
  // data 走 recognition_list}。
  final envelope = decodePlaybackEnvelope(bytes, errorCodeOptional: true);
  if (envelope.status != 1) {
    // 上游只判 status，error_code 随 business 码透传。
    throw KugouApiException(
      'business',
      '音乐服务返回失败（识曲）',
      code: envelope.errorCode,
    );
  }
  final rows = playbackRecognitionList(envelope.data, 'data');
  // (原始序号, 候选)：confidence 并列时保持上游 sort_by 的稳定次序。
  final entries = <(int, MusicRecognitionMatch)>[];
  for (var index = 0; index < rows.length; index++) {
    final wire = wireMap(rows[index]);
    if (wire == null) {
      // Candidate 是 serde 结构体：数组/标量行 → decode 失败（request::decode）。
      throw const KugouApiException('decode', '识曲候选不是 object');
    }
    entries.add((index, _convertCandidate(wire)));
  }
  entries.sort((a, b) {
    final ac = a.$2.confidence;
    final bc = b.$2.confidence;
    if (ac == null || bc == null) {
      // Option<f64> 的全序：Some > None → 无 distance 的候选排后面。
      if (ac == null && bc == null) return a.$1.compareTo(b.$1);
      return ac == null ? 1 : -1;
    }
    final descending = bc.compareTo(ac);
    return descending == 0 ? a.$1.compareTo(b.$1) : descending;
  });
  return [for (final (_, match) in entries) match];
}

/// 候选行解码（audio_match.rs `Candidate` + DiscoverySong 投影）。
MusicRecognitionMatch _convertCandidate(Map<String, Object?> raw) {
  final dist = playbackOptionalFiniteDouble(raw['dist']);
  final audioRight = _AudioRight.of(raw);
  final converted = audioRight.trans.convert();
  final rights = converted.$1;
  final resources = converted.$2;
  for (final (suffix, quality, extension) in const <(String, String, String?)>[
    ('128', 'standard', 'mp3'),
    ('192', '192', 'mp3'),
    ('320', 'higher', 'mp3'),
    ('flac', 'flac', 'flac'),
    ('high', 'hi_res', 'flac'),
    ('super', 'master', null),
    ('ape', 'ape', 'ape'),
    ('other', 'other', null),
  ]) {
    final hash = _rawText(raw['hash_$suffix']);
    final sizeBytes = _rawNumber(raw['filesize_$suffix']);
    final durationMs = _rawNumber(raw['timelength_$suffix']);
    final bitrate = _rawNumber(raw['bitrate_$suffix']);
    final bitRateBps = bitrate == null ? null : bitrate * 1000;
    if (hash != null ||
        sizeBytes != null ||
        durationMs != null ||
        bitRateBps != null) {
      resources.add(
        MusicAudioResource(
          quality: quality,
          hash: hash,
          sizeBytes: sizeBytes,
          durationMs: durationMs,
          bitRateBps: bitRateBps,
          extension: extension,
        ),
      );
    }
  }

  final authors = playbackRecognitionList(
    raw['authors'],
    'authors',
  ).map(_convertAuthor).toList();
  final singername = wireText(raw['singername']);
  if (authors.isEmpty && singername.isNotEmpty) {
    authors.add(MusicArtistRef(name: singername));
  }

  return MusicRecognitionMatch(
    song: MusicRecognitionSong(
      id: wireText(raw['mixsongid']),
      hash: wireText(raw['hash_hit']),
      title: wireText(raw['songname']),
      artists: authors,
      albumId: wireText(raw['album_id']),
      albumTitle: _albumTitleOf(raw, wireText(raw['album_id'])),
      durationMs: _rawNumber(raw['timelength_128']),
      coverUrl: coverUrl(wireText(raw['union_cover'])),
      privilege: playbackOptionalUnsigned(raw['privilege']),
      facts: MusicCatalogSongFacts(
        paymentType: audioRight.payType,
        failureCode: audioRight.failureCode,
        oldCopyrightCode: audioRight.oldCopyright,
        originalityCode: playbackOptionalUnsigned(raw['is_original']),
        rights: rights,
        resources: resources,
      ),
    ),
    distance: dist,
    // 展示分 = 1 - clamp(distance, 0, 1)；distance 缺失不代表满分（上游注释）。
    confidence: dist == null ? null : 1.0 - _clamp01(dist),
    timeOffset: optionalInt(raw['timeoffset']),
  );
}

double _clamp01(double value) {
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

/// audio_match.rs `Author`。
MusicArtistRef _convertAuthor(Object? value) {
  final wire = wireMap(value);
  if (wire == null) {
    throw const KugouApiException('decode', '识曲候选作者不是 object');
  }
  return MusicArtistRef(
    id: playbackOptionalUnsigned(wire['author_id']),
    name: wireText(wire['author_name']),
  );
}

/// audio_match.rs：候选 album 列表里 albumid == 候选 album_id 的专辑名。
String? _albumTitleOf(Map<String, Object?> raw, String albumId) {
  for (final row in playbackRecognitionList(raw['album'], 'album')) {
    final wire = wireMap(row);
    if (wire == null) {
      throw const KugouApiException('decode', '识曲候选专辑不是 object');
    }
    if (wireText(wire['albumid']) == albumId) {
      return wireText(wire['albumname']);
    }
  }
  return null;
}

/// audio_match.rs `Rights`（res_privilege 中 kind == "audio" 的那条）。
class _AudioRight {
  const _AudioRight(
    this.payType,
    this.failureCode,
    this.oldCopyright,
    this.trans,
  );

  final int? payType;
  final int? failureCode;
  final int? oldCopyright;
  final _WireTrans trans;

  static _AudioRight of(Map<String, Object?> raw) {
    for (final row in playbackRecognitionList(
      raw['res_privilege'],
      'res_privilege',
    )) {
      final wire = wireMap(row);
      if (wire == null) {
        throw const KugouApiException('decode', '识曲候选权益不是 object');
      }
      if (wireText(wire['type']) == 'audio') {
        final transValue = wire['trans_param'];
        // #[serde(default)]：trans_param 缺省 → 空；present 非 object → 整个
        // 候选 decode 失败（Rust serde 严格）。
        final trans = wireMap(transValue);
        if (transValue != null && trans == null) {
          throw const KugouApiException('decode', '识曲候选 trans_param 不是 object');
        }
        return _AudioRight(
          playbackOptionalUnsigned(wire['pay_type']),
          playbackOptionalUnsigned(wire['fail_process']),
          playbackOptionalUnsigned(wire['old_cpy']),
          _WireTrans(trans ?? const <String, Object?>{}),
        );
      }
    }
    // 无 audio 权益行：付款/失败事实全空，trans_param 走空默认（上游同构）。
    return const _AudioRight(null, null, null, _WireTrans(<String, Object?>{}));
  }
}

/// catalog_rights.rs `WireTrans` → `convert()`（CatalogRights + ogg 资源）。
class _WireTrans {
  const _WireTrans(this._wire);

  final Map<String, Object?> _wire;

  /// catalog_rights.rs `convert`：ogg_128/ogg_320 任一事实存在才产出资源行；
  /// preview 过滤全空区间；union_cover 过 {size} 占位符。
  (MusicCatalogRights, List<MusicAudioResource>) convert() {
    final resources = <MusicAudioResource>[];
    for (final (quality, hashKey, sizeKey) in const <(String, String, String)>[
      ('ogg_128', 'ogg_128_hash', 'ogg_128_filesize'),
      ('ogg_320', 'ogg_320_hash', 'ogg_320_filesize'),
    ]) {
      final hash = optionalText(_wire[hashKey]);
      final size = playbackOptionalUnsigned(_wire[sizeKey]);
      if (hash == null && size == null) continue;
      resources.add(
        MusicAudioResource(
          quality: quality,
          hash: hash,
          sizeBytes: size,
          extension: 'ogg',
        ),
      );
    }
    final previewWire = _wire['hash_offset'];
    final preview = playbackPreviewRange(previewWire);
    final voiceAdWire = wireMap(_wire['voice_ad']);
    final classMapWire = wireMap(_wire['classmap']);
    final unionCover = optionalText(_wire['union_cover']);
    return (
      MusicCatalogRights(
        qualityMap: playbackQualityMap(_wire['qualitymap']),
        classification: classMapWire?.map(
          (key, value) => MapEntry(key, playbackOptionalUnsigned(value)),
        ),
        ipMap: playbackEncodedMap(_wire['ipmap']),
        copyrightAttributes: playbackOptionalUnsigned(_wire['cpy_attr0']),
        copyrightScope: optionalText(_wire['cpy_map']),
        copyrightGrade: playbackOptionalUnsigned(_wire['cpy_grade']),
        copyrightLevel: playbackOptionalUnsigned(_wire['cpy_level']),
        displayCode: playbackOptionalUnsigned(_wire['display']),
        displayRate: playbackOptionalUnsigned(_wire['display_rate']),
        paymentTemplate: playbackOptionalUnsigned(_wire['pay_block_tpl']),
        blockedApplications: optionalText(_wire['appid_block']),
        originalityCode: playbackOptionalUnsigned(_wire['is_original']),
        advanceCode: playbackOptionalUnsigned(_wire['musicpack_advance']),
        preview: preview != null && !preview.isEmpty ? preview : null,
        multitrackHash: optionalText(_wire['hash_multitrack']),
        coverUrl: unionCover == null ? null : coverUrl(unionCover),
        audioPrivilege: playbackOptionalUnsigned(_wire['audio_privilege']),
        freeForAd: playbackOptionalUnsigned(_wire['free_for_ad']),
        freeLimited: playbackOptionalUnsigned(_wire['free_limited']),
        voiceAd: voiceAdWire == null
            ? null
            : MusicVoiceAd(
                startMs: playbackOptionalUnsigned(voiceAdWire['start_ms']),
                sizeBytes: playbackOptionalUnsigned(voiceAdWire['filesize']),
                hash: optionalText(voiceAdWire['hash']),
              ),
      ),
      resources,
    );
  }
}
