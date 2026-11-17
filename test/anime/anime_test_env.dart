import 'package:drift/native.dart';
import 'package:mimao/anime/anime_db.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';

/// 番剧领域服务的测试环境：内部权威库 + core 投影库各一个内存实例。
class AnimeTestEnv {
  final AppDb appDb;
  final AnimeDb animeDb;
  final LibraryRepository library;

  AnimeTestEnv._(this.appDb, this.animeDb) : library = LibraryRepository(appDb);

  factory AnimeTestEnv.create() => AnimeTestEnv._(
    AppDb.forTesting(NativeDatabase.memory()),
    AnimeDb.forTesting(NativeDatabase.memory()),
  );

  Future<void> close() async {
    await appDb.close();
    await animeDb.close();
  }
}
