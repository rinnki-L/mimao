/// MusicStore（MobX）测试：搜索成功/失败/空态/状态翻转。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_store.dart';

class _FakeApi implements MusicApi {
  _FakeApi({this.throwOnSearch});

  final Object? throwOnSearch;
  int calls = 0;

  @override
  Future<MusicPage<MusicSong>> searchSongs({
    required String keyword,
    int page = 1,
    int pageSize = 30,
  }) async {
    calls++;
    final error = throwOnSearch;
    if (error != null) throw error;
    if (keyword == '空') {
      return const MusicPage<MusicSong>(items: <MusicSong>[]);
    }
    return MusicPage<MusicSong>(
      page: 1,
      total: 2,
      items: <MusicSong>[
        MusicSong(
          id: '1',
          hash: 'h1',
          title: '$keyword 之一',
          artists: const <MusicArtistRef>[MusicArtistRef(name: '歌手')],
          albumId: '',
          albumTitle: '',
          coverUrl: '',
        ),
        MusicSong(
          id: '2',
          hash: 'h2',
          title: '$keyword 之二',
          artists: const <MusicArtistRef>[],
          albumId: '',
          albumTitle: '',
          coverUrl: '',
        ),
      ],
    );
  }

  @override
  Future<KugouIdentity> ensureDevice() async => const KugouIdentity.empty();

  @override
  Future<KugouIdentity?> currentIdentity() async => null;
}

void main() {
  test('搜索成功：结果入表、关键词回显、错误清空', () async {
    final api = _FakeApi();
    final store = MusicStore(api);

    await store.search('  周杰伦  ');
    expect(api.calls, 1);
    expect(store.results.length, 2);
    expect(store.results.first.title, '周杰伦 之一');
    expect(store.lastKeyword, '周杰伦', reason: '关键词先 trim');
    expect(store.error, isNull);
    expect(store.isLoading, isFalse);
    expect(store.searched, isTrue);
  });

  test('搜索失败：结果清空、错误可见、loading 复位', () async {
    final store = MusicStore(_FakeApi(throwOnSearch: StateError('超时')));
    await store.search('k');
    expect(store.results, isEmpty);
    expect(store.error, contains('搜索失败'));
    expect(store.error, contains('超时'));
    expect(store.isLoading, isFalse);
    expect(store.searched, isTrue);
  });

  test('空结果：不报错，searched 翻转供空态文案区分', () async {
    final store = MusicStore(_FakeApi());
    await store.search('空');
    expect(store.results, isEmpty);
    expect(store.error, isNull);
    expect(store.searched, isTrue);
  });

  test('空白关键词不触发请求', () async {
    final api = _FakeApi();
    final store = MusicStore(api);
    await store.search('   ');
    expect(api.calls, 0);
    expect(store.searched, isFalse);
  });

  test('连续搜索覆盖旧结果', () async {
    final store = MusicStore(_FakeApi());
    await store.search('第一首');
    await store.search('第二首');
    expect(store.results.map((s) => s.title), <String>['第二首 之一', '第二首 之二']);
    expect(store.lastKeyword, '第二首');
  });
}
