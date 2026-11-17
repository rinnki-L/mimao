/// closure-01 集成测试共用的内存环境与可注入替身。
///
/// 所有测试都用内存 AppDb/AnimeDb + 临时 RuleStore + Fixture 数据源 +
/// FakePlaybackEngine，绝不初始化 media_kit、不访问网络。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:mimao/anime/anime_db.dart';
import 'package:mimao/anime/data/anime_data_source.dart';
import 'package:mimao/anime/data/fixture_anime_data_source.dart';
import 'package:mimao/anime/engine/engine.dart';
import 'package:mimao/anime/player/playback_engine.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';

import 'player/fake_playback_engine.dart';

/// 内存版 RuleStore：widget 测试的 FakeAsync 不会推进 dart:io 的 future，
/// 所以覆盖所有 I/O 方法，让 initAppModules 的启动探针即时完成。
class MemoryRuleStore extends RuleStore {
  MemoryRuleStore() : super(Directory.systemTemp);

  final Map<String, AnimeRule> rules = <String, AnimeRule>{};

  @override
  Future<RuleLoadResult> loadAllDetailed() async =>
      RuleLoadResult(rules: List<AnimeRule>.unmodifiable(rules.values));

  @override
  Future<List<AnimeRule>> loadAll() async =>
      List<AnimeRule>.unmodifiable(rules.values);

  @override
  Future<List<File>> saveAll(Iterable<AnimeRule> rules) async {
    for (final rule in rules) {
      this.rules[rule.name] = rule;
    }
    return const <File>[];
  }

  @override
  Future<bool> delete(String name) async => rules.remove(name) != null;
}

class AnimeIntegrationEnv {
  AnimeIntegrationEnv._(
    this.appDb,
    this.animeDb,
    this.ruleDir,
    this.library,
    this.ruleStore,
    this.dataSource,
    this.engines,
  );

  late final AppDb appDb;
  late final AnimeDb animeDb;
  late final Directory ruleDir;
  late final LibraryRepository library;

  /// 内存仓库：widget 测试里用 [ruleStore] 替换真实 I/O 版本。
  late final RuleStore ruleStore;
  late final MemoryRuleStore memoryRuleStore;
  late final AnimeDataSource dataSource;

  /// 每次工厂调用都返回一个新的 Fake，便于断言 open/切集/重试。
  late final List<FakePlaybackEngine> engines;

  FakePlaybackEngine get lastEngine => engines.last;

  static Future<AnimeIntegrationEnv> create() async {
    final appDb = AppDb.forTesting(NativeDatabase.memory());
    final animeDb = AnimeDb.forTesting(NativeDatabase.memory());
    final dir = await Directory.systemTemp.createTemp('mimao_closure01_');
    final engines = <FakePlaybackEngine>[];
    final env = AnimeIntegrationEnv._(
      appDb,
      animeDb,
      dir,
      LibraryRepository(appDb),
      RuleStore(dir),
      const FixtureAnimeDataSource(),
      engines,
    );
    env.memoryRuleStore = MemoryRuleStore();
    return env;
  }

  PlaybackEngine Function() get engineFactory {
    return () {
      final engine = FakePlaybackEngine();
      engines.add(engine);
      return engine;
    };
  }

  Future<void> close() async {
    await appDb.close();
    await animeDb.close();
    if (await ruleDir.exists()) await ruleDir.delete(recursive: true);
    engines.clear();
  }
}
