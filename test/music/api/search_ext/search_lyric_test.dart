/// search_lyric 测试：clearDefaults 语义（query 只有端点 8 参数 + 签名）、
/// lyrics 主机、Hash/Keywords 两变体装配、候选解码、404/200/500 三态。
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/search_lyric.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;
  late MusicSession session;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
    session = fakeMusicSession(client, identity);
  });

  test('请求装配（hash 变体）：lyrics 主机 + query 恰为端点 8 参数 + 签名（clearDefaults）', () async {
    adapter.bytes = jsonBytes(
      '{"status":200,"candidates":[{"id":"137010759","accesskey":"AK",'
      '"singer":"歌手A","nickname":"昵称","song":"歌名","duration":269000,'
      '"product_from":"pf","language":"zh","krctype":1,"score":90,"contenttype":0}]}',
    );
    final candidates = await fetchSearchLyric(
      session,
      const MusicSearchLyricQuery.hash(
        hash: 'HASH001',
        songId: 7301,
        durationMs: 269000,
        allCandidates: true,
      ),
    );
    expect(candidates, isNotEmpty);

    expect(
      '${adapter.captured.uri}'.startsWith(
        'https://lyrics.kugou.com/v1/search?',
      ),
      isTrue,
      reason: '走 lyrics 主机（Origin::Lyrics）',
    );
    expect(adapter.captured.method, 'GET');
    expect(
      adapter.captured.headers.containsKey('x-router'),
      isFalse,
      reason: 'router=None',
    );

    final query = capturedQuery(adapter.captured);
    expect(query['album_audio_id'], '7301');
    expect(query['appid'], '3116', reason: '端点参数自带的 appid/clientver，不是注入默认');
    expect(query['clientver'], '11440');
    expect(query['duration'], '269000');
    expect(query['hash'], 'HASH001');
    expect(query['keyword'], '');
    expect(query['lrctxt'], '1');
    expect(query['man'], 'yes');
    // clearDefaults 语义：传输默认 appid/mid/dfid/clienttime/token/userid/uuid
    // 一个都不进 query。
    expect(
      query.keys.any(
        (key) => const <String>[
          'mid',
          'dfid',
          'clienttime',
          'token',
          'userid',
          'uuid',
        ].contains(key),
      ),
      isFalse,
      reason: 'request_lyric_search 清空默认参数（clearDefaults=true）',
    );
    expect(query.length, 9, reason: '端点 8 参数 + signature');

    // 仍有 Android 签名（对端点参数 + 空 body 自验）。
    final signature = query.remove('signature');
    expect(signature, kugouSignatureAndroid(query, const <int>[]));

    // 传输头仍带设备指纹（request.rs 固定 dfid/mid 头），但没有 clienttime 头。
    expect(adapter.captured.headers['dfid'], identity.dfid);
    expect(adapter.captured.headers['mid'], identity.mid);
    expect(adapter.captured.headers.containsKey('clienttime'), isFalse);
  });

  test(
    'keywords 变体：keyword trim/hash/album_audio_id=0/man 随 allCandidates',
    () async {
      adapter.bytes = jsonBytes('{"status":200,"candidates":[]}');
      await fetchSearchLyric(
        session,
        const MusicSearchLyricQuery.keywords(
          keywords: '  周杰伦 - 晴天  ',
          durationMs: 269000,
          allCandidates: true,
        ),
      );
      var query = capturedQuery(adapter.captured);
      expect(query['keyword'], '周杰伦 - 晴天', reason: 'keywords 在 params 阶段 trim');
      expect(query['hash'], '');
      expect(query['album_audio_id'], '0');
      expect(query['duration'], '269000');
      expect(query['man'], 'yes');

      await fetchSearchLyric(
        session,
        const MusicSearchLyricQuery.keywords(
          keywords: '晴天',
          durationMs: 269000,
          allCandidates: false,
        ),
      );
      query = capturedQuery(adapter.captured);
      expect(query['man'], 'no', reason: 'best 匹配模式');
    },
  );

  test(
    '解码：候选字段映射/krctype→word_timed/contenttype→scrollable/duration 毫秒透传',
    () async {
      adapter.bytes = jsonBytes(
        '{"status":200,"candidates":['
        '{"id":"137010759","accesskey":"AK1","singer":"歌手A","nickname":"昵称",'
        '"song":"歌名","duration":"269000","product_from":"pf","language":"zh",'
        '"krctype":1,"score":90,"contenttype":0},'
        '{"id":"2","accesskey":"AK2","singer":"歌手B","nickname":"",'
        '"song":"歌名2","duration":180000,"product_from":"","language":"",'
        '"krctype":2,"score":"0","contenttype":2}'
        ']}',
      );
      final candidates = await fetchSearchLyric(
        session,
        const MusicSearchLyricQuery.keywords(
          keywords: 'k',
          durationMs: 269000,
          allCandidates: false,
        ),
      );
      expect(candidates, hasLength(2));
      final first = candidates[0];
      expect(first.sourceId, '137010759');
      expect(first.accessKey, 'AK1');
      expect(first.artist, '歌手A');
      expect(first.nickname, '昵称');
      expect(first.title, '歌名');
      expect(first.durationMs, 269000, reason: '候选表 duration 本身是毫秒，不乘 1000');
      expect(first.sourceLabel, 'pf');
      expect(first.language, 'zh');
      expect(first.wordTimed, isTrue, reason: 'krctype=1 → 逐字歌词');
      expect(first.scrollable, isTrue, reason: 'contenttype=0 → 可滚动');
      expect(first.sourceFormatCode, 1);
      expect(first.contentTypeCode, 0);
      expect(first.score, 90);

      final second = candidates[1];
      expect(second.wordTimed, isFalse, reason: 'krctype=2 → 非逐字');
      expect(second.scrollable, isFalse, reason: 'contenttype=2 → 不可滚动');
      expect(second.score, 0, reason: '字符串 0 也是有效分数');
    },
  );

  test('krctype/contenttype 未提供或未知码 → word_timed/scrollable null', () async {
    adapter.bytes = jsonBytes(
      '{"status":200,"candidates":['
      '{"id":"1","accesskey":"AK","singer":"","nickname":"","song":"s",'
      '"product_from":"","language":""}'
      ']}',
    );
    final candidates = await fetchSearchLyric(
      session,
      const MusicSearchLyricQuery.keywords(
        keywords: 'k',
        durationMs: 1,
        allCandidates: false,
      ),
    );
    final candidate = candidates.single;
    expect(candidate.wordTimed, isNull);
    expect(candidate.scrollable, isNull);
    expect(candidate.sourceFormatCode, isNull);
    expect(candidate.contentTypeCode, isNull);
    expect(candidate.durationMs, isNull);
  });

  test('三态：404+空候选 → 空表；status=200 无候选 → 空表；404/500 其它 → business', () async {
    adapter.bytes = jsonBytes('{"status":404,"candidates":[]}');
    expect(
      await fetchSearchLyric(
        session,
        const MusicSearchLyricQuery.keywords(
          keywords: 'k',
          durationMs: 1,
          allCandidates: false,
        ),
      ),
      isEmpty,
      reason: '404 且 candidates 恰为空表 → 无候选（不是错误）',
    );

    adapter.bytes = jsonBytes('{"status":200}');
    expect(
      await fetchSearchLyric(
        session,
        const MusicSearchLyricQuery.keywords(
          keywords: 'k',
          durationMs: 1,
          allCandidates: false,
        ),
      ),
      isEmpty,
      reason: 'candidates 缺省 → unwrap_or_default',
    );

    adapter.bytes = jsonBytes('{"status":404}');
    await expectLater(
      fetchSearchLyric(
        session,
        const MusicSearchLyricQuery.keywords(
          keywords: 'k',
          durationMs: 1,
          allCandidates: false,
        ),
      ),
      throwsA(predicate((Object e) => '$e'.contains('business'))),
      reason: '404 但 candidates 缺失 → business',
    );

    adapter.bytes = jsonBytes('{"status":500,"candidates":[]}');
    await expectLater(
      fetchSearchLyric(
        session,
        const MusicSearchLyricQuery.keywords(
          keywords: 'k',
          durationMs: 1,
          allCandidates: false,
        ),
      ),
      throwsA(predicate((Object e) => '$e'.contains('business'))),
    );
  });

  test('候选表非法 → 整表当「无候选」（optional 宽容），不是 decode', () async {
    adapter.bytes = jsonBytes('{"status":200,"candidates":[{"id":true}]}');
    expect(
      await fetchSearchLyric(
        session,
        const MusicSearchLyricQuery.keywords(
          keywords: 'k',
          durationMs: 1,
          allCandidates: false,
        ),
      ),
      isEmpty,
      reason: 'text 字段出现 bool → Vec 解码失败 → optional 回 None → 空表',
    );

    adapter.bytes = jsonBytes('{"status":200,"candidates":"x"}');
    expect(
      await fetchSearchLyric(
        session,
        const MusicSearchLyricQuery.keywords(
          keywords: 'k',
          durationMs: 1,
          allCandidates: false,
        ),
      ),
      isEmpty,
    );
  });

  test(
    '登录过期：error_code=20018 → authentication；decode：根非 object/status 缺失',
    () async {
      adapter.bytes = jsonBytes(
        '{"status":200,"error_code":20018,"candidates":[]}',
      );
      await expectLater(
        fetchSearchLyric(
          session,
          const MusicSearchLyricQuery.keywords(
            keywords: 'k',
            durationMs: 1,
            allCandidates: false,
          ),
        ),
        throwsA(
          predicate(
            (Object e) => e is KugouApiException && e.kind == 'authentication',
          ),
        ),
      );

      adapter.bytes = jsonBytes('{"candidates":[]}');
      await expectLater(
        fetchSearchLyric(
          session,
          const MusicSearchLyricQuery.keywords(
            keywords: 'k',
            durationMs: 1,
            allCandidates: false,
          ),
        ),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );

      adapter.bytes = jsonBytes('"array-root"');
      await expectLater(
        fetchSearchLyric(
          session,
          const MusicSearchLyricQuery.keywords(
            keywords: 'k',
            durationMs: 1,
            allCandidates: false,
          ),
        ),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
    },
  );
}
