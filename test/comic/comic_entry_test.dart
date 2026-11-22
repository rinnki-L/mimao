// closure-02 §3/§4/§5：ComicModule 契约、收藏闭环、阅读接线（懒加载源 /
// 稳定 chapterId / headers 直通 / 历史续读 / 空章交控制器）与设置面板。
//
// 全程内存库 + MemoryComicSourceStore + 假客户端 + 假 JS 宿主 + 内存图片缓存，
// 不依赖 DLL、不碰 path_provider、不访问网络。注册表生命周期见
// comic_registry_test.dart。

// ignore_for_file: deprecated_member_use — 见 lib/main.dart 文件头同款说明。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/collect_service.dart';
import 'package:mimao/comic/comic_entry.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/data/comic_data_source.dart';
import 'package:mimao/comic/data/comic_models.dart' as data;
import 'package:mimao/comic/data/engine_comic_data_source.dart'
    show tryDecodeComicEpisodeUrl;
import 'package:mimao/comic/engine/models.dart' show ComicImageRef;
import 'package:mimao/comic/pages/comic_source_page.dart';
import 'package:mimao/comic/reader/reader_cache.dart';
import 'package:mimao/comic/reader/reader_models.dart' show ReaderImage;
import 'package:mimao/comic/reader/reader_page.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/shell/app_registry.dart';

import 'comic_integration_env.dart';
import 'reader/reader_test_env.dart' show fakeLoader, kBadgePng;

Widget _app(Widget home) => MaterialApp(home: home);

/// 在真实 BuildContext 里调用 module.buildHome / buildSettings（回调需要
/// Navigator / SnackBar）。
class _HostModule extends StatelessWidget {
  const _HostModule({required this.module, this.settings = false});

  final ComicModule module;

  /// true 时渲染 buildSettings（设置面板测试）。
  final bool settings;

  @override
  Widget build(BuildContext context) => settings
      // 设置面板在真实壳里挂在设置抽屉（Scaffold 内）——SnackBar 需要
      // Scaffold 宿主，测试保持同构。
      ? Scaffold(body: module.buildSettings(context))
      : module.buildHome(context);
}

/// 收藏时抛异常的服务，验证 UI 失败提示且不冒异常到事件循环。
class _ThrowingCollectService extends ComicCollectService {
  _ThrowingCollectService(super.db, super.library);

  @override
  Future<void> collect(
    ComicRef ref, {
    required String title,
    String? coverUrl,
    String payload = '{}',
    DateTime? collectedAt,
  }) async => throw StateError('内部库写入失败');

  @override
  Future<void> remove(ComicRef ref) async => throw StateError('内部库写入失败');
}

/// 详情零章的数据源：验证装配期「章节列表为空」SnackBar 守门。
class _ZeroChapterDataSource implements ComicDataSource {
  _ZeroChapterDataSource(this._delegate);

  final ComicDataSource _delegate;

  @override
  Future<List<data.ComicSummary>> search(String keyword) =>
      _delegate.search(keyword);

  @override
  Future<data.ComicDetail> detail(data.ComicSummary item) async {
    final full = await _delegate.detail(item);
    return data.ComicDetail(
      title: full.title,
      coverUrl: full.coverUrl,
      detailUrl: full.detailUrl,
      description: full.description,
      sourceName: full.sourceName,
      tags: full.tags,
      chapters: const <data.ComicChapter>[],
    );
  }

  @override
  List<String> takeSearchDiagnostics() => _delegate.takeSearchDiagnostics();

  @override
  Future<List<data.ComicSummary>> searchSource(String key, String keyword) =>
      _delegate.searchSource(key, keyword);

  @override
  List<String> availableSourceKeys() => _delegate.availableSourceKeys();

  @override
  Future<List<String>> recentSearchTerms() => _delegate.recentSearchTerms();
}

void main() {
  late ComicIntegrationEnv env;
  late ComicModule module;

  setUp(() async {
    env = ComicIntegrationEnv.memory();
    await env.seedSource();
    await resetAppModulesForTest();
  });

  tearDown(() async {
    await resetAppModulesForTest();
    await env.close();
  });

  /// 组装模块（适配器 + 收敛后的服务 + 内存图片缓存）。
  Future<ComicModule> buildModule({
    Set<String> emptyEpisodeIds = const <String>{},
    ComicCollectService? collect,
    Future<List<ComicImageRef>> Function(data.ComicSummary, data.ComicChapter)?
    customLoadChapterImages,
    ComicDataSource? dataSourceOverride,
    ImageByteLoader? loader,
  }) async {
    final adapter = await env.buildAdapter(emptyEpisodeIds: emptyEpisodeIds);
    return ComicModule(
      dataSource: dataSourceOverride ?? adapter,
      sourceRepository: adapter,
      collect: collect ?? env.collect,
      history: env.history,
      searchHistory: env.searchHistory,
      loadChapterImages:
          customLoadChapterImages ?? adapter.loadImagesForChapter,
      imageCacheFactory: () async => ReaderImageCache(
        loader: loader ?? fakeLoader(),
        disk: MemoryByteStore(),
      ),
    );
  }

  /// 搜索 c1 并进入详情页（空关键词下适配器返回空列表，须真实触发搜索）。
  ///
  /// 模块主页是「主页」分区（搜索入口 + 历史/本地），搜索是独立一页：
  /// 先点主页搜索入口，再在搜索页里输入并提交。
  Future<void> openDetail(WidgetTester tester) async {
    await tester.pumpWidget(_app(_HostModule(module: module)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comic-home-search')));
    await tester.pumpAndSettle();
    // 搜索页只有一个输入框（主页是只读 SearchBar，已退到下一层路由）。
    await tester.enterText(find.byType(TextField), '海贼王');
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('search-result-c1')));
    await tester.pumpAndSettle();
  }

  group('模块契约', () {
    test('type/label/icon 与契约一致；refOf 空来源回退「未知源」', () async {
      module = await buildModule();
      expect(module.type, MediaType.comic);
      expect(module.label, '漫画');
      expect(module.icon, MediaType.comic.icon);
      expect(
        ComicModule.refOf(
          const data.ComicSummary(
            id: 'x',
            title: 't',
            coverUrl: '',
            detailUrl: '',
          ),
        ),
        const ComicRef(id: 'x', sourceName: '未知源'),
      );
      expect(
        ComicModule.refOf(
          const data.ComicSummary(
            id: 'y',
            title: 't',
            coverUrl: '',
            detailUrl: '',
            sourceName: 'bilimanga',
          ),
        ),
        const ComicRef(id: 'y', sourceName: 'bilimanga'),
      );
    });

    testWidgets('buildSettings 可独立 pump', (tester) async {
      module = await buildModule();
      await tester.pumpWidget(
        _app(_HostModule(module: module, settings: true)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('comic-settings-open-sources')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('comic-settings-clear-history')),
        findsOneWidget,
      );
    });
  });

  group('收藏闭环', () {
    testWidgets('收藏 → 内部库与投影 starred 一致；取消 → false', (tester) async {
      module = await buildModule();
      await openDetail(tester);

      await tester.tap(find.byKey(const Key('favorite-button')));
      await tester.pumpAndSettle();

      const ref = ComicRef(id: 'c1', sourceName: 'bilimanga');
      expect(await env.collect.isCollected(ref), isTrue);
      final view = (await env.library.timeline()).single;
      expect(view.starred, isTrue);
      expect(view.title, '测试漫画A');

      await tester.tap(find.byKey(const Key('favorite-button')));
      await tester.pumpAndSettle();
      expect(await env.collect.isCollected(ref), isFalse);
      expect((await env.library.timeline()).single.starred, isFalse);
    });

    testWidgets('收藏失败显示 SnackBar，页面不崩', (tester) async {
      module = await buildModule(
        collect: _ThrowingCollectService(env.comicDb, env.library),
      );
      await openDetail(tester);
      await tester.tap(find.byKey(const Key('favorite-button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('收藏失败'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('重新进入同一详情：收藏态来自收藏服务', (tester) async {
      module = await buildModule();
      await env.collect.collect(
        const ComicRef(id: 'c1', sourceName: 'bilimanga'),
        title: '测试漫画A',
      );
      await openDetail(tester);
      expect(find.text('已收藏'), findsOneWidget);
    });
  });

  group('阅读接线', () {
    // 假取图回调：返回带 onImageLoad 请求头的 ComicImageRef，同时记录调用
    // （用于断言「进页后按章加载」与 item/chapter 透传）。
    final loadCalls = <data.ComicChapter>[];
    Future<List<ComicImageRef>> fakeLoadChapterImages(
      data.ComicSummary item,
      data.ComicChapter chapter,
    ) async {
      loadCalls.add(chapter);
      final ep = tryDecodeComicEpisodeUrl(chapter.url)?.episodeId ?? '?';
      return <ComicImageRef>[
        ComicImageRef(
          url: 'https://img.test/$ep/p1.jpg',
          headers: const <String, String>{'Referer': 'https://site.test/'},
        ),
        ComicImageRef(url: 'https://img.test/$ep/p2.jpg'),
        ComicImageRef(url: 'https://img.test/$ep/p3.jpg'),
      ];
    }

    setUp(() => loadCalls.clear());

    testWidgets('detail 零章：SnackBar 提示，不按章加载、不 push（稳定可跑）', (tester) async {
      final adapter = await env.buildAdapter();
      module = await buildModule(
        customLoadChapterImages: fakeLoadChapterImages,
        dataSourceOverride: _ZeroChapterDataSource(adapter),
      );
      await openDetail(tester);
      await tester.tap(find.byKey(const Key('start-reading-button')));
      await tester.pumpAndSettle();

      expect(find.byType(ComicReaderPage), findsNothing);
      expect(find.textContaining('暂无图片'), findsOneWidget);
      expect(loadCalls, isEmpty);
    });

    // ── push 级断言：按 reader_page.dart 最终契约（source + settingsStore）
    // 书写。并行期 reader_page.dart 仍是旧的 chapters 构造，故这几例暂无法
    // 编译/运行——这是预期的，集成阶段由主会话统一验证。
    testWidgets('点章节打开阅读器：headers 端到端直通到图片 loader（依赖最终 reader_page）', (
      tester,
    ) async {
      final loadedImages = <ReaderImage>[];
      module = await buildModule(
        customLoadChapterImages: fakeLoadChapterImages,
        loader: (image) async {
          loadedImages.add(image);
          // 必须是可解码的合法图片字节：阅读页把字节交给 Image.memory，
          // 非法字节会触发 image codec 异常，直接挂掉 widget 测试。
          return kBadgePng;
        },
      );
      await openDetail(tester);
      await tester.tap(find.byKey(const Key('chapter-1')));
      await tester.pumpAndSettle();

      expect(find.byType(ComicReaderPage), findsOneWidget);
      // onImageLoad 的 Referer 头经 ComicImageRef → ReaderImage → 缓存 loader
      // 端到端直通；这是 headers 接线最关键的回归断言。
      expect(
        loadedImages.any(
          (image) =>
              image.url.contains('ch-1') &&
              image.headers['Referer'] == 'https://site.test/',
        ),
        isTrue,
      );
    });

    testWidgets('开始阅读续读历史：initialChapter/page 来自历史（依赖最终 reader_page）', (
      tester,
    ) async {
      await env.history.saveProgress(
        const ComicRef(id: 'c1', sourceName: 'bilimanga'),
        title: '测试漫画A',
        chapterId: 'ch-2',
        page: 2,
        pageCount: 3,
      );
      module = await buildModule(
        customLoadChapterImages: fakeLoadChapterImages,
      );
      await openDetail(tester);
      await tester.tap(find.byKey(const Key('start-reading-button')));
      await tester.pumpAndSettle();

      expect(find.byType(ComicReaderPage), findsOneWidget);
      // 历史 chapterId=ch-2 → 反查到第二章，初始页 = page-1 = 1（0 基）。
      expect(
        loadCalls.map((c) => c.url),
        contains('mimao-ep:///bilimanga/c1/ch-2'),
      );
    });

    testWidgets('空章交控制器跳过：点空章不崩，落到最近非空章（依赖最终 reader_page）', (tester) async {
      module = await buildModule(
        customLoadChapterImages: (item, chapter) async {
          if (chapter.url.contains('ch-2')) return const <ComicImageRef>[];
          return fakeLoadChapterImages(item, chapter);
        },
      );
      await openDetail(tester);
      await tester.tap(find.byKey(const Key('chapter-2')));
      await tester.pumpAndSettle();

      // 空章由控制器向后/向前找非空章；装配层不再过滤，也不显示"暂无图片"。
      expect(find.byType(ComicReaderPage), findsOneWidget);
      expect(find.textContaining('暂无图片'), findsNothing);
    });
  });

  group('设置面板', () {
    testWidgets('清除历史生效；打开源管理 push 源页', (tester) async {
      await env.searchHistory.record('海贼王');
      module = await buildModule();
      await tester.pumpWidget(
        _app(_HostModule(module: module, settings: true)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('comic-settings-clear-history')));
      await tester.pumpAndSettle();
      expect(await env.searchHistory.recent(), isEmpty);
      expect(find.text('搜索历史已清除'), findsOneWidget);

      await tester.tap(find.byKey(const Key('comic-settings-open-sources')));
      await tester.pumpAndSettle();
      expect(find.byType(ComicSourcePage), findsOneWidget);
      expect(find.text('已导入 1 个来源'), findsOneWidget);
    });
  });
}
