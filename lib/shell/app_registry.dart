import 'package:mimao/anime/anime_db.dart';
import 'package:mimao/anime/anime_entry.dart';
import 'package:mimao/anime/anime_models.dart';
import 'package:mimao/anime/collect_service.dart';
import 'package:mimao/anime/data/anime_data_source.dart';
import 'package:mimao/anime/data/rule_anime_data_source.dart';
import 'package:mimao/anime/engine/engine.dart';
import 'package:mimao/anime/history_service.dart';
import 'package:mimao/anime/player/media_kit_playback_engine.dart';
import 'package:mimao/anime/player/playback_engine.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/core/library.dart';

/// 全库**唯一**允许 import 四个模块目录（`anime/`、`comic/`、`music/`、
/// `novel/`）的文件——第四条铁律的载体（docs/architecture.md §2）。
///
/// 壳只认这张目录表，不认识任何模块内部类型；模块实现与依赖全部在这里装配，
/// 删模块 = 删目录 + 删这里一行 import + 一处注册（机械可验证）。
///
/// 唯一 AudioHandler 也经本文件从模块入口取出并注册（§6.2，M2）。
final Map<MediaType, AppModule> appModules = <MediaType, AppModule>{};

/// 壳查询某类型的模块实现；返回 null 表示"尚未接入"，由壳显示占位页。
AppModule? moduleFor(MediaType type) => appModules[type];

/// 最近一次 [initAppModules] 的可读失败原因；null 表示没有失败。
String? appModulesError;

/// 由 registry 自己创建（而非测试注入）的 AnimeDb——只有它需要 reset 时关闭。
AnimeDb? _ownedAnimeDb;

/// 装配模块目录表。生产路径全部参数为 null；测试可逐个注入内存库/临时仓库/
/// fixture 数据源/fake 播放器工厂。
///
/// 初始化失败（如规则目录/AnimeDb 打不开）时不让异常冒到 main：番剧不注册、
/// [appModulesError] 记录原因，其它模块不受影响。
Future<void> initAppModules({
  required LibraryRepository library,
  AnimeDb? animeDb,
  RuleStore? ruleStore,
  AnimeDataSource? animeDataSource,
  PlaybackEngine Function()? playbackEngineFactory,
}) async {
  // 每次装配都是一次干净开始；避免旧的已关闭 DB 残留在表里。
  await _resetOwnedDb();
  appModules.clear();
  appModulesError = null;
  _ownedAnimeDb = null;

  try {
    final db = animeDb ?? AnimeDb();
    if (animeDb == null) _ownedAnimeDb = db;
    // 触发一次读，确保内部库真的可打开（建表在此完成）；打不开就走失败分支，
    // 不注册一个"点进去才崩"的模块。
    await db.collectRow(
      const AnimeRef(id: '__init_probe__', sourceName: '__init_probe__'),
    );

    final store = ruleStore ?? await RuleStore.openDefault();
    // 启动时读一次规则仓库：目录不可读就走失败分支并给出原因，
    // 不让用户点进番剧才发现规则全坏。
    await store.loadAll();
    final dataSource = animeDataSource ?? RuleAnimeDataSource.fromStore(store);
    final importer = RuleImporter();
    final collect = AnimeCollectService(db, library);
    final history = AnimeHistoryService(db, library);

    final module = AnimeModule(
      dataSource: dataSource,
      collect: collect,
      history: history,
      ruleStore: store,
      ruleImporter: importer,
      // 只有真正点剧集时才会调用这个工厂去初始化 media_kit；注入 fake 的
      // widget 测试不会走到这里。
      playbackEngineFactory:
          playbackEngineFactory ?? MediaKitPlaybackEngine.new,
    );
    appModules[MediaType.anime] = module;
  } catch (error) {
    appModulesError = '番剧模块初始化失败：$error';
    appModules.remove(MediaType.anime);
  }
}

/// 测试隔离：清空目录表，只关闭 registry 自己创建的 DB；
/// 测试注入的 DB 由测试自己关闭。允许重复调用。
Future<void> resetAppModulesForTest() async {
  appModules.clear();
  appModulesError = null;
  await _resetOwnedDb();
}

Future<void> _resetOwnedDb() async {
  final db = _ownedAnimeDb;
  _ownedAnimeDb = null;
  if (db != null) {
    try {
      await db.close();
    } catch (_) {
      // 关闭失败不应阻止重置；DB 可能已被测试提前关闭。
    }
  }
}
