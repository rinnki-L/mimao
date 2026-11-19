import 'package:drift/native.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/music/collect_service.dart';
import 'package:mimao/music/history_service.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_db.dart';
import 'package:mimao/music/search_history_service.dart';

/// 音乐领域服务的测试环境：内部权威库 + core 投影库各一个内存实例，
/// 并预组装三个服务（对齐 ComicTestEnv / AnimeTestEnv）。
class MusicTestEnv {
  final AppDb appDb;
  final MusicDb musicDb;
  final LibraryRepository library;
  final MusicCollectService collect;
  final MusicHistoryService history;
  final MusicSearchHistoryService searchHistory;

  MusicTestEnv._(this.appDb, this.musicDb)
    : library = LibraryRepository(appDb),
      collect = MusicCollectService(musicDb, LibraryRepository(appDb)),
      history = MusicHistoryService(musicDb, LibraryRepository(appDb)),
      searchHistory = MusicSearchHistoryService(musicDb);

  factory MusicTestEnv.create() => MusicTestEnv._(
    AppDb.forTesting(NativeDatabase.memory()),
    MusicDb.forTesting(NativeDatabase.memory()),
  );

  Future<void> close() async {
    await appDb.close();
    await musicDb.close();
  }
}

/// 测试曲目工厂：默认值覆盖历史续播要用的全部字段。
MusicSong testSong({
  String id = '7301',
  String hash = 'ABCDEF0123456789ABCDEF0123456789',
  String title = '稻香',
  String coverUrl = 'https://example.com/cover.jpg',
  int? durationMs = 223000,
}) => MusicSong(
  id: id,
  audioId: 9001,
  hash: hash,
  title: title,
  artists: const <MusicArtistRef>[MusicArtistRef(id: 1, name: '周杰伦')],
  albumId: '42',
  albumTitle: '魔杰座',
  durationMs: durationMs,
  coverUrl: coverUrl,
  privilege: 8,
  resources: const <MusicAudioResource>[
    MusicAudioResource(
      quality: '320',
      hash: 'ABCDEF0123456789ABCDEF0123456789',
      bitRateBps: 320000,
      extension: 'mp3',
    ),
  ],
);
