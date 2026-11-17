import 'package:drift/native.dart';
import 'package:mimao/comic/collect_service.dart';
import 'package:mimao/comic/comic_db.dart';
import 'package:mimao/comic/history_service.dart';
import 'package:mimao/comic/search_history_service.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';

/// 漫画领域服务的测试环境：内部权威库 + core 投影库各一个内存实例，
/// 并预组装三个服务（closure-02 进度收敛测试复用）。
class ComicTestEnv {
  final AppDb appDb;
  final ComicDb comicDb;
  final LibraryRepository library;
  final ComicCollectService comicCollect;
  final ComicHistoryService comicHistory;
  final ComicSearchHistoryService searchHistory;

  ComicTestEnv._(this.appDb, this.comicDb)
    : library = LibraryRepository(appDb),
      comicCollect = ComicCollectService(comicDb, LibraryRepository(appDb)),
      comicHistory = ComicHistoryService(comicDb, LibraryRepository(appDb)),
      searchHistory = ComicSearchHistoryService(comicDb);

  factory ComicTestEnv.create() => ComicTestEnv._(
    AppDb.forTesting(NativeDatabase.memory()),
    ComicDb.forTesting(NativeDatabase.memory()),
  );

  Future<void> close() async {
    await appDb.close();
    await comicDb.close();
  }
}
