import 'package:drift/native.dart';
import 'package:mimao/comic/comic_db.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';

/// 漫画领域服务的测试环境：内部权威库 + core 投影库各一个内存实例。
class ComicTestEnv {
  final AppDb appDb;
  final ComicDb comicDb;
  final LibraryRepository library;

  ComicTestEnv._(this.appDb, this.comicDb) : library = LibraryRepository(appDb);

  factory ComicTestEnv.create() => ComicTestEnv._(
    AppDb.forTesting(NativeDatabase.memory()),
    ComicDb.forTesting(NativeDatabase.memory()),
  );

  Future<void> close() async {
    await appDb.close();
    await comicDb.close();
  }
}
