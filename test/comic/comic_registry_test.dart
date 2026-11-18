// closure-02 §6/§7：漫画在 app_registry 的注册生命周期。
//
// 三条路径：
// - 整模块注入（widget 测试常用）：依赖自含，直接注册；
// - 分件注入（内存 DB + 内存源仓库 + 假宿主）：生产装配链路在 CI 走通；
// - owned-DB 关闭验证：mock PathProviderPlatform 让生产 ComicDb() 真的打开
//   临时目录 sqlite，reset 后验证 registry 自建实例已关闭。
//
// 注意：AnimeDb()/ComicDb() 生产构造会启动 drift 的 eager 连接，无插件环境下
// 错误会以 unhandled async error 逃逸——所以凡不验证失败分支的测试都必须注入
// animeDb（内存）避免生产构造。

import 'dart:io';

import 'package:drift/native.dart';
// transitive dep（path_provider 的 platform interface），仅为 owned-DB 关闭
// 验证做 mock，不进 pubspec.yaml。
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/anime_db.dart';
import 'package:mimao/comic/comic_db.dart';
import 'package:mimao/comic/comic_entry.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/engine/engine.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/shell/app_registry.dart';

import '../anime/anime_integration_env.dart' show MemoryRuleStore;
import 'comic_integration_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ComicIntegrationEnv env;
  late AnimeDb animeDb;
  late ComicModule module;

  setUp(() async {
    env = ComicIntegrationEnv.memory();
    await env.seedSource();
    animeDb = AnimeDb.forTesting(NativeDatabase.memory());
    await resetAppModulesForTest();
  });

  tearDown(() async {
    await resetAppModulesForTest();
    await env.close();
    await animeDb.close();
  });

  Future<ComicModule> buildModule() async {
    final adapter = await env.buildAdapter();
    return ComicModule(
      dataSource: adapter,
      sourceRepository: adapter,
      collect: env.collect,
      history: env.history,
      searchHistory: env.searchHistory,
      loadChapterImages: adapter.loadImagesForChapter,
    );
  }

  test('分件注入后番剧与漫画同时注册（type/label/icon 正确），小说仍占位', () async {
    module = await buildModule();
    await initAppModules(
      library: env.library,
      animeDb: animeDb,
      ruleStore: MemoryRuleStore(),
      comicDb: env.comicDb,
      comicSourceStore: env.sourceStore,
      comicHttpClient: env.client,
      comicHostFactory: () => FakeSourceHost(),
      comicModule: module,
    );

    final registered = moduleFor(MediaType.comic);
    expect(registered, same(module));
    expect(registered!.type, MediaType.comic);
    expect(registered.label, '漫画');
    expect(registered.icon, MediaType.comic.icon);
    expect(moduleFor(MediaType.anime), isNotNull, reason: '番剧不受漫画装配影响');
    // M4 骨架：音乐生产装配不碰插件（身份仓库惰性解析），无注入也注册。
    expect(moduleFor(MediaType.music), isNotNull);
    expect(moduleFor(MediaType.novel), isNull);
    expect(appModulesError, isNull);
  });

  test('resetAppModulesForTest 清空注册表、可重复调用、注入的 ComicDb 不被误关', () async {
    module = await buildModule();
    await initAppModules(
      library: env.library,
      animeDb: animeDb,
      ruleStore: MemoryRuleStore(),
      comicDb: env.comicDb,
      comicSourceStore: env.sourceStore,
      comicHttpClient: env.client,
      comicHostFactory: () => FakeSourceHost(),
      comicModule: module,
    );
    await resetAppModulesForTest();
    await resetAppModulesForTest();

    for (final type in MediaType.values) {
      expect(moduleFor(type), isNull);
    }
    expect(
      await env.comicDb.collectRow(
        const ComicRef(id: 'probe', sourceName: 'probe'),
      ),
      isNull,
      reason: '注入的 DB 仍可用 = 未被 registry 关闭',
    );
  });

  test('ComicDb 打不开 → 失败分支：漫画不注册、错误可读、番剧不受影响', () async {
    // drift 对已关闭的内存库会静默重开，探针不会失败——用子类让启动探针
    // 直接抛错，模拟「内部库打不开」。
    final brokenDb = _BrokenComicDb();

    await initAppModules(
      library: env.library,
      animeDb: animeDb,
      ruleStore: MemoryRuleStore(),
      comicDb: brokenDb,
      comicSourceStore: env.sourceStore,
      comicHttpClient: env.client,
      comicHostFactory: () => FakeSourceHost(),
    );

    expect(moduleFor(MediaType.comic), isNull);
    expect(appModulesError ?? '', contains('漫画模块初始化失败'));
    expect(moduleFor(MediaType.anime), isNotNull, reason: '其它模块不受影响');
  });

  test('registry 自建的 ComicDb 在 reset 时被关闭；生产装配链路整条走通', () async {
    // mock path_provider → 生产 AnimeDb()/ComicDb() 真的打开临时目录 sqlite，
    // 探针通过 → 除 DLL 外的生产装配（源仓库读取 + 执行池注册 + 适配器 +
    // ComicModule 装配）全部执行。
    final dir = await Directory.systemTemp.createTemp('mimao_owned_db_');
    final originalProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(dir);
    try {
      await initAppModules(
        library: env.library,
        comicSourceStore: env.sourceStore,
        comicHttpClient: env.client,
        comicHostFactory: () => FakeSourceHost(),
      );

      expect(moduleFor(MediaType.comic), isNotNull);
      expect(moduleFor(MediaType.anime), isNotNull);
      final owned = debugRegistryOwnedComicDb;
      expect(owned, isNotNull, reason: 'registry 自建的实例应在 ownership 内');

      // 生产装配的模块真的能用：内存源仓库里的 seed 源可搜索。
      final registered = moduleFor(MediaType.comic) as ComicModule;
      final results = await registered.dataSource.search('海贼王');
      expect(results.map((e) => e.sourceName), everyElement('bilimanga'));

      await resetAppModulesForTest();
      expect(debugRegistryOwnedComicDb, isNull);
      // registry 自建的 DB 已被关闭：新查询被拒（5s 超时防漂）。
      await expectLater(
        owned!
            .customSelect('SELECT 1')
            .get()
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () => throw TimeoutError('查询应在关闭后立即失败'),
            ),
        throwsA(isA<StateError>()),
      );
    } finally {
      PathProviderPlatform.instance = originalProvider;
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  test('源仓库不可读 → 失败分支，漫画不注册', () async {
    await initAppModules(
      library: env.library,
      animeDb: animeDb,
      ruleStore: MemoryRuleStore(),
      comicDb: env.comicDb,
      comicSourceStore: _ThrowingStore(),
      comicHttpClient: env.client,
      comicHostFactory: () => FakeSourceHost(),
    );
    expect(moduleFor(MediaType.comic), isNull);
    expect(appModulesError ?? '', contains('漫画模块初始化失败'));
  });
}

/// loadAllDetailed 抛异常的源仓库（模拟目录不可读）。
class _ThrowingStore extends MemoryComicSourceStore {
  @override
  Future<ComicSourceLoadResult> loadAllDetailed() async =>
      throw StateError('源目录不可读');
}

/// 启动探针直接抛错的 ComicDb（模拟内部库打不开）。
class _BrokenComicDb extends ComicDb {
  _BrokenComicDb() : super.forTesting(NativeDatabase.memory());

  @override
  Future<ComicCollectRow?> collectRow(ComicRef ref) async =>
      throw StateError('DB 打不开');
}

/// 把所有路径指到临时目录的 path_provider mock。
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.dir);

  final Directory dir;

  @override
  Future<String?> getTemporaryPath() async => dir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;

  @override
  Future<String?> getApplicationSupportPath() async => dir.path;

  @override
  Future<String?> getApplicationCachePath() async => dir.path;

  @override
  Future<String?> getDownloadsPath() async => dir.path;

  @override
  Future<String?> getLibraryPath() async => dir.path;
}

class TimeoutError extends Error {
  TimeoutError(this.message);
  final String message;

  @override
  String toString() => message;
}
