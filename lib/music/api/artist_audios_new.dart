/// 歌手歌曲端点——EchoMusicNext `crates/echo-api/src/module/artist_audios_new.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// /artist/audios/new 映射 /openapi/kmr/v2/audio_group/author（网关 GET，
/// 无 x-router，kg-tid=36）：每首歌带结构化 authors、毫秒 timelength、
/// 可选专辑/封面事实与平铺的各音质资源（角标用），并完整移植 trans_param
/// 版权事实（catalog_rights.rs `WireTrans`）的 ogg 资源与回退链。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/artist_models.dart';
import 'package:mimao/music/models/music_models.dart';

/// 歌手歌曲查询（audios_new.rs `Query`：page=1、page_size=100、sort='new'）。
class MusicArtistAudiosQuery {
  const MusicArtistAudiosQuery({
    required this.id,
    this.page = 1,
    this.pageSize = 100,
    this.sort = 'new',
  });

  /// 歌手 id（u64 输入域；负数在 Rust 侧是反序列化失败）。
  final int id;

  /// 1 起始页码。
  final int page;
  final int pageSize;
  final String sort;

  /// 上游 execute() 入口校验（顺序一致：分页在前，排序映射在后）。
  void validate() {
    if (id < 0) {
      throw const KugouApiException('input', '歌手 id 无效');
    }
    if (page < 1 || pageSize < 1 || pageSize > 100) {
      throw const KugouApiException('input', '歌手歌曲分页参数无效');
    }
    if (sort != 'hot' && sort != 'new') {
      throw const KugouApiException('input', '歌手歌曲排序无效');
    }
  }
}

/// 排序词 → wire sort（audios_new.rs：hot→'1'、new→'2'）。
String artistAudiosSortCode(String sort) => sort == 'hot' ? '1' : '2';

/// 歌手歌曲分页（含音质/权限/版权事实）。
Future<MusicPage<MusicArtistSong>> fetchArtistAudiosNew(
  MusicSession session,
  MusicArtistAudiosQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/openapi/kmr/v2/audio_group/author',
      method: 'GET',
      params: <String, String>{
        'author_id': query.id.toString(),
        'area_code': 'all',
        'sort': artistAudiosSortCode(query.sort),
        'page': query.page.toString(),
        'pagesize': query.pageSize.toString(),
        'replace_api_version': '1',
        'mvdata_need': '1',
        'show_audio_honor': '1',
        'show_audio_tag': '1',
        'replace_need': '1',
      },
      headers: const <(String, String)>[('kg-tid', '36')],
    ),
  );
  return _convertArtistAudios(response.bytes, query.page, query.pageSize);
}

/// wire 解析（audios_new.rs `convert`）。
MusicPage<MusicArtistSong> _convertArtistAudios(
  Uint8List bytes,
  int page,
  int pageSize,
) {
  final envelope = decodeBusinessEnvelope(bytes, context: '歌手歌曲');
  // Data：total 可选、songs list；data 缺省/null/数组都按 decode 失败
  // （Rust from_value::<Data> 对 Null/Array 的 map 反序列化必败）。
  final data = requiredWireMap(envelope.data, 'data');
  final items = <MusicArtistSong>[];
  for (final raw in wireList(data['songs'], 'songs')) {
    final song = wireMap(raw);
    if (song == null) {
      throw const KugouApiException('decode', '歌手歌曲响应 songs 元素不是 object');
    }
    items.add(_convertSong(song));
  }
  return MusicPage<MusicArtistSong>(
    page: page,
    pageSize: pageSize,
    total: optionalInt(data['total']),
    items: items,
  );
}

MusicArtistSong _convertSong(Map<String, Object?> song) {
  // 嵌套对象按上游 `object` 反序列化：缺省/非 object → 全默认结构，不报错。
  final audio = wireMap(song['audio_info']) ?? const <String, Object?>{};
  final albumInfo = wireMap(song['album_info']) ?? const <String, Object?>{};
  final copyright = wireMap(song['copyright']) ?? const <String, Object?>{};
  final goods = wireMap(song['goods_info']) ?? const <String, Object?>{};
  final extra = wireMap(song['extra']) ?? const <String, Object?>{};
  final privileges =
      wireMap(song['privilege_download']) ?? const <String, Object?>{};
  final trans =
      wireMap(copyright['trans_param_departed']) ?? const <String, Object?>{};

  final hash = wireText(audio['hash']);
  final rights = _convertTrans(trans);
  final resources = rights.resources;
  // 封面回退链：trans_param.union_cover（已过 cover_url）→ album_info.cover。
  final cover =
      rights.rights.coverUrl ?? coverUrl(wireText(albumInfo['cover']));
  final payType = optionalInt(goods['audio_pay_type']);
  final failureCode = optionalInt(privileges['fail_process_128']);

  // 平铺各音质资源（顺序：128/320/flac/high/super；hash 恒入表——空串保留，
  // 与搜索端点的全空跳过语义刻意不同）。bitrate 只有 128/flac/high/super。
  void pushQuality(
    String quality,
    String qualityHash,
    int? sizeBytes,
    int? durationMs,
    int? privilege,
    int? bitrate,
    String? extension,
  ) {
    resources.add(
      MusicAudioResource(
        quality: quality,
        hash: qualityHash,
        sizeBytes: sizeBytes,
        durationMs: durationMs,
        bitRateBps: bitrate == null ? null : _bitRateBps(bitrate),
        extension: extension,
        privilege: privilege,
        payType: payType,
        failureCode: failureCode,
      ),
    );
  }

  pushQuality(
    '128',
    hash,
    optionalInt(audio['filesize']),
    optionalInt(audio['timelength']),
    optionalInt(privileges['privilege_128']),
    optionalInt(audio['bitrate']),
    wireText(audio['extname']),
  );
  pushQuality(
    '320',
    wireText(audio['hash_320']),
    optionalInt(audio['filesize_320']),
    optionalInt(audio['timelength_320']),
    optionalInt(privileges['privilege_320']),
    null,
    null,
  );
  pushQuality(
    'flac',
    wireText(audio['hash_flac']),
    optionalInt(audio['filesize_flac']),
    optionalInt(audio['timelength_flac']),
    optionalInt(privileges['privilege_flac']),
    optionalInt(audio['bitrate_flac']),
    null,
  );
  pushQuality(
    'high',
    wireText(audio['hash_high']),
    optionalInt(audio['filesize_high']),
    optionalInt(audio['timelength_high']),
    optionalInt(privileges['privilege_high']),
    optionalInt(audio['bitrate_high']),
    null,
  );
  pushQuality(
    'super',
    wireText(audio['hash_super']),
    optionalInt(audio['filesize_super']),
    optionalInt(audio['timelength_super']),
    optionalInt(privileges['privilege_super']),
    optionalInt(audio['bitrate_super']),
    wireText(audio['extname_super']),
  );

  final authors = <MusicArtistRef>[];
  for (final entry in wireList(song['authors'], 'authors')) {
    final author = wireMap(entry);
    if (author == null) {
      throw const KugouApiException('decode', '歌手歌曲响应 authors 元素不是 object');
    }
    final base = wireMap(author['base']) ?? const <String, Object?>{};
    // into_ref：base.author_name 非空优先，否则回退平铺 author_name；两者
    // 皆空 → 整条丢弃（filter_map）。id 用 base.author_id 回退平铺值。
    final baseName = wireText(base['author_name']);
    final name = baseName.isNotEmpty
        ? baseName
        : wireText(author['author_name']);
    if (name.isEmpty) continue;
    authors.add(
      MusicArtistRef(
        id: optionalInt(base['author_id']) ?? optionalInt(author['author_id']),
        name: name,
      ),
    );
  }

  final albumAudioId = wireText(song['album_audio_id']);
  final albumName = wireText(albumInfo['album_name']);
  return MusicArtistSong(
    // id 回退链：album_audio_id 空 → 文件 hash。
    id: albumAudioId.isEmpty ? hash : albumAudioId,
    hash: hash,
    title: wireText(song['audio_name']),
    artists: authors,
    albumId: wireText(song['album_id']),
    albumTitle: albumName.isEmpty ? null : albumName,
    // timelength 本来就是毫秒，原样透传。
    durationMs: optionalInt(audio['timelength']),
    coverUrl: cover,
    privilege:
        optionalInt(privileges['privilege']) ??
        optionalInt(privileges['privilege_128']),
    metadata: MusicArtistSongFacts(
      paymentType: payType,
      failureCode: failureCode,
      oldCopyrightCode: optionalInt(copyright['old_cpy']),
      // originality 回退链：extra.is_original → trans_param.is_original。
      originalityCode:
          optionalInt(extra['is_original']) ?? rights.rights.originalityCode,
      rights: rights.rights,
      resources: resources,
    ),
  );
}

/// trans_param 版权事实（catalog_rights.rs `WireTrans::convert`）。
///
/// 上游所有字段都走 optional/text/object 宽容反序列化，convert 实际不会
/// 失败（Err 分支是不可达死码），因此恒产出 rights + ogg 资源。
class _TransConversion {
  const _TransConversion(this.rights, this.resources);

  final MusicArtistSongRights rights;
  final List<MusicAudioResource> resources;
}

_TransConversion _convertTrans(Map<String, Object?> trans) {
  final resources = <MusicAudioResource>[];
  // ogg 资源：hash 与 size 都缺省才跳过（与平铺音质的跳过判定一致）。
  for (final (quality, hashKey, sizeKey) in const <(String, String, String)>[
    ('ogg_128', 'ogg_128_hash', 'ogg_128_filesize'),
    ('ogg_320', 'ogg_320_hash', 'ogg_320_filesize'),
  ]) {
    final hash = optionalText(trans[hashKey]);
    final size = optionalInt(trans[sizeKey]);
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
  final unionCover = optionalText(trans['union_cover']);
  return _TransConversion(
    MusicArtistSongRights(
      qualityMap: _convertQualityMap(trans['qualitymap']),
      classification: _convertClassMap(trans['classmap']),
      ipMap: _convertEncodedMap(trans['ipmap']),
      copyrightAttributes: optionalInt(trans['cpy_attr0']),
      copyrightScope: optionalText(trans['cpy_map']),
      copyrightGrade: optionalInt(trans['cpy_grade']),
      copyrightLevel: optionalInt(trans['cpy_level']),
      displayCode: optionalInt(trans['display']),
      displayRate: optionalInt(trans['display_rate']),
      paymentTemplate: optionalInt(trans['pay_block_tpl']),
      blockedApplications: optionalText(trans['appid_block']),
      originalityCode: optionalInt(trans['is_original']),
      advanceCode: optionalInt(trans['musicpack_advance']),
      preview: _convertPreviewRange(trans['hash_offset']),
      multitrackHash: optionalText(trans['hash_multitrack']),
      coverUrl: unionCover == null ? null : coverUrl(unionCover),
      audioPrivilege: optionalInt(trans['audio_privilege']),
      freeForAd: optionalInt(trans['free_for_ad']),
      freeLimited: optionalInt(trans['free_limited']),
      voiceAd: _convertVoiceAd(trans['voice_ad']),
    ),
    resources,
  );
}

MusicArtistQualityMap? _convertQualityMap(Object? value) {
  final map = wireMap(value);
  if (map == null) return null;
  return MusicArtistQualityMap(
    attr0: optionalInt(map['attr0']),
    attr1: optionalInt(map['attr1']),
    bits: optionalText(map['bits']),
  );
}

/// classmap（optional_map）：非 object → null；解析不了的值保留 null 键位。
Map<String, int?>? _convertClassMap(Object? value) {
  final map = wireMap(value);
  if (map == null) return null;
  return map.map((key, value) => MapEntry(key, optionalInt(value)));
}

MusicArtistEncodedMap? _convertEncodedMap(Object? value) {
  final map = wireMap(value);
  if (map == null) return null;
  return MusicArtistEncodedMap(
    attr0: optionalInt(map['attr0']),
    bits: optionalText(map['bits']),
  );
}

/// `hash_offset`：object 解析失败 → null；全字段缺省 → null（is_empty 过滤）。
MusicArtistPreviewRange? _convertPreviewRange(Object? value) {
  final map = wireMap(value);
  if (map == null) return null;
  final preview = MusicArtistPreviewRange(
    startByte: optionalInt(map['start_byte']),
    endByte: optionalInt(map['end_byte']),
    startMs: optionalInt(map['start_ms']),
    endMs: optionalInt(map['end_ms']),
    offsetHash: optionalText(map['offset_hash']),
    fileType: optionalInt(map['file_type']),
    clipHash: optionalText(map['clip_hash']),
  );
  return preview.isEmpty ? null : preview;
}

/// wire `voice_ad`：filesize 映射为 size_bytes（VoiceAd）。
MusicArtistVoiceAd? _convertVoiceAd(Object? value) {
  final map = wireMap(value);
  if (map == null) return null;
  return MusicArtistVoiceAd(
    startMs: optionalInt(map['start_ms']),
    sizeBytes: optionalInt(map['filesize']),
    hash: optionalText(map['hash']),
  );
}

/// `checked_mul(1000)`：乘出的 bps 超出 Dart int 可表示域时回 null，不回绕
/// 出负数（Rust 溢出回 None；差异仅在 9.2e15～1.8e16 的不可达区间）。
int? _bitRateBps(int bitrate) =>
    bitrate > 9223372036854775 ? null : bitrate * 1000;
