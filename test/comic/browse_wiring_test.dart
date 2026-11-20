// 适配层「发现 / 分类」接线测试：EngineComicDataSource 实现 ComicBrowseSource，
// 逐源容错、诊断上达、字段映射（sourceName = 注册 key）。
//
// 全程内存 store + 假 JS 宿主，不依赖 DLL/网络。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/engine_comic_data_source.dart';
import 'package:mimao/comic/engine/engine.dart';

import 'comic_integration_env.dart';

void main() {
  late ComicIntegrationEnv env;
  late EngineComicDataSource adapter;

  setUp(() async {
    env = ComicIntegrationEnv.memory();
    await env.seedSource();
    adapter = await env.buildAdapter();
  });

  tearDown(() async {
    await env.close();
  });

  test('适配器同时实现 ComicBrowseSource（生产路径自动接线）', () {
    expect(adapter, isA<ComicBrowseSource>());
  });

  test('browseSources 只返回已启用源，name 空时回退 key', () async {
    final sources = await adapter.browseSources();

    expect(sources, isNotEmpty);
    for (final source in sources) {
      expect(source.key, isNotEmpty);
      expect(source.name, isNotEmpty);
    }
  });

  test('exploreGroups 把分区映射成带 sourceName 的 ComicBrowseGroup', () async {
    final groups = await adapter.exploreGroups('bilimanga');

    expect(groups, hasLength(1));
    final group = groups.single;
    expect(group.title, '热门');
    expect(group.exploreIndex, 0);
    expect(group.page, 1);
    expect(group.comics.single.title, '探索漫画');
    // 决策④：sourceName 承载注册 key，详情/图片加载据此反查源。
    expect(group.comics.single.sourceName, 'bilimanga');
    expect(group.comics.single.id, 'ex-1');
  });

  test('exploreSection 取单分区并保留 maxPage', () async {
    final group = await adapter.exploreSection('bilimanga', 0);

    expect(group.exploreIndex, 0);
    expect(group.comics.single.id, 'ex-1');
  });

  test('categoryTree 解析分组与平行 categoryParams', () async {
    final tree = await adapter.categoryTree('bilimanga');

    expect(tree, isNotNull);
    expect(tree!.title, '测试分类');
    final group = tree.groups.single;
    expect(group.name, '题材');
    expect(group.nodes.map((n) => n.name), <String>['科幻', '武侠']);
    expect(group.nodes.map((n) => n.param), <String>['scifi', 'wuxia']);
  });

  test('categoryComics 返回带 sourceName 的结果与 maxPage', () async {
    final group = await adapter.categoryComics(
      'bilimanga',
      const ComicCategoryNode(name: '科幻', param: 'scifi'),
    );

    expect(group.title, '科幻');
    expect(group.comics.single.title, '分类漫画');
    expect(group.comics.single.sourceName, 'bilimanga');
    expect(group.maxPage, 2);
    expect(group.hasMore, isTrue);
  });

  test('源未注册时浏览不抛异常，只回空并记诊断', () async {
    final groups = await adapter.exploreGroups('no-such-source');

    expect(groups, isEmpty);
    // 诊断经 takeSearchDiagnostics 取走（发现/分类页与搜索页共用出口）。
    expect(adapter.takeSearchDiagnostics(), isNotEmpty);
  });

  test('分类树缺失（源无 category）返回 null，UI 可回退 explore', () async {
    // 用只回 null 的宿主单独搭一个适配器：模拟没有 category / explore 的源。
    final pool = SourceExecutionPool(hostFactory: () => _NullHost());
    final bare = await EngineComicDataSource.create(
      store: env.sourceStore,
      engine: ComicSourceEngine(pool: pool),
      client: env.client,
    );
    addTearDown(pool.disposeAll);

    expect(await bare.categoryTree('bilimanga'), isNull);
    expect(await bare.exploreGroups('bilimanga'), isEmpty);
  });
}

/// 只回 null 的宿主：源脚本什么方法都没提供（最坏情况的源）。
class _NullHost implements JsHost {
  @override
  Future<void> loadScript(String script) async {}

  @override
  Future<Object?> evaluate(String expression) async => null;

  @override
  void close() {}
}
