/// top_playlist 端点测试：input 校验（十进制分类）+ body 装配（key 签名/
/// 字符串化 withtag/withsong）+ special_list 解码 + 空分类宽容。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/top_playlist.dart';
import 'package:mimao/music/client/kugou_error.dart';

import '../capture_adapter.dart';

import 'rank_fixture.dart';

void main() {
  late RankFixture fixture;

  setUp(() {
    fixture = RankFixture();
  });

  test('input 校验：category_id 必须是十进制 u64（按上游 decimal）', () {
    void expectInput(String categoryId, [String reason = '']) {
      try {
        MusicTopPlaylistQuery(categoryId: categoryId).validate();
        fail('应当抛 input${reason.isEmpty ? '' : '（$reason）'}：$categoryId');
      } on KugouApiException catch (e) {
        expect(e.kind, 'input');
      }
    }

    expectInput('');
    expectInput('660.0');
    expectInput('-1');
    expectInput(' 660');
    expectInput('abc');
    expectInput('9' * 21, '溢出 u64');

    // 合法形态：纯数字 / 前导零 / 前导 +（Rust u64::from_str 接受）。
    MusicTopPlaylistQuery(categoryId: '660').validate();
    MusicTopPlaylistQuery(categoryId: '0660').validate();
    MusicTopPlaylistQuery(categoryId: '+660').validate();
  });

  test('请求装配：POST /v2/special_recommend + router + 完整 body（key=md5）', () async {
    fixture.adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":{}}');
    await fetchTopPlaylists(
      fixture.session,
      const MusicTopPlaylistQuery(categoryId: '660'),
    );

    final request = fixture.adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, 'https://gateway.kugou.com/v2/special_recommend');
    expect(request.headers['x-router'], 'specialrec.service.kugou.com');
    expect(request.query.containsKey('signature'), isTrue);

    final body = jsonDecode(request.bodyText) as Map<String, Object?>;
    expect(body['appid'], 3116);
    expect(body['mid'], fixture.identity.mid);
    expect(body['clientver'], 11440);
    expect(body['platform'], 'android');
    expect(body['userid'], 0);
    expect(body['module_id'], 1);
    expect(body['page'], 1);
    expect(body['pagesize'], 30);
    expect(body['req_multi'], 1);
    expect(body['retrun_min'], 5);
    expect(body['return_special_falg'], 1);

    final special = body['special_recommend']! as Map<String, Object?>;
    expect(special, <String, Object?>{
      'withtag': '1',
      'withsong': '0',
      'sort': 1,
      'ugc': 1,
      'is_selected': 0,
      'withrecommend': 1,
      'area_code': 1,
      'categoryid': '660',
    }, reason: 'withtag/withsong 上游刻意发字符串；categoryid 字符串透传');

    // key = md5("3116LnT6xpN3khm36zse0QzvmgTZ3waWdRSA11440{clienttime}")。
    final clienttime = body['clienttime']! as String;
    expect(clienttime, matches(RegExp(r'^\d+$')));
    final digest = md5.convert(
      utf8.encode('3116LnT6xpN3khm36zse0QzvmgTZ3waWdRSA11440$clienttime'),
    );
    expect(body['key'], digest.toString());
  });

  test('解码：special_list 条目映射 + 标签 id 缺省归空串 + 封面回退', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"special_list":['
      '{"global_collection_id":"gcol_9","specialid":"402","specialname":"榜单精选",'
      '"nickname":"制作人","imgurl":"http://imge.kugou.com/stdmusic/{size}/p.png",'
      '"suid":5,"pic":"http://imge.kugou.com/kpic/{size}/n.png","intro":"intro",'
      '"tags":[{"tag_id":31,"tag_name":"流行"},{"tag_name":"无id标签"}],'
      '"play_count":"999","collectcount":12,"publishtime":"2026-11-01",'
      '"type":0,"from":3,"flexible_cover":"http://imge.kugou.com/stdmusic/{size}/f.png"}'
      ']}}',
    );
    final cards = await fetchTopPlaylists(
      fixture.session,
      const MusicTopPlaylistQuery(categoryId: '660'),
    );

    final card = cards.single;
    expect(card.id, 'gcol_9');
    expect(card.title, '榜单精选');
    expect(card.creator, '制作人');
    expect(card.coverUrl, 'http://imge.kugou.com/stdmusic/240/p.png');
    expect(card.songCount, isNull, reason: '上游 song_count 恒 None');
    expect(card.metadata.publicId, 402);
    expect(card.metadata.creatorId, 5);
    expect(
      card.metadata.creatorAvatarUrl,
      'http://imge.kugou.com/kpic/240/n.png',
    );
    expect(card.metadata.description, 'intro');
    expect(card.metadata.tags.map((t) => t.id), <String>['31', '']);
    expect(card.metadata.tags.map((t) => t.name), <String>['流行', '无id标签']);
    expect(card.metadata.playCount, 999);
    expect(card.metadata.collectionCount, 12);
    expect(card.metadata.publishedAt, '2026-11-01');
    expect(card.metadata.sourceCode, 3, reason: 'wire from 键');
    expect(card.metadata.kindCode, 0, reason: 'wire type 键，0 也保留');
    expect(
      card.metadata.alternateCoverUrl,
      'http://imge.kugou.com/stdmusic/240/f.png',
    );
  });

  test('成功分类无 special_list（OlexpIds / null / {}）→ 空表不报错', () async {
    for (final body in <String>[
      '{"status":1,"error_code":0,"data":{"OlexpIds":"category-experiment"}}',
      '{"status":1,"error_code":0,"data":{"special_list":null}}',
      '{"status":1,"error_code":0,"data":{"special_list":{}}}',
      '{"status":1,"error_code":0,"data":{}}',
    ]) {
      fixture.adapter.bytes = jsonBytes(body);
      expect(
        await fetchTopPlaylists(
          fixture.session,
          const MusicTopPlaylistQuery(categoryId: '660'),
        ),
        isEmpty,
        reason: body,
      );
    }
  });

  test('tags 空对象宽容；error_code 失败 → business；条目非 object → decode', () async {
    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"special_list":['
      '{"global_collection_id":"g","specialname":"s","nickname":"n","tags":{}}'
      ']}}',
    );
    final cards = await fetchTopPlaylists(
      fixture.session,
      const MusicTopPlaylistQuery(categoryId: '660'),
    );
    expect(cards.single.metadata.tags, isEmpty);

    fixture.adapter.bytes = jsonBytes(
      '{"status":0,"error_code":152,"data":{}}',
    );
    await expectLater(
      fetchTopPlaylists(
        fixture.session,
        const MusicTopPlaylistQuery(categoryId: '660'),
      ),
      throwsA(predicate((Object e) => '$e'.contains('business'))),
    );

    fixture.adapter.bytes = jsonBytes(
      '{"status":1,"error_code":0,"data":{"special_list":[7]}}',
    );
    await expectLater(
      fetchTopPlaylists(
        fixture.session,
        const MusicTopPlaylistQuery(categoryId: '660'),
      ),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('校验失败不发起请求', () async {
    await expectLater(
      fetchTopPlaylists(
        fixture.session,
        const MusicTopPlaylistQuery(categoryId: 'abc'),
      ),
      throwsA(predicate((Object e) => '$e'.contains('input'))),
    );
    expect(fixture.adapter.requests, isEmpty);
  });
}
