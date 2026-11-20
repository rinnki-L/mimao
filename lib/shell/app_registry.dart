import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:flutter/widgets.dart' show Center, Text;
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
import 'package:mimao/shell/dev/dev_capability.dart';
import 'package:mimao/shell/dev/dev_databases.dart';
import 'package:mimao/music/api/kugou_playback_api.dart';
import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/api/music_playback_api.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/collect_service.dart';
import 'package:mimao/music/history_service.dart';
import 'package:mimao/music/library_api.dart';
import 'package:mimao/music/music_db.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_entry.dart';
import 'package:mimao/music/pages/music_library_page.dart';
import 'package:mimao/music/player/media_kit_music_engine.dart';
import 'package:mimao/music/player/playback_engine.dart';
import 'package:mimao/music/player/player_progress.dart';
import 'package:mimao/music/player/player_ui.dart';
import 'package:mimao/music/player/player_ui_impl.dart';
import 'package:mimao/music/search_history_service.dart';
import 'package:mimao/novel/novel_entry.dart';

/// 全库**唯一**允许 import 三个模块目录（`comic/`、`music/`、
/// `novel/`）的文件——第四条铁律的载体（docs/architecture.md §2）。
///
/// 壳只认这张目录表，不认识任何模块内部类型；模块实现与依赖全部在这里装配，
/// 删模块 = 删目录 + 删这里一行 import + 一处注册（机械可验证）。
///
/// 番剧（anime）已按用户拍板下线，不再装配。
final Map<MediaType, AppModule> appModules = <MediaType, AppModule>{};

/// 壳查询某类型的模块实现；返回 null 表示"尚未接入"，由壳显示占位页。
AppModule? moduleFor(MediaType type) => appModules[type];

/// 最近一次 [initAppModules] 的可读失败原因；null 表示没有失败。
/// 多个模块同时失败时按模块逐行拼接。
String? appModulesError;

/// 由 registry 自己创建（而非测试注入）的 DB——只有它们需要 reset 时关闭。
ComicDb? _ownedComicDb;
MusicDb? _ownedMusicDb;

/// 测试可见：registry 自建、reset 时会关闭的 ComicDb（生产路径才有值）。
/// CI 没有 path_provider 插件，用这条缝验证 owned-DB 的关闭语义（closure-02
/// 验收 A：reset 后 registry 拥有的 ComicDb 已关闭）。
@visibleForTesting
ComicDb? get debugRegistryOwnedComicDb => _ownedComicDb;

/// 测试可见：registry 自建、reset 时会关闭的 MusicDb（生产路径才有值）。
@visibleForTesting
MusicDb? get debugRegistryOwnedMusicDb => _ownedMusicDb;

/// 装配模块目录表。生产路径全部参数为 null；测试可逐个注入内存库/临时仓库/
/// fixture 数据源/fake 播放器工厂/假 JS 宿主/整模块。
///
/// 初始化失败（如规则目录/DB 打不开）时不让异常冒到 main：对应模块不注册、
/// [appModulesError] 记录原因，其它模块不受影响。
Future<void> initAppModules({
  required LibraryRepository library,

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
  /// 音乐模块内部权威库；测试注入内存/临时实例，生产走惰性连接。
  MusicDb? musicDb,
  MusicCollectApi? musicCollect,
  MusicHistoryApi? musicHistory,
  MusicSearchHistoryApi? musicSearchHistory,

  /// 「我的」页构造器（C 线实现后注入；null 时不出底部导航）。
  MusicLibraryBuilder? musicLibraryBuilder,

  // ── 小说（M5 导航骨架）──
  /// 测试注入整模块（依赖自含），跳过默认装配直接注册。
  NovelModule? novelModule,
}) async {
  // 每次装配都是一次干净开始；避免旧的已关闭 DB 残留在表里。
  await _resetOwnedDb();
  appModules.clear();
  appModulesError = null;
  _ownedComicDb = null;
  _ownedMusicDb = null;

  final errors = <String>[];

  // ── 漫画装配（closure-02 §6）──
  try {
    if (comicModule != null) {
      // 测试整模块注入：依赖自含，直接注册。
      appModules[MediaType.comic] = comicModule;
    } else {
      final db = comicDb ?? ComicDb();
      if (comicDb == null) {
        _ownedComicDb = db;
        if (kDebugMode) devRegisterDatabase('comic', db);
      }
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
      // dev 能力（debug-only）：在指定源的 QuickJS runtime 里直跑任意表达式
      // ——真源联调时 agent 直接调源函数，不用点 UI 复现。pool.execute 已收敛
      // 错误（不抛），结果序列化交给 /eval 的 jsonEncode 兜底。
      if (kDebugMode) {
        devRegisterCapability('comic.eval', (args) async {
          final result = await pool.execute(
            args['sourceName']?.toString() ?? '',
            args['code']?.toString() ?? '',
          );
          return <String, Object?>{
            'ok': result.isOk,
            if (result.isOk) 'result': result.value else 'error': result.error,
          };
        });
      }
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
    // 漫画装配失败时摘掉 /eval 能力，避免 dev 端点摸到半死 pool。
    devUnregisterCapability('comic.eval');
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
      // ── M4-L 登录 ──
      // 与 API 共用同一 client/身份仓库；测试注入的假实现优先。
      final account =
          musicAccount ?? KugouAccountApi(client: client, identityApi: api);

      // ── M4-C 收藏历史 ──
      // musicDb 注入优先；否则用惰性连接的 MusicDb（构造不碰 path_provider，
      // 首个真实查询才开库），保证既有 registry 测试（无音乐库注入、无插件
      // 环境）仍能「零 I/O 注册」。启动探针刻意不做：探针会立即开库，与无
      // 插件测试环境冲突；坏库/坏磁盘会在首次收藏或打开「我的」页时暴露。
      var collectApi = musicCollect;
      var historyApi = musicHistory;
      var searchHistoryApi = musicSearchHistory;
      var libraryBuilder = musicLibraryBuilder;
      if (collectApi == null ||
          historyApi == null ||
          searchHistoryApi == null ||
          libraryBuilder == null) {
        final db = musicDb ?? MusicDb();
        if (musicDb == null) {
          _ownedMusicDb = db;
          if (kDebugMode) devRegisterDatabase('music', db);
        }
        collectApi ??= MusicCollectService(db, library);
        historyApi ??= MusicHistoryService(db, library);
        searchHistoryApi ??= MusicSearchHistoryService(db);
        libraryBuilder ??= _defaultMusicLibraryBuilder();
      }

      // 集成收口：未显式注入时，把播放进度写入口接到 C 线的权威库
      // （`saveProgress` 内部完成「写内部表 + 投影 core」）。
      final resolvedHistory = historyApi;
      final progressSink =
          musicProgressSink ??
          (MusicSong song, Duration position, Duration duration) =>
              resolvedHistory.saveProgress(song, position, duration);
      // 三个切片的依赖全部来自注入缝（契约提交）；各线在自己的标记块里
      // 补生产构造，本文件不需要再改签名。
      appModules[MediaType.music] = MusicModule(
        api: api,
        // ── M4-P 播放 ──
        // 默认实现（端点门面 + media_kit 引擎 + UI 工厂）；测试注入优先。
        // 引擎工厂只是 tear-off，首次 playSong 才构造，启动期不碰 libmpv。
        playbackApi: musicPlaybackApi ?? KugouPlaybackApi(client, api),
        engineFactory: musicPlaybackEngineFactory ?? MediaKitMusicEngine.new,
        progressSink: progressSink,
        playerUiFactory: musicPlayerUiFactory ?? createMusicPlayerUi,
        // ── M4-L 登录 ──
        account: account,
        // ── M4-C 收藏历史 ──
        collect: collectApi,
        history: historyApi,
        searchHistory: searchHistoryApi,
        libraryBuilder: libraryBuilder,
      );
    }
  } catch (error) {
    errors.add('音乐模块初始化失败：$error');
    appModules.remove(MediaType.music);
    final owned = _ownedMusicDb;
    _ownedMusicDb = null;
    if (owned != null) {
      try {
        await owned.close();
      } catch (_) {
        // 与番剧/漫画失败分支同款收尾。
      }
    }
  }

  // ── 小说装配（M5 导航骨架）──
  // 骨架期零依赖：模块只渲染五 tab + typed 路由占位屏，不碰任何库/网络/插件，
  // 启动探针与失败分支都无需——真实书源/数据层随后续切片接入时再在此补装配。
  try {
    appModules[MediaType.novel] = novelModule ?? NovelModule();
  } catch (error) {
    errors.add('小说模块初始化失败：$error');
    appModules.remove(MediaType.novel);
  }

  appModulesError = errors.isEmpty ? null : errors.join('\n');
}

/// 生产默认「我的」页构造器：C 线页面只认列表服务，续播缝在这里接到
/// P 线的 `MusicPlayerUi.playSong`。注入非本线实现时给可读占位而不是崩溃。
MusicLibraryBuilder _defaultMusicLibraryBuilder() {
  return (context, playerUi, collect, history) {
    final collectService = collect is MusicCollectService ? collect : null;
    final historyService = history is MusicHistoryService ? history : null;
    if (collectService == null || historyService == null) {
      return const Center(child: Text('音乐库未接线'));
    }
    return MusicLibraryPage(
      collect: collectService,
      history: historyService,
      onPlaySong: (song, startAt) => playerUi.playSong(song, startAt: startAt),
    );
  };
}

/// 测试隔离：清空目录表，只关闭 registry 自己创建的 DB；
/// 测试注入的 DB 由测试自己关闭。允许重复调用。
Future<void> resetAppModulesForTest() async {
  appModules.clear();
  appModulesError = null;
  await _resetOwnedDb();
}

Future<void> _resetOwnedDb() async {
  // 先从 /db 可寻址表摘掉再关闭：dev 端点永不摸到已关闭连接。
  devUnregisterDatabase('comic');
  final comicDb = _ownedComicDb;
  _ownedComicDb = null;
  if (comicDb != null) {
    try {
      await comicDb.close();
    } catch (_) {
      // 同上。
    }
  }
  devUnregisterDatabase('music');
  final musicDb = _ownedMusicDb;
  _ownedMusicDb = null;
  if (musicDb != null) {
    try {
      await musicDb.close();
    } catch (_) {
      // 同上；惰性连接从未打开时 close 是空操作。
    }
  }
}
