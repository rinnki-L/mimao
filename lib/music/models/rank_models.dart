/// 榜单域模型——EchoMusicNext 的组内翻译：
///
/// - `util/rank_catalog.rs`：Rank 目录条目（rank_list / rank_top 共用）；
/// - `domain/discovery.rs` 榜单子集：DiscoverySong / SongMetadata /
///   AudioResource / CatalogRights / VideoReference / RankingPosition 等
///   （rank_audio / top_song 共用）；
/// - `util/catalog_rights.rs`：trans_param 版权事实转换（rank_audio /
///   top_song 共用，按上游 util 的位置落在本文件，不进共享底座）。
///
/// 模型全部 `MusicRank*` / `MusicSongRanking*` / `MusicTopAlbum*` 前缀，
/// 避免与其它端点组的同名类型冲突。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/music_models.dart';

/// 排行榜目录条目（rank_catalog.rs `Rank`）。
class MusicRank {
  const MusicRank({
    this.id,
    required this.title,
    required this.coverUrl,
    required this.description,
    required this.updateFrequency,
    required this.publishedAt,
    required this.category,
  });

  /// wire `rankid`；不可解析时为 null。
  final int? id;
  final String title;
  final String coverUrl;
  final String description;

  /// wire `update_frequency`（如「每天更新」）。
  final String updateFrequency;

  /// wire `rank_id_publish_date`（原样文本，上游不解析日期）。
  final String? publishedAt;

  /// wire `ranktype`（分类码）。
  final int? category;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'coverUrl': coverUrl,
    'description': description,
    'updateFrequency': updateFrequency,
    'publishedAt': publishedAt,
    'category': category,
  };
}

/// 排行榜目录条目的 wire 转换（rank_catalog.rs `WireRank::convert`）。
MusicRank musicRankFromWire(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '排行榜条目不是 object');
  }
  return MusicRank(
    id: optionalInt(wire['rankid']),
    title: wireText(wire['rankname']),
    coverUrl: coverUrl(wireText(wire['imgurl'])),
    description: wireText(wire['intro']),
    updateFrequency: wireText(wire['update_frequency']),
    publishedAt: optionalText(wire['rank_id_publish_date']),
    category: optionalInt(wire['ranktype']),
  );
}

/// 榜单曲目的音质资源（discovery.rs `AudioResource`）。
///
/// 比搜索侧的 `MusicAudioResource` 多 `paymentType` / `downloadStatus` 两个
/// 事实；搜索共享模型放不下，榜单组按上游独立结构落模型。
class MusicRankResource {
  const MusicRankResource({
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

  Map<String, Object?> toJson() => <String, Object?>{
    'quality': quality,
    'hash': hash,
    'sizeBytes': sizeBytes,
    'durationMs': durationMs,
    'bitRateBps': bitRateBps,
    'extension': extension,
    'privilege': privilege,
    'paymentType': paymentType,
    'failureCode': failureCode,
    'downloadStatus': downloadStatus,
  };
}

/// MV/视频引用（discovery.rs `VideoReference`）。
class MusicRankVideoReference {
  const MusicRankVideoReference({
    required this.id,
    required this.hash,
    this.kind,
    this.track,
    this.durationMs,
    this.sizeBytes,
  });

  final String? id;
  final String? hash;

  /// wire `typ`（mvdata 分支）。
  final int? kind;

  /// wire `trk` / `video_track`（字符串透传）。
  final String? track;
  final int? durationMs;
  final int? sizeBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'hash': hash,
    'kind': kind,
    'track': track,
    'durationMs': durationMs,
    'sizeBytes': sizeBytes,
  };
}

/// 榜单歌手详情（discovery.rs `ArtistDetail`）。
class MusicRankArtistDetail {
  const MusicRankArtistDetail({
    this.id,
    required this.name,
    required this.avatarUrl,
    this.publicationCode,
  });

  final int? id;
  final String name;

  /// wire `sizable_avatar` 的 `{size}` 已替换为 240。
  final String? avatarUrl;

  /// wire `is_publish`（仅 top_song 的 authors 提供）。
  final int? publicationCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'avatarUrl': avatarUrl,
    'publicationCode': publicationCode,
  };
}

/// 推荐文案（discovery.rs `RecommendationText`；榜单端点 detail 恒空、
/// rankLabel 恒 null，字段保留对齐上游结构）。
class MusicRankRecommendationText {
  const MusicRankRecommendationText({
    required this.headline,
    this.detail = '',
    this.rankLabel,
  });

  final String headline;
  final String detail;
  final String? rankLabel;

  Map<String, Object?> toJson() => <String, Object?>{
    'headline': headline,
    'detail': detail,
    'rankLabel': rankLabel,
  };
}

/// 榜内位置事实（discovery.rs `RankingPosition`；rank_audio 专用）。
class MusicRankPosition {
  const MusicRankPosition({
    required this.rankId,
    required this.issue,
    this.rankCid,
    this.position,
    this.previousPosition,
    this.originalPosition,
    this.previousOriginalPosition,
    this.change,
    required this.publishedAt,
  });

  final String rankId;
  final String issue;
  final int? rankCid;
  final int? position;
  final int? previousPosition;
  final int? originalPosition;
  final int? previousOriginalPosition;
  final int? change;

  /// wire `rank_id_publish_date`（business 分支的原样文本）。
  final String publishedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'rankId': rankId,
    'issue': issue,
    'rankCid': rankCid,
    'position': position,
    'previousPosition': previousPosition,
    'originalPosition': originalPosition,
    'previousOriginalPosition': previousOriginalPosition,
    'change': change,
    'publishedAt': publishedAt,
  };
}

/// 相关版本备注（discovery.rs `RelatedVersion`）。
class MusicRankRelatedVersion {
  const MusicRankRelatedVersion({
    required this.albumAudioId,
    required this.remark,
    this.kind,
  });

  /// wire `rel_album_audio_id`；缺省按上游 unwrap_or_default 归空串。
  final String albumAudioId;
  final String remark;

  /// wire `type`（rank_audio）或 `remark_type`（top_song）。
  final int? kind;

  Map<String, Object?> toJson() => <String, Object?>{
    'albumAudioId': albumAudioId,
    'remark': remark,
    'kind': kind,
  };
}

/// 音质映射（privilege_lite.rs `QualityMap` 的榜单侧翻译；attr0/attr1 走
/// 数字/数字字符串宽容，bits 走文本）。
class MusicRankQualityMap {
  const MusicRankQualityMap({this.attr0, this.attr1, this.bits});

  final int? attr0;
  final int? attr1;
  final String? bits;

  Map<String, Object?> toJson() => <String, Object?>{
    'attr0': attr0,
    'attr1': attr1,
    'bits': bits,
  };
}

/// IP 映射（discovery.rs `EncodedMap`）。
class MusicRankIpMap {
  const MusicRankIpMap({this.attr0, this.bits});

  final int? attr0;
  final String? bits;

  Map<String, Object?> toJson() => <String, Object?>{
    'attr0': attr0,
    'bits': bits,
  };
}

/// 试听范围（privilege_lite.rs `PreviewRange`；全空按上游 is_empty 过滤掉）。
class MusicRankPreviewRange {
  const MusicRankPreviewRange({
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

  bool get isEmpty =>
      startByte == null &&
      endByte == null &&
      startMs == null &&
      endMs == null &&
      offsetHash == null &&
      fileType == null &&
      clipHash == null;

  Map<String, Object?> toJson() => <String, Object?>{
    'startByte': startByte,
    'endByte': endByte,
    'startMs': startMs,
    'endMs': endMs,
    'offsetHash': offsetHash,
    'fileType': fileType,
    'clipHash': clipHash,
  };
}

/// 语音广告片段（catalog_rights.rs `WireVoiceAd` → discovery.rs `VoiceAd`）。
class MusicRankVoiceAd {
  const MusicRankVoiceAd({this.startMs, this.sizeBytes, this.hash});

  final int? startMs;
  final int? sizeBytes;
  final String? hash;

  Map<String, Object?> toJson() => <String, Object?>{
    'startMs': startMs,
    'sizeBytes': sizeBytes,
    'hash': hash,
  };
}

/// 版权/权益事实（catalog_rights.rs `WireTrans::convert` →
/// discovery.rs `CatalogRights`）。这些码只做展示事实，不是播放授权。
class MusicRankCatalogRights {
  const MusicRankCatalogRights({
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

  /// wire `qualitymap`。
  final MusicRankQualityMap? qualityMap;

  /// wire `classmap`（键 → 数字或不可解析 null）。
  final Map<String, int?>? classification;

  /// wire `ipmap`。
  final MusicRankIpMap? ipMap;
  final int? copyrightAttributes;

  /// wire `cpy_map`（文本）。
  final String? copyrightScope;
  final int? copyrightGrade;
  final int? copyrightLevel;
  final int? displayCode;
  final int? displayRate;

  /// wire `pay_block_tpl`。
  final int? paymentTemplate;

  /// wire `appid_block`（文本）。
  final String? blockedApplications;

  /// wire `is_original`。
  final int? originalityCode;

  /// wire `musicpack_advance`。
  final int? advanceCode;

  /// wire `hash_offset`（全空对象过滤为 null）。
  final MusicRankPreviewRange? preview;

  /// wire `hash_multitrack`。
  final String? multitrackHash;

  /// wire `union_cover` 的 `{size}` 已替换为 240。
  final String? coverUrl;
  final int? audioPrivilege;
  final int? freeForAd;
  final int? freeLimited;
  final MusicRankVoiceAd? voiceAd;

  Map<String, Object?> toJson() => <String, Object?>{
    'qualityMap': qualityMap?.toJson(),
    'classification': classification,
    'ipMap': ipMap?.toJson(),
    'copyrightAttributes': copyrightAttributes,
    'copyrightScope': copyrightScope,
    'copyrightGrade': copyrightGrade,
    'copyrightLevel': copyrightLevel,
    'displayCode': displayCode,
    'displayRate': displayRate,
    'paymentTemplate': paymentTemplate,
    'blockedApplications': blockedApplications,
    'originalityCode': originalityCode,
    'advanceCode': advanceCode,
    'preview': preview?.toJson(),
    'multitrackHash': multitrackHash,
    'coverUrl': coverUrl,
    'audioPrivilege': audioPrivilege,
    'freeForAd': freeForAd,
    'freeLimited': freeLimited,
    'voiceAd': voiceAd?.toJson(),
  };
}

/// trans_param 的 wire 解析（catalog_rights.rs `WireTrans`；`object`
/// 反序列化语义：null/非 object → 全默认，不抛 decode）。
(MusicRankCatalogRights, List<MusicRankResource>)
rankCatalogRightsFromTransParam(Object? raw) {
  final wire = wireMap(raw) ?? const <String, Object?>{};
  final resources = <MusicRankResource>[];
  void pushOgg(String quality, Object? hash, Object? size) {
    final hashText = optionalText(hash);
    final sizeValue = optionalInt(size);
    // 上游：hash 与 size 都缺省时跳过（不产生全空 ogg 条目）。
    if (hashText == null && sizeValue == null) return;
    resources.add(
      MusicRankResource(
        quality: quality,
        hash: hashText,
        sizeBytes: sizeValue,
        extension: 'ogg',
      ),
    );
  }

  pushOgg('ogg_128', wire['ogg_128_hash'], wire['ogg_128_filesize']);
  pushOgg('ogg_320', wire['ogg_320_hash'], wire['ogg_320_filesize']);
  final previewWire = wireMap(wire['hash_offset']);
  final preview = previewWire == null
      ? null
      : MusicRankPreviewRange(
          startByte: optionalInt(previewWire['start_byte']),
          endByte: optionalInt(previewWire['end_byte']),
          startMs: optionalInt(previewWire['start_ms']),
          endMs: optionalInt(previewWire['end_ms']),
          offsetHash: optionalText(previewWire['offset_hash']),
          fileType: optionalInt(previewWire['file_type']),
          clipHash: optionalText(previewWire['clip_hash']),
        );
  final qualityMapWire = wireMap(wire['qualitymap']);
  final ipMapWire = wireMap(wire['ipmap']);
  final voiceAdWire = wireMap(wire['voice_ad']);
  final rights = MusicRankCatalogRights(
    qualityMap: qualityMapWire == null
        ? null
        : MusicRankQualityMap(
            attr0: optionalInt(qualityMapWire['attr0']),
            attr1: optionalInt(qualityMapWire['attr1']),
            bits: optionalText(qualityMapWire['bits']),
          ),
    classification: _optionalNumberMap(wire['classmap']),
    ipMap: ipMapWire == null
        ? null
        : MusicRankIpMap(
            attr0: optionalInt(ipMapWire['attr0']),
            bits: optionalText(ipMapWire['bits']),
          ),
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
    preview: preview != null && !preview.isEmpty ? preview : null,
    multitrackHash: optionalText(wire['hash_multitrack']),
    coverUrl: optionalText(wire['union_cover']) == null
        ? null
        : coverUrl(wireText(wire['union_cover'])),
    audioPrivilege: optionalInt(wire['audio_privilege']),
    freeForAd: optionalInt(wire['free_for_ad']),
    freeLimited: optionalInt(wire['free_limited']),
    voiceAd: voiceAdWire == null
        ? null
        : MusicRankVoiceAd(
            startMs: optionalInt(voiceAdWire['start_ms']),
            sizeBytes: optionalInt(voiceAdWire['filesize']),
            hash: optionalText(voiceAdWire['hash']),
          ),
  );
  return (rights, resources);
}

/// `optional_map`（response.rs）：非 object → null；object 内不可解析值 → null。
Map<String, int?>? _optionalNumberMap(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) return null;
  return <String, int?>{
    for (final entry in wire.entries) entry.key: optionalInt(entry.value),
  };
}

/// `number_map`（response.rs）：非 object/缺省 → 空表。
Map<String, int?> rankNumberMapFromWire(Object? raw) {
  return _optionalNumberMap(raw) ?? const <String, int?>{};
}

/// 榜单歌曲的目录事实（discovery.rs `SongMetadata` 的榜单子集）。
///
/// 上游 `original_title` / `official_title` / `language` 在 rank_audio /
/// top_song 恒为 None，未落模型字段；`tags` / `ip_tags` 恒为空表，同略。
class MusicRankSongMetadata {
  const MusicRankSongMetadata({
    this.audioId,
    this.titleSuffix,
    required this.albumAudioRemark,
    required this.sourceFileName,
    this.publishedAt,
    this.publicationCode,
    this.originalityCode,
    this.hasAccompaniment,
    this.accompanimentCode,
    this.paymentType,
    this.failureCode,
    this.oldCopyrightCode,
    required this.rights,
    required this.resources,
    required this.videos,
    required this.recommendation,
    this.ranking,
    required this.artists,
    required this.relatedVersions,
  });

  final int? audioId;

  /// wire `trans_param.songname_suffix`（仅 top_song 提供）。
  final String? titleSuffix;
  final String albumAudioRemark;
  final String sourceFileName;

  /// wire `publish_date`（仅 top_song 提供，原样文本）。
  final String? publishedAt;

  /// wire `is_publish`（仅 rank_audio 提供）。
  final int? publicationCode;

  /// wire `trans_param.is_original`。
  final int? originalityCode;

  /// numeric.rs `boolean`：0/1 → false/true，其它服务码保留未知。
  final bool? hasAccompaniment;

  /// wire `has_obbligato`（原码）。
  final int? accompanimentCode;
  final int? paymentType;
  final int? failureCode;
  final int? oldCopyrightCode;
  final MusicRankCatalogRights rights;
  final List<MusicRankResource> resources;
  final List<MusicRankVideoReference> videos;
  final MusicRankRecommendationText recommendation;

  /// 榜内位置（rank_audio 恒有；top_song 恒 null，用 chart 承载）。
  final MusicRankPosition? ranking;
  final List<MusicRankArtistDetail> artists;
  final List<MusicRankRelatedVersion> relatedVersions;

  Map<String, Object?> toJson() => <String, Object?>{
    'audioId': audioId,
    'titleSuffix': titleSuffix,
    'albumAudioRemark': albumAudioRemark,
    'sourceFileName': sourceFileName,
    'publishedAt': publishedAt,
    'publicationCode': publicationCode,
    'originalityCode': originalityCode,
    'hasAccompaniment': hasAccompaniment,
    'accompanimentCode': accompanimentCode,
    'paymentType': paymentType,
    'failureCode': failureCode,
    'oldCopyrightCode': oldCopyrightCode,
    'rights': rights.toJson(),
    'resources': [for (final resource in resources) resource.toJson()],
    'videos': [for (final video in videos) video.toJson()],
    'recommendation': recommendation.toJson(),
    'ranking': ranking?.toJson(),
    'artists': [for (final artist in artists) artist.toJson()],
    'relatedVersions': [
      for (final version in relatedVersions) version.toJson(),
    ],
  };
}

/// 榜单歌曲（discovery.rs `DiscoverySong`）：曲库摘要 + 目录事实。
/// 摘要复用共享 `MusicSong`（resources 留空——上游 SongSummary 无资源表，
/// 资源在 metadata.resources）。
class MusicRankSong {
  const MusicRankSong({required this.song, required this.metadata});

  final MusicSong song;
  final MusicRankSongMetadata metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'song': song.toJson(),
    'metadata': metadata.toJson(),
  };
}

/// rank_audio 响应（rank_audio.rs `RankSongs`）。
class MusicRankSongs {
  const MusicRankSongs({this.total, required this.songs});

  final int? total;
  final List<MusicRankSong> songs;
}

/// 新歌榜单位置（top_song.rs `Chart`）。
class MusicRankSongChart {
  const MusicRankSongChart({
    required this.rankId,
    required this.issue,
    this.rankCid,
    this.position,
    this.previousPosition,
    this.change,
  });

  final String rankId;
  final String issue;
  final int? rankCid;
  final int? position;
  final int? previousPosition;
  final int? change;

  Map<String, Object?> toJson() => <String, Object?>{
    'rankId': rankId,
    'issue': issue,
    'rankCid': rankCid,
    'position': position,
    'previousPosition': previousPosition,
    'change': change,
  };
}

/// top_song 条目（top_song.rs `NewSong`：摘要 + catalog/chart/别名码）。
class MusicRankNewSong {
  const MusicRankNewSong({required this.song, required this.metadata});

  final MusicSong song;
  final MusicRankNewSongMetadata metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'song': song.toJson(),
    'metadata': metadata.toJson(),
  };
}

/// top_song 条目的附加元数据（top_song.rs `Metadata`）。
class MusicRankNewSongMetadata {
  const MusicRankNewSongMetadata({
    required this.catalog,
    required this.chart,
    required this.defaultAliasCodes,
  });

  final MusicRankSongMetadata catalog;
  final MusicRankSongChart chart;

  /// wire `remarks[].is_defaut_alias` 原序（缺省保留 null）。
  final List<int?> defaultAliasCodes;

  Map<String, Object?> toJson() => <String, Object?>{
    'catalog': catalog.toJson(),
    'chart': chart.toJson(),
    'defaultAliasCodes': defaultAliasCodes,
  };
}

/// top_song 响应（top_song.rs `NewSongs`）。
class MusicRankNewSongs {
  const MusicRankNewSongs({this.total, required this.songs});

  final int? total;
  final List<MusicRankNewSong> songs;
}

/// 新碟榜单卡片（top_album.rs `AlbumCard`）。
class MusicTopAlbumCard {
  const MusicTopAlbumCard({
    required this.id,
    required this.title,
    required this.creator,
    required this.coverUrl,
    this.songCount,
    required this.publishedAt,
    required this.metadata,
  });

  /// wire `albumid`（必填标量，字符串化）。
  final String id;
  final String title;

  /// wire `singername`。
  final String creator;
  final String coverUrl;
  final int? songCount;
  final String publishedAt;
  final MusicTopAlbumMetadata metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'creator': creator,
    'coverUrl': coverUrl,
    'songCount': songCount,
    'publishedAt': publishedAt,
    'metadata': metadata.toJson(),
  };
}

/// 新碟卡片元数据（top_album.rs `Metadata`）。
class MusicTopAlbumMetadata {
  const MusicTopAlbumMetadata({
    this.artistId,
    this.advertisementId,
    required this.description,
    this.firstReleaseCode,
    this.privilege,
    this.qualityCode,
    required this.specialTag,
  });

  final int? artistId;
  final int? advertisementId;
  final String description;

  /// wire `isfirst`。
  final int? firstReleaseCode;
  final int? privilege;

  /// wire `quality`。
  final int? qualityCode;

  /// wire `trans_param.special_tag`。
  final String specialTag;

  Map<String, Object?> toJson() => <String, Object?>{
    'artistId': artistId,
    'advertisementId': advertisementId,
    'description': description,
    'firstReleaseCode': firstReleaseCode,
    'privilege': privilege,
    'qualityCode': qualityCode,
    'specialTag': specialTag,
  };
}

/// 新碟榜单（top_album.rs `Albums`；regions 键为 chn/eur/jpn/kor）。
class MusicTopAlbums {
  const MusicTopAlbums({required this.regions, this.timestamp});

  final Map<String, List<MusicTopAlbumCard>> regions;
  final int? timestamp;
}

/// 榜单歌单卡片（top_playlist.rs `PlaylistCard`；top_ip 复用同结构）。
class MusicRankPlaylistCard {
  const MusicRankPlaylistCard({
    required this.id,
    required this.title,
    required this.creator,
    required this.coverUrl,
    this.songCount,
    required this.metadata,
  });

  /// wire `global_collection_id`（top_ip 缺省归空串）。
  final String id;
  final String title;
  final String creator;
  final String coverUrl;

  /// 上游榜单侧恒 None（歌曲数不在本协议里）。
  final int? songCount;
  final MusicRankPlaylistMetadata metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'creator': creator,
    'coverUrl': coverUrl,
    'songCount': songCount,
    'metadata': metadata.toJson(),
  };
}

/// 榜单歌单元数据（top_playlist.rs `PlaylistMetadata`）。
class MusicRankPlaylistMetadata {
  const MusicRankPlaylistMetadata({
    this.publicId,
    this.alternateGlobalId,
    this.creatorId,
    this.creatorAvatarUrl,
    this.description,
    this.tags = const <MusicPlaylistTag>[],
    this.playCount,
    this.collectionCount,
    this.publishedAt,
    this.sourceCode,
    this.kindCode,
    this.alternateCoverUrl,
  });

  /// wire `specialid`。
  final int? publicId;

  /// wire `global_special_id`（仅 top_ip 提供）。
  final String? alternateGlobalId;

  /// wire `suid`。
  final int? creatorId;

  /// wire `pic` 的 `{size}` 已替换为 240。
  final String? creatorAvatarUrl;
  final String? description;

  /// wire `tags[]`（tag_id 缺省归空串，与上游 unwrap_or_default 一致）。
  final List<MusicPlaylistTag> tags;
  final int? playCount;

  /// wire `collectcount`。
  final int? collectionCount;
  final String? publishedAt;

  /// wire `from`。
  final int? sourceCode;

  /// wire `type`。
  final int? kindCode;

  /// wire `flexible_cover` 的 `{size}` 已替换为 240。
  final String? alternateCoverUrl;

  Map<String, Object?> toJson() => <String, Object?>{
    'publicId': publicId,
    'alternateGlobalId': alternateGlobalId,
    'creatorId': creatorId,
    'creatorAvatarUrl': creatorAvatarUrl,
    'description': description,
    'tags': [for (final tag in tags) tag.toJson()],
    'playCount': playCount,
    'collectionCount': collectionCount,
    'publishedAt': publishedAt,
    'sourceCode': sourceCode,
    'kindCode': kindCode,
    'alternateCoverUrl': alternateCoverUrl,
  };
}

/// 播放页歌曲排名成就（song_ranking.rs `Ranking`）。
class MusicSongRanking {
  const MusicSongRanking({
    this.albumAudioId,
    this.platformNum,
    this.platformTotal,
    this.title1 = '',
    this.title2 = '',
    this.achievements = const <MusicSongRankingAchievement>[],
  });

  final int? albumAudioId;
  final int? platformNum;
  final int? platformTotal;
  final String title1;
  final String title2;

  /// wire `info[]`。
  final List<MusicSongRankingAchievement> achievements;
}

/// 单平台排名成就（song_ranking.rs `Achievement`）。
class MusicSongRankingAchievement {
  const MusicSongRankingAchievement({
    this.platform,
    this.rankingNum,
    this.rankingTimes,
    required this.platformName,
    required this.platformLogo,
    required this.lastTime,
  });

  final int? platform;
  final int? rankingNum;
  final int? rankingTimes;
  final String platformName;
  final String platformLogo;
  final String lastTime;
}

/// 播放页榜单筛选（song_ranking_filter.rs `Ranking`）。
class MusicSongRankingFilter {
  const MusicSongRankingFilter({
    this.options = const <MusicSongRankingFilterOption>[],
  });

  /// wire `list[]`。
  final List<MusicSongRankingFilterOption> options;
}

/// 可解锁的榜单筛选入口（song_ranking_filter.rs `Achievement`）。
class MusicSongRankingFilterOption {
  const MusicSongRankingFilterOption({
    this.area,
    this.count,
    this.platform,
    this.topRanking,
    required this.logoPic,
    required this.name,
    required this.platformName,
    required this.sharePic,
  });

  final int? area;
  final int? count;
  final int? platform;
  final int? topRanking;
  final String logoPic;
  final String name;
  final String platformName;
  final String sharePic;
}

/// 非共享信封形状（song_ranking / song_ranking_filter / top_song）的根对象
/// 解码——request.rs `decode`：JSON 解析 + `authentication_expiration` 预检
/// （error_code==20018 或 msg 含「登录已过期」→ authentication，先于一切
/// 端点语义）。
Map<String, Object?> decodeRankRoot(Uint8List bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  final root = wireMap(decoded);
  if (root == null) {
    throw const KugouApiException('decode', '响应不是 JSON object');
  }
  final errorCode = optionalInt(root['error_code']);
  final msg = optionalText(root['msg']);
  if (errorCode == kugouErrorCodeAuthenticationExpired ||
      (msg != null && msg.contains('登录已过期'))) {
    throw KugouApiException('authentication', '账号认证无效，请重新登录', code: errorCode);
  }
  return root;
}
