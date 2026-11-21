// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// 歌手详情页测试：头部/专辑网格/歌曲渲染、点专辑回调、点歌曲播放（含
/// MusicArtistSong → MusicSong 映射）、分页追加、错误/空态、目录可选分区、
/// 「歌手写真」可选分区（加载/空/失败隐藏与去重限量）。
/// 全部走 fake（无网络、无真实计时器）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/models/artist_models.dart';
import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/pages/music_artist_detail_page.dart';

import 'fake_apis.dart';

Widget _wrap(Widget child) => MaterialApp(
  theme: buildMimaoTheme(
    seedColor: const Color(0xFF3B82F6),
    brightness: Brightness.light,
  ),
  home: child,
);

/// 测试面拉高到 2400：窄屏单列布局（<880）下头部 + 网格 + 列表全部可见，
/// 点击不必滚动（页面本身仍按视口自适应）。
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

FakeArtistApi _api({
  MusicArtistDetail? detail,
  Object? detailError,
  Map<int, MusicPage<MusicAlbumSummary>>? albumsPages,
  Map<int, MusicPage<MusicArtistSong>>? songsPages,
  Object? listsError,
  MusicArtistDirectory? lists,
}) => FakeArtistApi(
  detail: detail,
  detailError: detailError,
  albumsPages: albumsPages ?? const <int, MusicPage<MusicAlbumSummary>>{},
  songsPages: songsPages ?? const <int, MusicPage<MusicArtistSong>>{},
  listsError: listsError,
  lists: lists,
);

void main() {
  testWidgets('歌手页渲染专辑网格与歌曲；点专辑回调、点歌曲播放并映射 MusicSong', (tester) async {
    _useTallSurface(tester);
    final player = FakePlayerUi();
    final opened = <int>[];
    final api = _api(
      detail: artistDetailFixture(name: '歌手乙'),
      albumsPages: <int, MusicPage<MusicAlbumSummary>>{
        1: albumsPage(
          1,
          total: 2,
          albums: <MusicAlbumSummary>[
            albumSummaryFixture(10, '专辑甲'),
            albumSummaryFixture(11, '专辑乙'),
          ],
        ),
      },
      songsPages: <int, MusicPage<MusicArtistSong>>{
        1: artistSongsPage(
          1,
          total: 1,
          songs: <MusicArtistSong>[artistSongFixture(albumTitle: null)],
        ),
      },
    );
    await tester.pumpWidget(
      _wrap(
        MusicArtistDetailPage(
          artist: api,
          artistId: 5,
          player: player,
          onOpenAlbum: opened.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('歌手乙'), findsNWidgets(2)); // AppBar + 头部名字
    expect(find.text('专辑甲'), findsOneWidget);
    expect(find.text('专辑乙'), findsOneWidget);
    expect(find.text('热门歌'), findsOneWidget);

    await tester.tap(find.text('专辑甲'));
    expect(opened, <int>[10]);
    await tester.tap(find.text('专辑乙'));
    expect(opened, <int>[10, 11]);

    await tester.tap(find.text('热门歌'));
    await tester.pumpAndSettle();

    expect(player.played.map((song) => song.title), <String>['热门歌']);
    final song = player.played.single;
    expect(song.id, 'as-1');
    expect(song.hash, 'hash-as-1');
    // 平铺结构的 albumTitle null → MusicSong 的空串。
    expect(song.albumTitle, '');
    expect(find.text('fake-player'), findsOneWidget); // 播放页被 push
  });

  testWidgets('歌曲加载更多追加第二页；专辑卡片无 id 时不回调', (tester) async {
    _useTallSurface(tester);
    final opened = <int>[];
    final player = FakePlayerUi();
    final api = _api(
      detail: artistDetailFixture(),
      albumsPages: <int, MusicPage<MusicAlbumSummary>>{
        1: albumsPage(
          1,
          total: 1,
          albums: <MusicAlbumSummary>[albumSummaryFixture(10, '专辑甲')],
        ),
      },
      songsPages: <int, MusicPage<MusicArtistSong>>{
        1: artistSongsPage(
          1,
          total: 2,
          songs: <MusicArtistSong>[artistSongFixture(id: 'as-1', title: '热门歌')],
        ),
        2: artistSongsPage(
          2,
          total: 2,
          songs: <MusicArtistSong>[artistSongFixture(id: 'as-2', title: '冷门歌')],
        ),
      },
    );
    await tester.pumpWidget(
      _wrap(
        MusicArtistDetailPage(
          artist: api,
          artistId: 5,
          player: player,
          onOpenAlbum: opened.add,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.songsPageLog, <int>[1]);
    expect(find.text('加载更多'), findsOneWidget); // 专辑 total 已满，只剩歌曲区
    expect(find.text('冷门歌'), findsNothing);

    await tester.tap(find.text('加载更多'));
    await tester.pumpAndSettle();

    expect(api.songsPageLog, <int>[1, 2]);
    expect(find.text('冷门歌'), findsOneWidget);
    expect(find.text('加载更多'), findsNothing);
  });

  testWidgets('专辑卡片无 id 时不可点、不回调', (tester) async {
    _useTallSurface(tester);
    final opened = <int>[];
    final api = _api(
      detail: artistDetailFixture(),
      albumsPages: <int, MusicPage<MusicAlbumSummary>>{
        1: albumsPage(
          1,
          total: 1,
          albums: <MusicAlbumSummary>[
            MusicAlbumSummary(
              title: '无 ID 专辑',
              artists: const <MusicArtistRef>[MusicArtistRef(name: '歌手乙')],
              coverUrl: '',
              publishedAt: '',
            ),
          ],
        ),
      },
    );
    await tester.pumpWidget(
      _wrap(
        MusicArtistDetailPage(
          artist: api,
          artistId: 5,
          player: FakePlayerUi(),
          onOpenAlbum: opened.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('无 ID 专辑'));
    expect(opened, isEmpty); // 无 id 的专辑卡不回调
  });

  testWidgets('歌手详情失败显示重试；重试成功后恢复渲染', (tester) async {
    _useTallSurface(tester);
    final api = _api(detail: artistDetailFixture(), detailError: '歌手详情挂了');
    await tester.pumpWidget(
      _wrap(
        MusicArtistDetailPage(artist: api, artistId: 5, player: FakePlayerUi()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('歌手详情挂了'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(api.albumsPageLog, isEmpty); // 失败时不动主体分页

    api.detailError = null;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('歌手详情挂了'), findsNothing);
    expect(api.albumsPageLog, <int>[1]);
    expect(api.songsPageLog, <int>[1]);
  });

  testWidgets('artistLists 失败不影响主体；重试目录可恢复', (tester) async {
    _useTallSurface(tester);
    final api = _api(
      detail: artistDetailFixture(),
      albumsPages: <int, MusicPage<MusicAlbumSummary>>{
        1: albumsPage(
          1,
          total: 1,
          albums: <MusicAlbumSummary>[albumSummaryFixture(10, '专辑甲')],
        ),
      },
      songsPages: <int, MusicPage<MusicArtistSong>>{
        1: artistSongsPage(
          1,
          total: 1,
          songs: <MusicArtistSong>[artistSongFixture()],
        ),
      },
      listsError: '目录挂了',
    );
    await tester.pumpWidget(
      _wrap(
        MusicArtistDetailPage(artist: api, artistId: 5, player: FakePlayerUi()),
      ),
    );
    await tester.pumpAndSettle();

    // 主体完整渲染。
    expect(find.text('专辑甲'), findsOneWidget);
    expect(find.text('热门歌'), findsOneWidget);
    // 目录区只给行内提示，不冒充页面级错误。
    expect(find.text('目录挂了'), findsOneWidget);
    expect(find.text('重试目录'), findsOneWidget);

    api.listsError = null;
    api.lists = directoryFixture();
    await tester.tap(find.text('重试目录'));
    await tester.pumpAndSettle();

    expect(find.text('目录挂了'), findsNothing);
    expect(find.text('华语男歌手'), findsOneWidget);
    expect(find.text('目录歌手甲'), findsOneWidget);
  });

  testWidgets('目录筛选切换会带新参数重新请求 artistLists', (tester) async {
    _useTallSurface(tester);
    final api = _api(detail: artistDetailFixture(), lists: directoryFixture());
    await tester.pumpWidget(
      _wrap(
        MusicArtistDetailPage(artist: api, artistId: 5, player: FakePlayerUi()),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.listsLog, hasLength(1));
    expect(api.listsLog.first.sex, 0);
    expect(api.listsLog.first.musician, 0);

    await tester.tap(find.text('男歌手'));
    await tester.pumpAndSettle();
    expect(api.listsLog, hasLength(2));
    expect(api.listsLog.last.sex, 1);
    expect(api.listsLog.last.musician, 0);

    await tester.tap(find.text('音乐人'));
    await tester.pumpAndSettle();
    expect(api.listsLog, hasLength(3));
    expect(api.listsLog.last.musician, 3); // 类型筛选携带 musician
  });

  testWidgets('artistDetail 无数据时显示空态，不拉专辑/歌曲', (tester) async {
    _useTallSurface(tester);
    final api = _api(detail: null);
    await tester.pumpWidget(
      _wrap(
        MusicArtistDetailPage(artist: api, artistId: 5, player: FakePlayerUi()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('没有找到这位歌手'), findsOneWidget);
    expect(api.albumsPageLog, isEmpty);
    expect(api.songsPageLog, isEmpty);
    expect(api.listsLog, isEmpty);
  });

  testWidgets('歌手写真：歌曲 hash 去重后查询；缩略图可点击全屏预览', (tester) async {
    _useTallSurface(tester);
    final ext = FakePlaybackExtApi(portraitGroups: portraitGroupsFixture());
    final api = _api(
      detail: artistDetailFixture(name: '歌手乙'),
      songsPages: <int, MusicPage<MusicArtistSong>>{
        1: artistSongsPage(
          1,
          total: 2,
          songs: <MusicArtistSong>[
            artistSongFixture(id: 'as-1', title: '热门歌', hash: kValidHash),
            // 同 hash 的第二首：不重复进查询。
            artistSongFixture(id: 'as-2', title: '同Hash歌', hash: kValidHash),
          ],
        ),
      },
    );
    await tester.pumpWidget(
      _wrap(
        MusicArtistDetailPage(
          artist: api,
          artistId: 5,
          player: FakePlayerUi(),
          playbackExt: ext,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('歌手写真'), findsOneWidget);
    expect(ext.imagesLog, hasLength(1));
    expect(ext.imagesLog.single.resources, hasLength(1)); // hash 去重
    expect(ext.imagesLog.single.resources.single.hash, kValidHash);
    expect(ext.imagesLog.single.resources.single.filename, '热门歌');
    expect(find.byKey(const Key('music-portrait-thumb-0')), findsOneWidget);

    await tester.tap(find.byKey(const Key('music-portrait-thumb-0')));
    await tester.pumpAndSettle();
    expect(find.text('写真0.jpg'), findsOneWidget); // 预览标题（文件名）
    expect(find.text('关闭'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('写真0.jpg'), findsNothing);
    expect(find.text('歌手写真'), findsOneWidget); // 分区仍在
  });

  testWidgets('歌手写真：hash 去重最多取 20 个资源（超出截断）', (tester) async {
    _useTallSurface(tester);
    // 25 个不同合法 hash：只带前 20 个进查询。
    String hashFor(int i) =>
        'a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3${i.toRadixString(16).padLeft(2, '0')}';
    final ext = FakePlaybackExtApi(portraitGroups: portraitGroupsFixture());
    final api = _api(
      detail: artistDetailFixture(),
      songsPages: <int, MusicPage<MusicArtistSong>>{
        1: artistSongsPage(
          1,
          total: 25,
          songs: List<MusicArtistSong>.generate(
            25,
            (i) =>
                artistSongFixture(id: 'as-$i', title: '歌$i', hash: hashFor(i)),
          ),
        ),
      },
    );
    await tester.pumpWidget(
      _wrap(
        MusicArtistDetailPage(
          artist: api,
          artistId: 5,
          player: FakePlayerUi(),
          playbackExt: ext,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('歌手写真'), findsOneWidget);
    expect(ext.imagesLog, hasLength(1));
    expect(ext.imagesLog.single.resources, hasLength(20));
  });

  testWidgets('歌手写真：失败/空数据整段隐藏；未接线时隐藏且不打扰主体', (tester) async {
    _useTallSurface(tester);
    MusicPage<MusicArtistSong> pageWithOne() => artistSongsPage(
      1,
      total: 1,
      songs: <MusicArtistSong>[artistSongFixture(hash: kValidHash)],
    );

    // 失败：装饰性分区，不弹错误文案，主体照常。
    final failedApi = _api(
      detail: artistDetailFixture(name: '歌手乙'),
      songsPages: <int, MusicPage<MusicArtistSong>>{1: pageWithOne()},
    );
    final failedExt = FakePlaybackExtApi(imagesError: '写真挂了');
    await tester.pumpWidget(
      _wrap(
        // 同类型重复 pump 会原地复用 State（initState 不会重跑），
        // 三段用 UniqueKey 强制重建页面各自拉一次数据。
        MusicArtistDetailPage(
          key: UniqueKey(),
          artist: failedApi,
          artistId: 5,
          player: FakePlayerUi(),
          playbackExt: failedExt,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('热门歌'), findsOneWidget); // 主体照常
    expect(find.text('歌手写真'), findsNothing);
    expect(failedExt.imagesLog, hasLength(1)); // 请求确实发起过

    // 空数据：整段隐藏。
    final emptyApi = _api(
      detail: artistDetailFixture(name: '歌手乙'),
      songsPages: <int, MusicPage<MusicArtistSong>>{1: pageWithOne()},
    );
    final emptyExt = FakePlaybackExtApi();
    await tester.pumpWidget(
      _wrap(
        MusicArtistDetailPage(
          key: UniqueKey(),
          artist: emptyApi,
          artistId: 5,
          player: FakePlayerUi(),
          playbackExt: emptyExt,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('歌手写真'), findsNothing);
    expect(emptyExt.imagesLog, hasLength(1));

    // 未接线 playbackExt：不展示也不请求。
    final unwiredApi = _api(
      detail: artistDetailFixture(name: '歌手乙'),
      songsPages: <int, MusicPage<MusicArtistSong>>{1: pageWithOne()},
    );
    await tester.pumpWidget(
      _wrap(
        MusicArtistDetailPage(
          key: UniqueKey(),
          artist: unwiredApi,
          artistId: 5,
          player: FakePlayerUi(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('歌手写真'), findsNothing);
    expect(find.text('热门歌'), findsOneWidget);
  });
}
