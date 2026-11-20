/// closure-02 漫画集成测试共用环境：内存 DB + 假抓取客户端 + 假 JS 宿主。
///
/// 所有测试不依赖 flutter_qjs_plugin.dll、不访问网络。真 store（临时目录）
/// 用于非 widget 的适配器单测；widget 测试一律用 [MemoryComicSourceStore]
/// （FakeAsync 里真实文件 I/O 会让 pumpAndSettle 卡死——见既往坑）。
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:mimao/comic/collect_service.dart';
import 'package:mimao/comic/comic_db.dart';
import 'package:mimao/comic/data/engine_comic_data_source.dart';
import 'package:mimao/comic/engine/engine.dart';
import 'package:mimao/comic/history_service.dart';
import 'package:mimao/comic/search_history_service.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';

/// 内存版源仓库：覆盖所有 I/O 方法，widget 测试即时完成。
class MemoryComicSourceStore extends ComicSourceStore {
  MemoryComicSourceStore() : super(Directory.systemTemp);

  final Map<String, ComicSourceScript> sources = <String, ComicSourceScript>{};

  @override
  Future<ComicSourceLoadResult> loadAllDetailed() async {
    final list = sources.values.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return ComicSourceLoadResult(
      sources: List<ComicSourceScript>.unmodifiable(list),
    );
  }

  @override
  Future<void> save(ComicSourceScript source) async {
    sources[source.key] = source;
  }

  @override
  Future<bool> delete(String key) async => sources.remove(key) != null;

  @override
  Future<bool> exists(String key) async => sources.containsKey(key);
}

/// 按 URL 返回预置正文的假客户端；[throwOn] 里的 URL 抛网络异常。
class FakeComicHttpClient implements ComicHttpClient {
  FakeComicHttpClient({
    Map<String, String>? bodies,
    this.throwOn = const <String>{},
  }) : bodies = bodies ?? <String, String>{};

  /// url → 正文；`'*'` 兜底任意 URL。
  final Map<String, String> bodies;
  final Set<String> throwOn;
  final List<String> fetched = <String>[];
  int statusCode = 200;

  @override
  Future<ComicHttpResponse> fetch(
    String url, {
    ComicFetchOptions options = const ComicFetchOptions(),
  }) async {
    fetched.add(url);
    if (throwOn.contains(url)) {
      throw StateError('网络不可用：$url');
    }
    final body = bodies[url] ?? bodies['*'];
    return ComicHttpResponse(
      statusCode: body == null ? 404 : statusCode,
      body: body ?? 'not found',
      url: url,
      headers: const <String, List<String>>{},
    );
  }

  @override
  Future<void> setCookies(String url, Map<String, String> cookies) async {}

  @override
  List<Map<String, String>> getCookies(String url) =>
      const <Map<String, String>>[];

  @override
  Future<void> deleteCookies(String url) async {}
}

/// 假 JS 宿主：从池的注册表达式里学自己的 key，然后按表达式前缀回放预置
/// 结果。[failKeys] 里的源在方法调用时抛错（单源失败容错测试）；
/// [failLoadMarkers] 命中的脚本在 loadScript 时抛错（注册失败测试）；
/// [emptyEpisodeIds] 里的章节回放空图片列表（空章跳过测试）。
class FakeSourceHost implements JsHost {
  FakeSourceHost({
    this.failKeys = const <String>{},
    this.failLoadMarkers = const <String>{},
    this.emptyEpisodeIds = const <String>{},
  });

  final Set<String> failKeys;
  final Set<String> failLoadMarkers;
  final Set<String> emptyEpisodeIds;
  String? _key;

  @override
  Future<void> loadScript(String script) async {
    for (final marker in failLoadMarkers) {
      if (script.contains(marker)) {
        throw StateError('脚本加载失败（marker：$marker）');
      }
    }
  }

  @override
  Future<Object?> evaluate(String expression) async {
    final registration = RegExp(
      r'source\.key\s*=\s*"([^"]+)"',
    ).firstMatch(expression);
    if (registration != null) {
      _key = registration.group(1);
      return null;
    }
    // 注册期的额外探针（settings 默认值快照 / init()）不模拟故障：故障按
    // 契约发生在「方法调用」时（search/loadInfo/loadEp）。
    if (_key != null &&
        failKeys.contains(_key) &&
        (expression.startsWith('source.search.load') ||
            expression.startsWith('source.comic.loadInfo') ||
            expression.startsWith('source.comic.loadEp'))) {
      throw StateError('源 $_key 故障');
    }
    if (expression.startsWith('source.search.load')) {
      return integrationSearchResponse;
    }
    if (expression.startsWith('source.comic.loadInfo')) {
      return integrationDetailResponse;
    }
    if (expression.startsWith('source.comic.loadEp')) {
      final epId = RegExp(
        r'source\.comic\.loadEp\("[^"]+",\s*"([^"]+)"\)',
      ).firstMatch(expression)?.group(1);
      if (epId != null && emptyEpisodeIds.contains(epId)) {
        return <String, Object?>{'images': <String>[]};
      }
      return integrationImagesResponse;
    }
    return null;
  }

  @override
  void close() {}
}

/// `source.search.load` 的回放结果（引擎 parseComicList 直接消费）。
const Map<String, Object?> integrationSearchResponse = <String, Object?>{
  'comics': <Map<String, Object?>>[
    <String, Object?>{
      'id': 'c1',
      'title': '测试漫画A',
      'cover': 'https://img.test/c1.jpg',
      'subtitle': '作者甲',
      'tags': <String>['冒险'],
    },
    <String, Object?>{'id': 'c2', 'title': '测试漫画B', 'cover': ''},
  ],
  'maxPage': 2,
};

/// `source.comic.loadInfo` 的回放结果。
const Map<String, Object?> integrationDetailResponse = <String, Object?>{
  'title': '测试漫画A',
  'cover': 'https://img.test/c1.jpg',
  'url': 'https://site.test/comic/c1',
  'description': '这是一部测试漫画',
  'tags': <String, List<String>>{
    '作者': <String>['作者甲'],
    '题材': <String>['冒险', '热血'],
  },
  'chapters': <String, String>{'ch-1': '第一话', 'ch-2': '第二话', 'ch-3': '第三话'},
};

/// `source.comic.loadEp` 的回放结果。
const Map<String, Object?> integrationImagesResponse = <String, Object?>{
  'images': <String>[
    'https://img.test/p1.jpg',
    'https://img.test/p2.jpg',
    'https://img.test/p3.jpg',
  ],
};

/// URL 导入用的最小 Venera 源脚本（自带 key/name）。
const String integrationSourceScriptText = r'''
class BiliManga extends ComicSource {
  var name = "哔哩漫画";
  var key = "bilimanga";
  var version = "1.0.1";
  var minAppVersion = "0.1.0";
  var url = "https://example.com/bilimanga.js";
}
''';

/// 无 key 字段的脚本（fallback key 派生测试用）。
const String integrationSourceScriptNoKey = r'''
class NoKeySource extends ComicSource {
  var name = "无名源";
}
''';

/// 不是 Venera 源的文本。
const String integrationNotASourceScript = 'console.log("hello");';

/// 集成环境：内存 AppDb/ComicDb + 服务 + （可选）真临时目录 store。
class ComicIntegrationEnv {
  ComicIntegrationEnv._(
    this.appDb,
    this.comicDb,
    this.storeDir,
    this.library,
    this.client,
  );

  final AppDb appDb;
  final ComicDb comicDb;
  final Directory? storeDir;
  final LibraryRepository library;
  final FakeComicHttpClient client;

  late final ComicSourceStore sourceStore;
  late final ComicSearchHistoryService searchHistory;
  late final ComicCollectService collect;
  late final ComicHistoryService history;

  /// widget 测试用：内存源仓库。
  factory ComicIntegrationEnv.memory() {
    final appDb = AppDb.forTesting(NativeDatabase.memory());
    final comicDb = ComicDb.forTesting(NativeDatabase.memory());
    final env = ComicIntegrationEnv._(
      appDb,
      comicDb,
      null,
      LibraryRepository(appDb),
      FakeComicHttpClient(),
    );
    env.sourceStore = MemoryComicSourceStore();
    env._initServices();
    return env;
  }

  /// 适配器单测用：真 store（临时目录），可预置导入响应。
  static Future<ComicIntegrationEnv> create({
    Map<String, String>? bodies,
    Set<String> throwOn = const <String>{},
  }) async {
    final appDb = AppDb.forTesting(NativeDatabase.memory());
    final comicDb = ComicDb.forTesting(NativeDatabase.memory());
    final dir = await Directory.systemTemp.createTemp('mimao_closure02_');
    final env = ComicIntegrationEnv._(
      appDb,
      comicDb,
      dir,
      LibraryRepository(appDb),
      FakeComicHttpClient(bodies: bodies, throwOn: throwOn),
    );
    env.sourceStore = ComicSourceStore(dir);
    env._initServices();
    return env;
  }

  void _initServices() {
    searchHistory = ComicSearchHistoryService(comicDb);
    collect = ComicCollectService(comicDb, library);
    history = ComicHistoryService(comicDb, library);
  }

  /// 组装真实适配器（假执行池）。[failKeys] / [failLoadMarkers] 透传给宿主。
  Future<EngineComicDataSource> buildAdapter({
    Set<String> failKeys = const <String>{},
    Set<String> failLoadMarkers = const <String>{},
    Set<String> emptyEpisodeIds = const <String>{},
  }) {
    final pool = SourceExecutionPool(
      hostFactory: () => FakeSourceHost(
        failKeys: failKeys,
        failLoadMarkers: failLoadMarkers,
        emptyEpisodeIds: emptyEpisodeIds,
      ),
    );
    final engine = ComicSourceEngine(pool: pool);
    return EngineComicDataSource.create(
      store: sourceStore,
      engine: engine,
      client: client,
      searchHistory: searchHistory,
    );
  }

  /// 按 [integrationSourceScriptText] 预置一个已导入源（不走网络）。
  Future<void> seedSource() async {
    final script = ComicSourceImporter()
        .parseSingle(integrationSourceScriptText)
        .sources
        .single;
    await sourceStore.save(script);
    // reload 由 buildAdapter 完成。
  }

  Future<void> close() async {
    await appDb.close();
    await comicDb.close();
    final dir = storeDir;
    if (dir != null && await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
