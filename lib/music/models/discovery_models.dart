/// 发现/推荐端点组的领域模型——EchoMusicNext `crates/echo-api/src/domain.rs`
/// 的 `SongSummary` 与 `domain/discovery.rs` 全量 DTO 的 Dart 镜像。
///
/// 放组内而非共享层（规格 §2/§9）：SongSummary 的 album_title 保留
/// 「缺失(null) vs 空串」的 wire 区分，metadata 是发现组特有的大结构；
/// 骨架期共享 `MusicSong` 无法无损承载。集成时如需合并由集成者统一处理。
///
/// wire 解码语义（response.rs scalar/text/list/optional/object）由
/// `lib/music/api/everyday_recommend.dart` 的组内共享翻译承接，本文件只保留
/// 纯数据结构。
library;

import 'package:mimao/music/models/music_models.dart';

/// 曲目摘要（domain.rs `SongSummary`；发现组各端点共用）。
class MusicDiscoverySongSummary {
  const MusicDiscoverySongSummary({
    required this.id,
    required this.hash,
    required this.title,
    required this.artists,
    required this.albumId,
    required this.albumTitle,
    required this.durationMs,
    required this.coverUrl,
    required this.privilege,
  });

  /// 酷狗曲目主键：推荐歌曲协议用 album_audio_id，home/ai/fm 各有优先级链。
  final String id;
  final String hash;
  final String title;
  final List<MusicArtistRef> artists;
  final String albumId;

  /// wire 无专辑名 → null；上游显式 `Some("")` 时保留空串（不归一）。
  final String? albumTitle;
  final int? durationMs;
  final String coverUrl;
  final int? privilege;

  String get artistText => artists.map((a) => a.name).join(' / ');

  /// [albumTitle] 用哨兵区分「未传」与「显式置 null」。
  MusicDiscoverySongSummary copyWith({
    String? id,
    String? hash,
    String? title,
    List<MusicArtistRef>? artists,
    String? albumId,
    Object? albumTitle = _unset,
    int? durationMs,
    String? coverUrl,
    int? privilege,
  }) => MusicDiscoverySongSummary(
    id: id ?? this.id,
    hash: hash ?? this.hash,
    title: title ?? this.title,
    artists: artists ?? this.artists,
    albumId: albumId ?? this.albumId,
    albumTitle: identical(albumTitle, _unset)
        ? this.albumTitle
        : albumTitle as String?,
    durationMs: durationMs ?? this.durationMs,
    coverUrl: coverUrl ?? this.coverUrl,
    privilege: privilege ?? this.privilege,
  );

  static const Object _unset = Object();
}

/// 一条音质资源（domain/discovery.rs `AudioResource`）。
///
/// 与共享 `MusicAudioResource` 的差异：payment_type 与骨架 payType 命名无关、
/// 多 download_status（FM relate_goods 的 status）——不共用骨架模型。
class MusicDiscoveryAudioResource {
  const MusicDiscoveryAudioResource({
    required this.quality,
    required this.hash,
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

/// 版权事实（domain/discovery.rs `CatalogRights` ← util/catalog_rights.rs
/// `WireTrans::convert` 的重命名映射）。展示用事实，不是播放授权。
class MusicDiscoveryCatalogRights {
  const MusicDiscoveryCatalogRights({
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

  final MusicDiscoveryQualityMap? qualityMap;
  final Map<String, int?>? classification;
  final MusicDiscoveryEncodedMap? ipMap;
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
  final MusicDiscoveryPreviewRange? preview;
  final String? multitrackHash;
  final String? coverUrl;
  final int? audioPrivilege;
  final int? freeForAd;
  final int? freeLimited;
  final MusicDiscoveryVoiceAd? voiceAd;
}

/// 音质位图（privilege_lite.rs `QualityMap`；attr0/attr1 是版权位字段）。
class MusicDiscoveryQualityMap {
  const MusicDiscoveryQualityMap({this.attr0, this.attr1, this.bits});

  final int? attr0;
  final int? attr1;
  final String? bits;
}

/// 编码位图（domain/discovery.rs `EncodedMap`；ipmap 用）。
class MusicDiscoveryEncodedMap {
  const MusicDiscoveryEncodedMap({this.attr0, this.bits});

  final int? attr0;
  final String? bits;
}

/// 试听区间（privilege_lite.rs `PreviewRange`）。
class MusicDiscoveryPreviewRange {
  const MusicDiscoveryPreviewRange({
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

  /// catalog_rights.rs `PreviewRange::is_empty`：全空时 preview 归 null。
  bool get isEmpty =>
      startByte == null &&
      endByte == null &&
      startMs == null &&
      endMs == null &&
      offsetHash == null &&
      fileType == null &&
      clipHash == null;
}

/// 语音广告位（catalog_rights.rs `WireVoiceAd` → `VoiceAd`）。
class MusicDiscoveryVoiceAd {
  const MusicDiscoveryVoiceAd({this.startMs, this.sizeBytes, this.hash});

  final int? startMs;
  final int? sizeBytes;
  final String? hash;
}

/// 关联视频引用（domain/discovery.rs `VideoReference`；MV 概要事实）。
class MusicDiscoveryVideoReference {
  const MusicDiscoveryVideoReference({
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

/// 歌手详情（domain/discovery.rs `ArtistDetail`；比 ArtistRef 多头像/发布码）。
class MusicDiscoveryArtistDetail {
  const MusicDiscoveryArtistDetail({
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

/// 标签（domain/discovery.rs `SongTag`；tags/ip_tags 共用）。
class MusicDiscoverySongTag {
  const MusicDiscoverySongTag({this.id, this.name, this.parentId});

  final String? id;
  final String? name;
  final String? parentId;
}

/// 推荐文案（domain/discovery.rs `RecommendationText`）。
class MusicDiscoveryRecommendationText {
  const MusicDiscoveryRecommendationText({
    required this.headline,
    required this.detail,
    required this.rankLabel,
  });

  final String headline;
  final String detail;
  final String? rankLabel;

  MusicDiscoveryRecommendationText copyWith({
    String? headline,
    String? detail,
    String? rankLabel,
  }) => MusicDiscoveryRecommendationText(
    headline: headline ?? this.headline,
    detail: detail ?? this.detail,
    rankLabel: rankLabel ?? this.rankLabel,
  );
}

/// 榜单位置（domain/discovery.rs `RankingPosition`；本组端点恒为 null，
/// 模型保留字段以对齐 SongMetadata 形状）。
class MusicDiscoveryRankingPosition {
  const MusicDiscoveryRankingPosition({
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
  final String publishedAt;
}

/// 关联版本（domain/discovery.rs `RelatedVersion`；本组端点恒为空列表）。
class MusicDiscoveryRelatedVersion {
  const MusicDiscoveryRelatedVersion({
    required this.albumAudioId,
    required this.remark,
    this.kind,
  });

  final String albumAudioId;
  final String remark;
  final int? kind;
}

/// 曲目元数据大结构（domain/discovery.rs `SongMetadata`）。
///
/// provider_extension / related_goods_extension 是未建模供应商数据的**原样**
/// 保留位，不是已映射事实的替代品（上游注释语义）。
class MusicDiscoverySongMetadata {
  const MusicDiscoverySongMetadata({
    this.audioId,
    this.originalTitle,
    this.officialTitle,
    this.titleSuffix,
    required this.albumAudioRemark,
    required this.sourceFileName,
    this.language,
    this.publishedAt,
    this.publicationCode,
    this.originalityCode,
    this.hasAccompaniment,
    this.accompanimentCode,
    this.relatedGoodsExtension,
    this.providerExtension,
    this.paymentType,
    this.failureCode,
    this.oldCopyrightCode,
    required this.rights,
    required this.resources,
    required this.videos,
    required this.tags,
    required this.ipTags,
    required this.recommendation,
    this.ranking,
    required this.artists,
    required this.relatedVersions,
  });

  final int? audioId;
  final String? originalTitle;
  final String? officialTitle;
  final String? titleSuffix;
  final String albumAudioRemark;
  final String sourceFileName;
  final String? language;
  final String? publishedAt;
  final int? publicationCode;
  final int? originalityCode;

  /// util/numeric.rs `boolean`：0→false、1→true、其它未知。
  final bool? hasAccompaniment;
  final int? accompanimentCode;
  final Object? relatedGoodsExtension;
  final Object? providerExtension;
  final int? paymentType;
  final int? failureCode;
  final int? oldCopyrightCode;
  final MusicDiscoveryCatalogRights rights;
  final List<MusicDiscoveryAudioResource> resources;
  final List<MusicDiscoveryVideoReference> videos;
  final List<MusicDiscoverySongTag> tags;
  final List<MusicDiscoverySongTag> ipTags;
  final MusicDiscoveryRecommendationText recommendation;
  final MusicDiscoveryRankingPosition? ranking;
  final List<MusicDiscoveryArtistDetail> artists;
  final List<MusicDiscoveryRelatedVersion> relatedVersions;

  MusicDiscoverySongMetadata copyWith({
    int? audioId,
    String? originalTitle,
    String? officialTitle,
    String? titleSuffix,
    String? albumAudioRemark,
    String? sourceFileName,
    String? language,
    String? publishedAt,
    int? publicationCode,
    int? originalityCode,
    bool? hasAccompaniment,
    int? accompanimentCode,
    Object? relatedGoodsExtension = _unset,
    Object? providerExtension = _unset,
    int? paymentType,
    int? failureCode,
    int? oldCopyrightCode,
    MusicDiscoveryCatalogRights? rights,
    List<MusicDiscoveryAudioResource>? resources,
    List<MusicDiscoveryVideoReference>? videos,
    List<MusicDiscoverySongTag>? tags,
    List<MusicDiscoverySongTag>? ipTags,
    MusicDiscoveryRecommendationText? recommendation,
    MusicDiscoveryRankingPosition? ranking,
    List<MusicDiscoveryArtistDetail>? artists,
    List<MusicDiscoveryRelatedVersion>? relatedVersions,
  }) => MusicDiscoverySongMetadata(
    audioId: audioId ?? this.audioId,
    originalTitle: originalTitle ?? this.originalTitle,
    officialTitle: officialTitle ?? this.officialTitle,
    titleSuffix: titleSuffix ?? this.titleSuffix,
    albumAudioRemark: albumAudioRemark ?? this.albumAudioRemark,
    sourceFileName: sourceFileName ?? this.sourceFileName,
    language: language ?? this.language,
    publishedAt: publishedAt ?? this.publishedAt,
    publicationCode: publicationCode ?? this.publicationCode,
    originalityCode: originalityCode ?? this.originalityCode,
    hasAccompaniment: hasAccompaniment ?? this.hasAccompaniment,
    accompanimentCode: accompanimentCode ?? this.accompanimentCode,
    relatedGoodsExtension: identical(relatedGoodsExtension, _unset)
        ? this.relatedGoodsExtension
        : relatedGoodsExtension,
    providerExtension: identical(providerExtension, _unset)
        ? this.providerExtension
        : providerExtension,
    paymentType: paymentType ?? this.paymentType,
    failureCode: failureCode ?? this.failureCode,
    oldCopyrightCode: oldCopyrightCode ?? this.oldCopyrightCode,
    rights: rights ?? this.rights,
    resources: resources ?? this.resources,
    videos: videos ?? this.videos,
    tags: tags ?? this.tags,
    ipTags: ipTags ?? this.ipTags,
    recommendation: recommendation ?? this.recommendation,
    ranking: ranking ?? this.ranking,
    artists: artists ?? this.artists,
    relatedVersions: relatedVersions ?? this.relatedVersions,
  );

  static const Object _unset = Object();
}

/// 曲目 + 元数据（domain/discovery.rs `DiscoverySong`；Deref song 的语义在
/// Dart 里用 `song` 字段显式表达）。
class MusicDiscoverySong {
  const MusicDiscoverySong({required this.song, required this.metadata});

  final MusicDiscoverySongSummary song;
  final MusicDiscoverySongMetadata metadata;
}

// —— 端点模型（module/*.rs 的输出结构） ——

/// 首页发现推荐（home_discover.rs `DiscoverRecommendations`）。
class MusicDiscoverRecommendations {
  const MusicDiscoverRecommendations({
    required this.items,
    required this.unmappedItems,
  });

  final List<MusicDiscoverItem> items;

  /// item_type 不是 "song" 或没有 song_info 对象的条目，原样保留
  /// （only_song 正常情况下应为空）。
  final List<Object?> unmappedItems;
}

/// 首页发现条目（home_discover.rs `DiscoverItem`）。
class MusicDiscoverItem {
  const MusicDiscoverItem({
    required this.itemId,
    required this.algPath,
    required this.startTime,
    required this.song,
  });

  final String itemId;
  final String algPath;

  /// 原样保留；开播时刻语义上游未验证。
  final String? startTime;
  final MusicDiscoverySong song;
}

/// 每日推荐（everyday_recommend.rs `DailyRecommendations`）。
class MusicDailyRecommendations {
  const MusicDailyRecommendations({
    required this.songs,
    required this.date,
    required this.subtitle,
  });

  final List<MusicDiscoverySong> songs;
  final String date;
  final String subtitle;
}

/// 风格推荐（everyday_style_recommend.rs `StyleRecommendations`）。
class MusicStyleRecommendations {
  const MusicStyleRecommendations({required this.songs, required this.groups});

  final List<MusicDiscoverySong> songs;
  final List<MusicStyleTagGroup> groups;
}

/// 风格标签组（everyday_style_recommend.rs `Group`）。
class MusicStyleTagGroup {
  const MusicStyleTagGroup({required this.name, required this.child});

  final String name;
  final List<MusicStyleTag> child;
}

/// 风格标签（everyday_style_recommend.rs `Tag`；wire 键 `default`）。
class MusicStyleTag {
  const MusicStyleTag({
    required this.id,
    required this.name,
    required this.selected,
  });

  final String id;
  final String name;

  /// wire `default`（当前设备/账号勾选态的 0/1 码）。
  final int? selected;
}

/// 免费畅听推荐（ai_recommend_song.rs `FreeListenSongs`）。
class MusicFreeListenSongs {
  const MusicFreeListenSongs({required this.songs, required this.cardInfo});

  final List<MusicDiscoverySong> songs;
  final MusicAiCardInfo? cardInfo;
}

/// 推荐卡片头（ai_recommend_song.rs `CardInfo`）。
class MusicAiCardInfo {
  const MusicAiCardInfo({required this.cardTitle, required this.cardId});

  final String cardTitle;
  final int? cardId;
}

/// 私人 FM（personal_fm.rs `PersonalFmSongs`）。
class MusicPersonalFmSongs {
  const MusicPersonalFmSongs({
    required this.songs,
    required this.batchMark,
    required this.providerExtension,
  });

  final List<MusicPersonalFmSong> songs;
  final String batchMark;

  /// data 层除 song_list/cur_mark 之外的未建模键（serde flatten 语义）。
  final Map<String, Object?> providerExtension;
}

/// FM 单曲（personal_fm.rs `FmSong` = DiscoverySong + FM 元数据）。
class MusicPersonalFmSong {
  const MusicPersonalFmSong({required this.song, required this.personalFm});

  final MusicDiscoverySong song;
  final MusicPersonalFmMetadata personalFm;
}

/// FM 元数据（personal_fm.rs `FmMetadata`）。
class MusicPersonalFmMetadata {
  const MusicPersonalFmMetadata({
    required this.mark,
    required this.similarity,
    required this.algorithm,
    required this.climaxStartMs,
    required this.climaxEndMs,
    required this.climaxDurationMs,
  });

  final String mark;
  final String similarity;
  final String algorithm;
  final int? climaxStartMs;
  final int? climaxEndMs;
  final int? climaxDurationMs;
}

/// 歌曲高潮区间（song_climax.rs `ClimaxSegment`；毫秒为十进制串/数字宽容）。
class MusicSongClimaxSegment {
  const MusicSongClimaxSegment({
    required this.startMs,
    required this.endMs,
    required this.hash,
  });

  final int? startMs;
  final int? endMs;
  final String? hash;
}
