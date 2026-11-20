/// 专辑端点组模型——EchoMusicNext `module/album_detail.rs` / `album_songs.rs` /
/// `album_dycover.rs` / `favorite_count.rs` 的输出 DTO，以及 `domain/discovery.rs`
/// 的 `CatalogRights` 族（由 `util/catalog_rights.rs` 从 trans_param 装配）。
///
/// docs/architecture.md §4.3：`music/models/` ← domain。组内自包含；与其它组
/// 重复的类型由集成者合并。只提供 toJson——专辑模型当前没有从落盘重建的
/// 消费者（与 MusicPage 的处理一致）。
library;

import 'package:mimao/music/models/music_models.dart';

/// 专辑详情（album_detail.rs `AlbumDetail`）。
class MusicAlbumDetail {
  const MusicAlbumDetail({
    this.id,
    required this.title,
    required this.artists,
    required this.coverUrl,
    required this.publishedAt,
    required this.publisher,
    required this.description,
    required this.language,
    required this.category,
    this.heat,
    this.quality,
    this.exclusive,
    this.published,
  });

  /// 数字型专辑 id（wire `album_id` 是文本，解析失败 → null，上游 parse().ok()）。
  final int? id;
  final String title;
  final List<MusicArtistRef> artists;
  final String coverUrl;
  final String publishedAt;
  final String publisher;
  final String description;
  final String language;

  /// wire `type`（专辑分类文本）。
  final String category;
  final int? heat;
  final int? quality;

  /// 字符串 flag 经 numeric::boolean 归一：0→false、1→true、其它/缺失→null
  /// （未知服务码保留未知，不臆造负向事实）。
  final bool? exclusive;
  final bool? published;

  String get artistText => artists.map((a) => a.name).join(' / ');

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'artists': [for (final artist in artists) artist.toJson()],
    'coverUrl': coverUrl,
    'publishedAt': publishedAt,
    'publisher': publisher,
    'description': description,
    'language': language,
    'category': category,
    'heat': heat,
    'quality': quality,
    'exclusive': exclusive,
    'published': published,
  };
}

/// 专辑动态封面（album_dycover.rs `DynamicCover`）。
class MusicAlbumDynamicCover {
  const MusicAlbumDynamicCover({required this.albumId, required this.urls});

  /// 解析出的专辑 id（wire base.album_id 优先，缺省回退请求里的 album_id）。
  final String albumId;

  /// 签名 URL 原样保留（上游注释：只在临时内存里持有）；已按 http/https +
  /// 有 host 过滤并去重，主 URL 在前。
  final List<String> urls;

  Map<String, Object?> toJson() => <String, Object?>{
    'albumId': albumId,
    'urls': urls,
  };
}

/// 音质位图（privilege_lite.rs `QualityMap`；catalog_rights.rs `qualitymap`）。
class MusicQualityMap {
  const MusicQualityMap({this.attr0, this.attr1, this.bits});

  /// 版权位域按精确整数解码（上游注释：绝不经 f64 舍入）。
  final int? attr0;
  final int? attr1;
  final String? bits;

  Map<String, Object?> toJson() => <String, Object?>{
    'attr0': attr0,
    'attr1': attr1,
    'bits': bits,
  };
}

/// 编码版权映射（discovery.rs `EncodedMap`；catalog_rights.rs `ipmap`）。
class MusicEncodedMap {
  const MusicEncodedMap({this.attr0, this.bits});

  final int? attr0;
  final String? bits;

  Map<String, Object?> toJson() => <String, Object?>{
    'attr0': attr0,
    'bits': bits,
  };
}

/// 试听区间（privilege_lite.rs `PreviewRange`）。
class MusicPreviewRange {
  const MusicPreviewRange({
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

  /// 全空区间（catalog_rights.rs `preview`：空区间被 filter 丢弃）。
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

/// 语音广告区间（discovery.rs `VoiceAd`；catalog_rights.rs `voice_ad`）。
class MusicVoiceAd {
  const MusicVoiceAd({this.startMs, this.sizeBytes, this.hash});

  final int? startMs;
  final int? sizeBytes;
  final String? hash;

  Map<String, Object?> toJson() => <String, Object?>{
    'startMs': startMs,
    'sizeBytes': sizeBytes,
    'hash': hash,
  };
}

/// trans_param 版权事实（discovery.rs `CatalogRights`，util/catalog_rights.rs 装配）。
class MusicCatalogRights {
  const MusicCatalogRights({
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

  final MusicQualityMap? qualityMap;

  /// wire `classmap`：值逐项宽容解析，坏值保留为 null（optional_map）。
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

  /// wire `union_cover` 的 `{size}` 占位符已替换为 240。
  final String? coverUrl;
  final int? audioPrivilege;
  final int? freeForAd;
  final int? freeLimited;
  final MusicVoiceAd? voiceAd;

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

/// 目录歌曲事实（discovery.rs `CatalogSongFacts`）：支付/版权/资源行，供角标、
/// 过滤器与队列快照使用（album_songs.rs 每行一条）。
class MusicCatalogSongFacts {
  const MusicCatalogSongFacts({
    this.paymentType,
    this.failureCode,
    this.oldCopyrightCode,
    this.originalityCode,
    this.rights,
    required this.resources,
  });

  final int? paymentType;
  final int? failureCode;

  /// wire `deprecated.old_cpy`。
  final int? oldCopyrightCode;

  /// rights.originality_code 的快捷读取（album_songs.rs 同名提升）。
  final int? originalityCode;
  final MusicCatalogRights? rights;
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

/// 专辑内一首曲目（album_songs.rs `AlbumTrack`）：歌曲摘要 + 版权/音质事实 +
/// 碟片/曲序/伴奏事实。
class MusicAlbumTrack {
  const MusicAlbumTrack({
    required this.song,
    required this.metadata,
    this.disc,
    this.position,
    this.hasAccompaniment,
    this.accompanimentCode,
  });

  final MusicSong song;
  final MusicCatalogSongFacts metadata;

  /// wire `extend.disc`。
  final int? disc;

  /// wire `extend.sort`。
  final int? position;

  /// wire `extend.has_obbligato` 经 numeric::boolean（未知码 → null）。
  final bool? hasAccompaniment;

  /// 同一字段的原始码（未知码不丢失）。
  final int? accompanimentCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'song': song.toJson(),
    'metadata': metadata.toJson(),
    'disc': disc,
    'position': position,
    'hasAccompaniment': hasAccompaniment,
    'accompanimentCode': accompanimentCode,
  };
}

/// 专辑曲目分页（album_songs.rs `AlbumTracks`）。
class MusicAlbumTracks {
  const MusicAlbumTracks({required this.page, this.discCount});

  final MusicPage<MusicAlbumTrack> page;

  /// wire `extra.disc_cnt`（碟片数）。
  final int? discCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'page': <String, Object?>{
      'page': page.page,
      'pageSize': page.pageSize,
      'total': page.total,
      'items': [for (final item in page.items) item.toJson()],
    },
    'discCount': discCount,
  };
}

/// 收藏计数（favorite_count.rs `Count`）。
class MusicAlbumFavoriteCount {
  const MusicAlbumFavoriteCount({
    this.mixsongId,
    this.count,
    required this.countText,
    this.extension = const <String, Object?>{},
  });

  final int? mixsongId;
  final int? count;

  /// 服务端已格式化的计数文本（「1.2万」）。
  final String countText;

  /// wire 里其余未消费的键（Rust `#[serde(flatten)]` 的旁路捕获）。
  final Map<String, Object?> extension;

  Map<String, Object?> toJson() => <String, Object?>{
    'mixsongId': mixsongId,
    'count': count,
    'countText': countText,
    'extension': extension,
  };
}
