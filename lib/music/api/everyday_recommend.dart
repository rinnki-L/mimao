/// 每日推荐端点——EchoMusicNext `crates/echo-api/src/module/everyday_recommend.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 本文件同时承载发现/推荐组（G2）的**组内共享协议翻译**——规格 §2 允许把
/// 共享层缺口先落在组内文件里：
///
/// - `util/recommendation_song.rs`：Song wire 协议与 `decimal` 解析
///   （daily/style/fm 三端点共用的捕获布局）；
/// - `util/catalog_rights.rs` 的 `WireTrans` → 版权事实 + ogg 资源
///   （home/ai/fm/daily/style 五端点共用）；
/// - `util/response.rs` 的组内补充：u64/u32 的 `optional` 语义、
///   `drop_consumed_keys`、信封解码（含 msg「登录已过期」的 authentication
///   判定——共享 wire.dart 只判 error_code=20018；`errcode` 键上的 20018 按
///   上游语义仍是 business）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/discovery_models.dart';
import 'package:mimao/music/models/music_models.dart';

// ---------------------------------------------------------------------------
// util/response.rs 组内补充
// ---------------------------------------------------------------------------

/// `optional` + u64（response.rs ResponseValue::deserialize_u64 +
/// numeric.rs exact_unsigned）：负数、非整数（含 "1.25" 串）、bool/复合类型
/// → null；字符串先按 u64::from_str（容忍首尾空白与 `+` 前缀），再按 JSON
/// 数字文法精确解析（不经过 f64 四舍五入）。
///
/// 注：超过 Dart int（i64）上界的 u64 值（2^63..2^64-1）无法无损表示，
/// 这里返回 null；见交付报告的共享层缺口说明。
int? discoveryOptionalUnsigned(Object? value) =>
    _optionalUnsigned(value, 9223372036854775807);

/// `optional` + u32：超过 4294967295 的值按 `u32::try_from` 失败 → null。
int? discoveryOptionalUnsigned32(Object? value) =>
    _optionalUnsigned(value, 4294967295);

int? _optionalUnsigned(Object? value, int maxValue) {
  if (value == null) return null;
  if (value is int) {
    if (value < 0 || value > maxValue) return null;
    return value;
  }
  if (value is double) {
    // exact_unsigned：负数/非整数 → None。
    if (value.isNegative || !value.isFinite) return null;
    if (value != value.truncateToDouble()) return null;
    if (value > maxValue) return null;
    return value.toInt();
  }
  if (value is String) return _parseUnsignedText(value, maxValue);
  return null; // bool/数组/对象 → None
}

int? _parseUnsignedText(String raw, int maxValue) {
  final text = raw.trim();
  if (text.isEmpty || text.startsWith('-')) return null;
  // 路径一：u64::from_str（接受 +/前导零/首尾空白）。
  final plain = int.tryParse(text);
  if (plain != null) return plain > maxValue ? null : plain;
  // 路径二：serde_json Number 文法（严格：无 + 前缀、无前导零、小数点后
  // 必须有数字），按 exact_unsigned 精确解析。
  final match = RegExp(
    r'^(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$',
  ).firstMatch(text);
  if (match == null) return null;
  final intPart = match.group(1)!;
  final fracPart = match.group(2) ?? '';
  final exponent = int.tryParse(match.group(3) ?? '0') ?? 0;
  var digits = '$intPart$fracPart';
  while (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  // exact_unsigned：全零 → 0（例如 "0.000e20"）。
  if (digits.isEmpty) return 0;
  final scale = exponent - fracPart.length;
  String exact;
  if (scale < 0) {
    // 需要截掉 -scale 位；只有被截位全为 0 才是精确整数。
    final remove = -scale;
    if (remove > digits.length) return null;
    final cut = digits.substring(digits.length - remove);
    if (cut.contains(RegExp('[1-9]'))) return null;
    exact = digits.substring(0, digits.length - remove);
    if (exact.isEmpty) return 0;
  } else {
    // digits.len + zeros > 20 → None（u64 至多 20 位）。
    if (digits.length + scale > 20) return null;
    exact = '$digits${'0' * scale}';
  }
  final parsed = int.tryParse(exact);
  if (parsed == null) return null; // 2^63..2^64-1：Dart i64 装不下
  return parsed > maxValue ? null : parsed;
}

/// recommendation_song.rs `decimal`：无符号十进制串（Rust `str::parse`
/// 不容忍空白）；解析失败 → null（调用点全是 `.ok()`）。
int? discoveryDecimal(String value) {
  if (!RegExp(r'^\+?[0-9]+$').hasMatch(value)) return null;
  return int.tryParse(value);
}

/// response.rs `drop_consumed_keys`：按点分路径（'' = 根）删除已消费键。
/// 沿途容器写时复制——不污染解析输入的原始 wire 映射；缺失容器无操作。
void dropDiscoveryConsumedKeys(
  Map<String, Object?> raw,
  String path,
  List<String> keys,
) {
  var target = raw;
  for (final segment in path.split('.')) {
    if (segment.isEmpty) continue;
    final next = target[segment];
    if (next is! Map) return;
    final copy = Map<String, Object?>.from(next);
    target[segment] = copy;
    target = copy;
  }
  for (final key in keys) {
    target.remove(key);
  }
}

/// 组内信封解码：request.rs `decode` 在 serde 之前对原始字节做登录过期扫描
/// （顶层 `error_code`=20018 或 `msg` 含「登录已过期」→ authentication），
/// 随后按端点信封键解 status/error 码。
///
/// [errorCodeKey]：`errcode`（home_discover / ai_recommend_song）或
/// `error_code`（其余）。[errorCodeRequired]：personal_fm 的 error_code 带
/// serde default（缺省 → 0）；其余端点必填。
WireEnvelope decodeDiscoveryEnvelope(
  Uint8List bytes, {
  String errorCodeKey = 'error_code',
  bool errorCodeRequired = true,
}) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  if (decoded is! Map) {
    throw const KugouApiException('decode', '响应信封不是 JSON object');
  }
  final root = Map<String, Object?>.from(decoded);
  final authCode = optionalInt(root['error_code']);
  final msg = root['msg'];
  if (authCode == kugouErrorCodeAuthenticationExpired ||
      (msg is String && msg.contains('登录已过期'))) {
    throw KugouApiException('authentication', '账号认证无效，请重新登录', code: authCode);
  }
  final status = requiredScalarInt(root['status'], 'status');
  final errorCode = errorCodeRequired || root.containsKey(errorCodeKey)
      ? requiredScalarInt(root[errorCodeKey], errorCodeKey)
      : 0;
  return WireEnvelope(status, errorCode, root['data']);
}

// ---------------------------------------------------------------------------
// util/catalog_rights.rs（WireTrans）
// ---------------------------------------------------------------------------

/// catalog_rights.rs `CONSUMED_KEYS`：WireTrans 显式映射消费的 trans_param
/// 键；剩余键（如 cid）留给各端点的 provider_extension。
const List<String> kugouDiscoveryTransConsumedKeys = <String>[
  'qualitymap',
  'classmap',
  'ipmap',
  'cpy_attr0',
  'cpy_map',
  'cpy_grade',
  'cpy_level',
  'display',
  'display_rate',
  'pay_block_tpl',
  'appid_block',
  'musicpack_advance',
  'is_original',
  'hash_offset',
  'hash_multitrack',
  'union_cover',
  'ogg_128_hash',
  'ogg_128_filesize',
  'ogg_320_hash',
  'ogg_320_filesize',
  'songname_suffix',
  'audio_privilege',
  'free_for_ad',
  'free_limited',
  'voice_ad',
  'language',
];

/// `WireTrans::convert` 的产物（convert 消费结构体；language 在转换前取）。
typedef DiscoveryTransConvert = ({
  MusicDiscoveryCatalogRights rights,
  List<MusicDiscoveryAudioResource> resources,
  String? language,
});

/// `WireTrans` 解码 + `convert`：object 语义（非 object → 全默认，不报
/// decode）；ogg_128/ogg_320 在 hash 与 filesize 皆缺省时跳过，否则入表且
/// extension 恒为 "ogg"。
DiscoveryTransConvert discoveryConvertTransParam(Object? value) {
  final wire = wireMap(value) ?? const <String, Object?>{};
  final language = wireText(wire['language']);

  final qualityMap = wireMap(wire['qualitymap']);
  final classMap = wireMap(wire['classmap']);
  final ipMap = wireMap(wire['ipmap']);
  final voiceAd = wireMap(wire['voice_ad']);
  final unionCover = optionalText(wire['union_cover']);

  final rights = MusicDiscoveryCatalogRights(
    qualityMap: qualityMap == null
        ? null
        : MusicDiscoveryQualityMap(
            attr0: discoveryOptionalUnsigned(qualityMap['attr0']),
            attr1: discoveryOptionalUnsigned(qualityMap['attr1']),
            bits: optionalText(qualityMap['bits']),
          ),
    // optional_map：容器存在时逐值 `.ok()`（非法值 → null），键名原样保留。
    classification: classMap == null
        ? null
        : <String, int?>{
            for (final entry in classMap.entries)
              entry.key: discoveryOptionalUnsigned(entry.value),
          },
    ipMap: ipMap == null
        ? null
        : MusicDiscoveryEncodedMap(
            attr0: discoveryOptionalUnsigned(ipMap['attr0']),
            bits: optionalText(ipMap['bits']),
          ),
    copyrightAttributes: discoveryOptionalUnsigned(wire['cpy_attr0']),
    copyrightScope: optionalText(wire['cpy_map']),
    copyrightGrade: discoveryOptionalUnsigned32(wire['cpy_grade']),
    copyrightLevel: discoveryOptionalUnsigned32(wire['cpy_level']),
    displayCode: discoveryOptionalUnsigned(wire['display']),
    displayRate: discoveryOptionalUnsigned32(wire['display_rate']),
    paymentTemplate: discoveryOptionalUnsigned32(wire['pay_block_tpl']),
    blockedApplications: optionalText(wire['appid_block']),
    originalityCode: discoveryOptionalUnsigned32(wire['is_original']),
    advanceCode: discoveryOptionalUnsigned32(wire['musicpack_advance']),
    // hash_offset.filter(|value| !value.is_empty())：全空区间归 null。
    preview: _previewRange(wire['hash_offset']),
    multitrackHash: optionalText(wire['hash_multitrack']),
    coverUrl: unionCover == null ? null : coverUrl(unionCover),
    audioPrivilege: discoveryOptionalUnsigned32(wire['audio_privilege']),
    freeForAd: discoveryOptionalUnsigned32(wire['free_for_ad']),
    freeLimited: discoveryOptionalUnsigned32(wire['free_limited']),
    voiceAd: voiceAd == null
        ? null
        : MusicDiscoveryVoiceAd(
            startMs: discoveryOptionalUnsigned(voiceAd['start_ms']),
            sizeBytes: discoveryOptionalUnsigned(voiceAd['filesize']),
            hash: optionalText(voiceAd['hash']),
          ),
  );

  final resources = <MusicDiscoveryAudioResource>[];
  for (final (quality, hash, size) in <(String, Object?, Object?)>[
    ('ogg_128', wire['ogg_128_hash'], wire['ogg_128_filesize']),
    ('ogg_320', wire['ogg_320_hash'], wire['ogg_320_filesize']),
  ]) {
    final hashOrNull = optionalText(hash);
    final sizeOrNull = discoveryOptionalUnsigned(size);
    if (hashOrNull == null && sizeOrNull == null) continue;
    resources.add(
      MusicDiscoveryAudioResource(
        quality: quality,
        hash: hashOrNull,
        sizeBytes: sizeOrNull,
        extension: 'ogg',
      ),
    );
  }
  return (
    rights: rights,
    resources: resources,
    // language()：空串保持未知。
    language: language.isEmpty ? null : language,
  );
}

/// 试听区间（privilege_lite.rs `PreviewRange`；object 语义 → 非 object null）。
MusicDiscoveryPreviewRange? _previewRange(Object? value) {
  final map = wireMap(value);
  if (map == null) return null;
  return MusicDiscoveryPreviewRange(
    startByte: discoveryOptionalUnsigned(map['start_byte']),
    endByte: discoveryOptionalUnsigned(map['end_byte']),
    startMs: discoveryOptionalUnsigned(map['start_ms']),
    endMs: discoveryOptionalUnsigned(map['end_ms']),
    offsetHash: optionalText(map['offset_hash']),
    fileType: discoveryOptionalUnsigned32(map['file_type']),
    clipHash: optionalText(map['clip_hash']),
  );
}

// ---------------------------------------------------------------------------
// util/recommendation_song.rs（Song 协议）
// ---------------------------------------------------------------------------

/// recommendation_song.rs `Song` → `MusicDiscoverySong`。
/// [wire] 必须是 object（列表元素的非 object 由调用方按 `list` 语义报 decode）；
/// Song 的全部字段都有 serde default，任何 object 都可解析。
MusicDiscoverySong discoveryRecommendationSongFromWire(
  Map<String, Object?> wire,
) {
  final trans = discoveryConvertTransParam(wire['trans_param']);
  final rights = trans.rights;
  final resources = List.of(trans.resources);

  final timeLength = discoveryOptionalUnsigned(wire['time_length']);
  final bitrate = discoveryOptionalUnsigned(wire['bitrate']);
  // 六档资源全部无条件入表；hash 是 Some(空串)（与 trans_param 的 Option
  // 语义刻意不同——上游 push 循环原样）。
  for (final (quality, hash, size, seconds, ext)
      in <(String, String, int?, int?, String?)>[
        (
          '128',
          wireText(wire['hash_128']),
          discoveryOptionalUnsigned(wire['filesize_128']),
          timeLength,
          wireText(wire['extname']),
        ),
        (
          '192',
          wireText(wire['hash_192']),
          discoveryOptionalUnsigned(wire['filesize_192']),
          null,
          null,
        ),
        (
          '320',
          wireText(wire['hash_320']),
          discoveryOptionalUnsigned(wire['filesize_320']),
          discoveryOptionalUnsigned(wire['timelength_320']),
          null,
        ),
        (
          'flac',
          wireText(wire['hash_flac']),
          discoveryOptionalUnsigned(wire['filesize_flac']),
          null,
          null,
        ),
        (
          'ape',
          wireText(wire['hash_ape']),
          discoveryOptionalUnsigned(wire['filesize_ape']),
          null,
          null,
        ),
        (
          'other',
          wireText(wire['hash_other']),
          discoveryOptionalUnsigned(wire['filesize_other']),
          null,
          null,
        ),
      ]) {
    resources.add(
      MusicDiscoveryAudioResource(
        quality: quality,
        hash: hash,
        sizeBytes: size,
        durationMs: seconds == null ? null : seconds * 1000,
        // bit_rate_bps：只给 128 档（bitrate * 1000）。
        bitRateBps: quality == '128' && bitrate != null ? bitrate * 1000 : null,
        extension: ext,
      ),
    );
  }

  final artists = _singerDetails(wireList(wire['singerinfo'], 'singerinfo'));

  final mvHash = wireText(wire['mv_hash']);
  final videos = mvHash.isEmpty
      ? const <MusicDiscoveryVideoReference>[]
      : <MusicDiscoveryVideoReference>[
          MusicDiscoveryVideoReference(
            hash: mvHash,
            kind: discoveryOptionalUnsigned32(wire['mv_type']),
          ),
        ];

  final song = MusicDiscoverySongSummary(
    id: wireText(wire['album_audio_id']),
    hash: wireText(wire['hash']),
    title: wireText(wire['songname']),
    artists: <MusicArtistRef>[
      for (final artist in artists)
        MusicArtistRef(id: artist.id, name: artist.name),
    ],
    albumId: wireText(wire['album_id']),
    // 上游 Some(self.album_name)：空串也保留（不归一成 null）。
    albumTitle: wireText(wire['album_name']),
    durationMs: timeLength == null ? null : timeLength * 1000,
    coverUrl: coverUrl(wireText(wire['sizable_cover'])),
    privilege: discoveryOptionalUnsigned32(wire['privilege']),
  );
  final metadata = MusicDiscoverySongMetadata(
    // Option<Value> 的 optional：null → None，其余原样。
    relatedGoodsExtension: wire['relate_goods'],
    providerExtension: null,
    accompanimentCode: discoveryOptionalUnsigned32(wire['has_accompany']),
    audioId: discoveryOptionalUnsigned(wire['songid']),
    // original/official/suffix/language/published_at 上游恒 Some（空串保留）。
    originalTitle: wireText(wire['ori_audio_name']),
    officialTitle: wireText(wire['official_songname']),
    titleSuffix: wireText(wire['suffix_audio_name']),
    albumAudioRemark: wireText(wire['album_audio_remark']),
    sourceFileName: wireText(wire['filename']),
    language: wireText(wire['language']),
    publishedAt: wireText(wire['publish_date']),
    publicationCode: discoveryOptionalUnsigned32(wire['is_publish']),
    originalityCode: discoveryOptionalUnsigned32(wire['is_original']),
    // has_accompany.and_then(numeric::boolean)：0/1 → bool，其它未知。
    hasAccompaniment: optionalBool(wire['has_accompany']),
    paymentType: discoveryOptionalUnsigned32(wire['pay_type']),
    failureCode: discoveryOptionalUnsigned32(wire['fail_process']),
    oldCopyrightCode: discoveryOptionalUnsigned32(wire['old_cpy']),
    rights: rights,
    resources: resources,
    videos: videos,
    tags: _songTags(wireList(wire['tags'], 'tags')),
    ipTags: _ipTags(wire['ips_tags']),
    recommendation: MusicDiscoveryRecommendationText(
      headline: optionalText(wire['rec_copy_write']) ?? '',
      detail: optionalText(wire['rec_sub_copy_write']) ?? '',
      rankLabel: optionalText(wire['rank_label']),
    ),
    ranking: null,
    artists: artists,
    relatedVersions: const <MusicDiscoveryRelatedVersion>[],
  );
  return MusicDiscoverySong(song: song, metadata: metadata);
}

/// `Vec<Singer>`（list 语义：元素非 object → 整个 Song 解析失败 → decode）。
List<MusicDiscoveryArtistDetail> _singerDetails(List<Object?> singers) {
  final artists = <MusicDiscoveryArtistDetail>[];
  for (final raw in singers) {
    final singer = wireMap(raw);
    if (singer == null) {
      throw const KugouApiException('decode', '推荐歌曲歌手项不是 object');
    }
    // is_publish 是 Option<String>（数字串也收），decimal → u32::try_from。
    final isPublish = optionalText(singer['is_publish']);
    final publishCode = isPublish == null ? null : discoveryDecimal(isPublish);
    artists.add(
      MusicDiscoveryArtistDetail(
        id: discoveryDecimal(wireText(singer['id'])),
        name: wireText(singer['name']),
        publicationCode: publishCode != null && publishCode <= 4294967295
            ? publishCode
            : null,
      ),
    );
  }
  return artists;
}

/// `Vec<Tag>`（list 语义：元素非 object → decode）。
List<MusicDiscoverySongTag> _songTags(List<Object?> tags) {
  final result = <MusicDiscoverySongTag>[];
  for (final raw in tags) {
    final tag = wireMap(raw);
    if (tag == null) {
      throw const KugouApiException('decode', '推荐歌曲标签项不是 object');
    }
    result.add(
      MusicDiscoverySongTag(
        id: wireText(tag['tag_id']),
        name: wireText(tag['tag_name']),
        parentId: wireText(tag['parent_id']),
      ),
    );
  }
  return result;
}

/// `IpTags` untagged（`List(Vec<IpTag>) | Entry(IpTag)`），外层套 `object` 语义：
/// 缺省/null/数字等不可解析形态 → 字段默认空表；List 里任一元素非法 →
/// 同样整体回默认空表；单 Entry 三字段全缺省 → 空表。
List<MusicDiscoverySongTag> _ipTags(Object? value) {
  MusicDiscoverySongTag? tagOf(Object? raw) {
    final tag = wireMap(raw);
    if (tag == null) return null;
    return MusicDiscoverySongTag(
      id: optionalText(tag['ip_id']),
      name: optionalText(tag['name']),
      parentId: optionalText(tag['pid']),
    );
  }

  if (value is List) {
    final tags = <MusicDiscoverySongTag>[];
    for (final raw in value) {
      final tag = tagOf(raw);
      if (tag == null) return const <MusicDiscoverySongTag>[];
      tags.add(tag);
    }
    return tags;
  }
  if (value is Map) {
    final tag = tagOf(value);
    if (tag == null) return const <MusicDiscoverySongTag>[];
    final empty = tag.id == null && tag.name == null && tag.parentId == null;
    return empty
        ? const <MusicDiscoverySongTag>[]
        : <MusicDiscoverySongTag>[tag];
  }
  return const <MusicDiscoverySongTag>[];
}

/// `Vec<Song>`（list 语义：null/空 object → 空表；元素非 object → decode）。
/// daily/style 两端点共用同一字段名 song_list。
List<MusicDiscoverySong> discoveryRecommendationSongs(Object? value) {
  final songs = <MusicDiscoverySong>[];
  for (final raw in wireList(value, 'song_list')) {
    final wire = wireMap(raw);
    if (wire == null) {
      throw const KugouApiException('decode', '推荐歌曲项不是 object');
    }
    songs.add(discoveryRecommendationSongFromWire(wire));
  }
  return songs;
}

// ---------------------------------------------------------------------------
// 端点本体（module/everyday_recommend.rs）
// ---------------------------------------------------------------------------

/// 每日推荐——POST /everyday_song_recommend（网关 + x-router=
/// everydayrec.service.kugou.com；platform=ios；空请求体）。
Future<MusicDailyRecommendations> fetchEverydayRecommend(
  MusicSession session,
) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/everyday_song_recommend',
      router: 'everydayrec.service.kugou.com',
      method: 'POST',
      params: const <String, String>{'platform': 'ios'},
    ),
  );
  return _convertEverydayRecommend(response.bytes);
}

/// wire 解析（everyday_recommend.rs `convert`）。
MusicDailyRecommendations _convertEverydayRecommend(Uint8List bytes) {
  final envelope = decodeDiscoveryEnvelope(bytes);
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '每日推荐');
  // Envelope<Value> 的 data 缺省为 Null，Data 解析失败 → decode（上游一致）。
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '每日推荐响应 data 不是 object');
  }
  return MusicDailyRecommendations(
    songs: discoveryRecommendationSongs(data['song_list']),
    date: wireText(data['creation_date']),
    subtitle: wireText(data['sub_title']),
  );
}
