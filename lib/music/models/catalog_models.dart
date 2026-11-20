/// 跨端点组共享的目录摘要模型——EchoMusicNext `crates/echo-api/src/domain.rs`
/// 的 `AlbumSummary` / `ArtistSummary` / `PlaylistSummary` 子集。
///
/// 搜索、榜单、专辑、歌单、发现等端点都会产出这些摘要；放在共享文件里
/// 避免每个组各造一份、UI 集成时再做无意义的映射。
library;

import 'package:mimao/music/models/music_models.dart';

/// 专辑摘要（domain.rs `AlbumSummary`）。
class MusicAlbumSummary {
  const MusicAlbumSummary({
    this.id,
    required this.title,
    required this.artists,
    required this.coverUrl,
    this.songCount,
    required this.publishedAt,
  });

  /// 数字型专辑 id；wire 可能是数字/字符串，不可解析时为 null。
  final int? id;

  final String title;
  final List<MusicArtistRef> artists;
  final String coverUrl;
  final int? songCount;

  /// wire `publish_time` / `publish_date` 原样文本（上游不统一日期格式）。
  final String publishedAt;

  String get artistText => artists.map((a) => a.name).join(' / ');

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'artists': [for (final artist in artists) artist.toJson()],
    'coverUrl': coverUrl,
    'songCount': songCount,
    'publishedAt': publishedAt,
  };

  factory MusicAlbumSummary.fromJson(Map<String, Object?> json) =>
      MusicAlbumSummary(
        id: (json['id'] as num?)?.toInt(),
        title: '${json['title'] ?? ''}',
        artists: <MusicArtistRef>[
          for (final raw
              in (json['artists'] as List<Object?>? ?? const <Object?>[]))
            MusicArtistRef.fromJson(Map<String, Object?>.from(raw! as Map)),
        ],
        coverUrl: '${json['coverUrl'] ?? ''}',
        songCount: (json['songCount'] as num?)?.toInt(),
        publishedAt: '${json['publishedAt'] ?? ''}',
      );
}

/// 歌手摘要（domain.rs `ArtistSummary`）。
class MusicArtistSummary {
  const MusicArtistSummary({
    this.id,
    required this.name,
    required this.avatarUrl,
    this.albumCount,
    this.songCount,
    this.fans,
  });

  final int? id;
  final String name;
  final String avatarUrl;
  final int? albumCount;
  final int? songCount;
  final int? fans;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'avatarUrl': avatarUrl,
    'albumCount': albumCount,
    'songCount': songCount,
    'fans': fans,
  };

  factory MusicArtistSummary.fromJson(Map<String, Object?> json) =>
      MusicArtistSummary(
        id: (json['id'] as num?)?.toInt(),
        name: '${json['name'] ?? ''}',
        avatarUrl: '${json['avatarUrl'] ?? ''}',
        albumCount: (json['albumCount'] as num?)?.toInt(),
        songCount: (json['songCount'] as num?)?.toInt(),
        fans: (json['fans'] as num?)?.toInt(),
      );
}

/// 歌单摘要（domain.rs `PlaylistSummary`）。
class MusicPlaylistSummary {
  const MusicPlaylistSummary({
    this.id,
    required this.globalId,
    required this.title,
    required this.creatorId,
    required this.creatorName,
    required this.coverUrl,
    this.songCount,
    this.playCount,
  });

  final int? id;

  /// 酷狗全局歌单 id（`global_collection_id` / `global_id`）。
  final String globalId;

  final String title;
  final String creatorId;
  final String creatorName;
  final String coverUrl;
  final int? songCount;
  final int? playCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'globalId': globalId,
    'title': title,
    'creatorId': creatorId,
    'creatorName': creatorName,
    'coverUrl': coverUrl,
    'songCount': songCount,
    'playCount': playCount,
  };

  factory MusicPlaylistSummary.fromJson(Map<String, Object?> json) =>
      MusicPlaylistSummary(
        id: (json['id'] as num?)?.toInt(),
        globalId: '${json['globalId'] ?? ''}',
        title: '${json['title'] ?? ''}',
        creatorId: '${json['creatorId'] ?? ''}',
        creatorName: '${json['creatorName'] ?? ''}',
        coverUrl: '${json['coverUrl'] ?? ''}',
        songCount: (json['songCount'] as num?)?.toInt(),
        playCount: (json['playCount'] as num?)?.toInt(),
      );
}

/// 歌单标签（top_playlist / playlist_tags 共用）。
class MusicPlaylistTag {
  const MusicPlaylistTag({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'name': name};

  factory MusicPlaylistTag.fromJson(Map<String, Object?> json) =>
      MusicPlaylistTag(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
      );
}
