// closure-02 §1：A′→D′ 适配器单测——URL 导入、多源搜索打标与容错、
// 字段映射、章节 URL 编解码、启用持久化。全部走假客户端 + 假 JS 宿主，
// 不依赖 DLL、不访问网络。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/data/engine_comic_data_source.dart';
import 'package:mimao/comic/engine/engine.dart' as source_engine;

import 'comic_integration_env.dart';

void main() {
  late ComicIntegrationEnv env;

  setUp(() async {
    env = await ComicIntegrationEnv.create(
      bodies: <String, String>{
        'https://example.com/bilimanga.js': integrationSourceScriptText,
        'https://example.com/nokey.js': integrationSourceScriptNoKey,
        'https://example.com/bad.js': integrationNotASourceScript,
        'https://example.com/empty.js': '',
      },
      throwOn: <String>{'https://down.test/broken.js'},
    );
  });

  tearDown(() => env.close());

  group('URL 导入', () {
    test('合法脚本导入：store 落库、key 用脚本自带、URL 元数据为导入地址', () async {
      final adapter = await env.buildAdapter();
      final sources = await adapter.importSource(
        'https://example.com/bilimanga.js',
      );

      expect(sources, hasLength(1));
      expect(sources.single.id, 'bilimanga');
      expect(sources.single.name, '哔哩漫画');
      expect(sources.single.url, 'https://example.com/bilimanga.js');
      expect(sources.single.enabled, isTrue);
      // 执行池已注册，可直接搜索。
      final result = await adapter.search('海贼王');
      expect(result.map((e) => e.sourceName), everyElement('bilimanga'));
    });

    test('重复导入同 URL：同 key 覆盖，不产生第二条', () async {
      final adapter = await env.buildAdapter();
      await adapter.importSource('https://example.com/bilimanga.js');
      final sources = await adapter.importSource(
        'https://example.com/bilimanga.js',
      );
      expect(sources, hasLength(1));
    });

    test('脚本无 key 字段：fallback key 由 URL basename 派生', () async {
      final adapter = await env.buildAdapter();
      final sources = await adapter.importSource(
        'https://example.com/nokey.js',
      );
      expect(sources.single.id, 'nokey');
    });

    test('非法 URL（非 http / 相对串）：明确失败且 store 无变化', () async {
      final adapter = await env.buildAdapter();
      await expectLater(
        adapter.importSource('ftp://example.com/x.js'),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        adapter.importSource('not a url'),
        throwsA(isA<FormatException>()),
      );
      expect((await adapter.listSources()), isEmpty);
      expect(env.client.fetched, isEmpty, reason: '非法 URL 不应发起请求');
    });

    test('网络异常：抛出含可读原因的异常，不静默成功', () async {
      final adapter = await env.buildAdapter();
      await expectLater(
        adapter.importSource('https://down.test/broken.js'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('下载源脚本失败'),
          ),
        ),
      );
    });

    test('HTTP 404：明确失败', () async {
      final adapter = await env.buildAdapter();
      await expectLater(
        adapter.importSource('https://missing.test/x.js'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('HTTP 404'),
          ),
        ),
      );
    });

    test('畸形脚本（非 Venera 源）/空内容：失败且不留半成品', () async {
      final adapter = await env.buildAdapter();
      await expectLater(
        adapter.importSource('https://example.com/bad.js'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('extends ComicSource'),
          ),
        ),
      );
      await expectLater(
        adapter.importSource('https://example.com/empty.js'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('内容为空'),
          ),
        ),
      );
      expect((await adapter.listSources()), isEmpty);
    });

    test('脚本注册失败：导入失败且 store 不落盘', () async {
      final adapter = await env.buildAdapter(
        failLoadMarkers: <String>{'bilimanga'},
      );
      await expectLater(
        adapter.importSource('https://example.com/bilimanga.js'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('无法注册'),
          ),
        ),
      );
      expect((await adapter.listSources()), isEmpty);
      expect(await env.sourceStore.exists('bilimanga'), isFalse);
    });
  });

  group('多源搜索', () {
    setUp(() => env.seedSource());

    test('双源聚合：每源结果都带自己的 key', () async {
      // 直接向 store 里再放一个 key 不同的源。
      final other = source_engine.parseSourceScript(
        integrationSourceScriptText.replaceFirst('bilimanga', 'othermanga'),
      );
      await env.sourceStore.save(other);
      final adapter = await env.buildAdapter();

      final results = await adapter.search('海贼王');
      expect(results, hasLength(4), reason: '两个源各返回 2 条');
      final keys = results.map((e) => e.sourceName).toSet();
      expect(keys, <String>{'bilimanga', 'othermanga'});
      for (final item in results) {
        expect(item.sourceName, anyOf('bilimanga', 'othermanga'));
        expect(item.detailUrl, '', reason: 'A′ 搜索结果没有详情地址');
      }
    });

    test('禁用源不参与搜索', () async {
      final other = source_engine.parseSourceScript(
        integrationSourceScriptText.replaceFirst('bilimanga', 'othermanga'),
      );
      await env.sourceStore.save(other);
      final adapter = await env.buildAdapter();
      await adapter.setEnabled('othermanga', false);

      final results = await adapter.search('海贼王');
      expect(results.map((e) => e.sourceName).toSet(), <String>{'bilimanga'});
    });

    test('单源故障不拖垮其它源', () async {
      final other = source_engine.parseSourceScript(
        integrationSourceScriptText.replaceFirst('bilimanga', 'badsource'),
      );
      await env.sourceStore.save(other);
      final adapter = await env.buildAdapter(failKeys: <String>{'badsource'});

      final results = await adapter.search('海贼王');
      expect(results, hasLength(2));
      expect(results.map((e) => e.sourceName).toSet(), <String>{
        'bilimanga',
      }, reason: 'badsource 故障，其余源结果仍在');
      expect(adapter.takeDiagnostics(), isNotEmpty);
    });

    test('单源解析异常不拖垮其它源：转诊断而非整次「搜索失败」', () async {
      // 真实事故：某源 maxPage=NaN 让 parseComicList 抛异常，Future.wait
      // 整体 reject，搜索页只剩「搜索失败，请稍后重试」。
      final other = source_engine.parseSourceScript(
        integrationSourceScriptText.replaceFirst('bilimanga', 'boomsource'),
      );
      await env.sourceStore.save(other);
      final adapter = await env.buildAdapter(
        boomSearchKeys: <String>{'boomsource'},
      );

      final results = await adapter.search('海贼王');
      expect(results, hasLength(2));
      expect(results.map((e) => e.sourceName).toSet(), <String>{
        'bilimanga',
      }, reason: 'boomsource 解析失败，其余源结果仍在');
      final diagnostics = adapter.takeSearchDiagnostics();
      expect(diagnostics.join(), contains('boomsource'));
      expect(diagnostics.join(), contains('搜索异常'));
    });

    test('空关键词返回空列表，不调用源脚本', () async {
      final adapter = await env.buildAdapter();
      expect(await adapter.search(''), isEmpty);
      expect(await adapter.search('   '), isEmpty);
    });

    test('搜索词经 ComicSearchHistoryService 落库', () async {
      final adapter = await env.buildAdapter();
      await adapter.search('海贼王');
      expect(await env.searchHistory.recent(), <String>['海贼王']);
      await adapter.search('');
      expect(await env.searchHistory.recent(), <String>[
        '海贼王',
      ], reason: '空关键词不落历史');
    });
  });

  group('聚合搜索按源分组', () {
    setUp(() => env.seedSource());

    test('多源成功：每源一个 section，按 key 稳定排序，条目带各自 sourceName', () async {
      final other = source_engine.parseSourceScript(
        integrationSourceScriptText.replaceFirst('bilimanga', 'othermanga'),
      );
      await env.sourceStore.save(other);
      final adapter = await env.buildAdapter();

      final sections = await adapter.searchGrouped('海贼王');
      expect(sections.map((s) => s.sourceKey).toList(), <String>[
        'bilimanga',
        'othermanga',
      ], reason: '按源 key 稳定排序');
      for (final section in sections) {
        expect(section.items, hasLength(2));
        expect(
          section.items.every((item) => item.sourceName == section.sourceKey),
          isTrue,
        );
        expect(section.diagnostics, isEmpty);
      }
    });

    test('单源解析异常：该源 section 空 items + 带诊断，其它源不受影响', () async {
      final other = source_engine.parseSourceScript(
        integrationSourceScriptText.replaceFirst('bilimanga', 'boomsource'),
      );
      await env.sourceStore.save(other);
      final adapter = await env.buildAdapter(
        boomSearchKeys: <String>{'boomsource'},
      );

      final sections = await adapter.searchGrouped('海贼王');
      expect(sections.map((s) => s.sourceKey).toList(), <String>[
        'bilimanga',
        'boomsource',
      ]);
      final healthy = sections.singleWhere((s) => s.sourceKey == 'bilimanga');
      final broken = sections.singleWhere((s) => s.sourceKey == 'boomsource');
      expect(healthy.items, hasLength(2));
      expect(healthy.diagnostics, isEmpty);
      expect(broken.items, isEmpty, reason: '失败源 0 结果');
      expect(broken.diagnostics.join(), contains('boomsource'));
      expect(broken.diagnostics.join(), contains('搜索异常'));
      // 失败源 section 可见且不静默：诊断同时进入 takeSearchDiagnostics。
      expect(
        adapter.takeSearchDiagnostics().join(),
        contains('boomsource：搜索异常'),
      );
    });

    test('单源调用抛异常：失败源 section 仍存在且带原因', () async {
      final other = source_engine.parseSourceScript(
        integrationSourceScriptText.replaceFirst('bilimanga', 'badsource'),
      );
      await env.sourceStore.save(other);
      final adapter = await env.buildAdapter(failKeys: <String>{'badsource'});

      final sections = await adapter.searchGrouped('海贼王');
      final broken = sections.singleWhere((s) => s.sourceKey == 'badsource');
      expect(broken.items, isEmpty);
      // failKeys 走引擎诊断通道（result.diagnostics），文案带源 key 前缀；
      // boomSearchKeys 走 throw 通道，文案是「搜索异常（…）」。两条都可见。
      expect(broken.diagnostics.join(), contains('badsource：'));
      expect(broken.diagnostics, isNotEmpty);
      expect(
        sections.singleWhere((s) => s.sourceKey == 'bilimanga').items,
        hasLength(2),
      );
    });

    test('空关键词返回空分组列表', () async {
      final adapter = await env.buildAdapter();
      expect(await adapter.searchGrouped(''), isEmpty);
      expect(await adapter.searchGrouped('   '), isEmpty);
    });

    test('search() 摊平结果与 searchGrouped 一致，历史已记录', () async {
      final other = source_engine.parseSourceScript(
        integrationSourceScriptText.replaceFirst('bilimanga', 'othermanga'),
      );
      await env.sourceStore.save(other);
      final adapter = await env.buildAdapter();

      final sections = await adapter.searchGrouped('海贼王');
      final flat = await adapter.search('海贼王');
      final flattened = sections.expand((s) => s.items).toList();
      expect(
        flat.map((e) => '${e.sourceName}:${e.id}').toList(),
        flattened.map((e) => '${e.sourceName}:${e.id}').toList(),
        reason: '摊平顺序 = 分组按 key 排序后逐源拼接',
      );
      expect(await env.searchHistory.recent(), contains('海贼王'));
    });
  });

  group('详情与章节映射', () {
    setUp(() => env.seedSource());

    ComicSummary summaryFor(String key) => ComicSummary(
      id: 'c1',
      title: '测试漫画A',
      coverUrl: '',
      detailUrl: '',
      sourceName: key,
    );

    test('detail 字段映射逐项正确', () async {
      final adapter = await env.buildAdapter();
      final detail = await adapter.detail(summaryFor('bilimanga'));

      expect(detail.title, '测试漫画A');
      expect(detail.coverUrl, 'https://img.test/c1.jpg');
      expect(detail.detailUrl, 'https://site.test/comic/c1');
      expect(detail.description, '这是一部测试漫画');
      expect(detail.sourceName, 'bilimanga');
      // 标签分组展平去重保序：作者甲 / 冒险 / 热血。
      expect(detail.tags, <String>['作者甲', '冒险', '热血']);
    });

    test('章节 number 从 1 递增，url 可反查 (key, comicId, epId)', () async {
      final adapter = await env.buildAdapter();
      final detail = await adapter.detail(summaryFor('bilimanga'));

      expect(detail.chapters, hasLength(3));
      expect(detail.chapters.map((c) => c.number).toList(), <int>[1, 2, 3]);
      final decoded = tryDecodeComicEpisodeUrl(detail.chapters[1].url)!;
      expect(decoded.sourceKey, 'bilimanga');
      expect(decoded.comicId, 'c1');
      expect(decoded.episodeId, 'ch-2');
    });

    test('缺 sourceName / 未知 key / 引擎失败 → 明确报错', () async {
      final adapter = await env.buildAdapter();
      await expectLater(
        adapter.detail(
          ComicSummary(id: 'c1', title: 't', coverUrl: '', detailUrl: ''),
        ),
        throwsArgumentError,
      );
      await expectLater(
        adapter.detail(summaryFor('not-imported')),
        throwsStateError,
      );
      final broken = await env.buildAdapter(failKeys: <String>{'bilimanga'});
      await expectLater(
        broken.detail(summaryFor('bilimanga')),
        throwsStateError,
      );
    });

    test('loadEpImages：正常返回 URL 列表；故障/坏 URL/来源不匹配返回空', () async {
      final adapter = await env.buildAdapter();
      final urls = await adapter.loadEpImages(
        key: 'bilimanga',
        comicId: 'c1',
        episodeId: 'ch-1',
      );
      expect(urls, <String>[
        'https://img.test/p1.jpg',
        'https://img.test/p2.jpg',
        'https://img.test/p3.jpg',
      ]);

      final broken = await env.buildAdapter(failKeys: <String>{'bilimanga'});
      expect(
        await broken.loadEpImages(
          key: 'bilimanga',
          comicId: 'c1',
          episodeId: 'ch-1',
        ),
        isEmpty,
      );

      expect(
        await adapter.loadImagesForChapter(
          summaryFor('bilimanga'),
          const ComicChapter(number: 1, title: 'x', url: 'https://other/1'),
        ),
        isEmpty,
        reason: '非 mimao-ep 串无法反查',
      );
      expect(
        await adapter.loadImagesForChapter(
          summaryFor('bilimanga'),
          const ComicChapter(
            number: 1,
            title: 'x',
            url: 'mimao-ep:///othermanga/c1/ch-1',
          ),
        ),
        isEmpty,
        reason: '章节来源 key 与条目不一致',
      );
    });
  });

  group('源管理', () {
    setUp(() => env.seedSource());

    test('listSources：key/名称/URL/enabled 逐项正确', () async {
      final adapter = await env.buildAdapter();
      final sources = await adapter.listSources();
      expect(sources, hasLength(1));
      expect(sources.single.id, 'bilimanga');
      expect(sources.single.name, '哔哩漫画');
      expect(sources.single.url, 'https://example.com/bilimanga.js');
      expect(sources.single.enabled, isTrue);
      expect(sources.single.comicCount, isNull);
    });

    test('setEnabled 持久化到 manifest，reload 后仍生效', () async {
      final adapter = await env.buildAdapter();
      await adapter.setEnabled('bilimanga', false);
      expect((await adapter.listSources()).single.enabled, isFalse);

      final rebuilt = await env.buildAdapter();
      expect((await rebuilt.listSources()).single.enabled, isFalse);
    });

    test('deleteSource：store 与执行池同步清理', () async {
      final adapter = await env.buildAdapter();
      expect(await adapter.deleteSource('bilimanga'), isEmpty);
      expect(await env.sourceStore.exists('bilimanga'), isFalse);
      expect(await adapter.search('海贼王'), isEmpty, reason: '源已删除，搜索不再出结果');
      await expectLater(
        adapter.deleteSource('bilimanga'),
        throwsStateError,
        reason: '删除不存在的来源报错',
      );
    });

    test('syncPool：对已删除源释放执行池；对新增源补注册', () async {
      final adapter = await env.buildAdapter();
      await adapter.importSource('https://example.com/bilimanga.js');
      await env.sourceStore.delete('bilimanga');
      await adapter.syncPool();
      expect(await adapter.search('海贼王'), isEmpty);

      await env.seedSource();
      await adapter.syncPool();
      final results = await adapter.search('海贼王');
      expect(results, isNotEmpty);
    });

    test('坏脚本文件：reload 汇入 failures，不影响其它源', () async {
      // 直接向真 store 写一个坏脚本文件（清单外的孤儿脚本按文件名补录）。
      await env.seedSource();
      await File(
        '${env.storeDir!.path}/broken.js',
      ).writeAsString('class X extends ComicSource { var key = "broken";');
      // 上面这行故意是残缺 JS；parseSourceScript 仍能抽出 key，
      // 但 FakeSourceHost 的 loadScript 对 marker 抛错模拟注册失败。
      final adapter = await env.buildAdapter(
        failLoadMarkers: <String>{'key = "broken"'},
      );
      expect(
        adapter.takeDiagnostics().join(),
        contains('broken'),
        reason: '注册失败原因进入诊断',
      );
      final results = await adapter.search('海贼王');
      expect(results.map((e) => e.sourceName).toSet(), <String>{'bilimanga'});
    });
  });

  group('导入副作用（对抗性审查 P2 回归）', () {
    setUp(() => env.seedSource());

    test('重导同 key 源保留用户已有的启用状态', () async {
      final adapter = await env.buildAdapter();
      await adapter.importSource('https://example.com/bilimanga.js');
      await adapter.setEnabled('bilimanga', false);
      await adapter.importSource('https://example.com/bilimanga.js');
      expect(
        (await adapter.listSources()).single.enabled,
        isFalse,
        reason: 'name/version 随新脚本刷新，但禁用选择不该被重置',
      );
    });

    test('store.save 失败：异常上抛且回滚执行池条目', () async {
      final store = _SaveThrowingStore();
      final pool = source_engine.SourceExecutionPool(
        hostFactory: () => FakeSourceHost(),
      );
      final adapter = await EngineComicDataSource.create(
        store: store,
        engine: source_engine.ComicSourceEngine(pool: pool),
        client: env.client,
        searchHistory: env.searchHistory,
      );
      await expectLater(
        adapter.importSource('https://example.com/bilimanga.js'),
        throwsStateError,
      );
      expect(store.sources, isEmpty, reason: '未落盘');
      expect(pool.contains('bilimanga'), isFalse, reason: '池条目已回滚');
    });
  });

  group('章节 URL 编解码', () {
    test('round-trip：含特殊字符的 key/comicId/epId', () {
      final url = comicChapterUrl(
        sourceKey: 'a b/c',
        comicId: 'https://site.test/comic/1',
        episodeId: "ep'1\"2",
      );
      final decoded = tryDecodeComicEpisodeUrl(url)!;
      expect(decoded.sourceKey, 'a b/c');
      expect(decoded.comicId, 'https://site.test/comic/1');
      expect(decoded.episodeId, "ep'1\"2");
    });

    test('round-trip：epId 含字面 % 与百分号序列（审查 P1 回归）', () {
      for (final epId in <String>['a%2Fb', '50%off', 'p%20q']) {
        final url = comicChapterUrl(
          sourceKey: 'k',
          comicId: 'c',
          episodeId: epId,
        );
        expect(
          tryDecodeComicEpisodeUrl(url)!.episodeId,
          epId,
          reason: 'pathSegments 单次解码与 encodeComponent 精确互逆',
        );
      }
    });

    test('裸 % 畸形串不抛异常，按字面还原', () {
      expect(
        tryDecodeComicEpisodeUrl('mimao-ep:///k/c/50%off')!.episodeId,
        '50%off',
      );
      expect(tryDecodeComicEpisodeUrl('mimao-ep:///k'), isNull);
    });

    test('非 mimao-ep 串返回 null', () {
      expect(tryDecodeComicEpisodeUrl('https://site.test/read/1'), isNull);
      expect(tryDecodeComicEpisodeUrl('mimao-ep://only/two'), isNull);
      expect(tryDecodeComicEpisodeUrl(''), isNull);
    });
  });

  group('URL → key 派生', () {
    test('basename 去扩展名、清洗非法字符、空兜底', () {
      expect(
        deriveSourceKeyFromUrl('https://x.test/a/bilimanga.js'),
        'bilimanga',
      );
      expect(
        deriveSourceKeyFromUrl('https://x.test/a/bili manga.js'),
        'bili-manga',
      );
      expect(deriveSourceKeyFromUrl('https://x.test/a/源.js'), '源');
      expect(deriveSourceKeyFromUrl('https://x.test/'), 'source');
      expect(deriveSourceKeyFromUrl('https://x.test/a/no-ext'), 'no-ext');
    });
  });
}

/// save 抛错的内存仓库（落盘失败回滚测试用）。
class _SaveThrowingStore extends MemoryComicSourceStore {
  @override
  Future<void> save(source_engine.ComicSourceScript source) async =>
      throw StateError('磁盘写入失败');
}
