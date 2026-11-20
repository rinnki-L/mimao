/// 已购单曲端点——EchoMusicNext `crates/echo-api/src/module/
/// user_purchased_songs.rs` 的翻译（docs/architecture.md §4.3）。
///
/// 行语义按 2026-10-28 非空样本映射：audio_info 携带各音质 hash/大小/权限，
/// trans_param 显式消费进版权事实（util/catalog_rights.rs `WireTrans`），
/// 未消费键与行内未知键留进 provider_extension；购买商品 id 与音频身份
/// （album_audio_id/hash）分开保留。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/user_purchased_albums.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/user_library_models.dart';

export 'package:mimao/music/api/user_purchased_albums.dart'
    show MusicUserPagedQuery;

/// trans_param 已被显式映射消费的键（catalog_rights.rs `CONSUMED_KEYS`）；
/// 剩余键原样进 provider_extension。
const Set<String> _kConsumedTransKeys = <String>{
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
};

const Set<String> _kRowKeys = <String>{
  'album_audio_id',
  'album_id',
  'hash',
  'songname',
  'album_cover',
  'author_name',
  'author_avatar',
  'audio_info',
};

const Set<String> _kAudioKeys = <String>{
  'hash_128',
  'hash_320',
  'hash_flac',
  'hash_high',
  'filesize_128',
  'filesize_320',
  'filesize_flac',
  'filesize_high',
  'privilege_128',
  'privilege_320',
  'privilege_flac',
  'privilege_high',
  'name',
  'album_name',
  'album_id',
  'duration',
  'bitrate',
  'pay_type',
  'old_cpy',
  'fail_process',
  'trans_param',
};

/// POST /openapi/copyright/v1/audio/get_goods（网关；需要账号）。
Future<MusicPage<MusicPurchasedSong>> fetchUserPurchasedSongs(
  MusicSession session,
  MusicUserPagedQuery query,
) async {
  final identity = await session.ensureDevice();
  requireMusicAccount(identity);
  query.validate(invalidMessage: '已购单曲分页参数无效');

  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/openapi/copyright/v1/audio/get_goods',
      method: 'POST',
      // Rust json! 宏经 BTreeMap 序列化：键按字典序输出。
      body: encodeJsonBody(<String, Object?>{
        'appid': 3116,
        'area_code': '1',
        'clientver': '11440',
        'deleted': 0,
        'need_audio_info': 1,
        'page': query.page,
        'pagesize': query.pageSize,
        'token': identity.token,
        'userid': identity.userId,
      }),
    ),
  );
  return _convertPurchasedSongs(response.bytes, query.page, query.pageSize);
}

/// wire 解析（user_purchased_songs.rs `convert`）。
MusicPage<MusicPurchasedSong> _convertPurchasedSongs(
  Uint8List bytes,
  int page,
  int pageSize,
) {
  final envelope = decodeEnvelope(bytes);
  if (envelope.status != 1 && envelope.errorCode == 20017) {
    throw KugouApiException(
      'authentication',
      '账号认证无效，请重新登录',
      code: envelope.errorCode,
    );
  }
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '已购单曲');
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '已购单曲响应 data 不是 object');
  }
  final items = wireList(
    data['goods'],
    'goods',
  ).map(_convertPurchasedSong).toList();
  return MusicPage<MusicPurchasedSong>(
    page: page,
    pageSize: pageSize,
    total: musicWireUnsigned(data['total']),
    items: items,
  );
}

MusicPurchasedSong _convertPurchasedSong(Object? raw) {
  final row = wireMap(raw);
  if (row == null) {
    throw const KugouApiException('decode', '已购单曲条目不是 object');
  }
  // audio_info：缺省/null/非 object → 全空默认（上游 `object` 反序列化器）。
  final audio = wireMap(row['audio_info']) ?? const <String, Object?>{};
  final trans = wireMap(audio['trans_param']) ?? const <String, Object?>{};

  // trans_param → 版权事实 + ogg 资源（catalog_rights.rs `WireTrans::convert`）。
  final rights = _convertRights(trans);
  final resources = _oggResources(trans);
  final bitrate = musicWireUnsigned(audio['bitrate']);

  // 128/320/flac/high：全空条目跳过；bitrate 只修饰 128 档（×1000）。
  for (final (quality, hashKey, sizeKey, privilegeKey)
      in const <(String, String, String, String)>[
        ('128', 'hash_128', 'filesize_128', 'privilege_128'),
        ('320', 'hash_320', 'filesize_320', 'privilege_320'),
        ('flac', 'hash_flac', 'filesize_flac', 'privilege_flac'),
        ('high', 'hash_high', 'filesize_high', 'privilege_high'),
      ]) {
    final hash = wireText(audio[hashKey]);
    final size = musicWireUnsigned(audio[sizeKey]);
    final privilege = musicWireU32(audio[privilegeKey]);
    if (hash.isEmpty && size == null && privilege == null) continue;
    resources.add(
      MusicAudioResource(
        quality: quality,
        hash: hash.isEmpty ? null : hash,
        sizeBytes: size,
        // 每档不携带独立时长；128kbps 的事实描述的是默认音频。
        durationMs: null,
        bitRateBps: quality == '128' && bitrate != null ? bitrate * 1000 : null,
        extension: null,
        privilege: privilege,
        payType: musicWireU32(audio['pay_type']),
        failureCode: musicWireU32(audio['fail_process']),
      ),
    );
  }

  // 播放 hash 择优：high > flac > 320 > 128 > 行顶 hash。
  final selectedHash = <String>[
    wireText(audio['hash_high']),
    wireText(audio['hash_flac']),
    wireText(audio['hash_320']),
    wireText(audio['hash_128']),
    wireText(row['hash']),
  ].firstWhere((hash) => hash.isNotEmpty, orElse: () => '');

  final authorName = wireText(row['author_name']);
  final authorAvatar = wireText(row['author_avatar']);
  final audioAlbumId = musicWireUnsigned(audio['album_id']);
  final rowAlbumId = musicWireUnsigned(row['album_id']);
  final audioAlbumName = wireText(audio['album_name']);
  final audioId = musicWireUnsigned(row['album_audio_id']);

  return MusicPurchasedSong(
    song: MusicSongSummary(
      id: audioId != null && audioId > 0 ? audioId.toString() : '',
      hash: selectedHash,
      title: wireText(row['songname']),
      artists: authorName.isEmpty
          ? const <MusicArtistRef>[]
          : <MusicArtistRef>[MusicArtistRef(name: authorName)],
      // 专辑 id：audio 优先（>0），回退行顶（>0）；都缺 → 空串。
      albumId:
          (audioAlbumId != null && audioAlbumId > 0
                  ? audioAlbumId
                  : (rowAlbumId != null && rowAlbumId > 0 ? rowAlbumId : null))
              ?.toString() ??
          '',
      albumTitle: audioAlbumName.isEmpty ? null : audioAlbumName,
      durationMs: musicWireUnsigned(audio['duration']),
      coverUrl: wireText(row['album_cover']).replaceAll('{size}', '400'),
      // 权限链：high → flac → 320 → 128。
      privilege:
          musicWireU32(audio['privilege_high']) ??
          musicWireU32(audio['privilege_flac']) ??
          musicWireU32(audio['privilege_320']) ??
          musicWireU32(audio['privilege_128']),
    ),
    metadata: MusicPurchasedSongMetadata(
      catalog: MusicCatalogFacts(
        paymentType: musicWireU32(audio['pay_type']),
        failureCode: musicWireU32(audio['fail_process']),
        oldCopyrightCode: musicWireU32(audio['old_cpy']),
        // 目录事实的原创码来自 trans_param 的 is_original（不是 old_cpy）。
        originalityCode: rights.originalityCode,
        rights: rights,
        resources: resources,
      ),
      sourceFileName: wireText(audio['name']),
      language: _languageOf(trans),
      artists: authorName.isEmpty
          ? const <MusicArtistDetail>[]
          : <MusicArtistDetail>[
              MusicArtistDetail(
                id: null,
                name: authorName,
                avatarUrl: authorAvatar.isEmpty ? null : coverUrl(authorAvatar),
                publicationCode: null,
              ),
            ],
      providerExtension: _providerExtension(row, audio, trans),
    ),
  );
}

/// trans_param `language`（text）；空串保持未知。
String? _languageOf(Map<String, Object?> trans) {
  final language = wireText(trans['language']);
  return language.isEmpty ? null : language;
}

/// WireTrans 的显式消费面（catalog_rights.rs `convert` 的 rights 半边）；
/// 所有字段宽容解码——trans_param 永不导致整行 decode 失败。
MusicCatalogRights _convertRights(Map<String, Object?> trans) {
  final unionCover = optionalText(trans['union_cover']);
  return MusicCatalogRights(
    qualityMap: _qualityMap(trans['qualitymap']),
    classification: _unsignedMap(trans['classmap']),
    ipMap: _encodedMap(trans['ipmap']),
    copyrightAttributes: musicWireUnsigned(trans['cpy_attr0']),
    copyrightScope: optionalText(trans['cpy_map']),
    copyrightGrade: musicWireU32(trans['cpy_grade']),
    copyrightLevel: musicWireU32(trans['cpy_level']),
    displayCode: musicWireUnsigned(trans['display']),
    displayRate: musicWireU32(trans['display_rate']),
    paymentTemplate: musicWireU32(trans['pay_block_tpl']),
    blockedApplications: optionalText(trans['appid_block']),
    originalityCode: musicWireU32(trans['is_original']),
    advanceCode: musicWireU32(trans['musicpack_advance']),
    preview: _previewRange(trans['hash_offset']),
    multitrackHash: optionalText(trans['hash_multitrack']),
    coverUrl: unionCover == null ? null : coverUrl(unionCover),
    audioPrivilege: musicWireU32(trans['audio_privilege']),
    freeForAd: musicWireU32(trans['free_for_ad']),
    freeLimited: musicWireU32(trans['free_limited']),
    voiceAd: _voiceAd(trans['voice_ad']),
  );
}

MusicQualityMap? _qualityMap(Object? raw) {
  final map = wireMap(raw);
  if (map == null) return null;
  return MusicQualityMap(
    attr0: musicWireUnsigned(map['attr0']),
    attr1: musicWireUnsigned(map['attr1']),
    bits: optionalText(map['bits']),
  );
}

MusicEncodedMap? _encodedMap(Object? raw) {
  final map = wireMap(raw);
  if (map == null) return null;
  return MusicEncodedMap(
    attr0: musicWireUnsigned(map['attr0']),
    bits: optionalText(map['bits']),
  );
}

/// 键 → u64 或未知（optional_map 语义：未知条目保留为 null，不整表丢弃）。
Map<String, int?>? _unsignedMap(Object? raw) {
  final map = wireMap(raw);
  if (map == null) return null;
  return <String, int?>{
    for (final entry in map.entries) entry.key: musicWireUnsigned(entry.value),
  };
}

MusicPreviewRange? _previewRange(Object? raw) {
  final map = wireMap(raw);
  if (map == null) return null;
  final preview = MusicPreviewRange(
    startByte: musicWireUnsigned(map['start_byte']),
    endByte: musicWireUnsigned(map['end_byte']),
    startMs: musicWireUnsigned(map['start_ms']),
    endMs: musicWireUnsigned(map['end_ms']),
    offsetHash: optionalText(map['offset_hash']),
    fileType: musicWireU32(map['file_type']),
    clipHash: optionalText(map['clip_hash']),
  );
  // 全空区间按无试听信息处理（上游 `filter(!is_empty)`）。
  return preview.isEmpty ? null : preview;
}

MusicVoiceAd? _voiceAd(Object? raw) {
  final map = wireMap(raw);
  if (map == null) return null;
  return MusicVoiceAd(
    startMs: musicWireUnsigned(map['start_ms']),
    sizeBytes: musicWireUnsigned(map['filesize']),
    hash: optionalText(map['hash']),
  );
}

/// WireTrans 的 ogg 资源（catalog_rights.rs `convert` 的 resources 半边）：
/// hash/size 全空跳过；固定 extension=ogg。
List<MusicAudioResource> _oggResources(Map<String, Object?> trans) {
  final resources = <MusicAudioResource>[];
  for (final (quality, hashKey, sizeKey) in const <(String, String, String)>[
    ('ogg_128', 'ogg_128_hash', 'ogg_128_filesize'),
    ('ogg_320', 'ogg_320_hash', 'ogg_320_filesize'),
  ]) {
    final hash = optionalText(trans[hashKey]);
    final size = musicWireUnsigned(trans[sizeKey]);
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
  return resources;
}

/// provider_extension（convert_row 的 `extension` JSON；BTreeMap 键序）：
/// audio / listed_album_id / listed_hash / purchase / trans_param。
Object? _providerExtension(
  Map<String, Object?> row,
  Map<String, Object?> audio,
  Map<String, Object?> trans,
) {
  final leftoverTransKeys =
      trans.keys.where((key) => !_kConsumedTransKeys.contains(key)).toList()
        ..sort();
  return <String, Object?>{
    'audio': _extraOf(audio, _kAudioKeys),
    'listed_album_id': musicWireUnsigned(row['album_id']),
    'listed_hash': wireText(row['hash']),
    'purchase': _extraOf(row, _kRowKeys),
    'trans_param': <String, Object?>{
      for (final key in leftoverTransKeys) key: trans[key],
    },
  };
}

/// `#[serde(flatten)] extra`：未知键原样保留（按 BTreeMap 键序整理）。
Map<String, Object?> _extraOf(Map<String, Object?> wire, Set<String> known) {
  final extraKeys = wire.keys.where((key) => !known.contains(key)).toList()
    ..sort();
  return <String, Object?>{for (final key in extraKeys) key: wire[key]};
}
