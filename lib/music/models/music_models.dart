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
}

/// 分页结果（domain.rs `Page<T>`）。
class MusicPage<T> {
  const MusicPage({this.page, this.pageSize, this.total, required this.items});

  final int? page;
  final int? pageSize;
  final int? total;
  final List<T> items;
}
