/// 专辑歌曲端点——EchoMusicNext `crates/echo-api/src/module/album_songs.rs` 的
/// 翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// POST `/v1/album_audio/lite`（网关 + x-router=openapi.kugou.com）。每条记录
/// 自带 album_audio_id 与结构化 authors（绝不拆 base.author_name）；平铺的
/// 各音质 hash 与 trans_param 喂给共享的行级角标（上游模块注释）。
/// `audio_info.duration` 系列本来就是毫秒，直接透传不再乘 1000。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/album_models.dart';
import 'package:mimao/music/models/music_models.dart';

/// 专辑歌曲查询（album_songs.rs `Query`：page 缺省 1、page_size 缺省 30）。
class AlbumSongsQuery {
  const AlbumSongsQuery({required this.id, this.page = 1, this.pageSize = 30});

  final int id;

  /// 1 起始页码。
  final int page;
  final int pageSize;

  void validate() {
    // album_songs.rs execute：page == 0（u32 域即 <1）或 page_size 出
    // 1..=100 → input。
    if (page < 1 || pageSize < 1 || pageSize > 100) {
      throw const KugouApiException('input', '专辑分页参数无效');
    }
  }
}

/// 专辑曲目分页（album_songs.rs `execute`）。
Future<MusicAlbumTracks> fetchAlbumSongs(
  MusicSession session,
  AlbumSongsQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  // serde 序列化顺序 = 字段声明顺序：album_id → is_buy → page → pagesize。
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v1/album_audio/lite',
      router: 'openapi.kugou.com',
      method: 'POST',
      body: encodeJsonBody(<String, Object?>{
        'album_id': query.id.toString(),
        'is_buy': '',
        'page': query.page,
        'pagesize': query.pageSize,
      }),
      headers: const <(String, String)>[('kg-tid', '255')],
    ),
  );
  return _convertAlbumSongs(response.bytes, query.page, query.pageSize);
}

/// wire 解析（album_songs.rs `convert`）。
///
/// 响应根上除了 status/error_code/data 还有 `extra`（碟片数）——共享
/// WireEnvelope 只带三件套，这里按 song_url_auth 的先例自解根对象。
MusicAlbumTracks _convertAlbumSongs(Uint8List bytes, int page, int pageSize) {
  final root = _decodeRoot(bytes);
  final status = requiredScalarInt(root['status'], 'status');
  final errorCode = requiredScalarInt(root['error_code'], 'error_code');
  ensureBusinessSuccess(status, errorCode, context: '专辑歌曲');
  // Wire.data 是 serde_json::Value + from_value(Data)：null/非 object → decode。
  final data = wireMap(root['data']);
  if (data == null) {
    throw const KugouApiException('decode', '专辑歌曲响应 data 不是 object');
  }
  final songs = wireList(data['songs'], 'songs').map(_convertTrack).toList();
  // extra 是 object 语义：缺省/null/错配 → 默认节（disc_cnt 缺席）。
  final extra = wireMap(root['extra']);
  return MusicAlbumTracks(
    page: MusicPage<MusicAlbumTrack>(
      page: page,
      pageSize: pageSize,
      total: optionalInt(data['total']),
      items: songs,
    ),
    discCount: extra == null ? null : optionalInt(extra['disc_cnt']),
  );
}

/// 根对象解码：request.rs `decode` 在 serde 之前统一判登录过期
/// （authentication_expiration：error_code==20018 或 msg 含「登录已过期」）。
Map<String, Object?> _decodeRoot(Uint8List bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  final root = wireMap(decoded);
  if (root == null) {
    throw const KugouApiException('decode', '专辑歌曲响应不是 JSON object');
  }
  final code = optionalInt(root['error_code']);
  final message = root['msg'];
  final expired = message is String && message.contains('登录已过期');
  if (code == kugouErrorCodeAuthenticationExpired || expired) {
    throw KugouApiException('authentication', '账号认证无效，请重新登录', code: code);
  }
  return root;
}

MusicAlbumTrack _convertTrack(Object? raw) {
  final item = wireMap(raw);
  if (item == null) {
    throw const KugouApiException('decode', '专辑歌曲条目不是 object');
  }
  // 各分节都是 object 语义：缺省/null/错配 → 默认空节（unwrap_or_default）。
  final base = wireMap(item['base']) ?? const <String, Object?>{};
  final audio = wireMap(item['audio_info']) ?? const <String, Object?>{};
  final album = wireMap(item['album_info']) ?? const <String, Object?>{};
  final copyright = wireMap(item['copyright']) ?? const <String, Object?>{};
  final deprecated = wireMap(item['deprecated']) ?? const <String, Object?>{};
  final extend = wireMap(item['extend']) ?? const <String, Object?>{};
  // authors 是 list 语义：错配/坏元素按 decode 失败（不静默吞掉）。
  final authors = wireList(
    item['authors'],
    'authors',
  ).map(_convertAuthor).toList();

  final payType = optionalInt(deprecated['pay_type']);
  // trans_param 转换失败 → rights 缺席 + 空资源表（上游 match Err 分支）。
  final (rights, transResources) = _convertWireTrans(item['trans_param']);
  final resources = List<MusicAudioResource>.from(transResources);

  // 五档常规音质行——上游无条件追加（hash 空串也保留 Some("")），与搜索端点的
  // 「全空跳过」刻意不同。rate：128 用通用 bitrate，320 不带，flac/high/super 各自独立。
  void push(
    String quality,
    Object? hash,
    Object? size,
    Object? durationMs,
    Object? privilege,
    Object? bitrate, [
    String? extension,
  ]) {
    final rate = optionalInt(bitrate);
    resources.add(
      MusicAudioResource(
        quality: quality,
        hash: wireText(hash),
        sizeBytes: optionalInt(size),
        durationMs: optionalInt(durationMs),
        bitRateBps: rate == null ? null : rate * 1000,
        extension: extension,
        privilege: optionalInt(privilege),
        payType: payType,
      ),
    );
  }

  push(
    '128',
    audio['hash_128'],
    audio['filesize_128'],
    audio['duration_128'],
    copyright['privilege_128'],
    audio['bitrate'],
    wireText(audio['extname']),
  );
  push(
    '320',
    audio['hash_320'],
    audio['filesize_320'],
    audio['duration_320'],
    copyright['privilege_320'],
    null,
  );
  push(
    'flac',
    audio['hash_flac'],
    audio['filesize_flac'],
    audio['duration_flac'],
    copyright['privilege_flac'],
    audio['bitrate_flac'],
  );
  push(
    'high',
    audio['hash_high'],
    audio['filesize_high'],
    audio['duration_high'],
    null,
    audio['bitrate_high'],
  );
  push(
    'super',
    audio['hash_super'],
    audio['filesize_super'],
    audio['duration_super'],
    null,
    audio['bitrate_super'],
    wireText(audio['extname_super']),
  );

  return MusicAlbumTrack(
    song: MusicSong(
      id: wireText(base['album_audio_id']),
      hash: wireText(audio['hash']),
      title: wireText(base['audio_name']),
      artists: authors,
      albumId: wireText(base['album_id']),
      albumTitle: wireText(album['album_name']),
      durationMs: optionalInt(audio['duration']),
      coverUrl: coverUrl(wireText(album['cover'])),
      privilege: optionalInt(copyright['privilege']),
    ),
    metadata: MusicCatalogSongFacts(
      paymentType: payType,
      failureCode: null,
      oldCopyrightCode: optionalInt(deprecated['old_cpy']),
      originalityCode: rights?.originalityCode,
      rights: rights,
      resources: resources,
    ),
    disc: optionalInt(extend['disc']),
    position: optionalInt(extend['sort']),
    hasAccompaniment: optionalBool(extend['has_obbligato']),
    accompanimentCode: optionalInt(extend['has_obbligato']),
  );
}

MusicArtistRef _convertAuthor(Object? raw) {
  final author = wireMap(raw);
  if (author == null) {
    throw const KugouApiException('decode', '专辑歌曲作者条目不是 object');
  }
  return MusicArtistRef(
    id: optionalInt(author['author_id']),
    name: wireText(author['author_name']),
  );
}

/// util/catalog_rights.rs `WireTrans::convert` 的翻译：trans_param →
/// (版权事实, ogg 附加资源行)。上游失败分支（Err → (None, vec![])）在 Dart 里
/// 不可能出现——转换全程宽容、不抛错，语义等效。
(MusicCatalogRights?, List<MusicAudioResource>) _convertWireTrans(Object? raw) {
  // trans_param 是 object 语义：缺省/null/错配 → 默认全空的 WireTrans。
  final wire = wireMap(raw) ?? const <String, Object?>{};
  final resources = <MusicAudioResource>[];
  // ogg 附加资源：hash 与 size 都缺省才跳过；extension 固定 "ogg"。
  for (final (quality, hashKey, sizeKey) in const <(String, String, String)>[
    ('ogg_128', 'ogg_128_hash', 'ogg_128_filesize'),
    ('ogg_320', 'ogg_320_hash', 'ogg_320_filesize'),
  ]) {
    final hash = optionalText(wire[hashKey]);
    final size = optionalInt(wire[sizeKey]);
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

  // preview：hash_offset 存在但全空 → 丢弃（filter(|v| !v.is_empty())）。
  MusicPreviewRange? preview;
  final offset = wireMap(wire['hash_offset']);
  if (offset != null) {
    final candidate = MusicPreviewRange(
      startByte: optionalInt(offset['start_byte']),
      endByte: optionalInt(offset['end_byte']),
      startMs: optionalInt(offset['start_ms']),
      endMs: optionalInt(offset['end_ms']),
      offsetHash: optionalText(offset['offset_hash']),
      fileType: optionalInt(offset['file_type']),
      clipHash: optionalText(offset['clip_hash']),
    );
    if (!candidate.isEmpty) preview = candidate;
  }

  final unionCover = optionalText(wire['union_cover']);
  final voiceAd = wireMap(wire['voice_ad']);
  final rights = MusicCatalogRights(
    qualityMap: _qualityMap(wire['qualitymap']),
    classification: _optionalNumberMap(wire['classmap']),
    ipMap: _encodedMap(wire['ipmap']),
    copyrightAttributes: optionalInt(wire['cpy_attr0']),
    copyrightScope: optionalText(wire['cpy_map']),
    copyrightGrade: optionalInt(wire['cpy_grade']),
    copyrightLevel: optionalInt(wire['cpy_level']),
    displayCode: optionalInt(wire['display']),
    displayRate: optionalInt(wire['display_rate']),
    paymentTemplate: optionalInt(wire['pay_block_tpl']),
    blockedApplications: optionalText(wire['appid_block']),
    originalityCode: optionalInt(wire['is_original']),
    advanceCode: optionalInt(wire['musicpack_advance']),
    preview: preview,
    multitrackHash: optionalText(wire['hash_multitrack']),
    coverUrl: unionCover == null ? null : coverUrl(unionCover),
    audioPrivilege: optionalInt(wire['audio_privilege']),
    freeForAd: optionalInt(wire['free_for_ad']),
    freeLimited: optionalInt(wire['free_limited']),
    voiceAd: voiceAd == null
        ? null
        : MusicVoiceAd(
            // wire `filesize` → 模型 sizeBytes（catalog_rights.rs 同名换字段）。
            startMs: optionalInt(voiceAd['start_ms']),
            sizeBytes: optionalInt(voiceAd['filesize']),
            hash: optionalText(voiceAd['hash']),
          ),
  );
  return (rights, resources);
}

/// privilege_lite.rs `QualityMap`：非 object → 缺席；attr0/attr1 数字或数字
/// 字符串，逐字段宽容。
MusicQualityMap? _qualityMap(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) return null;
  return MusicQualityMap(
    attr0: optionalInt(wire['attr0']),
    attr1: optionalInt(wire['attr1']),
    bits: optionalText(wire['bits']),
  );
}

/// discovery.rs `EncodedMap`：非 object → 缺席。
MusicEncodedMap? _encodedMap(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) return null;
  return MusicEncodedMap(
    attr0: optionalInt(wire['attr0']),
    bits: optionalText(wire['bits']),
  );
}

/// response.rs `optional_map`：值逐项宽容解析（坏值归 null），非 object → 缺席。
Map<String, int?>? _optionalNumberMap(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) return null;
  return <String, int?>{
    for (final entry in wire.entries) entry.key: optionalInt(entry.value),
  };
}
