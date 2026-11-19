/// 音乐域模型——EchoMusicNext `crates/echo-api/src/domain.rs` 的 Dart 镜像
/// （docs/architecture.md §4.3：`music/models/` ← domain）。
///
/// 骨架期只落搜索链路用到的部分（曲目/歌手/分页/音质资源）；歌单、歌词、
/// 歌手详情等 domain 分片随后续切片生长。字段与 wire 的对应关系见
/// `lib/music/README.md` 的对照表。
library;

/// 歌手/作者引用（domain.rs `ArtistRef`）。
class MusicArtistRef {
  const MusicArtistRef({this.id, required this.name});

  /// 酷狗歌手 id；wire 里可能缺省，null 表示「没有 id」。
  final int? id;

  final String name;

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'name': name};

  factory MusicArtistRef.fromJson(Map<String, Object?> json) => MusicArtistRef(
    id: json['id'] is num ? (json['id']! as num).toInt() : null,
    name: '${json['name'] ?? ''}',
  );
}

/// 一条音质资源（domain.rs/discovery.rs `AudioResource`）。
///
/// 搜索 wire 里同一首歌的 HQ/SQ/Res 有「平铺字段」与「嵌套对象」两种拼法，
/// 适配层把它们都折成这里的条目；quality 沿用 EchoMusicNext 的内部词表
/// （"320" / "flac" / "high"），不使用 wire 上的魔法前缀。
class MusicAudioResource {
  const MusicAudioResource({
    required this.quality,
    required this.hash,
    this.sizeBytes,
    this.durationMs,
    this.bitRateBps,
    this.extension,
    this.privilege,
    this.payType,
    this.failureCode,
  });

  final String quality;
  final String? hash;
  final int? sizeBytes;
  final int? durationMs;
  final int? bitRateBps;
  final String? extension;
  final int? privilege;
  final int? payType;
  final int? failureCode;

  Map<String, Object?> toJson() => <String, Object?>{
    'quality': quality,
    'hash': hash,
    'sizeBytes': sizeBytes,
    'durationMs': durationMs,
    'bitRateBps': bitRateBps,
    'extension': extension,
    'privilege': privilege,
    'payType': payType,
    'failureCode': failureCode,
  };

  factory MusicAudioResource.fromJson(Map<String, Object?> json) =>
      MusicAudioResource(
        quality: '${json['quality'] ?? ''}',
        hash: json['hash'] as String?,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
        durationMs: (json['durationMs'] as num?)?.toInt(),
        bitRateBps: (json['bitRateBps'] as num?)?.toInt(),
        extension: json['extension'] as String?,
        privilege: (json['privilege'] as num?)?.toInt(),
        payType: (json['payType'] as num?)?.toInt(),
        failureCode: (json['failureCode'] as num?)?.toInt(),
      );
}

/// 一首曲目（domain.rs `SongSummary` 的骨架子集）。
///
/// `hash` + `resources` 是后续播放链路（song_auth → tracker 播放地址）的输入；
/// 标准音质的 hash 就是 [hash]，其余音质看 [resources]。
class MusicSong {
  const MusicSong({
    required this.id,
    this.audioId,
    required this.hash,
    required this.title,
    required this.artists,
    required this.albumId,
    required this.albumTitle,
    this.durationMs,
    required this.coverUrl,
    this.privilege,
    this.resources = const <MusicAudioResource>[],
  });

  /// 酷狗曲目主键（wire `MixSongID`，可能是数字也可能是字符串，统一成 String）。
  final String id;

  /// wire `Audioid`；搜索结果可能缺省。
  final int? audioId;

  /// 标准音质文件 hash（wire `FileHash`）。
  final String hash;

  final String title;
  final List<MusicArtistRef> artists;
  final String albumId;
  final String albumTitle;

  /// wire `Duration` 单位是秒，模型统一毫秒。
  final int? durationMs;

  /// 封面 URL；`{size}` 占位符已按上游 cover_url() 替换为 240。
  final String coverUrl;

  /// wire `Privilege`；权限语义随播放链路切片再展开。
  final int? privilege;

  final List<MusicAudioResource> resources;

  /// 歌手名的展示串（「A / B / C」）。
  String get artistText => artists.map((a) => a.name).join(' / ');

  /// 完整序列化：历史/收藏据此重建曲目（续播需要 hash/albumId 等全部字段）。
  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'audioId': audioId,
    'hash': hash,
    'title': title,
    'artists': [for (final artist in artists) artist.toJson()],
    'albumId': albumId,
    'albumTitle': albumTitle,
    'durationMs': durationMs,
    'coverUrl': coverUrl,
    'privilege': privilege,
    'resources': [for (final resource in resources) resource.toJson()],
  };

  factory MusicSong.fromJson(Map<String, Object?> json) => MusicSong(
    id: '${json['id'] ?? ''}',
    audioId: (json['audioId'] as num?)?.toInt(),
    hash: '${json['hash'] ?? ''}',
    title: '${json['title'] ?? ''}',
    artists: <MusicArtistRef>[
      for (final raw
          in (json['artists'] as List<Object?>? ?? const <Object?>[]))
        MusicArtistRef.fromJson(Map<String, Object?>.from(raw! as Map)),
    ],
    albumId: '${json['albumId'] ?? ''}',
    albumTitle: '${json['albumTitle'] ?? ''}',
    durationMs: (json['durationMs'] as num?)?.toInt(),
    coverUrl: '${json['coverUrl'] ?? ''}',
    privilege: (json['privilege'] as num?)?.toInt(),
    resources: <MusicAudioResource>[
      for (final raw
          in (json['resources'] as List<Object?>? ?? const <Object?>[]))
        MusicAudioResource.fromJson(Map<String, Object?>.from(raw! as Map)),
    ],
  );
}

/// 分页结果（domain.rs `Page<T>`）。
class MusicPage<T> {
  const MusicPage({this.page, this.pageSize, this.total, required this.items});

  final int? page;
  final int? pageSize;
  final int? total;
  final List<T> items;
}

/// 音质档位——EchoMusicNext `module/song_url_auth_merge.rs` 的 `Quality` 枚举。
/// wire 值映射（standard→128 等）由播放端点层负责，模型层只表达档位。
enum MusicQuality {
  standard,
  higher,
  flac,
  hiRes,
  viperTape,
  viperClear,
  viperAtmos,

  /// 原 hash 回退；tracker 收到归一化后的 128。
  automatic,
}

/// 播放地址解析结果（`module/song_url_auth.rs` `PlaybackSource`）。
class MusicPlaybackSource {
  const MusicPlaybackSource({
    required this.hash,
    required this.urls,
    this.backupUrls = const <String>[],
    this.fileSizeBytes,
    this.bitRateBps,
    this.durationMs,
    this.standardDurationMs,
    required this.extension,
    required this.fileName,
    this.fileHead,
    this.loudness,
    this.peak,
    this.gain,
  });

  final String hash;

  /// 主地址列表（`url[]`）；空表示服务端未给出可播地址。
  final List<String> urls;
  final List<String> backupUrls;
  final int? fileSizeBytes;
  final int? bitRateBps;
  final int? durationMs;
  final int? standardDurationMs;
  final String extension;
  final String fileName;
  final int? fileHead;
  final double? loudness;
  final double? peak;
  final double? gain;

  /// 首选播放地址；null 表示没有可播地址。
  String? get primaryUrl => urls.isEmpty ? null : urls.first;
}

/// 音乐模块内部权威主键。音乐没有源维度，投影 `sourceName` 恒为
/// [kugouSourceName]（与 core `media_entries` 的复合主键对齐）。
class MusicRef {
  const MusicRef({required this.id});

  final String id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is MusicRef && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MusicRef($id)';
}

/// 投影 `sourceName` 的固定值（core 复合主键的第三维）。
const String kugouSourceName = 'kugou';

/// 曲目 → 权威主键：优先 `MixSongID`，缺失回退文件 hash；两者都空则抛错
/// （调用方应跳过该条，不能把空 id 写进库）。
MusicRef musicRefOf(MusicSong song) {
  final id = song.id.isNotEmpty ? song.id : song.hash;
  if (id.isEmpty) {
    throw ArgumentError('曲目缺少 id 与 hash，无法构造 MusicRef');
  }
  return MusicRef(id: id);
}
