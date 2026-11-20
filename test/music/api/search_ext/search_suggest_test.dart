/// search_suggest 测试：searchtip 路由、四类限额参数、分组/建议解码宽容
/// （tags/jump 的 optional 语义）、decode_envelope 回退链与 input 校验。
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/search_suggest.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

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

  test(
    '请求装配：GET /v2/getSearchTip + x-router=searchtip + 四类限额/radiotip',
    () async {
      adapter.bytes = jsonBytes(
        '{"status":1,"error_code":0,"data":[],"SingerShortcut":null,"Shortcuts":null}',
      );
      await fetchSearchSuggest(
        session,
        const MusicSearchSuggestQuery(keyword: '周杰伦'),
      );

      expect(
        '${adapter.captured.uri}'.startsWith(
          'https://gateway.kugou.com/v2/getSearchTip?',
        ),
        isTrue,
      );
      expect(adapter.captured.headers['x-router'], 'searchtip.kugou.com');
      final query = capturedQuery(adapter.captured);
      expect(query['keyword'], '周杰伦');
      expect(query['AlbumTipCount'], '10', reason: '四个限额默认 10');
      expect(query['CorrectTipCount'], '10');
      expect(query['MVTipCount'], '10');
      expect(query['MusicTipCount'], '10');
      expect(query['radiotip'], '1');
      expect(
        query.length,
        13,
        reason: '6 端点参数 + 6 传输默认（含 clientver，未被覆盖）+ signature',
      );
    },
  );

  test('限额可自定义并进入对应参数', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":[]}');
    await fetchSearchSuggest(
      session,
      const MusicSearchSuggestQuery(
        keyword: 'k',
        albumLimit: 5,
        correctionLimit: 15,
        mvLimit: 25,
        musicLimit: 35,
      ),
    );
    final query = capturedQuery(adapter.captured);
    expect(query['AlbumTipCount'], '5');
    expect(query['CorrectTipCount'], '15');
    expect(query['MVTipCount'], '25');
    expect(query['MusicTipCount'], '35');
  });

  test('解码：分组/建议字段映射 + tags 数字项宽容 + jump 解码 + 扩展原样保留', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":['
      '{"LableName":"歌曲","RecordCount":"12","RecordDatas":['
      '{"HintInfo":"周杰伦 - 晴天","MatchCount":"3","Hot":"990","Use":"kugou",'
      '"subtitle":"副标题","tags":[1,"摇滚"],"jump":{"type":"song","id":"42","url":"https://j"}},'
      '{"HintInfo":"第二条","MatchCount":0,"Hot":null,"Use":"","subtitle":"",'
      '"tags":null,"jump":null}'
      ']},'
      '{"LableName":"空分组","RecordDatas":[]}'
      '],"SingerShortcut":{"singer":"ext"},"Shortcuts":[1,2]}',
    );
    final result = await fetchSearchSuggest(
      session,
      const MusicSearchSuggestQuery(keyword: 'k'),
    );

    expect(result.groups, hasLength(2));
    final group = result.groups[0];
    expect(group.title, '歌曲');
    expect(group.reportedCount, 12);
    final first = group.items[0];
    expect(first.text, '周杰伦 - 晴天');
    expect(first.matches, 3);
    expect(first.heat, 990);
    expect(first.source, 'kugou');
    expect(first.subtitle, '副标题');
    expect(first.tags, <String>['1', '摇滚'], reason: '数字项按 text 宽容成字符串');
    expect(first.jump?.kind, 'song');
    expect(first.jump?.id, 42);
    expect(first.jump?.url, 'https://j');
    final second = group.items[1];
    expect(second.matches, 0);
    expect(second.heat, isNull, reason: 'null → None');
    expect(second.tags, isNull);
    expect(second.jump, isNull);
    expect(result.groups[1].items, isEmpty);
    expect(result.singerShortcutExtension, <String, Object?>{
      'singer': 'ext',
    }, reason: '未建模扩展原样保留');
    expect(result.shortcutsExtension, <Object?>[1, 2]);
  });

  test('解码边界：tags 非法整体 null；jump 非 object → null；data 缺省/空对象回空', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":[{"LableName":"g","RecordDatas":['
      '{"HintInfo":"x","tags":true},'
      '{"HintInfo":"y","tags":[true]},'
      '{"HintInfo":"z","tags":"no"},'
      '{"HintInfo":"j","jump":"bad"}'
      ']}]}',
    );
    final result = await fetchSearchSuggest(
      session,
      const MusicSearchSuggestQuery(keyword: 'k'),
    );
    final items = result.groups.single.items;
    expect(items[0].tags, isNull, reason: 'bool 项让整个 tags 回 None');
    expect(items[1].tags, isNull);
    expect(items[2].tags, isNull, reason: '非数组 → None');
    expect(items[3].jump, isNull, reason: 'jump 字符串 → None');

    for (final body in <String>[
      '{"status":1,"error_code":0}',
      '{"status":1,"error_code":0,"data":null}',
      '{"status":1,"error_code":0,"data":{}}',
    ]) {
      adapter.bytes = jsonBytes(body);
      final empty = await fetchSearchSuggest(
        session,
        const MusicSearchSuggestQuery(keyword: 'k'),
      );
      expect(empty.groups, isEmpty, reason: body);
    }
  });

  test('回退链：payload 解码失败时 error_code!=0 或 status==0 → business(code)', () async {
    adapter.bytes = jsonBytes('{"error_code":152}');
    await expectLater(
      fetchSearchSuggest(session, const MusicSearchSuggestQuery(keyword: 'k')),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 152,
        ),
      ),
      reason:
          '缺少 status → decode 失败 → decode_envelope 回退：code!=0 → business(152)',
    );

    adapter.bytes = jsonBytes('{"status":0}');
    await expectLater(
      fetchSearchSuggest(session, const MusicSearchSuggestQuery(keyword: 'k')),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 0,
        ),
      ),
      reason: 'status==0 且无错误码 → business(0)',
    );

    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":"not-a-list"}',
    );
    await expectLater(
      fetchSearchSuggest(session, const MusicSearchSuggestQuery(keyword: 'k')),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
      reason: '成功信封下 data 非数组仍是 decode',
    );
  });

  test(
    '业务失败与登录过期：error_code=152 → business；error_code=20018 → authentication',
    () async {
      adapter.bytes = jsonBytes('{"status":0,"error_code":152,"data":[]}');
      await expectLater(
        fetchSearchSuggest(
          session,
          const MusicSearchSuggestQuery(keyword: 'k'),
        ),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException && e.kind == 'business' && e.code == 152,
          ),
        ),
      );

      adapter.bytes = jsonBytes('{"status":1,"error_code":20018,"data":[]}');
      await expectLater(
        fetchSearchSuggest(
          session,
          const MusicSearchSuggestQuery(keyword: 'k'),
        ),
        throwsA(
          predicate(
            (Object e) => e is KugouApiException && e.kind == 'authentication',
          ),
        ),
      );
    },
  );

  test('decode：分组项/建议项非 object → decode', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":[null]}');
    await expectLater(
      fetchSearchSuggest(session, const MusicSearchSuggestQuery(keyword: 'k')),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );

    adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":[{"LableName":"g","RecordDatas":[null]}]}',
    );
    await expectLater(
      fetchSearchSuggest(session, const MusicSearchSuggestQuery(keyword: 'k')),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('input：空关键词 / 限额 0 / 限额 101 / 默认限额合法', () async {
    for (final query in const <MusicSearchSuggestQuery>[
      MusicSearchSuggestQuery(keyword: '  '),
      MusicSearchSuggestQuery(keyword: 'k', albumLimit: 0),
      MusicSearchSuggestQuery(keyword: 'k', correctionLimit: 101),
      MusicSearchSuggestQuery(keyword: 'k', mvLimit: 0),
      MusicSearchSuggestQuery(keyword: 'k', musicLimit: 101),
    ]) {
      await expectLater(
        fetchSearchSuggest(session, query),
        throwsA(predicate((Object e) => '$e'.contains('input'))),
      );
    }
    const MusicSearchSuggestQuery(
      keyword: 'k',
      albumLimit: 1,
      correctionLimit: 100,
    ).validate();
  });
}
