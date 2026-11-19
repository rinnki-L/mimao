import 'package:flutter/foundation.dart' show visibleForTesting;
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
import 'package:mimao/comic/collect_service.dart';
import 'package:mimao/comic/comic_db.dart';
import 'package:mimao/comic/comic_entry.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/data/engine_comic_data_source.dart';
import 'package:mimao/comic/engine/engine.dart';
import 'package:mimao/comic/history_service.dart';
import 'package:mimao/comic/reader/reader_cache.dart';
import 'package:mimao/comic/search_history_service.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/music/api/kugou_playback_api.dart';
import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/api/music_playback_api.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/library_api.dart';
import 'package:mimao/music/music_entry.dart';
import 'package:mimao/music/player/media_kit_music_engine.dart';
import 'package:mimao/music/player/playback_engine.dart';
import 'package:mimao/music/player/player_progress.dart';
import 'package:mimao/music/player/player_ui.dart';
import 'package:mimao/music/player/player_ui_impl.dart';

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
/// 多个模块同时失败时按模块逐行拼接。
String? appModulesError;

/// 由 registry 自己创建（而非测试注入）的 DB——只有它们需要 reset 时关闭。
AnimeDb? _ownedAnimeDb;
ComicDb? _ownedComicDb;

/// 测试可见：registry 自建、reset 时会关闭的 ComicDb（生产路径才有值）。
/// CI 没有 path_provider 插件，用这条缝验证 owned-DB 的关闭语义（closure-02
/// 验收 A：reset 后 registry 拥有的 ComicDb 已关闭）。
@visibleForTesting
ComicDb? get debugRegistryOwnedComicDb => _ownedComicDb;

/// 装配模块目录表。生产路径全部参数为 null；测试可逐个注入内存库/临时仓库/
/// fixture 数据源/fake 播放器工厂/假 JS 宿主/整模块。
///
/// 初始化失败（如规则目录/DB 打不开）时不让异常冒到 main：对应模块不注册、
/// [appModulesError] 记录原因，其它模块不受影响。
Future<void> initAppModules({
  required LibraryRepository library,

  // ── 番剧 ──
  AnimeDb? animeDb,
  RuleStore? ruleStore,
  AnimeDataSource? animeDataSource,
  PlaybackEngine Function()? playbackEngineFactory,

  // ── 漫画（closure-02）──
  ComicDb? comicDb,

  /// 测试注入内存/临时源仓库；生产走 openDefault()（path_provider）。
  ComicSourceStore? comicSourceStore,

  /// 测试注入假抓取客户端；生产 ComicWebClient（dio + cookie_jar）。
  ComicHttpClient? comicHttpClient,

  /// 测试注入假 JS 宿主工厂（CI 无 flutter_qjs_plugin.dll）；生产 QuickJsHost。
  JsHost Function()? comicHostFactory,

  /// 测试注入内存图片缓存工厂；生产 defaultComicImageCache（磁盘 LRU）。
  Future<ReaderImageCache> Function()? comicImageCacheFactory,

  /// 测试注入整模块（依赖自含），跳过漫画生产装配直接注册。
  ComicModule? comicModule,

  // ── 音乐（M4 骨架 + 三线契约）──
  /// 测试注入整模块（依赖自含），跳过音乐生产装配直接注册。
  MusicModule? musicModule,

  /// 测试注入内存/临时身份仓库；生产走 openDefault()（path_provider）。
  KugouIdentityStore? musicIdentityStore,

  // ── M4-P 播放（契约缝）──
  /// 播放解析门面；P 线生产实现就绪后由 registry 构造注入。
  MusicPlaybackApi? musicPlaybackApi,

  /// 播放引擎工厂（生产 = media_kit 实现）；测试注入 fake。
  MusicPlaybackEngine Function()? musicPlaybackEngineFactory,

  /// 播放 UI 构造器（P 线实现后注入；null 时点歌只显示占位）。
  MusicPlayerUiFactory? musicPlayerUiFactory,

  /// 播放进度写入口；集成时由 `history.saveProgress` 包成 lambda。
  ProgressSink? musicProgressSink,

  // ── M4-L 登录（契约缝）──
  MusicAccountApi? musicAccount,

  // ── M4-C 收藏历史（契约缝）──
  MusicCollectApi? musicCollect,
  MusicHistoryApi? musicHistory,
  MusicSearchHistoryApi? musicSearchHistory,

  /// 「我的」页构造器（C 线实现后注入；null 时不出底部导航）。
  MusicLibraryBuilder? musicLibraryBuilder,
}) async {
  // 每次装配都是一次干净开始；避免旧的已关闭 DB 残留在表里。
  await _resetOwnedDb();
  appModules.clear();
  appModulesError = null;
  _ownedAnimeDb = null;
  _ownedComicDb = null;

  final errors = <String>[];

  // ── 番剧装配 ──
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
    errors.add('番剧模块初始化失败：$error');
    appModules.remove(MediaType.anime);
    // 失败分支不留下已打开的自建连接（审查 P2；漫画块同款对称处理）。
    final owned = _ownedAnimeDb;
    _ownedAnimeDb = null;
    if (owned != null) {
      try {
        await owned.close();
      } catch (_) {
        // 关闭失败不影响失败分支的收尾。
      }
    }
  }

  // ── 漫画装配（closure-02 §6）──
  try {
    if (comicModule != null) {
      // 测试整模块注入：依赖自含，直接注册。
      appModules[MediaType.comic] = comicModule;
    } else {
      final db = comicDb ?? ComicDb();
      if (comicDb == null) _ownedComicDb = db;
      // 启动探针：内部库打不开就走失败分支，不注册"点进去才崩"的模块。
      await db.collectRow(
        const ComicRef(id: '__init_probe__', sourceName: '__init_probe__'),
      );

      final store = comicSourceStore ?? await ComicSourceStore.openDefault();
      // 启动读一次源仓库：目录不可读/清单损坏在此暴露为可读失败原因。
      await store.loadAllDetailed();

      final client = comicHttpClient ?? ComicWebClient();
      // 生产宿主与适配器共用同一 client（共享 cookie 语义）；
      // CI/测试注入假宿主工厂，不依赖 flutter_qjs_plugin.dll。
      final pool = SourceExecutionPool(
        hostFactory:
            comicHostFactory ??
            () => QuickJsHost(bridge: ComicJsBridge(client: client)),
      );
      final searchHistory = ComicSearchHistoryService(db);
      final adapter = await EngineComicDataSource.create(
        store: store,
        engine: ComicSourceEngine(pool: pool),
        client: client,
        searchHistory: searchHistory,
      );

      // 源仓库目录与适配器共用同一 client（共享 UA/Cookie 语义）；
      // 浏览清单只读 index.json，导入仍走 adapter.importSource 的既有链路。
      final sourceCatalog = ComicSourceCatalog(client: client);
      appModules[MediaType.comic] = ComicModule(
        dataSource: adapter,
        sourceRepository: adapter,
        sourceCatalog: sourceCatalog,
        collect: ComicCollectService(db, library),
        history: ComicHistoryService(db, library),
        searchHistory: searchHistory,
        loadChapterImages: adapter.loadImagesForChapter,
        imageCacheFactory: comicImageCacheFactory ?? defaultComicImageCache,
      );
    }
  } catch (error) {
    errors.add('漫画模块初始化失败：$error');
    appModules.remove(MediaType.comic);
    final owned = _ownedComicDb;
    _ownedComicDb = null;
    if (owned != null) {
      try {
        await owned.close();
      } catch (_) {
        // 同上。
      }
    }
  }

  // ── 音乐装配（M4 骨架）──
  try {
    if (musicModule != null) {
      // 测试整模块注入：依赖自含，直接注册。
      appModules[MediaType.music] = musicModule;
    } else {
      // 身份仓库走工厂惰性解析（首次 API 调用才碰 path_provider）；设备
      // 注册与搜索都是联网动作，留给首次搜索时经 MusicApi.ensureDevice
      // 惰性执行——启动期不发网络请求、不碰插件。
      // 与番剧/漫画的「启动探针」刻意不同：音乐没有本地库可探，联网动作
      // 的失败延迟到首搜，由 MusicStore.error 呈现（lib/music/README.md）。
      final client = KugouClient();
      final api = KugouMusicApi(
        client: client,
        identityStoreFactory: () async =>
            musicIdentityStore ?? KugouIdentityStore.openDefault(),
      );
      // 三个切片的依赖全部来自注入缝（契约提交）；各线在自己的标记块里
      // 补生产构造，本文件不需要再改签名。
      appModules[MediaType.music] = MusicModule(
        api: api,
        // ── M4-P 播放 ──
        // 默认实现（端点门面 + media_kit 引擎 + UI 工厂）；测试注入优先。
        // 引擎工厂只是 tear-off，首次 playSong 才构造，启动期不碰 libmpv。
        playbackApi: musicPlaybackApi ?? KugouPlaybackApi(client, api),
        engineFactory: musicPlaybackEngineFactory ?? MediaKitMusicEngine.new,
        progressSink: musicProgressSink,
        playerUiFactory: musicPlayerUiFactory ?? createMusicPlayerUi,
        // ── M4-L 登录 ──
        account: musicAccount,
        // ── M4-C 收藏历史 ──
        collect: musicCollect,
        history: musicHistory,
        searchHistory: musicSearchHistory,
        libraryBuilder: musicLibraryBuilder,
      );
    }
  } catch (error) {
    errors.add('音乐模块初始化失败：$error');
    appModules.remove(MediaType.music);
  }

  appModulesError = errors.isEmpty ? null : errors.join('\n');
}

/// 测试隔离：清空目录表，只关闭 registry 自己创建的 DB；
/// 测试注入的 DB 由测试自己关闭。允许重复调用。
Future<void> resetAppModulesForTest() async {
  appModules.clear();
  appModulesError = null;
  await _resetOwnedDb();
}

Future<void> _resetOwnedDb() async {
  final animeDb = _ownedAnimeDb;
  _ownedAnimeDb = null;
  if (animeDb != null) {
    try {
      await animeDb.close();
    } catch (_) {
      // 关闭失败不应阻止重置；DB 可能已被测试提前关闭。
    }
  }
  final comicDb = _ownedComicDb;
  _ownedComicDb = null;
  if (comicDb != null) {
    try {
      await comicDb.close();
    } catch (_) {
      // 同上。
    }
  }
}
