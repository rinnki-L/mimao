// closure-01：AnimeModule 装配、收藏回调、同 id 不同源与 registry 生命周期。
// 全程内存库 + fixture + fake engine，不初始化 media_kit、不联网。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/anime_entry.dart';
import 'package:mimao/anime/anime_models.dart';
import 'package:mimao/anime/collect_service.dart';
import 'package:mimao/anime/data/anime_models.dart';
import 'package:mimao/anime/data/fixture_anime_data_source.dart';
import 'package:mimao/anime/engine/engine.dart';
import 'package:mimao/anime/history_service.dart';
import 'package:mimao/anime/player/anime_player_page.dart';
import 'package:mimao/comic/comic_db.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/shell/app_registry.dart';

import '../comic/comic_integration_env.dart'
    show FakeComicHttpClient, FakeSourceHost, MemoryComicSourceStore;
import 'anime_integration_env.dart';

Widget _app(Widget home) => MaterialApp(home: home);

/// 在真实 BuildContext 里调用 module.buildHome（它要拿 context 给 Navigator/SnackBar）。
class _HostModule extends StatelessWidget {
  const _HostModule({required this.module});

  final AnimeModule module;

  @override
  Widget build(BuildContext context) => module.buildHome(context);
}

/// 启动时读规则就抛异常的仓库，用于验证初始化失败分支。
class _ThrowingRuleStore extends RuleStore {
  _ThrowingRuleStore(super.directory);

  @override
  Future<List<AnimeRule>> loadAll() async => throw StateError('规则目录不可读');
}

/// 收藏时抛异常的 fake，用于验证 UI 失败提示且不把异常冒到事件循环。
class _ThrowingCollectService extends AnimeCollectService {
  _ThrowingCollectService(super.db, super.library);

  @override
  Future<void> collect(
    AnimeRef ref, {
    required String title,
    String? coverUrl,
    String payload = '{}',
    DateTime? collectedAt,
  }) async => throw StateError('内部库写入失败');
}

/// 打开点校正即抛的服务替身：验证校正失败不挡导航、无 unhandled async error。
class _ThrowingHistoryService extends AnimeHistoryService {
  _ThrowingHistoryService(super.db, super.library);

  @override
  Future<void> open(AnimeRef ref) async => throw StateError('打开点校正失败');
}

void main() {
  late AnimeIntegrationEnv env;
  late AnimeCollectService collect;
  late AnimeHistoryService history;

  // closure-02：initAppModules 的漫画生产装配需要分件注入（内存 DB/源仓库/
  // 假宿主），否则 ComicDb() 生产构造的 drift eager 连接在无插件测试环境
  // 会以 unhandled async error 逃逸。
  late ComicDb comicDb;
  late MemoryComicSourceStore comicSourceStore;

  setUp(() async {
    env = await AnimeIntegrationEnv.create();
    collect = AnimeCollectService(env.animeDb, env.library);
    history = AnimeHistoryService(env.animeDb, env.library);
    comicDb = ComicDb.forTesting(NativeDatabase.memory());
    comicSourceStore = MemoryComicSourceStore();
    await resetAppModulesForTest();
  });

  tearDown(() async {
    await resetAppModulesForTest();
    await comicDb.close();
    await env.close();
  });

  AnimeModule buildModule() => AnimeModule(
    dataSource: env.dataSource,
    collect: collect,
    history: history,
    ruleStore: env.ruleStore,
    ruleImporter: RuleImporter(),
    playbackEngineFactory: env.engineFactory,
  );

  test('initAppModules 后只注册番剧，其它三个为 null', () async {
    await initAppModules(
      library: env.library,
      animeDb: env.animeDb,
      ruleStore: env.ruleStore,
      animeDataSource: env.dataSource,
      playbackEngineFactory: env.engineFactory,
      comicDb: comicDb,
      comicSourceStore: comicSourceStore,
      comicHttpClient: FakeComicHttpClient(),
      comicHostFactory: () => FakeSourceHost(),
    );

    expect(moduleFor(MediaType.anime), isNotNull);
    // closure-02：漫画分件注入后也注册；小说/音乐仍为占位。
    expect(moduleFor(MediaType.comic), isNotNull);
    for (final type in <MediaType>[MediaType.novel, MediaType.music]) {
      expect(moduleFor(type), isNull);
    }
    expect(appModulesError, isNull);
  });

  test('resetAppModulesForTest 清空注册表且可重复调用', () async {
    await initAppModules(
      library: env.library,
      animeDb: env.animeDb,
      ruleStore: env.ruleStore,
      animeDataSource: env.dataSource,
      playbackEngineFactory: env.engineFactory,
      comicDb: comicDb,
      comicSourceStore: comicSourceStore,
      comicHttpClient: FakeComicHttpClient(),
      comicHostFactory: () => FakeSourceHost(),
    );
    await resetAppModulesForTest();
    await resetAppModulesForTest();

    for (final type in MediaType.values) {
      expect(moduleFor(type), isNull);
    }
    // 注入的 DB 未被 registry 关闭：仍可正常读写。
    expect(
      await env.animeDb.collectRow(AnimeRef(id: 'x', sourceName: 'y')),
      isNull,
    );
  });

  test('初始化失败：不注册番剧、记录原因、不抛异常', () async {
    // 注入读取即抛的 RuleStore，令初始化在规则探针处失败 → 走失败分支。
    await initAppModules(
      library: env.library,
      animeDb: env.animeDb,
      ruleStore: _ThrowingRuleStore(env.ruleDir),
      animeDataSource: env.dataSource,
      playbackEngineFactory: env.engineFactory,
      comicDb: comicDb,
      comicSourceStore: comicSourceStore,
      comicHttpClient: FakeComicHttpClient(),
      comicHostFactory: () => FakeSourceHost(),
    );

    expect(moduleFor(MediaType.anime), isNull);
    expect(appModulesError, isNotNull);
    expect(appModulesError, contains('番剧模块初始化失败'));
  });

  test('AnimeModule 的 type/label/icon 与契约一致', () {
    final module = buildModule();
    expect(module.type, MediaType.anime);
    expect(module.label, '番剧');
    expect(module.icon, MediaType.anime.icon);
  });

  test('refOf：sourceName 为空时回退"未知源"', () {
    const item = AnimeSummary(
      id: 'https://example.com/a',
      title: 'A',
      coverUrl: '',
      detailUrl: 'https://example.com/a',
    );
    expect(
      AnimeModule.refOf(item),
      const AnimeRef(id: 'https://example.com/a', sourceName: '未知源'),
    );
  });

  testWidgets('收藏回调写入 AnimeDb 与 core 投影，取消后 starred=false', (tester) async {
    final module = buildModule();
    const item = FixtureAnimeDataSource.xinghai;
    await tester.pumpWidget(_app(_HostModule(module: module)));
    await tester.pumpAndSettle();

    // 直接走模块层：点搜索结果 → 详情 → 追番。
    await tester.tap(
      find.byKey(const ValueKey<String>('search-result-xinghai')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorite-button')));
    await tester.pumpAndSettle();

    final ref = AnimeModule.refOf(item);
    expect(await env.animeDb.collectRow(ref), isNotNull);
    var timeline = await env.library.timeline();
    expect(timeline.single.starred, isTrue);

    await tester.tap(find.byKey(const Key('favorite-button')));
    await tester.pumpAndSettle();
    expect(await env.animeDb.collectRow(ref), isNull);
    timeline = await env.library.timeline();
    expect(timeline.single.starred, isFalse);
  });

  testWidgets('重新进入同一详情时 initiallyFavorite 来自收藏服务', (tester) async {
    const item = FixtureAnimeDataSource.xinghai;
    final ref = AnimeModule.refOf(item);
    await collect.collect(ref, title: item.title);

    final module = buildModule();
    await tester.pumpWidget(_app(_HostModule(module: module)));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('search-result-xinghai')),
    );
    await tester.pumpAndSettle();
    expect(find.text('已追番'), findsOneWidget);
  });

  test('相同 id、不同 sourceName 的收藏与投影互不覆盖', () async {
    const id = 'https://example.com/same';
    final a = AnimeRef(id: id, sourceName: '源A');
    final b = AnimeRef(id: id, sourceName: '源B');
    await collect.collect(a, title: '同一部·A');
    await collect.collect(b, title: '同一部·B');

    expect(await env.animeDb.collectRow(a), isNotNull);
    expect(await env.animeDb.collectRow(b), isNotNull);
    final timeline = await env.library.timeline();
    expect(timeline, hasLength(2));
    expect(timeline.map((e) => e.sourceName).toSet(), <String>{'源A', '源B'});
  });

  testWidgets('收藏服务抛异常时页面不崩溃，显示失败提示', (tester) async {
    final module = AnimeModule(
      dataSource: env.dataSource,
      collect: _ThrowingCollectService(env.animeDb, env.library),
      history: AnimeHistoryService(env.animeDb, env.library),
      ruleStore: env.ruleStore,
      ruleImporter: RuleImporter(),
    );
    await tester.pumpWidget(_app(_HostModule(module: module)));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('search-result-xinghai')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('favorite-button')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('追番失败'), findsOneWidget);
  });

  testWidgets('点剧集 push AnimePlayerPage 并调用注入的 engine.open', (tester) async {
    final module = buildModule();
    await tester.pumpWidget(_app(_HostModule(module: module)));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('search-result-xinghai')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('episode-2')));
    await tester.pumpAndSettle();

    expect(find.byType(AnimePlayerPage), findsOneWidget);
    expect(env.engines, hasLength(1));
    expect(
      env.lastEngine.openedUrls,
      contains('https://example.com/play/xinghai/2'),
    );
  });

  group('打开点校正接线（onOpenDetail 详情入口 + _openPlayer 播放入口）', () {
    /// 把 core 投影人工写旧，模拟"投影漏写/写旧"后的脏数据
    /// （内部库 ep5 权威不变，投影停在 ep4）。
    Future<void> writeDirtyProjection(AnimeRef ref, String title) {
      return env.library.upsert(
        id: ref.id,
        type: MediaType.anime,
        sourceName: ref.sourceName,
        title: title,
        payload: '{"episode":4,"positionSec":0,"durationSec":0}',
        progressText: '看到第 4 话',
      );
    }

    /// 看过第 5 话（内部库权威 = ep5 · 300s/1440s → 21%）。
    Future<AnimeRef> seedWatchedXinghai() async {
      const item = FixtureAnimeDataSource.xinghai;
      final ref = AnimeModule.refOf(item);
      await history.saveProgress(
        ref,
        title: item.title,
        episode: 5,
        positionSec: 300,
        durationSec: 1440,
      );
      return ref;
    }

    /// 从搜索结果点进星海旅人详情（详情入口，回调已 await 完才导航）。
    Future<void> openXinghaiDetail(
      WidgetTester tester,
      AnimeModule module,
    ) async {
      await tester.pumpWidget(_app(_HostModule(module: module)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('search-result-xinghai')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('详情入口：打开详情把脏投影（内部库 ep5、投影 ep4）校正为 ep5', (tester) async {
      const item = FixtureAnimeDataSource.xinghai;
      final ref = await seedWatchedXinghai();
      await writeDirtyProjection(ref, item.title);
      expect((await env.library.timeline()).single.progressText, '看到第 4 话');

      await openXinghaiDetail(tester, buildModule());
      expect(find.text('番剧详情'), findsOneWidget);

      // 内部库权威值覆盖投影；内部行不被破坏。
      expect((await env.library.timeline()).single.progressText, '第 5 话 · 21%');
      expect((await history.latest(ref))?.episode, 5);
    });

    testWidgets('无观看记录时打开详情不新增书架条目', (tester) async {
      const item = FixtureAnimeDataSource.saibo; // 从未看过、未收藏
      final module = buildModule();
      await tester.pumpWidget(_app(_HostModule(module: module)));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('search-result-saibo')),
      );
      await tester.pumpAndSettle();

      expect(find.text('番剧详情'), findsOneWidget);
      // open 在无内部库记录时短路：不凭空造书架条目。
      expect(await env.library.timeline(), isEmpty);
      expect(await history.latest(AnimeModule.refOf(item)), isNull);
    });

    testWidgets('双入口幂等：详情与播放入口各校正一次，时间线不重复', (tester) async {
      const item = FixtureAnimeDataSource.xinghai;
      final ref = await seedWatchedXinghai();
      final module = buildModule();
      await tester.pumpWidget(_app(_HostModule(module: module)));
      await tester.pumpAndSettle();

      // 详情入口校正一次。
      await writeDirtyProjection(ref, item.title);
      await tester.tap(
        find.byKey(const ValueKey<String>('search-result-xinghai')),
      );
      await tester.pumpAndSettle();
      expect((await env.library.timeline()).single.progressText, '第 5 话 · 21%');

      // 再写脏 → 播放入口（push 播放器前）校正第二次：仍只有一条时间线。
      await writeDirtyProjection(ref, item.title);
      await tester.tap(find.byKey(const Key('episode-2')));
      await tester.pumpAndSettle();
      expect(find.byType(AnimePlayerPage), findsOneWidget);
      final timeline = await env.library.timeline();
      expect(timeline, hasLength(1));
      expect(timeline.single.progressText, '第 5 话 · 21%');
    });

    testWidgets('open 抛异常时详情仍打开，无 unhandled async error', (tester) async {
      final module = AnimeModule(
        dataSource: env.dataSource,
        collect: collect,
        history: _ThrowingHistoryService(env.animeDb, env.library),
        ruleStore: env.ruleStore,
        ruleImporter: RuleImporter(),
        playbackEngineFactory: env.engineFactory,
      );

      await openXinghaiDetail(tester, module);

      expect(find.text('番剧详情'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('open 抛异常时播放器仍打开，无 unhandled async error', (tester) async {
      final module = AnimeModule(
        dataSource: env.dataSource,
        collect: collect,
        history: _ThrowingHistoryService(env.animeDb, env.library),
        ruleStore: env.ruleStore,
        ruleImporter: RuleImporter(),
        playbackEngineFactory: env.engineFactory,
      );
      await tester.pumpWidget(_app(_HostModule(module: module)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('search-result-xinghai')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('episode-2')));
      await tester.pumpAndSettle();

      expect(find.byType(AnimePlayerPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
