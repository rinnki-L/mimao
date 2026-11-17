// closure-02 §3/§4/§5：ComicModule 契约、收藏闭环、阅读接线（章节图片/
// 历史续读/空章跳过）与设置面板。
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
import 'package:mimao/comic/data/comic_models.dart' as data;
import 'package:mimao/comic/pages/comic_source_page.dart';
import 'package:mimao/comic/reader/reader_cache.dart';
import 'package:mimao/comic/reader/reader_page.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/shell/app_registry.dart';

import 'comic_integration_env.dart';
import 'reader/reader_test_env.dart' show fakeLoader;

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
  }) async {
    final adapter = await env.buildAdapter(emptyEpisodeIds: emptyEpisodeIds);
    return ComicModule(
      dataSource: adapter,
      sourceRepository: adapter,
      collect: collect ?? env.collect,
      history: env.history,
      searchHistory: env.searchHistory,
      loadChapterImages: adapter.loadImagesForChapter,
      imageCacheFactory: () async =>
          ReaderImageCache(loader: fakeLoader(), disk: MemoryByteStore()),
    );
  }

  /// 搜索 c1 并进入详情页（空关键词下适配器返回空列表，须真实触发搜索）。
  Future<void> openDetail(WidgetTester tester) async {
    await tester.pumpWidget(_app(_HostModule(module: module)));
    await tester.pumpAndSettle();
    // IndexedStack 同时构建了源管理页（含 URL 输入框），用 SearchBar 后代
    // 精确定位搜索输入框；提交按钮用唯一图标定位。
    await tester.enterText(
      find.descendant(
        of: find.byType(SearchBar),
        matching: find.byType(TextField),
      ),
      '海贼王',
    );
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
    testWidgets('点章节打开阅读器：章节/图片来自适配器映射', (tester) async {
      module = await buildModule();
      await openDetail(tester);
      expect(find.text('第一话'), findsOneWidget);

      await tester.tap(find.byKey(const Key('chapter-1')));
      await tester.pumpAndSettle();

      expect(find.byType(ComicReaderPage), findsOneWidget);
      final info = tester.widget<Text>(find.byKey(const Key('reader-info')));
      // 第 1 章（假宿主每章 3 图），第 1 页，paged 模式 1.00x。
      expect(info.data, '第一话 · 1/3 · paged · 1.00x');
    });

    testWidgets('开始阅读续读历史：initialChapter/initialPage 来自历史', (tester) async {
      // 预写历史：读到 ep-2 第 2 页（1 基）。
      await env.history.saveProgress(
        const ComicRef(id: 'c1', sourceName: 'bilimanga'),
        title: '测试漫画A',
        chapterId: 'ch-2',
        page: 2,
        pageCount: 3,
      );
      module = await buildModule();
      await openDetail(tester);

      await tester.tap(find.byKey(const Key('start-reading-button')));
      await tester.pumpAndSettle();

      expect(find.byType(ComicReaderPage), findsOneWidget);
      final info = tester.widget<Text>(find.byKey(const Key('reader-info')));
      expect(info.data, '第二话 · 2/3 · paged · 1.00x');
    });

    testWidgets('空章跳过：点空章落到最近可读章，不崩溃', (tester) async {
      module = await buildModule(emptyEpisodeIds: <String>{'ch-2'});
      await openDetail(tester);
      await tester.tap(find.byKey(const Key('chapter-2')));
      await tester.pumpAndSettle();

      expect(find.byType(ComicReaderPage), findsOneWidget);
      final info = tester.widget<Text>(find.byKey(const Key('reader-info')));
      expect(
        info.data,
        '第一话 · 1/3 · paged · 1.00x',
        reason: 'ch-2 无图被跳过，回退第一章',
      );
    });

    testWidgets('全部章节为空：SnackBar 提示，不打开阅读器', (tester) async {
      module = await buildModule(
        emptyEpisodeIds: <String>{'ch-1', 'ch-2', 'ch-3'},
      );
      await openDetail(tester);
      await tester.tap(find.byKey(const Key('chapter-1')));
      await tester.pumpAndSettle();

      expect(find.byType(ComicReaderPage), findsNothing);
      expect(find.textContaining('暂无图片'), findsOneWidget);
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
