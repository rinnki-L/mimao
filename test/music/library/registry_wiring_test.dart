// 验收 D / app_registry C 段：musicDb 注入优先、生产路径零 I/O 注册、
// reset 关闭 registry 自建库。全部注入番剧/漫画内存分件（同既有 registry 测试）。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/anime_db.dart';
import 'package:mimao/comic/comic_db.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/music/collect_service.dart';
import 'package:mimao/music/history_service.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_db.dart';
import 'package:mimao/music/music_entry.dart';
import 'package:mimao/music/player/player_ui.dart';
import 'package:mimao/music/search_history_service.dart';
import 'package:mimao/shell/app_registry.dart';

import '../../anime/anime_integration_env.dart' show MemoryRuleStore;
import '../../comic/comic_integration_env.dart'
    show FakeComicHttpClient, FakeSourceHost, MemoryComicSourceStore;

void main() {
  setUp(() async {
    await resetAppModulesForTest();
  });

  tearDown(() async {
    await resetAppModulesForTest();
  });

  test('注入 musicDb 后 C 段补齐三个服务与「我的」页构造器', () async {
    final appDb = AppDb.forTesting(NativeDatabase.memory());
    final animeDb = AnimeDb.forTesting(NativeDatabase.memory());
    final comicDb = ComicDb.forTesting(NativeDatabase.memory());
    final musicDb = MusicDb.forTesting(NativeDatabase.memory());
    addTearDown(appDb.close);
    addTearDown(animeDb.close);
    addTearDown(comicDb.close);
    addTearDown(musicDb.close);

    await initAppModules(
      library: LibraryRepository(appDb),
      animeDb: animeDb,
      ruleStore: MemoryRuleStore(),
      comicDb: comicDb,
      comicSourceStore: MemoryComicSourceStore(),
      comicHttpClient: FakeComicHttpClient(),
      comicHostFactory: () => FakeSourceHost(),
      musicDb: musicDb,
    );

    expect(appModulesError, isNull);
    final module = moduleFor(MediaType.music)! as MusicModule;
    expect(module.collect, isA<MusicCollectService>());
    expect(module.history, isA<MusicHistoryService>());
    expect(module.searchHistory, isA<MusicSearchHistoryService>());
    expect(module.libraryBuilder, isNotNull);
    expect(module.libraryBuilder, isA<MusicLibraryBuilder>());
    expect(
      debugRegistryOwnedMusicDb,
      isNull,
      reason: '注入的 MusicDb 不属于 registry',
    );

    // 注入库在 reset 后仍可读写（未被 registry 关闭）。
    await resetAppModulesForTest();
    expect(await musicDb.collectRow(const MusicRef(id: 'probe')), isNull);
  });

  test('未注入 musicDb：registry 建惰性库、reset 后释放所有权（不碰插件）', () async {
    final appDb = AppDb.forTesting(NativeDatabase.memory());
    final animeDb = AnimeDb.forTesting(NativeDatabase.memory());
    final comicDb = ComicDb.forTesting(NativeDatabase.memory());
    addTearDown(appDb.close);
    addTearDown(animeDb.close);
    addTearDown(comicDb.close);

    await initAppModules(
      library: LibraryRepository(appDb),
      animeDb: animeDb,
      ruleStore: MemoryRuleStore(),
      comicDb: comicDb,
      comicSourceStore: MemoryComicSourceStore(),
      comicHttpClient: FakeComicHttpClient(),
      comicHostFactory: () => FakeSourceHost(),
    );

    expect(appModulesError, isNull);
    expect(moduleFor(MediaType.music), isNotNull);
    expect(debugRegistryOwnedMusicDb, isNotNull);

    await resetAppModulesForTest();
    expect(debugRegistryOwnedMusicDb, isNull);
  });
}
