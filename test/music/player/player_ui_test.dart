// ignore_for_file: deprecated_member_use — 与模块页面测试同款说明。
/// 播放 UI 测试：入口点歌进播放页、播放/暂停、拖动 seek、错误重试、mini player。
///
/// 全部走 fake engine + fake playbackApi，不初始化 media_kit、不联网。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_store.dart';
import 'package:mimao/music/pages/music_module_page.dart';
import 'package:mimao/music/player/pages/music_mini_player.dart';
import 'package:mimao/music/player/pages/music_player_page.dart';
import 'package:mimao/music/player/play_mode.dart';
import 'package:mimao/music/player/playback_engine.dart';
import 'package:mimao/music/player/player_store.dart';
import 'package:mimao/music/player/player_ui_impl.dart';

import 'player_fakes.dart';

class _FakeMusicApi implements MusicApi {
  @override
  Future<MusicPage<MusicSong>> searchSongs({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async =>
      MusicPage<MusicSong>(page: 1, items: <MusicSong>[fakeSong(title: '稻香')]);

  @override
  Future<KugouIdentity> ensureDevice() async => KugouIdentity.anonymous();

  @override
  Future<KugouIdentity?> currentIdentity() async => null;
}

void main() {
  late FakeMusicEngine engine;
  late FakePlaybackApi playback;
  late MusicPlayerUiImpl playerUi;
  late MusicStore store;

  setUp(() {
    engine = FakeMusicEngine();
    playback = FakePlaybackApi();
    playerUi = MusicPlayerUiImpl(
      MusicPlayerStore(playbackApi: playback, engineFactory: () => engine),
    );
    store = MusicStore(_FakeMusicApi());
  });

  tearDown(() => playerUi.dispose());

  Future<void> pumpModule(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MusicModulePage(store: store, embedded: true, playerUi: playerUi),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> searchAndOpen(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), '稻香');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '稻香'));
    // 歌曲行改成 onTap + onDoubleTap 共存：单击要等双击判定窗口（约
    // 300ms）过期才触发，pumpAndSettle 只推进动画帧、不推进这个 Timer。
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  testWidgets('点列表项进入播放页并显示歌名/歌手', (tester) async {
    await pumpModule(tester);
    await searchAndOpen(tester);

    expect(find.byType(MusicPlayerPage), findsOneWidget);
    expect(find.text('正在播放'), findsOneWidget);
    expect(find.text('稻香'), findsWidgets);
    expect(find.text('周杰伦'), findsWidgets);
    expect(playerUi.store.currentSong!.id, '7301');
    expect(engine.openedUrl, 'https://cdn.example/7301.mp3');
    expect(engine.playCalls, 1);
  });

  testWidgets('播放/暂停按钮切换图标并调用引擎', (tester) async {
    await pumpModule(tester);
    await searchAndOpen(tester);

    final page = find.byType(MusicPlayerPage);
    final playButton = find.descendant(
      of: page,
      matching: find.byTooltip('播放'),
    );
    expect(playButton, findsOneWidget);

    await tester.tap(playButton);
    await tester.pump();
    expect(
      find.descendant(of: page, matching: find.byTooltip('暂停')),
      findsOneWidget,
    );
    expect(engine.playCalls, 2, reason: 'playSong 一次 + toggle 一次');

    await tester.tap(find.descendant(of: page, matching: find.byTooltip('暂停')));
    await tester.pump();
    expect(
      find.descendant(of: page, matching: find.byTooltip('播放')),
      findsOneWidget,
    );
    expect(engine.pauseCalls, 1);
  });

  testWidgets('拖动进度条调用 seek', (tester) async {
    await pumpModule(tester);
    await searchAndOpen(tester);

    engine.emit(
      const MusicPlaybackSnapshot(
        position: Duration.zero,
        duration: Duration(seconds: 200),
        playing: true,
      ),
    );
    // MobX 反应在事件投递后调度下一帧：pumpAndSettle 才看到 slider 变为可用。
    await tester.pumpAndSettle();

    final slider = find.descendant(
      of: find.byType(MusicPlayerPage),
      matching: find.byType(Slider),
    );
    final rect = tester.getRect(slider);
    // 点轨道 75% 处：Slider 会走 onChangeStart → onChange → onChangeEnd。
    await tester.tapAt(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.pumpAndSettle();

    expect(engine.seeks, isNotEmpty);
  });

  testWidgets('解析失败显示错误态与重试；重试走同一链路', (tester) async {
    playback.failure = const KugouApiException('authentication', '过期');
    await pumpModule(tester);
    await searchAndOpen(tester);

    expect(find.text('请先登录酷狗账号后播放'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    playback.failure = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('请先登录酷狗账号后播放'), findsNothing);
    expect(playback.resolvedSongs.single.id, '7301');
    expect(engine.playCalls, 1);
  });

  testWidgets('队列为空无 mini player；点歌后出现且可点回播放页', (tester) async {
    await pumpModule(tester);
    expect(find.byType(MusicMiniPlayer), findsNothing);

    await searchAndOpen(tester);
    expect(find.byType(MusicMiniPlayer), findsNothing, reason: '播放页在上层');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(MusicMiniPlayer), findsOneWidget);

    // 点标题（非按钮区域）进播放页：改造后迷你条中心是播放按钮，
    // 不能再点整卡的几何中心。
    await tester.tap(
      find.descendant(
        of: find.byType(MusicMiniPlayer),
        matching: find.text('稻香'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MusicPlayerPage), findsOneWidget);
  });

  group('迷你条传输控件 / 模式卡片 / 队列抽屉', () {
    const secondHash = 'bbcdef0123456789abcdef0123456789';

    /// 两首歌：[fakeSong] 在 index 0，晴天在 index 1。
    Future<MusicPlayerStore> seedTwoSongs() async {
      final store = MusicPlayerStore(
        playbackApi: playback,
        engineFactory: () => engine,
      );
      addTearDown(store.dispose);
      await store.playSong(fakeSong());
      await store.playSong(fakeSong(id: '7302', title: '晴天', hash: secondHash));
      await store.playAt(0);
      return store;
    }

    /// 迷你条放在屏幕底部，与生产布局一致（模式卡片的「上方」才有空间）。
    Future<void> pumpMini(WidgetTester tester, MusicPlayerStore store) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MusicMiniPlayer(player: store),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('上一首/下一首按钮存在并驱动 store 切歌', (tester) async {
      final store = await seedTwoSongs();
      await pumpMini(tester, store);

      expect(find.byKey(const Key('mini-previous')), findsOneWidget);
      expect(find.byKey(const Key('mini-play-pause')), findsOneWidget);
      expect(find.byKey(const Key('mini-next')), findsOneWidget);

      await tester.tap(find.byKey(const Key('mini-next')));
      await tester.pumpAndSettle();
      expect(store.index, 1);
      expect(engine.openedUrl, 'https://cdn.example/7302.mp3');

      await tester.tap(find.byKey(const Key('mini-previous')));
      await tester.pumpAndSettle();
      expect(store.index, 0);
      expect(engine.openedUrl, 'https://cdn.example/7301.mp3');
    });

    testWidgets('模式按钮：卡片只列另外两种模式，弹在按钮上方，点选生效', (tester) async {
      final store = await seedTwoSongs();
      await pumpMini(tester, store);

      expect(find.byKey(const Key('mini-play-mode')), findsOneWidget);
      expect(store.playMode, PlayMode.listLoop);
      expect(find.byIcon(Icons.repeat), findsOneWidget);

      await tester.tap(find.byKey(const Key('mini-play-mode')));
      await tester.pumpAndSettle();

      final card = find.byKey(const Key('music-mode-card'));
      expect(card, findsOneWidget);
      // 只列另外两种：当前模式（列表循环）不出现在卡片里。
      expect(find.text('随机'), findsOneWidget);
      expect(find.text('单曲循环'), findsOneWidget);
      expect(find.text('列表循环'), findsNothing);
      expect(find.byKey(const Key('music-mode-option-listLoop')), findsNothing);
      // 卡片整体在模式按钮上方。
      expect(
        tester.getRect(card).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byKey(const Key('mini-play-mode'))).top,
        ),
      );

      await tester.tap(find.text('随机'));
      await tester.pumpAndSettle();

      expect(store.playMode, PlayMode.shuffle);
      expect(find.byKey(const Key('music-mode-card')), findsNothing);
      // setPlayMode 在弹窗 pop 完成后的微任务里执行，补一帧让 Observer 重建。
      await tester.pump();
      expect(find.byIcon(Icons.shuffle), findsOneWidget);

      // 再打开：当前是随机，卡片只列单曲循环 / 列表循环。
      await tester.tap(find.byKey(const Key('mini-play-mode')));
      await tester.pumpAndSettle();
      expect(find.text('随机'), findsNothing);
      expect(find.text('单曲循环'), findsOneWidget);
      expect(find.text('列表循环'), findsOneWidget);

      await tester.tap(find.text('列表循环'));
      await tester.pumpAndSettle();
      expect(store.playMode, PlayMode.listLoop);
      expect(find.byKey(const Key('music-mode-card')), findsNothing);
    });

    testWidgets('列表按钮：右侧抽屉只含队列，点行切歌并关闭', (tester) async {
      final store = await seedTwoSongs();
      await pumpMini(tester, store);

      await tester.tap(find.byKey(const Key('mini-queue')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('music-queue-drawer')), findsOneWidget);
      expect(find.byKey(const Key('music-queue-list')), findsOneWidget);
      // 模式选择已迁到独立卡片，抽屉里不再有模式控件。
      expect(find.byKey(const Key('music-queue-play-mode')), findsNothing);
      expect(find.text('播放模式'), findsNothing);
      expect(find.widgetWithText(ListTile, '稻香'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '晴天'), findsOneWidget);

      await tester.tap(find.widgetWithText(ListTile, '晴天'));
      await tester.pumpAndSettle();
      expect(store.index, 1);
      expect(engine.openedUrl, 'https://cdn.example/7302.mp3');
      expect(find.byKey(const Key('music-queue-list')), findsNothing);
    });
  });

  // ---- MD3 Expressive 波浪进度条（M4-P）----

  testWidgets('播放页出现波浪进度条（可拖动 Slider）', (tester) async {
    await pumpModule(tester);
    await searchAndOpen(tester);

    expect(
      find.byKey(const Key('player-wavy-progress')),
      findsOneWidget,
      reason: '播放页替换为波浪进度条后仍保留 Slider 供点击 seek',
    );
    // 波浪进度条本体仍是 Slider，既有 find.byType(Slider) 测试不受影响。
    expect(
      find.descendant(
        of: find.byType(MusicPlayerPage),
        matching: find.byType(Slider),
      ),
      findsOneWidget,
    );
  });

  testWidgets('迷你条出现波浪进度条（Key 存在且不拦截整卡点击）', (tester) async {
    await pumpModule(tester);
    await searchAndOpen(tester);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 有播放进度时底部绘制波形细条。
    engine.emit(
      const MusicPlaybackSnapshot(
        position: Duration(seconds: 30),
        duration: Duration(seconds: 200),
        playing: true,
      ),
    );
    await tester.pumpAndSettle();

    final mini = find.byType(MusicMiniPlayer);
    final progress = find.descendant(
      of: mini,
      matching: find.byKey(const Key('mini-wavy-progress')),
    );
    expect(progress, findsOneWidget);

    // 点进度条区域仍能穿透到整卡 InkWell 进入播放页（用 tapAt 避免
    // IgnorePointer  widget 本身不可命中的 hit-test 警告——这正是期望行为）。
    final progressRect = tester.getRect(progress);
    await tester.tapAt(progressRect.center);
    await tester.pumpAndSettle();
    expect(find.byType(MusicPlayerPage), findsOneWidget);
  });

  testWidgets('拖动波浪进度条后 engine.seeks 非空且 pumpAndSettle 收敛', (tester) async {
    await pumpModule(tester);
    await searchAndOpen(tester);

    engine.emit(
      const MusicPlaybackSnapshot(
        position: Duration.zero,
        duration: Duration(seconds: 200),
        playing: true,
      ),
    );
    await tester.pumpAndSettle();

    final slider = find.byKey(const Key('player-wavy-progress'));
    final rect = tester.getRect(slider);
    await tester.tapAt(Offset(rect.left + rect.width * 0.75, rect.center.dy));
    await tester.pumpAndSettle();

    expect(engine.seeks, isNotEmpty);
    expect(engine.seeks.last.inSeconds, greaterThan(0));
  });
}
