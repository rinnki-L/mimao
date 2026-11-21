// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// 专辑详情页测试：渲染、播放、歌手回调、disc/position 排序、分页防重复、
/// 错误/空态、可选增强（dycover/favoriteCount）降级、长按曲目弹资料面板。
/// 全部走 fake（无网络、无真实计时器）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/models/album_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playback_ext_models.dart';
import 'package:mimao/music/pages/music_album_detail_page.dart';
import 'package:mimao/music/pages/music_song_info_sheet.dart';

import 'fake_apis.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildMimaoTheme(
    seedColor: const Color(0xFF3B82F6),
    brightness: Brightness.light,
  ),
  home: child,
);

/// 测试面拉高到 2400：窄屏单列布局（<880）下头部 + 列表全部可见，
/// 点击不必滚动（页面本身仍按视口自适应）。
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

FakeAlbumApi _api({
  MusicAlbumDetail? detail,
  Object? detailError,
  Map<int, MusicAlbumTracks>? songsPages,
  Object? dycoverError,
}) => FakeAlbumApi(
  detail: detail,
  detailError: detailError,
  songsPages: songsPages ?? const <int, MusicAlbumTracks>{},
  dycoverError: dycoverError,
);

void main() {
  testWidgets('专辑页渲染标题与曲目；点曲目起播并打开播放页', (tester) async {
    _useTallSurface(tester);
    final player = FakePlayerUi();
    final api = _api(
      detail: albumDetailFixture(title: '测试专辑'),
      songsPages: <int, MusicAlbumTracks>{
        1: tracksPage(
          1,
          total: 2,
          tracks: <MusicAlbumTrack>[
            albumTrackFixture(1, title: '曲目一', songId: 's1'),
            albumTrackFixture(2, title: '曲目二', songId: 's2'),
          ],
        ),
      },
    );
    await tester.pumpWidget(
      _wrap(MusicAlbumDetailPage(album: api, albumId: 7, player: player)),
    );
    await tester.pumpAndSettle();

    expect(find.text('测试专辑'), findsNWidgets(2)); // AppBar + 头部标题
    expect(find.text('曲目一'), findsOneWidget);
    expect(find.text('曲目二'), findsOneWidget);
    expect(player.played, isEmpty);

    await tester.tap(find.text('曲目一'));
    await tester.pumpAndSettle();

    expect(player.played.map((song) => song.title), <String>['曲目一']);
    expect(player.played.single.id, 's1');
    expect(find.text('fake-player'), findsOneWidget); // 播放页被 push
  });

  testWidgets('点头部歌手名回调 onOpenArtist；无 id 的歌手只展示不可点', (tester) async {
    _useTallSurface(tester);
    final opened = <int>[];
    final api = _api(
      detail: albumDetailFixture(
        artists: const <MusicArtistRef>[
          MusicArtistRef(id: 42, name: '歌手甲'),
          MusicArtistRef(name: '无名歌手'),
        ],
      ),
    );
    await tester.pumpWidget(
      _wrap(
        MusicAlbumDetailPage(
          album: api,
          albumId: 7,
          player: FakePlayerUi(),
          onOpenArtist: opened.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('歌手甲'), findsOneWidget);
    await tester.tap(find.text('歌手甲'));
    expect(opened, <int>[42]);

    await tester.tap(find.text('无名歌手'));
    expect(opened, <int>[42]); // 无 id 的歌手不可点
  });

  testWidgets('曲目按 disc/position 稳定排序（乱序输入按序展示）', (tester) async {
    _useTallSurface(tester);
    final api = _api(
      detail: albumDetailFixture(),
      songsPages: <int, MusicAlbumTracks>{
        1: tracksPage(
          1,
          total: 2,
          tracks: <MusicAlbumTrack>[
            albumTrackFixture(2, title: '应排后', songId: 's2'),
            albumTrackFixture(1, title: '应排前', songId: 's1'),
          ],
        ),
      },
    );
    await tester.pumpWidget(
      _wrap(
        MusicAlbumDetailPage(album: api, albumId: 7, player: FakePlayerUi()),
      ),
    );
    await tester.pumpAndSettle();

    final front = tester.getTopLeft(find.text('应排前')).dy;
    final back = tester.getTopLeft(find.text('应排后')).dy;
    expect(front, lessThan(back));
  });

  testWidgets('加载更多追加第二页；请求中重复点击不重复请求', (tester) async {
    _useTallSurface(tester);
    final api = _api(
      detail: albumDetailFixture(),
      songsPages: <int, MusicAlbumTracks>{
        1: tracksPage(
          1,
          total: 4,
          tracks: <MusicAlbumTrack>[
            albumTrackFixture(1, title: '曲目一', songId: 's1'),
            albumTrackFixture(2, title: '曲目二', songId: 's2'),
          ],
        ),
        2: tracksPage(
          2,
          total: 4,
          tracks: <MusicAlbumTrack>[
            albumTrackFixture(3, title: '曲目三', songId: 's3'),
            albumTrackFixture(4, title: '曲目四', songId: 's4'),
          ],
        ),
      },
    );
    await tester.pumpWidget(
      _wrap(
        MusicAlbumDetailPage(album: api, albumId: 7, player: FakePlayerUi()),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.songsPageLog, <int>[1]);
    expect(find.text('加载更多'), findsOneWidget);
    expect(find.text('曲目三'), findsNothing);

    // 挂起第二页：加载中按钮禁用，重复点击不产生第二次请求。
    api.gateSongsPage(2);
    await tester.tap(find.text('加载更多'));
    await tester.pump();
    await tester.tap(find.text('加载更多'));
    await tester.pump();
    expect(api.songsPageLog, <int>[1, 2]);

    api.completeSongsPage(2);
    await tester.pumpAndSettle();

    expect(api.songsPageLog, <int>[1, 2]); // 仍只有两次请求
    expect(find.text('曲目三'), findsOneWidget);
    expect(find.text('曲目四'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing); // total 已满，按钮消失
  });

  testWidgets('专辑详情失败显示重试；重试成功后恢复渲染', (tester) async {
    _useTallSurface(tester);
    final api = _api(
      detail: albumDetailFixture(title: '测试专辑'),
      detailError: '专辑详情挂了',
    );
    await tester.pumpWidget(
      _wrap(
        MusicAlbumDetailPage(album: api, albumId: 7, player: FakePlayerUi()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('专辑详情挂了'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    api.detailError = null; // 一次性失败：重试走成功路径
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('测试专辑'), findsNWidgets(2));
    expect(find.text('专辑详情挂了'), findsNothing);
  });

  testWidgets('dycover 失败不影响专辑主体（封面回退、曲目照常）', (tester) async {
    _useTallSurface(tester);
    final api = _api(
      detail: albumDetailFixture(title: '测试专辑'),
      songsPages: <int, MusicAlbumTracks>{
        1: tracksPage(
          1,
          total: 1,
          tracks: <MusicAlbumTrack>[albumTrackFixture(1, title: '曲目一')],
        ),
      },
      dycoverError: '动态封面挂了',
    );
    await tester.pumpWidget(
      _wrap(
        MusicAlbumDetailPage(album: api, albumId: 7, player: FakePlayerUi()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('测试专辑'), findsNWidgets(2));
    expect(find.text('曲目一'), findsOneWidget);
    expect(find.text('动态封面挂了'), findsNothing);
    expect(find.text('重试'), findsNothing);
  });

  testWidgets('albumDetail 无数据时显示空态，且不拉曲目', (tester) async {
    _useTallSurface(tester);
    final api = _api(detail: null); // 上游 null 语义：无此专辑
    await tester.pumpWidget(
      _wrap(
        MusicAlbumDetailPage(album: api, albumId: 7, player: FakePlayerUi()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('没有找到这张专辑'), findsOneWidget);
    expect(api.songsPageLog, isEmpty); // 无详情时不拉曲目
  });

  testWidgets('曲目为空时提示暂无曲目', (tester) async {
    _useTallSurface(tester);
    final api = _api(
      detail: albumDetailFixture(),
      songsPages: <int, MusicAlbumTracks>{1: tracksPage(1, total: 0)},
    );
    await tester.pumpWidget(
      _wrap(
        MusicAlbumDetailPage(album: api, albumId: 7, player: FakePlayerUi()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('专辑暂无曲目'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
  });

  testWidgets('接线 playbackExt：长按曲目弹出资料面板并带上专辑 id', (tester) async {
    _useTallSurface(tester);
    final ext = FakePlaybackExtApi(
      privileges: <MusicResourcePrivileges>[privilegeFixture()],
      presentations: <MusicSongPresentation>[presentationFixture()],
      portraitGroups: portraitGroupsFixture(),
    );
    final api = _api(
      detail: albumDetailFixture(title: '测试专辑'),
      songsPages: <int, MusicAlbumTracks>{
        1: tracksPage(
          1,
          total: 1,
          tracks: <MusicAlbumTrack>[
            albumTrackFixture(
              1,
              title: '曲目一',
              songId: 's1',
              hash: kValidHash,
              audioId: 9001,
            ),
          ],
        ),
      },
    );
    await tester.pumpWidget(
      _wrap(
        MusicAlbumDetailPage(
          album: api,
          albumId: 7,
          player: FakePlayerUi(),
          playbackExt: ext,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('曲目一'));
    await tester.pumpAndSettle();

    expect(find.text('权益'), findsOneWidget);
    expect(find.text('资料'), findsOneWidget);
    expect(find.text('歌手图片'), findsOneWidget);
    expect(find.byKey(const Key('music-portrait-thumb-0')), findsOneWidget);
    // 单曲查询带上了当前专辑 id（privilege_lite 的 album_id）。
    expect(ext.privilegeLog, hasLength(1));
    expect(ext.privilegeLog.single.resources.single.albumId, 7);
    expect(ext.privilegeLog.single.resources.single.hash, kValidHash);
  });

  testWidgets('未接线 playbackExt：长按曲目不弹面板，点击仍可播放', (tester) async {
    _useTallSurface(tester);
    final player = FakePlayerUi();
    final api = _api(
      detail: albumDetailFixture(title: '测试专辑'),
      songsPages: <int, MusicAlbumTracks>{
        1: tracksPage(
          1,
          total: 1,
          tracks: <MusicAlbumTrack>[albumTrackFixture(1, title: '曲目一')],
        ),
      },
    );
    await tester.pumpWidget(
      _wrap(MusicAlbumDetailPage(album: api, albumId: 7, player: player)),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('曲目一'));
    await tester.pumpAndSettle();
    // 未接线时长按不弹资料面板（长按松开会触发 ListTile 的点击播放，
    // 属于 ListTile 既有行为，这里只关注面板不出现）。
    expect(find.byType(MusicSongInfoSheet), findsNothing);
    expect(find.text('权益'), findsNothing);
  });
}
