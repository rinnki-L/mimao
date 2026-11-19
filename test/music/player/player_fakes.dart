/// 音乐播放线测试替身：fake engine / fake playbackApi / 进度记录 / 曲目工厂。
///
/// 全部纯内存，不初始化 media_kit、不联网；播放器内核与 UI 测试共用。
library;

import 'dart:async';

import 'package:mimao/music/api/music_playback_api.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/player/playback_engine.dart';

/// 曲目工厂：默认 hash 为 32 位十六进制、id 为数字（可播路径的合法输入）。
MusicSong fakeSong({
  String id = '7301',
  String hash = 'abcdef0123456789abcdef0123456789',
  String title = '稻香',
  String artist = '周杰伦',
  String albumId = '42',
}) => MusicSong(
  id: id,
  audioId: 9001,
  hash: hash,
  title: title,
  artists: <MusicArtistRef>[MusicArtistRef(id: 1, name: artist)],
  albumId: albumId,
  albumTitle: '魔杰座',
  durationMs: 181000,
  coverUrl: '',
);

/// 引擎替身：只记录调用，不产生任何真实播放。
class FakeMusicEngine implements MusicPlaybackEngine {
  FakeMusicEngine({this.log});

  /// 与 fake playbackApi 共用的调用序列（断言「解析→open→play」用）。
  final List<String>? log;

  final StreamController<MusicPlaybackSnapshot> _controller =
      StreamController<MusicPlaybackSnapshot>.broadcast();

  String? openedUrl;
  Duration? openedStartAt;
  final List<Duration> seeks = <Duration>[];
  final List<double> speeds = <double>[];
  int playCalls = 0;
  int pauseCalls = 0;
  bool disposed = false;

  @override
  Stream<MusicPlaybackSnapshot> get snapshots => _controller.stream;

  void emit(MusicPlaybackSnapshot snapshot) => _controller.add(snapshot);

  @override
  Future<void> open(String url, {Duration startAt = Duration.zero}) async {
    openedUrl = url;
    openedStartAt = startAt;
    log?.add('open:$url');
  }

  @override
  Future<void> play() async {
    playCalls++;
    log?.add('play');
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    log?.add('pause');
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    log?.add('seek');
  }

  @override
  Future<void> setSpeed(double speed) async {
    speeds.add(speed);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    // 刻意不关闭 controller：测试需要在 dispose 之后继续 emit，验证
    // store 已取消订阅（真实引擎由 media_kit 负责释放）。
  }
}

/// 播放解析替身：可配置失败、记录调用参数。
class FakePlaybackApi implements MusicPlaybackApi {
  FakePlaybackApi({this.log});

  final List<String>? log;

  /// 非 null 时每次解析都抛它（测试中途清空以模拟重试成功）。
  Object? failure;

  final List<MusicSong> resolvedSongs = <MusicSong>[];
  final List<MusicQuality> qualities = <MusicQuality>[];

  @override
  Future<MusicPlaybackSource> resolvePlayback(
    MusicSong song, {
    MusicQuality quality = MusicQuality.higher,
    String? authorization,
  }) async {
    final error = failure;
    if (error != null) throw error;
    resolvedSongs.add(song);
    qualities.add(quality);
    log?.add('resolve');
    return MusicPlaybackSource(
      hash: song.hash,
      urls: <String>['https://cdn.example/${song.id}.mp3'],
      extension: 'mp3',
      fileName: 'f.mp3',
      durationMs: song.durationMs,
    );
  }
}

/// 进度写入记录器（[ProgressSink] 形态）。
class RecordingProgressSink {
  final List<(String, Duration, Duration)> writes =
      <(String, Duration, Duration)>[];

  Future<void> call(
    MusicSong song,
    Duration position,
    Duration duration,
  ) async {
    writes.add((song.id, position, duration));
  }
}
