/// 歌单读端点组模型——EchoMusicNext `module/playlist_detail.rs` /
/// `playlist_track_all.rs` / `playlist_track_all_new.rs` / `playlist_tags.rs` /
/// `import_playlist.rs` 的输出结构，以及 `util/playlist_song.rs` /
/// `util/catalog_rights.rs` 歌曲事实转换的组内翻译（不改共享层）。
///
/// 命名前缀 `MusicPlaylist...`：与共享 `MusicPlaylistSummary` /
/// `MusicPlaylistTag`（catalog_models.dart）及搜索的 `MusicSong` 并存，
/// 跨组重复类型由集成者合并。
library;

import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/models/music_models.dart';

// ---------------------------------------------------------------------------
// playlist_detail.rs —— PlaylistDetail / SongTag
// ---------------------------------------------------------------------------

/// 歌单详情（playlist_detail.rs `PlaylistDetail`）。
class MusicPlaylistDetail {
  const MusicPlaylistDetail({
    required this.globalId,
    this.publicId,
    required this.title,
    required this.description,
    required this.coverUrl,
    this.creatorId,
    this.creatorListId,
    required this.creatorName,
    required this.creatorAvatarUrl,
    this.songCount,
    this.revision,
    required this.publishedAt,
    this.collectionCount,
    this.private,
    this.privateCode,
    this.published,
    this.publicationCode,
    this.tags,
    this.createdAtSeconds,
    this.updatedAtSeconds,
    this.creatorGlobalId,
    this.sourceCode,
    this.customCover,
    this.customCoverCode,
    this.defaultKind,
    this.musicTags,
  });

  /// 公开歌单标识（wire `global_collection_id`）。
  final String globalId;

  /// 账号内歌单 id（wire `specialid`）。
  final int? publicId;
  final String title;
  final String description;
  final String coverUrl;
  final int? creatorId;

  /// 创建者的账号歌单主键（只读评论身份元数据；写操作走 user_playlist）。
  final int? creatorListId;
  final String creatorName;
  final String creatorAvatarUrl;
  final int? songCount;

  /// wire `list_ver`。
  final int? revision;
  final String publishedAt;
  final int? collectionCount;

  /// wire `is_pri` 的 0/1 展示布尔；原码保留在 [privateCode]。
  final bool? private;
  final int? privateCode;

  /// wire `is_publish` 的 0/1 展示布尔；原码保留在 [publicationCode]。
  final bool? published;
  final int? publicationCode;

  /// wire `tags` 原样文本（上游不拆分）。
  final String? tags;
  final int? createdAtSeconds;
  final int? updatedAtSeconds;
  final String? creatorGlobalId;
  final int? sourceCode;

  /// wire `is_custom_pic` 的 0/1 展示布尔；原码保留在 [customCoverCode]。
  final bool? customCover;
  final int? customCoverCode;
  final int? defaultKind;

  /// wire `musiclib_tags`；非数组/解析失败按上游 `optional` 归 null。
  final List<MusicPlaylistSongTag>? musicTags;
}

/// 曲库标签（discovery.rs `SongTag`，playlist_detail 的 musiclib_tags 行）。
class MusicPlaylistSongTag {
  const MusicPlaylistSongTag({this.id, required this.name, this.parentId});

  /// wire `tag_id` 的十进制文本；缺省为 null。
  final String? id;
  final String name;
  final String? parentId;
}

// ---------------------------------------------------------------------------
// util/playlist_song.rs —— Singer / Facts / Metadata 及相关资源行
// ---------------------------------------------------------------------------

/// 歌手行（playlist_song.rs `Singer`）。
class MusicPlaylistSinger {
  const MusicPlaylistSinger({
    this.id,
    required this.name,
    this.avatar,
    this.publish,
  });

  final int? id;
  final String name;
  final String? avatar;
  final int? publish;

  /// playlist_song.rs `Singer::detail`：头像过 cover_url（{size}→240）。
  MusicPlaylistArtistDetail detail() {
    final avatarOrNull = avatar;
    return MusicPlaylistArtistDetail(
      id: id,
      name: name,
      avatarUrl: avatarOrNull == null ? null : coverUrl(avatarOrNull),
      publicationCode: publish,
    );
  }
}

/// 歌手详情（discovery.rs `ArtistDetail`）。
class MusicPlaylistArtistDetail {
  const MusicPlaylistArtistDetail({
    this.id,
    required this.name,
    this.avatarUrl,
    this.publicationCode,
  });

  final int? id;
  final String name;
  final String? avatarUrl;
  final int? publicationCode;
}

/// 一条音质资源（discovery.rs `AudioResource` 全字段——共享 `MusicAudioResource`
/// 缺 download_status/paymentType 命名，歌单组需要完整事实）。
class MusicPlaylistResource {
  const MusicPlaylistResource({
    required this.quality,
    this.hash,
    this.sizeBytes,
    this.durationMs,
    this.bitRateBps,
    this.extension,
    this.privilege,
    this.paymentType,
    this.failureCode,
    this.downloadStatus,
  });

  final String quality;
  final String? hash;
  final int? sizeBytes;
  final int? durationMs;
  final int? bitRateBps;
  final String? extension;
  final int? privilege;
  final int? paymentType;
  final int? failureCode;
  final int? downloadStatus;
}

/// 视频引用（discovery.rs `VideoReference`；playlist_song 只填 hash/kind/track）。
class MusicPlaylistVideoReference {
  const MusicPlaylistVideoReference({
    this.id,
    this.hash,
    this.kind,
    this.track,
    this.durationMs,
    this.sizeBytes,
  });

  final String? id;
  final String? hash;
  final int? kind;
  final String? track;
  final int? durationMs;
  final int? sizeBytes;
}

/// 关联资源行（playlist_song.rs `RelatedResource`，wire `relate_goods`）。
class MusicPlaylistRelatedResource {
  const MusicPlaylistRelatedResource({
    required this.hash,
    this.size,
    this.bitrate,
    this.privilege,
    this.level,
  });

  final String hash;
  final int? size;
  final int? bitrate;
  final int? privilege;
  final int? level;
}

/// 下载授权行（playlist_song.rs `Download`，wire `download`）。
class MusicPlaylistDownload {
  const MusicPlaylistDownload({
    required this.hash,
    this.status,
    this.payType,
    this.failProcess,
  });

  final String hash;
  final int? status;
  final int? payType;
  final int? failProcess;
}

/// 音质映射（privilege_lite.rs `QualityMap`，wire trans_param.qualitymap）。
class MusicPlaylistQualityMap {
  const MusicPlaylistQualityMap({this.attr0, this.attr1, this.bits});

  final int? attr0;
  final int? attr1;
  final String? bits;
}

/// 试听区间（privilege_lite.rs `PreviewRange`，wire trans_param.hash_offset）。
class MusicPlaylistPreviewRange {
  const MusicPlaylistPreviewRange({
    this.startByte,
    this.endByte,
    this.startMs,
    this.endMs,
    this.offsetHash,
    this.fileType,
    this.clipHash,
  });

  final int? startByte;
  final int? endByte;
  final int? startMs;
  final int? endMs;
  final String? offsetHash;
  final int? fileType;
  final String? clipHash;

  /// privilege_lite.rs `is_empty`：全空区间在 rights.preview 里被过滤掉。
  bool get isEmpty =>
      startByte == null &&
      endByte == null &&
      startMs == null &&
      endMs == null &&
      offsetHash == null &&
      fileType == null &&
      clipHash == null;
}

/// 编码属性（discovery.rs `EncodedMap`，wire trans_param.ipmap）。
class MusicPlaylistEncodedMap {
  const MusicPlaylistEncodedMap({this.attr0, this.bits});

  final int? attr0;
  final String? bits;
}

/// 语音广告事实（discovery.rs `VoiceAd`，wire trans_param.voice_ad）。
class MusicPlaylistVoiceAd {
  const MusicPlaylistVoiceAd({this.startMs, this.sizeBytes, this.hash});

  final int? startMs;
  final int? sizeBytes;
  final String? hash;
}

/// 版权/权益码事实（discovery.rs `CatalogRights`；rights codes 仅供展示）。
class MusicPlaylistRights {
  const MusicPlaylistRights({
    this.qualityMap,
    this.classification,
    this.ipMap,
    this.copyrightAttributes,
    this.copyrightScope,
    this.copyrightGrade,
    this.copyrightLevel,
    this.displayCode,
    this.displayRate,
    this.paymentTemplate,
    this.blockedApplications,
    this.originalityCode,
    this.advanceCode,
    this.preview,
    this.multitrackHash,
    this.coverUrl,
    this.audioPrivilege,
    this.freeForAd,
    this.freeLimited,
    this.voiceAd,
  });

  final MusicPlaylistQualityMap? qualityMap;
  final Map<String, int?>? classification;
  final MusicPlaylistEncodedMap? ipMap;
  final int? copyrightAttributes;
  final String? copyrightScope;
  final int? copyrightGrade;
  final int? copyrightLevel;
  final int? displayCode;
  final int? displayRate;
  final int? paymentTemplate;
  final String? blockedApplications;
  final int? originalityCode;
  final int? advanceCode;
  final MusicPlaylistPreviewRange? preview;
  final String? multitrackHash;
  final String? coverUrl;
  final int? audioPrivilege;
  final int? freeForAd;
  final int? freeLimited;
  final MusicPlaylistVoiceAd? voiceAd;
}

/// 歌单歌曲平铺事实（playlist_song.rs `Facts`，serde(flatten) 进歌曲行）。
class MusicPlaylistTrackFacts {
  const MusicPlaylistTrackFacts({
    this.audioId,
    this.language,
    this.publishDate,
    this.oldCopyrightCode,
    this.mvHash,
    this.mvType,
    this.mvTrack,
    this.size,
    this.bitrate,
    this.extName,
    this.transParam,
    this.tagMap,
    this.remark,
  });

  /// 从歌曲 wire 行解析（`optional` 宽容：非法值 → null）。
  factory MusicPlaylistTrackFacts.of(Map<String, Object?> wire) =>
      MusicPlaylistTrackFacts(
        audioId: optionalInt(wire['audio_id']),
        language: optionalText(wire['language']),
        publishDate: optionalText(wire['publish_date']),
        oldCopyrightCode: optionalInt(wire['media_old_cpy']),
        mvHash: optionalText(wire['mvhash']),
        mvType: optionalInt(wire['mvtype']),
        mvTrack: optionalInt(wire['mvtrack']),
        size: optionalInt(wire['size']),
        bitrate: optionalInt(wire['bitrate']),
        extName: optionalText(wire['extname']),
        transParam: wire['trans_param'],
        tagMap: optionalIntMap(wire['tagmap']),
        remark: optionalText(wire['remark']),
      );

  final int? audioId;
  final String? language;
  final String? publishDate;
  final int? oldCopyrightCode;
  final String? mvHash;
  final int? mvType;
  final int? mvTrack;
  final int? size;
  final int? bitrate;
  final String? extName;

  /// wire `trans_param` 原始值（null/空 object/非 object → 无权益事实）。
  final Object? transParam;

  /// wire `tagmap`（optional_map：非 object → null）。
  final Map<String, int?>? tagMap;
  final String? remark;
}

/// 歌曲元数据（playlist_song.rs `Metadata`）。
class MusicPlaylistTrackMetadata {
  const MusicPlaylistTrackMetadata({
    this.audioId,
    this.albumDetailsId,
    this.language,
    this.publishedAt,
    required this.sourceFileName,
    this.filenameArtistName,
    this.titleSuffix,
    this.albumAudioRemark,
    this.oldCopyrightCode,
    this.paymentType,
    this.failureCode,
    this.publicationCode,
    this.hasAccompaniment,
    this.rights,
    this.resources = const <MusicPlaylistResource>[],
    this.videos = const <MusicPlaylistVideoReference>[],
    this.artists = const <MusicPlaylistArtistDetail>[],
    this.genreMap,
    this.relatedResources = const <MusicPlaylistRelatedResource>[],
    this.downloads = const <MusicPlaylistDownload>[],
    this.accompanimentCode,
  });

  final int? audioId;

  /// 专辑详情页 id（调用方从 albuminfo.id 回填）。
  final int? albumDetailsId;
  final String? language;
  final String? publishedAt;

  /// 歌单名是传输文件名：这里保留完整原始拼写。
  final String sourceFileName;
  final String? filenameArtistName;
  final String? titleSuffix;
  final String? albumAudioRemark;
  final int? oldCopyrightCode;
  final int? paymentType;
  final int? failureCode;
  final int? publicationCode;

  /// wire 伴唱码（has_obbligato/is_publish 同款 0/1 布尔）。
  final bool? hasAccompaniment;
  final MusicPlaylistRights? rights;
  final List<MusicPlaylistResource> resources;
  final List<MusicPlaylistVideoReference> videos;
  final List<MusicPlaylistArtistDetail> artists;
  final Map<String, int?>? genreMap;
  final List<MusicPlaylistRelatedResource> relatedResources;
  final List<MusicPlaylistDownload> downloads;
  final int? accompanimentCode;
}

/// optional_map（response.rs）：object → {键: int?}；null/非 object → null。
Map<String, int?>? optionalIntMap(Object? value) {
  if (value is! Map) return null;
  return <String, int?>{
    for (final entry in value.entries) '${entry.key}': optionalInt(entry.value),
  };
}

/// playlist_song.rs `display_title`：歌单名是传输文件名——只在第一个「 - 」
/// 处分割取展示标题（后续分隔符保留在标题里），并去掉终端音频扩展名。
String musicPlaylistDisplayTitle(String name) {
  final separator = name.indexOf(' - ');
  final title = separator < 0 ? name : name.substring(separator + 3);
  const extensions = <String>['.mp3', '.flac', '.wav', '.aac', '.m4a', '.ape'];
  final lower = title.toLowerCase();
  for (final extension in extensions) {
    if (lower.endsWith(extension)) {
      return title.substring(0, title.length - extension.length);
    }
  }
  return title;
}

/// playlist_song.rs `filename_artist_name`：歌手行全空时从文件名补展示歌手。
String? musicPlaylistFilenameArtistName(
  String name,
  List<MusicPlaylistSinger> singers,
) {
  for (final singer in singers) {
    if (singer.name.trim().isNotEmpty) return null;
  }
  final separator = name.indexOf(' - ');
  if (separator < 0) return null;
  final artist = name.substring(0, separator).trim();
  return artist.isEmpty ? null : artist;
}

/// playlist_song.rs `display_artists`：文件名歌手只做展示、不给可导航身份。
List<MusicArtistRef> musicPlaylistDisplayArtists(
  String name,
  List<MusicPlaylistSinger> singers,
) {
  final filenameArtist = musicPlaylistFilenameArtistName(name, singers);
  if (filenameArtist != null) {
    return <MusicArtistRef>[MusicArtistRef(id: null, name: filenameArtist)];
  }
  return <MusicArtistRef>[
    for (final singer in singers)
      MusicArtistRef(id: singer.id, name: singer.name),
  ];
}

/// trans_param 的组内翻译产物（catalog_rights.rs `WireTrans::convert` 子集：
/// title_suffix + CatalogRights + ogg 资源）。
class MusicPlaylistTransFacts {
  const MusicPlaylistTransFacts._(
    this.titleSuffix,
    this.rights,
    this.resources,
  );

  final String? titleSuffix;
  final MusicPlaylistRights? rights;
  final List<MusicPlaylistResource> resources;

  static const MusicPlaylistTransFacts empty = MusicPlaylistTransFacts._(
    null,
    null,
    <MusicPlaylistResource>[],
  );
}

/// catalog_rights.rs `WireTrans` 解析：null / 空 object / 非 object → 无事实
/// （Facts.convert 的三分支；WireTrans 字段全默认，object 必然成功）。
MusicPlaylistTransFacts convertMusicPlaylistTrans(Object? transParam) {
  final wire = wireMap(transParam);
  if (wire == null || wire.isEmpty) return MusicPlaylistTransFacts.empty;

  final qualityMapWire = wireMap(wire['qualitymap']);
  final qualityMap = qualityMapWire == null
      ? null
      : MusicPlaylistQualityMap(
          attr0: optionalInt(qualityMapWire['attr0']),
          attr1: optionalInt(qualityMapWire['attr1']),
          bits: optionalText(qualityMapWire['bits']),
        );
  final ipMapWire = wireMap(wire['ipmap']);
  final ipMap = ipMapWire == null
      ? null
      : MusicPlaylistEncodedMap(
          attr0: optionalInt(ipMapWire['attr0']),
          bits: optionalText(ipMapWire['bits']),
        );
  final previewWire = wireMap(wire['hash_offset']);
  // catalog_rights.rs：全空试听区间被 filter 掉。
  MusicPlaylistPreviewRange? preview;
  if (previewWire != null) {
    final range = _previewRangeOf(previewWire);
    preview = range.isEmpty ? null : range;
  }
  final voiceAdWire = wireMap(wire['voice_ad']);
  final voiceAd = voiceAdWire == null
      ? null
      : MusicPlaylistVoiceAd(
          startMs: optionalInt(voiceAdWire['start_ms']),
          sizeBytes: optionalInt(voiceAdWire['filesize']),
          hash: optionalText(voiceAdWire['hash']),
        );

  final rights = MusicPlaylistRights(
    qualityMap: qualityMap,
    classification: optionalIntMap(wire['classmap']),
    ipMap: ipMap,
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
    coverUrl: _unionCover(wire['union_cover']),
    audioPrivilege: optionalInt(wire['audio_privilege']),
    freeForAd: optionalInt(wire['free_for_ad']),
    freeLimited: optionalInt(wire['free_limited']),
    voiceAd: voiceAd,
  );

  final resources = <MusicPlaylistResource>[];
  // ogg 资源：hash 与 size 全空才跳过；extension 固定 ogg。
  void pushOgg(String quality, Object? hash, Object? size) {
    final hashOrNull = optionalText(hash);
    final sizeOrNull = optionalInt(size);
    if (hashOrNull == null && sizeOrNull == null) return;
    resources.add(
      MusicPlaylistResource(
        quality: quality,
        hash: hashOrNull,
        sizeBytes: sizeOrNull,
        extension: 'ogg',
      ),
    );
  }

  pushOgg('ogg_128', wire['ogg_128_hash'], wire['ogg_128_filesize']);
  pushOgg('ogg_320', wire['ogg_320_hash'], wire['ogg_320_filesize']);
  return MusicPlaylistTransFacts._(
    optionalText(wire['songname_suffix']),
    rights,
    resources,
  );
}

MusicPlaylistPreviewRange _previewRangeOf(Map<String, Object?> wire) =>
    MusicPlaylistPreviewRange(
      startByte: optionalInt(wire['start_byte']),
      endByte: optionalInt(wire['end_byte']),
      startMs: optionalInt(wire['start_ms']),
      endMs: optionalInt(wire['end_ms']),
      offsetHash: optionalText(wire['offset_hash']),
      fileType: optionalInt(wire['file_type']),
      clipHash: optionalText(wire['clip_hash']),
    );

/// union_cover → cover_url（{size}→240；空串保持 Some("") 语义）。
String? _unionCover(Object? value) {
  final text = optionalText(value);
  return text == null ? null : coverUrl(text);
}

/// playlist_song.rs `Facts::convert`：把平铺事实折成 Metadata。
/// 每个实参都是独立可选事实；trans_param 未知容器不让整行失败。
MusicPlaylistTrackMetadata convertMusicPlaylistFacts({
  required MusicPlaylistTrackFacts facts,
  required String hash,
  required String title,
  required int? durationMs,
  required List<MusicPlaylistSinger> singers,
  required List<MusicPlaylistRelatedResource> related,
  required List<MusicPlaylistDownload> downloads,
  required int? paymentType,
  required int? failureCode,
  required int? publicationCode,
  required int? accompanimentCode,
  int? albumDetailsId,
}) {
  final trans = convertMusicPlaylistTrans(facts.transParam);
  final baseDownload = _findDownload(downloads, hash);

  final resources = <MusicPlaylistResource>[...trans.resources];
  for (final item in related) {
    // relate_goods 的 level → 内部音质词表（playlist_song.rs 的 match 块）。
    final quality = switch (item.level) {
      2 => '128',
      4 => '320',
      5 => 'flac',
      6 => 'high',
      7 => 'level_7',
      _ => 'unspecified',
    };
    final download = _findDownload(downloads, item.hash);
    resources.add(
      MusicPlaylistResource(
        quality: quality,
        hash: item.hash,
        sizeBytes: item.size,
        durationMs: item.hash == hash ? durationMs : null,
        bitRateBps: item.bitrate == null ? null : item.bitrate! * 1000,
        extension: item.hash == hash ? facts.extName : null,
        privilege: item.privilege,
        paymentType: download?.payType,
        failureCode: download?.failProcess,
        downloadStatus: download?.status,
      ),
    );
  }
  // 主 hash 行：任一平铺事实或下载授权存在才入表。
  if (facts.size != null ||
      facts.bitrate != null ||
      facts.extName != null ||
      baseDownload != null) {
    resources.add(
      MusicPlaylistResource(
        quality: facts.bitrate?.toString() ?? 'unspecified',
        hash: hash,
        sizeBytes: facts.size,
        durationMs: durationMs,
        bitRateBps: facts.bitrate == null ? null : facts.bitrate! * 1000,
        extension: facts.extName,
        privilege: null,
        paymentType: paymentType,
        failureCode: failureCode,
        downloadStatus: baseDownload?.status,
      ),
    );
  }

  final videos =
      facts.mvHash != null || facts.mvType != null || facts.mvTrack != null
      ? <MusicPlaylistVideoReference>[
          MusicPlaylistVideoReference(
            id: null,
            hash: facts.mvHash,
            kind: facts.mvType,
            track: facts.mvTrack?.toString(),
            durationMs: null,
            sizeBytes: null,
          ),
        ]
      : const <MusicPlaylistVideoReference>[];

  return MusicPlaylistTrackMetadata(
    audioId: facts.audioId,
    albumDetailsId: albumDetailsId,
    language: facts.language,
    publishedAt: facts.publishDate,
    sourceFileName: title,
    filenameArtistName: musicPlaylistFilenameArtistName(title, singers),
    titleSuffix: trans.titleSuffix,
    albumAudioRemark: facts.remark,
    oldCopyrightCode: facts.oldCopyrightCode,
    paymentType: paymentType ?? baseDownload?.payType,
    failureCode: failureCode ?? baseDownload?.failProcess,
    publicationCode: publicationCode,
    hasAccompaniment: optionalBool(accompanimentCode),
    rights: trans.rights,
    resources: resources,
    videos: videos,
    artists: <MusicPlaylistArtistDetail>[
      for (final singer in singers) singer.detail(),
    ],
    genreMap: facts.tagMap,
    relatedResources: related,
    downloads: downloads,
    accompanimentCode: accompanimentCode,
  );
}

MusicPlaylistDownload? _findDownload(
  List<MusicPlaylistDownload> downloads,
  String hash,
) {
  for (final download in downloads) {
    if (download.hash == hash) return download;
  }
  return null;
}

// ---------------------------------------------------------------------------
// playlist_track_all.rs / playlist_track_all_new.rs —— 曲目行
// ---------------------------------------------------------------------------

/// 歌单曲目行（`PublicPlaylistTrack` / `CloudPlaylistTrack` 合并：
/// cloud 专有的 `file_sort_index` 公开歌单恒为 null）。
class MusicPlaylistTrack {
  const MusicPlaylistTrack({
    required this.song,
    required this.metadata,
    this.fileId,
    this.sortIndex,
    this.fileSortIndex,
    this.collectedAtSeconds,
  });

  /// 展示摘要（SongSummary；resources 留空——音质事实在 metadata.resources）。
  final MusicSong song;
  final MusicPlaylistTrackMetadata metadata;
  final int? fileId;
  final int? sortIndex;

  /// wire `fsort`（仅云歌单）。
  final int? fileSortIndex;
  final int? collectedAtSeconds;
}

/// 云歌单曲目页（playlist_track_all_new.rs `CloudPlaylistTracks`）。
class MusicCloudPlaylistTracks {
  const MusicCloudPlaylistTracks({
    required this.page,
    this.userId,
    this.cloudListId,
    this.revision,
  });

  /// page/pageSize/total 取自 wire（与公开歌单的请求回显不同）。
  final MusicPage<MusicPlaylistTrack> page;
  final int? userId;
  final int? cloudListId;
  final int? revision;
}

// ---------------------------------------------------------------------------
// playlist_tags.rs —— Category
// ---------------------------------------------------------------------------

/// 歌单标签分类（playlist_tags.rs `Category`；children 只递归一层）。
class MusicPlaylistTagCategory {
  const MusicPlaylistTagCategory({
    required this.id,
    required this.name,
    required this.parentId,
    this.position,
    required this.children,
  });

  /// 标签 id 保持字符串（不丢前导零）。
  final String id;
  final String name;
  final String parentId;

  /// wire `sort` 的 u64 精确解析；不可解析 → null。
  final int? position;
  final List<MusicPlaylistTagCategory> children;
}

// ---------------------------------------------------------------------------
// import_playlist.rs —— ImportTask / MissedTrack / ImportResult / Outcome
// ---------------------------------------------------------------------------

/// 导入任务行（import_playlist.rs `ImportTask`；created/status/result 三处
/// 共用，缺省字段按各分支原样留空）。
class MusicImportTask {
  const MusicImportTask({
    this.taskId,
    this.userId,
    this.cloudListId,
    this.source,
    this.taskType,
    this.status,
    required this.title,
    this.total,
    this.matched,
    this.imported,
    this.missed,
    required this.message,
  });

  final int? taskId;
  final int? userId;
  final int? cloudListId;
  final int? source;
  final int? taskType;
  final int? status;
  final String title;
  final int? total;
  final int? matched;
  final int? imported;
  final int? missed;
  final String message;
}

/// 未匹配曲目（import_playlist.rs `MissedTrack`）。
class MusicMissedTrack {
  const MusicMissedTrack({
    required this.title,
    required this.artist,
    required this.album,
    required this.reason,
  });

  final String title;
  final String artist;
  final String album;
  final String reason;
}

/// 导入明细（import_playlist.rs `ImportResult`）。
class MusicImportResult {
  const MusicImportResult({
    required this.task,
    required this.missedTracks,
    required this.page,
    required this.pageSize,
  });

  final MusicImportTask task;
  final List<MusicMissedTrack> missedTracks;
  final int page;
  final int pageSize;
}

/// 导入动作的按分支产物（execute 的 match 块：不同动作返回不同形状）。
sealed class MusicImportOutcome {
  const MusicImportOutcome();
}

/// link / screenshot → convert_created 的任务回执。
class MusicImportCreatedOutcome extends MusicImportOutcome {
  const MusicImportCreatedOutcome(this.task);

  final MusicImportTask task;
}

/// submit_img → convert_upload 的 {"uploaded":true} 确认（上游自造的占位）。
class MusicImportUploadedOutcome extends MusicImportOutcome {
  const MusicImportUploadedOutcome();
}

/// status → convert_status 的任务行列表。
class MusicImportStatusOutcome extends MusicImportOutcome {
  const MusicImportStatusOutcome(this.tasks);

  final List<MusicImportTask> tasks;
}

/// result → convert_result 的明细分页。
class MusicImportResultOutcome extends MusicImportOutcome {
  const MusicImportResultOutcome(this.result);

  final MusicImportResult result;
}

/// count → convert_count 的 user_id/count/failed_count。
class MusicImportCountOutcome extends MusicImportOutcome {
  const MusicImportCountOutcome({this.userId, this.count, this.failedCount});

  final int? userId;
  final int? count;
  final int? failedCount;
}
