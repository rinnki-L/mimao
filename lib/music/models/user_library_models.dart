/// 用户库（听歌历史/云歌单/偏好/已购）与验证回执的领域模型——EchoMusicNext
/// `crates/echo-api/src/module/user_history.rs` / `user_playlist.rs` /
/// `user_preference.rs` / `user_preference_update.rs` /
/// `user_purchased_albums.rs` / `user_purchased_songs.rs` / `verify_user_info.rs`
/// 输出结构体与 `domain.rs` / `domain/discovery.rs` 相关 DTO 的 Dart 镜像。
///
/// 组内自包含：跨组通用摘要复用 `catalog_models.dart` / `music_models.dart`
/// 的共享类型；本文件新增类型均以 `MusicUser*` / `Music*` 命名且全局唯一。
library;

import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/music_models.dart';

/// response.rs `unsigned`（u64/u32/i64 标量的宽容面）：数字按字面量十进制
/// 截断，字符串先 trim 再解析；bool/复合类型 → null（optional 语义）。
int? musicWireUnsigned(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final trimmed = value.trim();
    final integer = int.tryParse(trimmed);
    if (integer != null) return integer;
    // 上游 exact_unsigned 对 "1.0"/"1e-1" 这类十进制字面量按位截断。
    return double.tryParse(trimmed)?.toInt();
  }
  return null;
}

/// response.rs `bool` + `optional`：bool 原样；"true"/"false"；整数 0/1；
/// 其它（含 2 及不可解析）→ null——未知服务码不臆造负向事实。
bool? musicWireFlag(Object? value) {
  if (value is bool) return value;
  if (value is String && (value == 'true' || value == 'false')) {
    return value == 'true';
  }
  final numeric = musicWireUnsigned(value);
  return switch (numeric) {
    0 => false,
    1 => true,
    _ => null,
  };
}

/// response.rs `optional` 的 u32：超出 32 位范围按未知处理（Rust
/// `u32::try_from(u64).ok()`）。
int? musicWireU32(Object? value) {
  final numeric = musicWireUnsigned(value);
  if (numeric == null || numeric > 0xFFFFFFFF) return null;
  return numeric;
}

/// 听歌历史一页（user_history.rs `HistoryPage`）。
class MusicHistoryPage {
  const MusicHistoryPage({
    required this.userId,
    required this.cursor,
    required this.finished,
    required this.hasMore,
    required this.items,
  });

  /// wire `userid`（text 宽容）；64 位 id 保持字符串。
  final String userId;

  /// 服务端翻页游标（wire `bp`），原样透传（含空串）。
  final String? cursor;

  /// 完结事实只由 `has_more` 推导；`bp_finished` 是游标别名不是完结标志。
  final bool? finished;
  final bool? hasMore;
  final List<MusicHistoryItem> items;
}

/// 听歌历史条目（user_history.rs `HistoryItem`）。
class MusicHistoryItem {
  const MusicHistoryItem({
    required this.songId,
    required this.name,
    required this.artist,
    required this.album,
    required this.albumId,
    required this.audioId,
    required this.hash,
    required this.cover,
    required this.durationMs,
    required this.bitrate,
    required this.playCount,
    required this.lastPlayedAt,
  });

  /// `mxid` 优先，缺省回退 `info.mixsongid`；64 位 id 保持字符串。
  final String songId;
  final String name;
  final String artist;
  final String album;
  final String? albumId;
  final String? audioId;
  final String hash;
  final String? cover;

  /// wire `timelen` 已是毫秒。
  final int? durationMs;

  /// wire `bitrate`（>32 位按未知处理）。
  final int? bitrate;

  /// wire `pc`。
  final int? playCount;

  /// wire `ot`：最近播放 Unix 秒级时间戳。
  final int? lastPlayedAt;
}

/// 云歌单种类（user_playlist.rs `CloudPlaylistKind`）：`type` 0=自建、
/// 1=收藏、其它=未知。
enum MusicCloudPlaylistKind { owned, collected, unknown }

/// 云歌单的 0/1/2 标志码原样保留（user_playlist.rs `PlaylistFlagCodes`）——
/// 布尔投影独立于码值，未来码值不丢。
class MusicPlaylistFlagCodes {
  const MusicPlaylistFlagCodes({
    required this.editable,
    required this.private,
    required this.published,
    required this.deleted,
    required this.dropped,
    required this.customCover,
  });

  final int? editable;
  final int? private;
  final int? published;
  final int? deleted;
  final int? dropped;
  final int? customCover;
}

/// 一张账号云歌单（user_playlist.rs `UserPlaylist`）。云歌单 id 与公共
/// 合集 id 是两套主键，永不合并计数。
class MusicUserPlaylist {
  const MusicUserPlaylist({
    required this.cloudListId,
    required this.globalId,
    required this.creatorGlobalId,
    required this.title,
    required this.descriptionPresent,
    required this.tagsPresent,
    required this.description,
    required this.tags,
    required this.coverUrl,
    required this.creatorId,
    required this.creatorName,
    required this.creatorListId,
    required this.songCount,
    required this.revision,
    required this.sortIndex,
    required this.sourceCode,
    required this.kind,
    required this.kindCode,
    required this.editable,
    required this.private,
    required this.published,
    required this.deleted,
    required this.dropped,
    required this.customCover,
    required this.defaultKind,
    required this.flagCodes,
    required this.createdAtSeconds,
    required this.updatedAtSeconds,
  });

  /// 云歌单 id（wire `listid`）。
  final int? cloudListId;

  /// 公共合集 id（wire `global_collection_id`，字符串）。
  final String globalId;
  final String creatorGlobalId;
  final String title;

  /// 公开访问（详情/取曲端点）应使用的 global_collection_id。
  ///
  /// 收藏条目（kind == collected）自身的 [globalId] 是**订阅架位合成 id**
  /// （`collection_<kind>_<本人 userid>_<架位 listid>_<序号>`，实测 2026-11-22），
  /// 公开端点对它只回骨架/空页；创作者的真 id 在 [creatorGlobalId]
  /// （wire `list_create_gid`）。自建条目两者相同，直接用 [globalId]。
  String get publicGlobalId {
    if (kind != MusicCloudPlaylistKind.collected) return globalId;
    return creatorGlobalId.isNotEmpty ? creatorGlobalId : globalId;
  }

  /// intro/tags 是否存在于 wire（区分「空串」与「服务端没给」）。
  final bool descriptionPresent;
  final bool tagsPresent;
  final String description;
  final String tags;
  final String coverUrl;
  final int? creatorId;
  final String creatorName;
  final int? creatorListId;
  final int? songCount;
  final int? revision;

  /// wire `sort` 可为负（i64）。
  final int? sortIndex;
  final int? sourceCode;
  final MusicCloudPlaylistKind kind;
  final int? kindCode;
  final bool? editable;
  final bool? private;
  final bool? published;
  final bool? deleted;
  final bool? dropped;
  final bool? customCover;

  /// wire `is_def` 原样码（不是布尔投影）。
  final int? defaultKind;
  final MusicPlaylistFlagCodes flagCodes;
  final int? createdAtSeconds;
  final int? updatedAtSeconds;
}

/// 账号云歌单分页（user_playlist.rs `UserPlaylists`）。
class MusicUserPlaylists {
  const MusicUserPlaylists({
    required this.page,
    required this.userId,
    required this.totalRevision,
    required this.collectionCount,
    required this.albumCount,
  });

  /// page/pageSize 回显请求值；total 取 wire `list_count`。
  final MusicPage<MusicUserPlaylist> page;
  final int? userId;

  /// wire `total_ver`。
  final int? totalRevision;

  /// wire `collect_count`（收藏数）。
  final int? collectionCount;
  final int? albumCount;
}

/// 权重型偏好（user_preference.rs `WeightPreference`）。
class MusicWeightPreference {
  const MusicWeightPreference({
    required this.encoded,
    required this.weights,
    required this.raw,
  });

  /// String 原样；object 序列化为紧凑 JSON（BTreeMap 键序）；其它 → null。
  final String? encoded;

  /// encoded 解出的 `Map<String, double>`；encoded 为空串 → 空表；
  /// 解析失败/含不可读值 → null（不丢弃远端原值）。
  final Map<String, double>? weights;

  /// wire 原值（对象/字符串/数字/bool 均保留，供调试与上传对拍）。
  final Object? raw;
}

/// 当前账号的偏好快照（user_preference.rs `Preferences`）。
class MusicPreferences {
  const MusicPreferences({
    required this.recommendationMode,
    required this.gender,
    required this.age,
    required this.languages,
    required this.styles,
    required this.recommendation,
  });

  final String? recommendationMode;
  final String? gender;
  final String? age;
  final MusicWeightPreference languages;
  final MusicWeightPreference styles;
  final MusicWeightPreference recommendation;
}

/// 偏好写入回执（user_preference_update.rs `Acknowledgement`）。
class MusicPreferenceAcknowledgement {
  const MusicPreferenceAcknowledgement({required this.updated});

  final bool updated;
}

/// 已购专辑条目（user_purchased_albums.rs `PurchasedAlbum`）。
class MusicPurchasedAlbum {
  const MusicPurchasedAlbum({
    required this.album,
    required this.publicationCode,
    required this.providerExtension,
  });

  /// 复用共享专辑摘要（domain.rs `AlbumSummary`；id 过滤 >0，封面
  /// `{size}` → 400）。
  final MusicAlbumSummary album;

  /// wire `is_publish` 原样码。
  final int? publicationCode;

  /// row 的未知键（Rust `#[serde(flatten)] extra`）。
  final Map<String, Object?> providerExtension;
}

/// 购买的歌曲摘要（domain.rs `SongSummary`；与既有 [MusicSong] 字段集不同，
/// 独立命名避免混淆）。
class MusicSongSummary {
  const MusicSongSummary({
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

  /// wire `album_audio_id`（>0 才有；0/缺省 → 空串）。
  final String id;
  final String hash;
  final String title;
  final List<MusicArtistRef> artists;
  final String albumId;

  /// 空专辑名不造占位值（None 表示 wire 没给）。
  final String? albumTitle;

  /// wire `duration` 已是毫秒。
  final int? durationMs;
  final String coverUrl;
  final int? privilege;
}

/// 歌手详情（domain/discovery.rs `ArtistDetail`）。
class MusicArtistDetail {
  const MusicArtistDetail({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.publicationCode,
  });

  final int? id;
  final String name;
  final String? avatarUrl;
  final int? publicationCode;
}

/// 音质映射（privilege_lite.rs `QualityMap`；attr 走 unsigned 宽容）。
class MusicQualityMap {
  const MusicQualityMap({
    required this.attr0,
    required this.attr1,
    required this.bits,
  });

  final int? attr0;
  final int? attr1;
  final String? bits;
}

/// 编码映射（domain/discovery.rs `EncodedMap`）。
class MusicEncodedMap {
  const MusicEncodedMap({required this.attr0, required this.bits});

  final int? attr0;
  final String? bits;
}

/// 试听区间（privilege_lite.rs `PreviewRange`）。
class MusicPreviewRange {
  const MusicPreviewRange({
    required this.startByte,
    required this.endByte,
    required this.startMs,
    required this.endMs,
    required this.offsetHash,
    required this.fileType,
    required this.clipHash,
  });

  final int? startByte;
  final int? endByte;
  final int? startMs;
  final int? endMs;
  final String? offsetHash;
  final int? fileType;
  final String? clipHash;

  /// 全空表示无试听信息（上游 `is_empty`）。
  bool get isEmpty =>
      startByte == null &&
      endByte == null &&
      startMs == null &&
      endMs == null &&
      offsetHash == null &&
      fileType == null &&
      clipHash == null;
}

/// 声音广告区间（domain/discovery.rs `VoiceAd`）。
class MusicVoiceAd {
  const MusicVoiceAd({
    required this.startMs,
    required this.sizeBytes,
    required this.hash,
  });

  final int? startMs;
  final int? sizeBytes;
  final String? hash;
}

/// 版权/试听事实（domain/discovery.rs `CatalogRights`；trans_param 的显式
/// 消费面，未消费的键留给 provider_extension）。
class MusicCatalogRights {
  const MusicCatalogRights({
    required this.qualityMap,
    required this.classification,
    required this.ipMap,
    required this.copyrightAttributes,
    required this.copyrightScope,
    required this.copyrightGrade,
    required this.copyrightLevel,
    required this.displayCode,
    required this.displayRate,
    required this.paymentTemplate,
    required this.blockedApplications,
    required this.originalityCode,
    required this.advanceCode,
    required this.preview,
    required this.multitrackHash,
    required this.coverUrl,
    required this.audioPrivilege,
    required this.freeForAd,
    required this.freeLimited,
    required this.voiceAd,
  });

  final MusicQualityMap? qualityMap;

  /// wire `classmap`：键 → u64 或未知（null 保留未知项）。
  final Map<String, int?>? classification;
  final MusicEncodedMap? ipMap;
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
  final MusicPreviewRange? preview;
  final String? multitrackHash;
  final String? coverUrl;
  final int? audioPrivilege;
  final int? freeForAd;
  final int? freeLimited;
  final MusicVoiceAd? voiceAd;
}

/// 已购单曲的目录事实（domain/discovery.rs `CatalogSongFacts`）。
class MusicCatalogFacts {
  const MusicCatalogFacts({
    required this.paymentType,
    required this.failureCode,
    required this.oldCopyrightCode,
    required this.originalityCode,
    required this.rights,
    required this.resources,
  });

  final int? paymentType;
  final int? failureCode;
  final int? oldCopyrightCode;
  final int? originalityCode;
  final MusicCatalogRights? rights;
  final List<MusicAudioResource> resources;
}

/// 已购单曲元数据（user_purchased_songs.rs `PurchasedSongMetadata`）。
class MusicPurchasedSongMetadata {
  const MusicPurchasedSongMetadata({
    required this.catalog,
    required this.sourceFileName,
    required this.language,
    required this.artists,
    required this.providerExtension,
  });

  final MusicCatalogFacts catalog;

  /// wire `audio_info.name`（源文件名）。
  final String sourceFileName;

  /// trans_param `language`；空串保持未知。
  final String? language;
  final List<MusicArtistDetail> artists;

  /// row/audio 的未知键与 trans_param 未消费键的并集（JSON object）。
  final Object? providerExtension;
}

/// 一首已购单曲（user_purchased_songs.rs `PurchasedSong`）。
class MusicPurchasedSong {
  const MusicPurchasedSong({required this.song, required this.metadata});

  final MusicSongSummary song;
  final MusicPurchasedSongMetadata metadata;
}

/// 验证码提交回执（verify_user_info.rs `Acknowledgement`）。
class MusicVerifyAcknowledgement {
  const MusicVerifyAcknowledgement({required this.acknowledged});

  final bool acknowledged;
}
