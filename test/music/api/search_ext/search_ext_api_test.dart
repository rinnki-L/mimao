/// search_ext_api 测试：MusicSearchExtApi 九个方法与顶层 fetch 函数的转调
/// 关系（防「方法绑错端点」的装配回归），顺带覆盖各端点路径特征。
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/search.dart';
import 'package:mimao/music/api/search_ext_api.dart';
import 'package:mimao/music/api/search_lyric.dart';
import 'package:mimao/music/api/search_suggest.dart';
import 'package:mimao/music/api/sidedt.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;
  late KugouSearchExtApi api;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
    api = KugouSearchExtApi(fakeMusicSession(client, identity));
  });

  test('九个方法逐一转调到对应端点（method + path + 关键参数）', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":{}}');
    await api.searchAlbums(const SearchSongsQuery(keyword: 'k'));
    expect(adapter.captured.uri.path, '/v1/search/album');
    expect(capturedQuery(adapter.captured)['category'], '1');

    await api.searchArtists(const SearchSongsQuery(keyword: 'k'));
    expect(adapter.captured.uri.path, '/v1/search/author');

    await api.searchPlaylists(const SearchSongsQuery(keyword: 'k'));
    expect(adapter.captured.uri.path, '/v1/search/special');

    await api.searchLyrics(const SearchSongsQuery(keyword: 'k'));
    expect(adapter.captured.uri.path, '/v1/search/lyric');

    adapter.bytes = jsonBytes('{"status":1,"errcode":0,"data":{}}');
    await api.searchDefault();
    expect(adapter.captured.uri.path, '/searchnofocus/v1/search_no_focus_word');
    expect(adapter.captured.method, 'POST');
    expect(adapter.requests.last.bodyText, contains('"vip_type":65530'));

    await api.searchHot();
    expect(adapter.captured.uri.path, '/api/v3/search/hot_tab');
    expect(capturedQuery(adapter.captured)['navid'], '1');

    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":[]}');
    await api.searchSuggest(const MusicSearchSuggestQuery(keyword: 'k'));
    expect(adapter.captured.uri.path, '/v2/getSearchTip');
    expect(capturedQuery(adapter.captured)['keyword'], 'k');

    adapter.bytes = jsonBytes('{"status":200,"candidates":[]}');
    await api.searchLyric(
      const MusicSearchLyricQuery.keywords(
        keywords: 'k',
        durationMs: 1,
        allCandidates: false,
      ),
    );
    expect(
      '${adapter.captured.uri}'.startsWith(
        'https://lyrics.kugou.com/v1/search',
      ),
      isTrue,
    );

    adapter.bytes = jsonBytes('{"status":1,"error_code":0}');
    await api.sideDt(
      const MusicSideDtQuery(eventId: 'e', verifyType: 23, proof: 'p'),
      // KugouSearchExtApi 不透传测试参数；指纹/信封用安全随机即可。
    );
    expect(adapter.captured.uri.path, '/v4/verify_user_info');

    expect(adapter.requests, hasLength(9));
  });

  test('searchLyric 委托保持 clearDefaults 语义（query 无传输默认）', () async {
    adapter.bytes = jsonBytes('{"status":200,"candidates":[]}');
    await api.searchLyric(
      const MusicSearchLyricQuery.keywords(
        keywords: 'k',
        durationMs: 1,
        allCandidates: false,
      ),
    );
    final query = capturedQuery(adapter.captured);
    expect(query.containsKey('dfid'), isFalse);
    expect(query.containsKey('mid'), isFalse);
    expect(query.containsKey('clienttime'), isFalse);
    expect(query.containsKey('signature'), isTrue);
  });
}
