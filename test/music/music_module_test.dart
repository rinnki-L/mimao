// ignore_for_file: deprecated_member_use — 与壳层测试同款说明。
/// 音乐模块测试：模块注册（整模块注入）、主页搜索流、错误态、设置分组。
/// 全部走 fake MusicApi，无真实 I/O（FakeAsync 兼容）。
///
/// registry 测试必须同时注入番剧/漫画的内存分件——initAppModules 会跑全部
/// 模块的生产装配，不注入的话 drift 懒连接在无插件环境会永久挂起
/// （comic_registry_test.dart 头注记录过同款坑）。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/anime_db.dart';
import 'package:mimao/comic/comic_db.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_entry.dart';
import 'package:mimao/music/music_store.dart';
import 'package:mimao/music/pages/music_module_page.dart';
import 'package:mimao/music/pages/music_module_settings.dart';
import 'package:mimao/shell/app_registry.dart';

import '../anime/anime_integration_env.dart' show MemoryRuleStore;
import '../comic/comic_integration_env.dart'
    show FakeComicHttpClient, FakeSourceHost, MemoryComicSourceStore;

class _FakeApi implements MusicApi {
  _FakeApi({this.error});

  final Object? error;

  @override
  Future<MusicPage<MusicSong>> searchSongs({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async {
    final e = error;
    if (e != null) throw e;
    if (keyword == '空') {
      return const MusicPage<MusicSong>(items: <MusicSong>[]);
    }
    return MusicPage<MusicSong>(
      page: 1,
      total: 1,
      items: <MusicSong>[
        MusicSong(
          id: '1',
          hash: 'h1',
          title: '$keyword 之一',
          artists: const <MusicArtistRef>[MusicArtistRef(name: '歌手A')],
          albumId: '9',
          albumTitle: '专辑',
          coverUrl: '',
          durationMs: 213000,
        ),
      ],
    );
  }

  @override
  Future<KugouIdentity> ensureDevice() async => KugouIdentity.anonymous();

  @override
  Future<KugouIdentity?> currentIdentity() async =>
      KugouIdentity.anonymous().withDfid('dfid1234567890');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await resetAppModulesForTest();
  });

  tearDown(() async {
    await resetAppModulesForTest();
  });

  test('整模块注入后注册成功（type/label/icon 正确）', () async {
    final appDb = AppDb.forTesting(NativeDatabase.memory());
    final animeDb = AnimeDb.forTesting(NativeDatabase.memory());
    final comicDb = ComicDb.forTesting(NativeDatabase.memory());
    final module = MusicModule(api: _FakeApi());
    await initAppModules(
      library: LibraryRepository(appDb),
      animeDb: animeDb,
      ruleStore: MemoryRuleStore(),
      comicDb: comicDb,
      comicSourceStore: MemoryComicSourceStore(),
      comicHttpClient: FakeComicHttpClient(),
      comicHostFactory: () => FakeSourceHost(),
      musicModule: module,
    );

    final registered = moduleFor(MediaType.music);
    expect(registered, same(module));
    expect(registered!.type, MediaType.music);
    expect(registered.label, '音乐');
    expect(registered.icon, MediaType.music.icon);
    expect(appModulesError, isNull);
    await appDb.close();
    await animeDb.close();
    await comicDb.close();
  });

  testWidgets('注册后的模块出口真的能渲染：buildHome 进搜索主页、buildSettings 进设置分组', (
    tester,
  ) async {
    final appDb = AppDb.forTesting(NativeDatabase.memory());
    final animeDb = AnimeDb.forTesting(NativeDatabase.memory());
    final comicDb = ComicDb.forTesting(NativeDatabase.memory());
    final module = MusicModule(api: _FakeApi());
    await initAppModules(
      library: LibraryRepository(appDb),
      animeDb: animeDb,
      ruleStore: MemoryRuleStore(),
      comicDb: comicDb,
      comicSourceStore: MemoryComicSourceStore(),
      comicHttpClient: FakeComicHttpClient(),
      comicHostFactory: () => FakeSourceHost(),
      musicModule: module,
    );
    addTearDown(appDb.close);
    addTearDown(animeDb.close);
    addTearDown(comicDb.close);

    late Widget home;
    late Widget settings;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            home = moduleFor(MediaType.music)!.buildHome(context);
            settings = moduleFor(MediaType.music)!.buildSettings(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(home, isA<MusicModulePage>());
    expect(settings, isA<MusicModuleSettings>());

    // buildHome 的出口直接进壳层的模块层也能跑：搜索交互可用。
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.enterText(find.byType(TextField), '出口');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('出口 之一'), findsOneWidget);
  });

  testWidgets('主页：输入关键词搜索 → 结果渲染（歌名/歌手/时长）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MusicModulePage(store: MusicStore(_FakeApi()), embedded: true),
      ),
    );
    expect(find.text('输入关键词开始搜索'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '周杰伦');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    expect(find.text('周杰伦 之一'), findsOneWidget);
    expect(find.text('歌手A · 专辑'), findsOneWidget);
    expect(find.text('3:33'), findsOneWidget);
    // wire 高亮标签在展示层剥除（模型层保持原样）。
    expect(find.textContaining('<em>'), findsNothing);
  });

  testWidgets('回车提交与按钮提交等价', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MusicModulePage(store: MusicStore(_FakeApi()), embedded: true),
      ),
    );
    await tester.enterText(find.byType(TextField), '回车搜索');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('回车搜索 之一'), findsOneWidget);
  });

  testWidgets('空结果 → 空态文案', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MusicModulePage(store: MusicStore(_FakeApi()), embedded: true),
      ),
    );
    await tester.enterText(find.byType(TextField), '空');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('没有找到相关歌曲'), findsOneWidget);
  });

  testWidgets('搜索失败 → 错误态 + 重试按钮可点', (tester) async {
    final store = MusicStore(_FakeApi(error: StateError('网络超时')));
    await tester.pumpWidget(
      MaterialApp(home: MusicModulePage(store: store, embedded: true)),
    );
    await tester.enterText(find.byType(TextField), 'k');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    expect(find.textContaining('搜索失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('未 embedded 时自带 AppBar 标题', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: MusicModulePage(store: MusicStore(_FakeApi()))),
    );
    expect(find.text('音乐'), findsOneWidget);
  });

  testWidgets('设置分组：身份卡与登录占位渲染（无网络调用）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: <Widget>[MusicModuleSettings(api: _FakeApi())],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('设备身份'), findsOneWidget);
    expect(find.text('匿名设备'), findsOneWidget);
    expect(find.text('酷狗账号登录（二维码）'), findsOneWidget);
    expect(
      find.textContaining('dfid1234'),
      findsOneWidget,
      reason: 'DFID 脱敏展示前 8 位',
    );
  });
}
