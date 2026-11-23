// 小说 WebDAV 全量备份：打包→恢复闭环、格式校验、配置读写。全程离线（fake client）。
// ignore_for_file: deprecated_member_use — 与其他 novel 测试同款。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/novel/collect_service.dart';
import 'package:mimao/novel/history_service.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/search_history_service.dart';
import 'package:mimao/novel/source/novel_source_model.dart';
import 'package:mimao/novel/source/novel_source_store.dart';
import 'package:mimao/novel/stats_service.dart';
import 'package:mimao/novel/webdav_backup.dart';

void main() {
  late AppDb appDb;
  late NovelDb novelDb;
  late LibraryRepository library;
  late NovelCollectService collect;
  late NovelHistoryService history;
  late NovelSearchHistoryService searchHistory;
  late NovelStatsService stats;
  late _MemorySourceStorage sourceStore;
  late _FakeWebDavClient client;
  late NovelWebDavBackupService service;

  final config = NovelWebDavConfig(
    url: 'https://dav.example.com/mimao/novel.json',
    user: 'u',
    password: 'p',
  );

  setUp(() {
    appDb = AppDb.forTesting(NativeDatabase.memory());
    novelDb = NovelDb.forTesting(NativeDatabase.memory());
    library = LibraryRepository(appDb);
    collect = NovelCollectService(novelDb, library);
    history = NovelHistoryService(novelDb, library);
    searchHistory = NovelSearchHistoryService(novelDb);
    stats = NovelStatsService(novelDb);
    sourceStore = _MemorySourceStorage();
    client = _FakeWebDavClient();
    service = NovelWebDavBackupService(
      client: client,
      collect: collect,
      history: history,
      searchHistory: searchHistory,
      sourceStorage: sourceStore,
      prefs: stats,
    );
  });

  tearDown(() async {
    await appDb.close();
    await novelDb.close();
  });

  NovelSummary book(String id, String title) =>
      NovelSummary(id: id, title: title, coverUrl: '');

  test('备份：把收藏/历史/搜索/书源/偏好打成一个 JSON 包上传', () async {
    await collect.collect(book('b1', '三体'));
    await collect.setGroup('b1', '科幻');
    await history.saveProgress(book('b1', '三体'), 12, 400);
    await searchHistory.record('三体');
    await sourceStore.saveAll(<NovelBookSource>[
      NovelBookSource(
        key: 'k1',
        name: '源甲',
        url: 'https://a.example',
        type: 0,
        enabled: true,
        raw: const <String, dynamic>{},
      ),
    ]);
    await stats.setGoalMinutes(45);

    final result = await service.backup(config);

    expect(result.collects, 1);
    expect(result.histories, 1);
    expect(result.sources, 1);
    expect(client.lastUrl, config.url);
    expect(client.lastConfig?.user, 'u');
    final doc = NovelBackupDocument.decode(client.lastBody!);
    expect(doc.collects.single.book.title, '三体');
    expect(doc.collects.single.groupName, '科幻');
    expect(doc.histories.single.chapterIndex, 12);
    expect(doc.searchKeywords, <String>['三体']);
    expect(doc.sources.single.name, '源甲');
    expect(doc.prefs[novelPrefGoalMinutes], '45');
  });

  test('恢复：从 WebDAV 下载并覆盖本地数据', () async {
    // 先在源库造数据并备份。
    await collect.collect(book('b1', '三体'));
    await collect.setGroup('b1', '科幻');
    await history.saveProgress(book('b1', '三体'), 12, 400);
    await searchHistory.record('三体');
    await sourceStore.saveAll(<NovelBookSource>[
      NovelBookSource(
        key: 'k1',
        name: '源甲',
        url: 'https://a.example',
        type: 0,
        enabled: true,
        raw: const <String, dynamic>{},
      ),
    ]);
    await stats.setGoalMinutes(45);
    await service.backup(config);
    final backupBody = client.lastBody!;

    // 清空本地，再从 WebDAV 恢复。
    await collect.remove('b1');
    await history.clear();
    await searchHistory.clear();
    await sourceStore.saveAll(const <NovelBookSource>[]);
    await stats.setGoalMinutes(0);
    client.getBody = backupBody;

    final result = await service.restore(config);

    expect(result.collects, 1);
    expect(result.histories, 1);
    expect(result.sources, 1);
    expect((await collect.list()).single.title, '三体');
    expect((await collect.list()).single.groupName, '科幻');
    expect((await history.recent()).single.chapterIndex, 12);
    expect(await searchHistory.recent(), <String>['三体']);
    expect((await sourceStore.loadAll()).single.name, '源甲');
    expect((await stats.snapshot()).goalMinutes, 45);
  });

  test('解码：拒绝非 mimao 备份文件', () {
    expect(
      () => NovelBackupDocument.decode('{"format":"other","version":1}'),
      throwsFormatException,
    );
  });

  test('配置：读写 WebDAV 配置到模块 kv', () async {
    expect(await readWebDavConfig(stats), isNull);
    await writeWebDavConfig(stats, config);
    final loaded = await readWebDavConfig(stats);
    expect(loaded, isNotNull);
    expect(loaded!.url, config.url);
    expect(loaded.user, 'u');
    expect(loaded.password, 'p');
    expect(config.isValid, isTrue);
  });
}

class _FakeWebDavClient implements NovelWebDavClient {
  String? lastUrl;
  String? lastBody;
  NovelWebDavConfig? lastConfig;
  String getBody = '';

  @override
  Future<void> put(String url, String body, NovelWebDavConfig config) async {
    lastUrl = url;
    lastBody = body;
    lastConfig = config;
  }

  @override
  Future<String> get(String url, NovelWebDavConfig config) async {
    lastUrl = url;
    lastConfig = config;
    return getBody;
  }
}

class _MemorySourceStorage implements NovelSourceStorage {
  final Map<String, NovelBookSource> _data = <String, NovelBookSource>{};

  @override
  Future<List<NovelBookSource>> loadAll() async =>
      List<NovelBookSource>.unmodifiable(_data.values);

  @override
  Future<int> saveAll(Iterable<NovelBookSource> sources) async {
    for (final source in sources) {
      _data[source.key] = source;
    }
    return sources.length;
  }

  @override
  Future<void> setEnabled(String key, bool enabled) async {
    final source = _data[key];
    if (source != null) _data[key] = source.copyWith(enabled: enabled);
  }

  @override
  Future<bool> delete(String key) async => _data.remove(key) != null;
}
