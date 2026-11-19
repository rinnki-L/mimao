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

    await tester.tap(find.byType(MusicMiniPlayer));
    await tester.pumpAndSettle();
    expect(find.byType(MusicPlayerPage), findsOneWidget);
  });
}
