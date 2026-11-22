// ignore_for_file: deprecated_member_use — 与模块页面测试同款说明。
/// 契约提交的守卫测试：三条并行线的共享类型与 null 降级行为。
///
/// 这里不测任何一条线的实现（它们还没落地），只保证：
/// - 共享模型可序列化/可重建（历史续播依赖它）；
/// - 模块/页面在依赖未接线时仍可渲染（既有测试继续可跑）；
/// - 可空缝真的可空（不抛、不空指针）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_store.dart';
import 'package:mimao/music/pages/music_module_page.dart';
import 'package:mimao/music/pages/music_module_settings.dart';
import 'package:mimao/music/player/playback_engine.dart';

class _FakeApi implements MusicApi {
  @override
  Future<MusicPage<MusicSong>> searchSongs({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async => MusicPage<MusicSong>(
    page: 1,
    items: <MusicSong>[
      MusicSong(
        id: '7301',
        audioId: 9001,
        hash: 'ABCDEF0123456789ABCDEF0123456789',
        title: '稻香',
        artists: const <MusicArtistRef>[MusicArtistRef(id: 1, name: '周杰伦')],
        albumId: '42',
        albumTitle: '魔杰座',
        durationMs: 223000,
        coverUrl: 'https://example.com/c.jpg',
        privilege: 8,
        resources: const <MusicAudioResource>[
          MusicAudioResource(
            quality: '320',
            hash: 'ABCDEF0123456789ABCDEF0123456789',
            bitRateBps: 320000,
            extension: 'mp3',
          ),
        ],
      ),
    ],
  );

  @override
  Future<KugouIdentity> ensureDevice() async => KugouIdentity.anonymous();

  @override
  Future<KugouIdentity?> currentIdentity() async => null;
}

void main() {
  test('MusicQuality 八个档位齐全（对齐上游 Quality 枚举）', () {
    expect(MusicQuality.values.length, 8);
    expect(MusicQuality.values, contains(MusicQuality.hiRes));
    expect(MusicQuality.values, contains(MusicQuality.automatic));
  });

  test('MusicSong JSON 往返无损（历史/收藏重建曲目靠这个）', () async {
    final store = MusicStore(_FakeApi());
    await store.search('稻香');
    final song = store.results.single;

    final restored = MusicSong.fromJson(song.toJson());
    expect(restored.id, song.id);
    expect(restored.audioId, song.audioId);
    expect(restored.hash, song.hash);
    expect(restored.title, song.title);
    expect(restored.albumId, song.albumId);
    expect(restored.albumTitle, song.albumTitle);
    expect(restored.durationMs, song.durationMs);
    expect(restored.coverUrl, song.coverUrl);
    expect(restored.privilege, song.privilege);
    expect(restored.artists.single.id, 1);
    expect(restored.artists.single.name, '周杰伦');
    expect(restored.resources.single.quality, '320');
    expect(restored.resources.single.bitRateBps, 320000);
    expect(restored.resources.single.extension, 'mp3');
  });

  test('musicRefOf：优先 MixSongID、缺省回退 hash、都空则抛错', () {
    const withId = MusicSong(
      id: '7301',
      hash: 'HASH',
      title: 't',
      artists: <MusicArtistRef>[],
      albumId: '',
      albumTitle: '',
      coverUrl: '',
    );
    expect(musicRefOf(withId).id, '7301');

    const hashOnly = MusicSong(
      id: '',
      hash: 'HASH',
      title: 't',
      artists: <MusicArtistRef>[],
      albumId: '',
      albumTitle: '',
      coverUrl: '',
    );
    expect(musicRefOf(hashOnly).id, 'HASH');

    const empty = MusicSong(
      id: '',
      hash: '',
      title: 't',
      artists: <MusicArtistRef>[],
      albumId: '',
      albumTitle: '',
      coverUrl: '',
    );
    expect(() => musicRefOf(empty), throwsArgumentError);
    expect(kugouSourceName, 'kugou');
  });

  test('MusicPlaybackSource：primaryUrl 空列表为 null', () {
    const source = MusicPlaybackSource(
      hash: 'H',
      urls: <String>[],
      extension: 'mp3',
      fileName: 'f.mp3',
    );
    expect(source.primaryUrl, isNull);
    const withUrl = MusicPlaybackSource(
      hash: 'H',
      urls: <String>['https://cdn/1.mp3', 'https://cdn/2.mp3'],
      extension: 'mp3',
      fileName: 'f.mp3',
    );
    expect(withUrl.primaryUrl, 'https://cdn/1.mp3');
  });

  test('MusicPlaybackSnapshot.copyWith 保留未覆盖字段', () {
    const snapshot = MusicPlaybackSnapshot(
      position: Duration(seconds: 3),
      duration: Duration(seconds: 30),
      playing: true,
    );
    final paused = snapshot.copyWith(playing: false);
    expect(paused.position, const Duration(seconds: 3));
    expect(paused.duration, const Duration(seconds: 30));
    expect(paused.playing, isFalse);
  });

  testWidgets('页面 null 降级：无播放/收藏/我的页仍可搜索并提示未接线', (tester) async {
    final store = MusicStore(_FakeApi());
    await tester.pumpWidget(
      MaterialApp(home: MusicModulePage(store: store, embedded: true)),
    );
    await tester.enterText(find.byType(TextField), '稻香');
    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, '稻香'), findsOneWidget);
    // 未接线：不显示收藏按钮；侧栏只有「搜索」入口、无设置区，
    // 也不回退到底部导航（2026-11-22 侧栏化，原为 NavigationBar 守卫）。
    expect(find.byIcon(Icons.favorite_border), findsNothing);
    expect(find.byKey(const Key('music-sidebar')), findsOneWidget);
    expect(find.byKey(const Key('music-sidebar-settings')), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.widgetWithText(ListTile, '稻香'));
    await tester.pump();
    // 单击与双击并存：单击要等双击判定超时（约 300ms）后才触发。
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('播放功能随播放器切片接入'), findsOneWidget);
  });

  testWidgets('页面提供 libraryTab 时侧栏出现「搜索 / 我的」入口', (tester) async {
    final store = MusicStore(_FakeApi());
    await tester.pumpWidget(
      MaterialApp(
        home: MusicModulePage(
          store: store,
          embedded: true,
          libraryTab: const Center(child: Text('我的音乐占位')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 侧栏入口出现（2026-11-22 侧栏化，原为 NavigationBar 守卫）。
    expect(find.byKey(const Key('music-sidebar')), findsOneWidget);
    expect(find.text('搜索'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('我的音乐占位'), findsOneWidget);
  });

  testWidgets('设置分组：account 未接线时保留既有占位锚点', (tester) async {
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
    expect(find.text('酷狗账号登录（二维码）'), findsOneWidget);
    expect(find.text('设备身份'), findsOneWidget);
  });
}
