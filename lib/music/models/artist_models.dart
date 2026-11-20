/// 歌手域模型——EchoMusicNext `crates/echo-api/src/domain.rs` 的
/// `ArtistDetail` / `SongSummary` 扩展切片，以及 `domain/discovery.rs` 里
/// 歌手歌曲行用到的目录事实（`CatalogSongFacts` / `CatalogRights` /
/// `AudioResource` 复用共享 [MusicAudioResource]）与 `artist_lists.rs` 的
/// 目录卡片（`ArtistGroup` / `ArtistCard` / `Filter`）。
///
/// 类型名统一加 `MusicArtist` 前缀保证全局唯一（发现/专辑组若产出同名目录
/// 事实，由集成者合并）；字段与 wire 的对应关系逐条对齐上游结构体。
library;

import 'package:mimao/music/models/music_models.dart';

/// 歌手详情（artist_detail.rs `ArtistDetail`）。
class MusicArtistDetail {
  const MusicArtistDetail({
    this.id,
    required this.name,
    required this.avatarUrl,
    required this.description,
    required this.birthday,
    this.fans,
    this.albumCount,
    this.mvCount,
    this.published,
  });

  /// `author_id` 文本按 u64 解析；不可解析（含非纯数字）为 null。
  final int? id;

  final String name;

  /// `sizable_avatar`，`{size}` 占位符已按上游 cover_url() 替换为 240。
  final String avatarUrl;

  /// `long_intro` 各段非空 content 用空行连接（不加展示性标题）。
  final String description;

  final String birthday;
  final int? fans;
  final int? albumCount;
  final int? mvCount;

  /// `is_publish` 0/1 布尔；未知服务码保留 null。
  final bool? published;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'avatarUrl': avatarUrl,
    'description': description,
    'birthday': birthday,
    'fans': fans,
    'albumCount': albumCount,
    'mvCount': mvCount,
    'published': published,
  };
}

/// 歌手歌曲行（artist_audios_new.rs `ArtistSong`：`SongSummary` 平铺 +
/// `metadata` 目录事实，与上游 serde(flatten) 序列化形状一致）。
class MusicArtistSong {
  const MusicArtistSong({
    required this.id,
    required this.hash,
    required this.title,
    required this.artists,
    required this.albumId,
    required this.albumTitle,
    this.durationMs,
    required this.coverUrl,
    this.privilege,
    required this.metadata,
  });

  /// `album_audio_id`；空回退文件 hash（上游 convert 的 id 回退链）。
  final String id;

  /// 标准音质 hash（audio_info.hash）。
  final String hash;
  final String title;
  final List<MusicArtistRef> artists;
  final String albumId;

  /// `album_name` 为空 → null（上游 `then_some` 语义，不是空串）。
  final String? albumTitle;

  /// wire `timelength` 本来就是毫秒，原样透传。
  final int? durationMs;
  final String coverUrl;

  /// `privilege` 缺省回退 `privilege_128`。
  final int? privilege;

  final MusicArtistSongFacts metadata;

  /// 歌手名的展示串（「A / B / C」，与 MusicSong 一致）。
  String get artistText => artists.map((a) => a.name).join(' / ');

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'hash': hash,
    'title': title,
    'artists': [for (final artist in artists) artist.toJson()],
    'albumId': albumId,
    'albumTitle': albumTitle,
    'durationMs': durationMs,
    'coverUrl': coverUrl,
    'privilege': privilege,
    'metadata': metadata.toJson(),
  };
}

/// 目录事实（discovery.rs `CatalogSongFacts` 子集）——版权/支付/资源表，
/// 供角标、筛选与队列快照使用。
class MusicArtistSongFacts {
  const MusicArtistSongFacts({
    this.paymentType,
    this.failureCode,
    this.oldCopyrightCode,
    this.originalityCode,
    this.rights,
    required this.resources,
  });

  final int? paymentType;
  final int? failureCode;
  final int? oldCopyrightCode;

  /// `extra.is_original` 缺省回退 trans_param 的 `is_original`。
  final int? originalityCode;

  /// trans_param 版权事实（上游恒 Some——WireTrans::convert 不会失败）。
  final MusicArtistSongRights? rights;

  /// ogg 资源在前（来自 trans_param），其后按 128/320/flac/high/super。
  final List<MusicAudioResource> resources;

  Map<String, Object?> toJson() => <String, Object?>{
    'paymentType': paymentType,
    'failureCode': failureCode,
    'oldCopyrightCode': oldCopyrightCode,
    'originalityCode': originalityCode,
    'rights': rights?.toJson(),
    'resources': [for (final resource in resources) resource.toJson()],
  };
}

/// 版权事实（catalog_rights.rs `WireTrans::convert` → discovery.rs
/// `CatalogRights`）。字段名沿用上游 convert 的语义命名。
class MusicArtistSongRights {
  const MusicArtistSongRights({
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

  final MusicArtistQualityMap? qualityMap;

  /// classmap：键 → 解析失败的值保留 null（optional_map 语义）。
  final Map<String, int?>? classification;
  final MusicArtistEncodedMap? ipMap;
  final int? copyrightAttributes;

  /// wire `cpy_map`（文本）。
  final String? copyrightScope;
  final int? copyrightGrade;
  final int? copyrightLevel;
  final int? displayCode;
  final int? displayRate;
  final int? paymentTemplate;

  /// wire `appid_block`（文本）。
  final String? blockedApplications;
  final int? originalityCode;
  final int? advanceCode;

  /// `hash_offset` 全字段缺省时为 null（上游 is_empty 过滤）。
  final MusicArtistPreviewRange? preview;

  /// wire `hash_multitrack`（文本）。
  final String? multitrackHash;
  final int? audioPrivilege;
  final int? freeForAd;
  final int? freeLimited;
  final MusicArtistVoiceAd? voiceAd;

  /// `union_cover` 存在时已经过 cover_url()（{size} → 240）。
  final String? coverUrl;

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

/// privilege_lite.rs `QualityMap`。
class MusicArtistQualityMap {
  const MusicArtistQualityMap({this.attr0, this.attr1, this.bits});

  final int? attr0;
  final int? attr1;
  final String? bits;

  Map<String, Object?> toJson() => <String, Object?>{
    'attr0': attr0,
    'attr1': attr1,
    'bits': bits,
  };
}

/// discovery.rs `EncodedMap`。
class MusicArtistEncodedMap {
  const MusicArtistEncodedMap({this.attr0, this.bits});

  final int? attr0;
  final String? bits;

  Map<String, Object?> toJson() => <String, Object?>{
    'attr0': attr0,
    'bits': bits,
  };
}

/// privilege_lite.rs `PreviewRange`（试听区间）。
class MusicArtistPreviewRange {
  const MusicArtistPreviewRange({
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

/// discovery.rs `VoiceAd`（wire `voice_ad`：start_ms/filesize/hash）。
class MusicArtistVoiceAd {
  const MusicArtistVoiceAd({this.startMs, this.sizeBytes, this.hash});

  final int? startMs;
  final int? sizeBytes;
  final String? hash;

  Map<String, Object?> toJson() => <String, Object?>{
    'startMs': startMs,
    'sizeBytes': sizeBytes,
    'hash': hash,
  };
}

/// 歌手目录分组（artist_lists.rs `ArtistGroup`）。
class MusicArtistGroup {
  const MusicArtistGroup({required this.label, required this.artists});

  final String label;
  final List<MusicArtistCard> artists;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'artists': [for (final artist in artists) artist.toJson()],
  };
}

/// 歌手卡片（artist_lists.rs `ArtistCard`）。
class MusicArtistCard {
  const MusicArtistCard({
    required this.id,
    required this.title,
    required this.creator,
    required this.coverUrl,
    required this.metadata,
  });

  /// `singerid` 字符串化。
  final String id;
  final String title;

  /// 上游恒为空串（保留字段）。
  final String creator;

  /// `imgurl`，`{size}` 占位符已替换为 240。
  final String coverUrl;
  final MusicArtistCardMetadata metadata;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'creator': creator,
    'coverUrl': coverUrl,
    'metadata': metadata.toJson(),
  };
}

/// 歌手卡片事实（artist_lists.rs `Metadata`）。
class MusicArtistCardMetadata {
  const MusicArtistCardMetadata({
    this.albumCount,
    this.songCount,
    this.fansCount,
    this.mvCount,
    this.description,
    required this.introduction,
    this.settledCode,
    this.heat,
    this.heatChange,
    this.sortChange,
    required this.dynamicFrameUrl,
  });

  final int? albumCount;
  final int? songCount;
  final int? fansCount;
  final int? mvCount;

  /// `descibe`（wire 原拼写）；数字文本化为字符串，bool/复合 → null。
  final String? description;
  final String introduction;
  final int? settledCode;
  final int? heat;
  final int? heatChange;
  final int? sortChange;

  /// `dycover.first_frame_image`，`{size}` 占位符已替换为 240。
  final String dynamicFrameUrl;

  Map<String, Object?> toJson() => <String, Object?>{
    'albumCount': albumCount,
    'songCount': songCount,
    'fansCount': fansCount,
    'mvCount': mvCount,
    'description': description,
    'introduction': introduction,
    'settledCode': settledCode,
    'heat': heat,
    'heatChange': heatChange,
    'sortChange': sortChange,
    'dynamicFrameUrl': dynamicFrameUrl,
  };
}

/// 目录筛选（artist_lists.rs `Filter`）。
class MusicArtistFilter {
  const MusicArtistFilter({
    required this.id,
    required this.label,
    required this.category,
    required this.musician,
  });

  /// 类型筛选是 `key:musician 文本`；性别筛选是 key 字符串。
  final String id;
  final String label;

  /// wire `key`（性别/类型共用）。
  final int category;

  /// 类型筛选按 decimal 解析（u32 域）；性别筛选固定 0。
  final int? musician;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'category': category,
    'musician': musician,
  };
}

/// 歌手目录（artist_lists.rs `Directory`）。
class MusicArtistDirectory {
  const MusicArtistDirectory({
    required this.groups,
    required this.sexFilters,
    required this.typeFilters,
    this.timestamp,
  });

  final List<MusicArtistGroup> groups;
  final List<MusicArtistFilter> sexFilters;
  final List<MusicArtistFilter> typeFilters;
  final int? timestamp;

  Map<String, Object?> toJson() => <String, Object?>{
    'groups': [for (final group in groups) group.toJson()],
    'sexFilters': [for (final filter in sexFilters) filter.toJson()],
    'typeFilters': [for (final filter in typeFilters) filter.toJson()],
    'timestamp': timestamp,
  };
}
