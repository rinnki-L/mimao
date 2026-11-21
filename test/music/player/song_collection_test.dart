/// 收藏能力（我喜欢/指定歌单）的纯逻辑测试：不碰网络、不碰 UI。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:mimao/music/player/song_collection.dart';

import '../pages/playlist/fakes.dart';

MusicUserPlaylist _playlist({
  int? cloudListId,
  String title = '歌单',
  bool? editable = true,
  int? defaultKind,
}) => MusicUserPlaylist(
  cloudListId: cloudListId,
  globalId: 'g-$cloudListId',
  creatorGlobalId: 'creator',
  title: title,
  descriptionPresent: false,
  tagsPresent: false,
  description: '',
  tags: '',
  coverUrl: '',
  creatorId: 1,
  creatorName: '我',
  creatorListId: 1,
  songCount: 0,
  revision: 0,
  sortIndex: 0,
  sourceCode: 0,
  kind: MusicCloudPlaylistKind.owned,
  kindCode: 0,
  editable: editable,
  private: null,
  published: null,
  deleted: null,
  dropped: null,
  customCover: null,
  defaultKind: defaultKind,
  flagCodes: const MusicPlaylistFlagCodes(
    editable: null,
    private: null,
    published: null,
    deleted: null,
    dropped: null,
    customCover: null,
  ),
  createdAtSeconds: null,
  updatedAtSeconds: null,
);

void main() {
  group('loadEditablePlaylists', () {
    test('过滤不可编辑与缺少 cloudListId 的歌单', () async {
      final library = FakeUserLibraryApi(chunkSize: 200);
      library.items.addAll(<MusicUserPlaylist>[
        _playlist(cloudListId: 101, title: '可编辑'),
        _playlist(cloudListId: 102, title: '只读', editable: false),
        _playlist(cloudListId: null, title: '无云 id'),
        _playlist(cloudListId: 103, title: '未给 editable', editable: null),
      ]);
      final collection = KugouSongCollection(library, FakePlaylistWriteApi());

      final result = await collection.loadEditablePlaylists();

      expect(result.map((p) => p.cloudListId), <int>[101, 103]);
      expect(library.queries.single.page, 1);
      expect(library.queries.single.pageSize, 200);
    });

    test('匿名/接口异常原样透传', () async {
      final library = FakeUserLibraryApi(
        error: const KugouApiException('authentication', '需要登录'),
      );
      final collection = KugouSongCollection(library, FakePlaylistWriteApi());

      await expectLater(
        collection.loadEditablePlaylists(),
        throwsA(
          isA<KugouApiException>().having(
            (e) => e.kind,
            'kind',
            'authentication',
          ),
        ),
      );
    });
  });

  group('addToFavorite', () {
    test('优先选择 is_def == 2 的歌单并加歌', () async {
      final library = FakeUserLibraryApi(chunkSize: 200);
      library.items.addAll(<MusicUserPlaylist>[
        _playlist(cloudListId: 201, title: '收藏夹'),
        _playlist(cloudListId: 202, title: '我喜欢', defaultKind: 2),
      ]);
      final write = FakePlaylistWriteApi();
      final collection = KugouSongCollection(library, write);

      await collection.addToFavorite(testSong());

      final query = write.tracksAddQueries.single;
      expect(query.cloudListId, 202);
      expect(query.tracks.single.title, '歌曲');
      expect(query.tracks.single.hash, 'h501'.padLeft(32, '0'));
      expect(query.tracks.single.albumId, 42);
      expect(query.tracks.single.songId, 501);
    });

    test('is_def 缺失时按标题「我喜欢」兜底', () async {
      final library = FakeUserLibraryApi(chunkSize: 200);
      library.items.add(
        _playlist(cloudListId: 203, title: '我喜欢', defaultKind: 0),
      );
      final write = FakePlaylistWriteApi();
      final collection = KugouSongCollection(library, write);

      await collection.addToFavorite(testSong());

      expect(write.tracksAddQueries.single.cloudListId, 203);
    });

    test('找不到「我喜欢」时抛异常且不发加歌请求', () async {
      final library = FakeUserLibraryApi(chunkSize: 200);
      library.items.add(_playlist(cloudListId: 301, title: '普通歌单'));
      final write = FakePlaylistWriteApi();
      final collection = KugouSongCollection(library, write);

      await expectLater(
        collection.addToFavorite(testSong()),
        throwsA(
          isA<KugouApiException>().having((e) => e.kind, 'kind', 'not_found'),
        ),
      );
      expect(write.tracksAddQueries, isEmpty);
    });
  });

  group('addSongToPlaylist', () {
    test('把歌曲字段映射成 PlaylistTrackInput', () async {
      final write = FakePlaylistWriteApi();
      final collection = KugouSongCollection(FakeUserLibraryApi(), write);
      final playlist = _playlist(cloudListId: 777, title: '目标歌单');

      await collection.addSongToPlaylist(
        testSong(id: '501', title: '夜曲', albumId: '42', hash: 'a' * 32),
        playlist,
      );

      final query = write.tracksAddQueries.single;
      expect(query.cloudListId, 777);
      expect(query.tracks, hasLength(1));
      final track = query.tracks.single;
      expect(track.title, '夜曲');
      expect(track.hash, 'a' * 32);
      expect(track.albumId, 42);
      expect(track.songId, 501);
    });

    test('song 缺 hash 时抛 input 且不请求', () async {
      final write = FakePlaylistWriteApi();
      final collection = KugouSongCollection(FakeUserLibraryApi(), write);

      await expectLater(
        collection.addSongToPlaylist(
          testSong(hash: ''),
          _playlist(cloudListId: 888),
        ),
        throwsA(
          isA<KugouApiException>().having((e) => e.kind, 'kind', 'input'),
        ),
      );
      expect(write.tracksAddQueries, isEmpty);
    });

    test('albumId 非数字时抛 input 且不请求', () async {
      final write = FakePlaylistWriteApi();
      final collection = KugouSongCollection(FakeUserLibraryApi(), write);

      await expectLater(
        collection.addSongToPlaylist(
          testSong(albumId: 'not-a-number'),
          _playlist(cloudListId: 888),
        ),
        throwsA(
          isA<KugouApiException>().having((e) => e.kind, 'kind', 'input'),
        ),
      );
      expect(write.tracksAddQueries, isEmpty);
    });

    test('playlist 缺 cloudListId 时抛 input', () async {
      final collection = KugouSongCollection(
        FakeUserLibraryApi(),
        FakePlaylistWriteApi(),
      );

      await expectLater(
        collection.addSongToPlaylist(testSong(), _playlist(cloudListId: null)),
        throwsA(
          isA<KugouApiException>().having((e) => e.kind, 'kind', 'input'),
        ),
      );
    });
  });
}
