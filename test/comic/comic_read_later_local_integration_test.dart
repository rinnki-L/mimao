// ignore_for_file: deprecated_member_use — 见 lib/comic/pages/ 文件头同款说明。

/// 稍后阅读 + 本地下载两条新能力的「端到端」接线测试。
///
/// 目标不是重复单测，而是证明二者经真实 ComicModule / ComicModulePage 与真实
/// 服务串起来可用：
/// - A 服务级：真适配器搜索→详情→下载落盘→本地清单/阅读章节；稍后阅读经
///   ComicLibraryApiImpl 落库且不写 core 投影；
/// - B 组件级：详情页加入稍后阅读→主页卡片计数与海报→稍后阅读整页；
/// - C 组件级：本地条目入口→本地管理页→本地详情（无下载按钮）→删除路径。
///
/// 全程内存 DB + 假 JS 宿主；仅种子/清理用系统临时目录。widget 测试里目录
/// 扫描/删除等真实 dart:io 用 runAsync 在真实 zone 预计算，避免 fake async 卡死。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/comic_entry.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/data/comic_models.dart' as data;
import 'package:mimao/comic/download_store.dart';
import 'package:mimao/comic/library_api_impl.dart';
import 'package:mimao/comic/local_comic_content.dart';
import 'package:mimao/comic/local_comic_manifest.dart';
import 'package:mimao/comic/local_comic_service.dart';
import 'package:mimao/comic/local_download_service.dart';
import 'package:mimao/comic/pages/comic_local_page.dart';
import 'package:mimao/comic/pages/comic_read_later_page.dart';
import 'package:mimao/comic/read_later_service.dart';
import 'package:mimao/comic/reader/reader_cache.dart';
import 'package:mimao/shell/app_registry.dart';
import 'package:path/path.dart' as p;

import 'comic_integration_env.dart';
import 'reader/reader_test_env.dart' show fakeLoader, kBadgePng;

Widget _app(Widget home) => MaterialApp(home: home);

/// 在真实 BuildContext 里调用 module.buildHome（回调需要 Navigator/SnackBar）。
class _HostModule extends StatelessWidget {
  const _HostModule({required this.module});

  final ComicModule module;

  @override
  Widget build(BuildContext context) => module.buildHome(context);
}

/// 用真实 [ComicLocalContent] 在真实 zone 预计算的详情替代读取方法。
///
/// widget 测试的 fake async 区无法完成 `Directory.list()` 流；把真实扫描放到
/// runAsync 里、结果注入本类，页面拿到的仍是真服务算出的章节数据。
class _PrecachedLocalContent extends ComicLocalContent {
  _PrecachedLocalContent(super.localService, this.cachedDetail);

  final data.ComicDetail cachedDetail;

  @override
  Future<data.ComicDetail> detail(ComicLocalEntry entry) async => cachedDetail;
}

/// 小屏 390×844：任何 render overflow 都会作为异常让测试失败。
void _usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  late ComicIntegrationEnv env;
  late ComicModule module;

  /// 本测试创建的临时目录，统一在 tearDown 删除（env.memory 无 storeDir）。
  final List<Directory> tempDirs = <Directory>[];

  Directory newTempDir(String prefix) {
    final dir = Directory.systemTemp.createTempSync(prefix);
    tempDirs.add(dir);
    return dir;
  }

  setUp(() async {
    env = ComicIntegrationEnv.memory();
    await env.seedSource();
    await resetAppModulesForTest();
  });

  tearDown(() async {
    await resetAppModulesForTest();
    await env.close();
    for (final dir in tempDirs) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
    tempDirs.clear();
  });

  /// 组装真实模块：真适配器 + 收敛后的服务 + 内存图片缓存。
  /// 本地/稍后阅读能力按需注入，未注入即走模块降级路径。
  Future<ComicModule> buildModule({
    ComicReadLaterService? readLater,
    ComicLocalService? localService,
    ComicLocalContent? localContent,
  }) async {
    final adapter = await env.buildAdapter();
    return ComicModule(
      dataSource: adapter,
      sourceRepository: adapter,
      collect: env.collect,
      history: env.history,
      searchHistory: env.searchHistory,
      loadChapterImages: adapter.loadImagesForChapter,
      localService: localService,
      localContent: localContent,
      readLater: readLater,
      imageCacheFactory: () async =>
          ReaderImageCache(loader: fakeLoader(), disk: MemoryByteStore()),
    );
  }

  /// 搜索 c1 并进入详情页（空关键词下适配器返回空列表，须真实触发搜索）。
  Future<void> openDetail(WidgetTester tester) async {
    await tester.pumpWidget(_app(_HostModule(module: module)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('comic-home-search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '海贼王');
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('search-result-c1')));
    await tester.pumpAndSettle();
  }

  /// 手工导入的旧文件夹：两章（第1话 2 页 / 第2话 1 页），无清单走扫描回退。
  Directory seedLocalFolder(String prefix) {
    final folder = newTempDir(prefix);
    final ch1 = Directory(p.join(folder.path, '第1话'))..createSync();
    File(p.join(ch1.path, '1.jpg')).writeAsBytesSync(kBadgePng);
    File(p.join(ch1.path, '2.jpg')).writeAsBytesSync(kBadgePng);
    final ch2 = Directory(p.join(folder.path, '第2话'))..createSync();
    File(p.join(ch2.path, '1.jpg')).writeAsBytesSync(kBadgePng);
    return folder;
  }

  /// 用真实服务把 legacy（payload '{}'）本地文件夹导入为漫画条目。
  Future<ComicLocalEntry> seedLegacyLocalComic(
    ComicLocalService localService,
    Directory folder,
  ) => localService.import(
    ref: ComicRef.local('seed-1'),
    title: '离线漫画',
    folderPath: folder.path,
    payload: '{}',
    pageCount: 3,
  );

  group('A 服务级端到端', () {
    test('在线章节下载：落盘页文件/清单/本地详情/阅读章节全链路可消费', () async {
      final root = newTempDir('mimao_e2e_dl_');
      final localService = ComicLocalService(env.comicDb, env.library);
      final localContent = ComicLocalContent(localService);
      final store = ComicDownloadStore(env.comicDb);
      final adapter = await env.buildAdapter();
      final downloads = ComicLocalDownloadService(
        local: localService,
        store: store,
        rootDirectory: () async => root,
        // 任意 URL 都返回非空字节；真实字节加载由 fake loader 顶替。
        loadBytes: (url) async => Uint8List.fromList(utf8.encode('bytes:$url')),
        loadChapterImages: adapter.loadImagesForChapter,
      );
      addTearDown(downloads.dispose);

      // 真适配器：搜索 → 详情（假 JS 宿主回放源 bilimanga / 漫画 c1 / 三章）。
      final results = await adapter.search('海贼王');
      final summary = results.singleWhere((item) => item.id == 'c1');
      final detail = await adapter.detail(summary);
      final chapter = detail.chapters.first;

      await downloads.downloadChapter(summary, detail, chapter);
      await downloads.whenIdle();

      // 本地条目落库一条，来源恒为 local。
      final all = await localService.all();
      expect(all, hasLength(1));
      expect(all.single.ref.sourceName, ComicRef.localSource);
      expect(all.single.title, '测试漫画A');

      // 页文件落在 <root>/<folderId>/001-第一话/0001..0003.jpg。
      final folderId = localComicFolderId(
        ComicRef(id: summary.id, sourceName: summary.sourceName!),
      );
      final chapterDir = Directory(p.join(root.path, folderId, '001-第一话'));
      expect(chapterDir.existsSync(), isTrue);
      for (var i = 1; i <= 3; i++) {
        final name = '${i.toString().padLeft(4, '0')}.jpg';
        expect(File(p.join(chapterDir.path, name)).existsSync(), isTrue);
      }

      // 清单解析：1 章、3 页；封面 URL 是 http 且假 loader 有字节，
      // cover.jpg 可能存在，但只断言页文件这一刚性约束。
      final manifest = LocalComicManifest.tryParse(all.single.payload);
      expect(manifest, isNotNull);
      expect(manifest!.chapters, hasLength(1));
      expect(manifest.chapters.single.pages, 3);

      // 本地详情与阅读章节都从清单/落盘目录装配。
      final localDetail = await localContent.detail(all.single);
      expect(localDetail.chapters, hasLength(1));
      final readerChapters = await localContent.readerChapters(all.single);
      expect(readerChapters, hasLength(1));
      expect(readerChapters.single.imageUrls, hasLength(3));
      expect(
        readerChapters.single.imageUrls.every(
          (url) => url.startsWith('file://'),
        ),
        isTrue,
      );
      expect(
        readerChapters.single.imageUrls
            .map((url) => p.basename(Uri.parse(url).path))
            .toList(),
        <String>['0001.jpg', '0002.jpg', '0003.jpg'],
      );
    });

    test('稍后阅读经 ComicLibraryApiImpl 落库：可读写，但不写 core 投影', () async {
      final readLater = ComicReadLaterService(env.comicDb);
      final api = ComicLibraryApiImpl(
        collect: env.collect,
        history: env.history,
        readLaterService: readLater,
      );
      const online = data.ComicSummary(
        id: 'c1',
        title: '测试漫画A',
        coverUrl: 'https://img.test/c1.jpg',
        detailUrl: '',
        sourceName: 'bilimanga',
      );

      await api.setReadLater(
        id: online.id,
        sourceName: online.sourceName!,
        title: online.title,
        coverUrl: online.coverUrl,
        included: true,
      );

      final saved = await api.readLater();
      expect(saved, hasLength(1));
      expect(saved.single.id, 'c1');
      expect(saved.single.title, '测试漫画A');
      expect(await api.isReadLater('c1', 'bilimanga'), isTrue);

      // 稍后阅读是模块内部表，不投影书架：时间线与 media_entries 均无该 ref。
      expect(await env.library.timeline(), isEmpty);
      final rows = await env.appDb.select(env.appDb.mediaEntries).get();
      expect(rows, isEmpty);
      expect(
        rows.where((r) => r.id == 'c1' && r.sourceName == 'bilimanga'),
        isEmpty,
      );

      await api.setReadLater(
        id: online.id,
        sourceName: online.sourceName!,
        title: online.title,
        included: false,
      );
      expect(await api.isReadLater('c1', 'bilimanga'), isFalse);
      expect(await api.readLater(), isEmpty);
    });

    test('本地 legacy 扫描与删除：真实服务在普通 test 里读到两章并清库清盘', () async {
      final folder = seedLocalFolder('mimao_e2e_scan_');
      final localService = ComicLocalService(env.comicDb, env.library);
      final localContent = ComicLocalContent(localService);
      await seedLegacyLocalComic(localService, folder);

      final entry = (await localService.find(ComicRef.local('seed-1')))!;
      final detail = await localContent.detail(entry);
      expect(detail.chapters.map((c) => c.title), <String>['第1话', '第2话']);
      final readerChapters = await localContent.readerChapters(entry);
      expect(readerChapters.map((c) => c.title), <String>['第1话', '第2话']);
      expect(readerChapters[0].imageUrls, hasLength(2));
      expect(readerChapters[1].imageUrls, hasLength(1));

      await localContent.remove(ComicRef.local('seed-1'));
      expect(await localService.find(ComicRef.local('seed-1')), isNull);
      expect(folder.existsSync(), isFalse);
    });
  });

  group('B 组件级：稍后阅读经模块持久化', () {
    testWidgets('详情页加入 → 主页卡片 1 部/海报 → 稍后阅读整页', (tester) async {
      _usePhoneSize(tester);
      // 本地能力按目标要求一并接真实服务（本用例不产生本地条目）。
      final localService = ComicLocalService(env.comicDb, env.library);
      final localContent = ComicLocalContent(localService);
      final readLater = ComicReadLaterService(env.comicDb);
      module = await buildModule(
        readLater: readLater,
        localService: localService,
        localContent: localContent,
      );
      await openDetail(tester);

      // 详情页的稍后阅读按钮：点击后文案切为「已加入」，并真落内部库。
      expect(find.byKey(const Key('read-later-button')), findsOneWidget);
      expect(find.text('稍后阅读'), findsOneWidget);
      await tester.tap(find.byKey(const Key('read-later-button')));
      await tester.pumpAndSettle();
      expect(find.text('已加入'), findsOneWidget);
      expect(
        await readLater.contains(
          const ComicRef(id: 'c1', sourceName: 'bilimanga'),
        ),
        isTrue,
      );

      // 详情页 → 搜索页 → 主页（点各自的返回按钮两次）。
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // 主页稍后阅读卡片：计数与海报来自真实服务。
      expect(
        find.byKey(const Key('comic-home-read-later-card')),
        findsOneWidget,
      );
      expect(find.text('1 部'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('home-read-later-c1')),
        findsOneWidget,
      );

      // 点头（卡片 header）→ 稍后阅读整页，海报仍在。
      await tester.tap(find.byKey(const Key('comic-home-read-later-card-tap')));
      await tester.pumpAndSettle();
      expect(find.byType(ComicReadLaterPage), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('read-later-c1')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('C 组件级：本地入口 → 本地详情', () {
    testWidgets('主页本地卡片 → 管理页行 → 本地详情（无下载按钮）→ 删除确认', (tester) async {
      _usePhoneSize(tester);
      final folder = seedLocalFolder('mimao_e2e_local_');
      final localService = ComicLocalService(env.comicDb, env.library);
      final realContent = ComicLocalContent(localService);
      await seedLegacyLocalComic(localService, folder);

      // 真实扫描放到 runAsync 的真实 zone 完成，拿到的仍是真服务的章节数据。
      final seedEntry = (await localService.find(ComicRef.local('seed-1')))!;
      final realDetail = await tester.runAsync<data.ComicDetail>(
        () => realContent.detail(seedEntry),
      );
      expect(realDetail!.chapters.map((c) => c.title), <String>['第1话', '第2话']);
      final localContent = _PrecachedLocalContent(localService, realDetail);
      module = await buildModule(
        localService: localService,
        localContent: localContent,
      );

      await tester.pumpWidget(_app(_HostModule(module: module)));
      await tester.pumpAndSettle();

      // 主页本地卡片：计数来自真实 localService。
      expect(find.byKey(const Key('comic-home-local-card')), findsOneWidget);
      expect(find.text('已保存 1 部 · 点击管理'), findsOneWidget);

      // 点卡片 → 本地漫画管理页 → 行 key 由条目 id 决定。
      await tester.tap(find.byKey(const Key('comic-home-local-card-tap')));
      await tester.pumpAndSettle();
      expect(find.byType(ComicLocalPage), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('local-entry-seed-1')),
        findsOneWidget,
      );

      // 点行 → 本地详情：章节来自真实目录扫描（无清单回退）的预计算结果。
      await tester.tap(
        find.byKey(const ValueKey<String>('local-entry-seed-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('离线漫画'), findsOneWidget);
      expect(find.text('第1话'), findsOneWidget);
      expect(find.text('第2话'), findsOneWidget);
      // 本地漫画无在线下载入口；收藏/稍后阅读仍可用。
      expect(find.byKey(const Key('download-chapter-1')), findsNothing);
      expect(find.byKey(const Key('download-all-button')), findsNothing);
      expect(find.byKey(const Key('favorite-button')), findsOneWidget);
      expect(find.byKey(const Key('read-later-button')), findsOneWidget);

      // 不点「开始阅读」（本地真文件 I/O 在 fake async 里易抖动）。
      // 返回管理页，验证删除确认框与真正落库的删除路径。
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(ComicLocalPage), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('local-delete-seed-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('删除本地漫画？'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      // 删除走真实 localContent.remove（含目录删除），用 runAsync 放行真实 I/O。
      await tester.runAsync(() => realContent.remove(ComicRef.local('seed-1')));
      await tester.pumpAndSettle();

      expect(await localService.find(ComicRef.local('seed-1')), isNull);
      expect(folder.existsSync(), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
