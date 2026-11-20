/// 歌手目录端点测试：请求装配（无 x-router/无 kg-tid）+ 分组/筛选解码 +
/// errcode 信封分支 + 分类校验。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/artist_lists.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_error.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// lists.rs 采样结构（ErrcodeEnvelope + info/enu_list）。
String listsWire({
  Object? status = 1,
  Object? errcode = 0,
  Object? data,
}) => jsonEncode(<String, Object?>{
  'status': status,
  'errcode': errcode,
  if (data != null) 'data': data,
  if (data == null)
    'data': <String, Object?>{
      'timestamp': '1699000000',
      'info': <Object?>[
        <String, Object?>{
          'title': '热',
          'singer': <Object?>[
            <String, Object?>{
              'singerid': 123,
              'singername': '周杰伦',
              'imgurl': 'http://imge.kugou.com/stdmusic/{size}/av.png',
              'albumcount': 45,
              'songcount': '300',
              'fanscount': 999999,
              'mvcount': 6,
              'intro': '歌手简介',
              'descibe': 123,
              'is_settled': 1,
              'heat': 88,
              'heatoffset': '-5',
              'sortoffset': 3,
              'dycover': <String, Object?>{
                'first_frame_image': 'http://imge.kugou.com/dy/{size}/f.png',
              },
            },
            <String, Object?>{
              'singerid': '88',
              'singername': '林俊杰',
              'imgurl': '',
            },
          ],
        },
      ],
      'enu_list': <String, Object?>{
        'types': <Object?>[
          <String, Object?>{'key': 1, 'value': '华语男歌手', 'musician': '0'},
          <String, Object?>{'key': 2, 'value': '华语女歌手', 'musician': ''},
          <String, Object?>{'key': 3, 'value': '海外', 'musician': '4294967296'},
        ],
        'sextypes': <Object?>[
          <String, Object?>{'key': 1, 'value': '男歌手'},
          <String, Object?>{'key': 2, 'value': '女歌手'},
        ],
      },
    },
});

void main() {
  late CaptureAdapter adapter;
  late MusicSession session;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    session = fakeMusicSession(artistTestClient(adapter), artistTestIdentity());
  });

  test('请求装配：GET /ocean/v6/singer/list + 固定参数 + 无 x-router/kg-tid', () async {
    adapter.bytes = jsonBytes(listsWire());
    final directory = await fetchArtistLists(
      session,
      const MusicArtistListsQuery(sex: 1, category: 2, musician: 0),
    );
    expect(directory.groups, isNotEmpty);

    final request = adapter.requests.single;
    expect(request.method, 'GET');
    expect(
      request.path,
      startsWith('https://gateway.kugou.com/ocean/v6/singer/list'),
    );
    expect(request.headers.containsKey('x-router'), isFalse);
    expect(
      request.headers.containsKey('kg-tid'),
      isFalse,
      reason: '上游 request() 的 headers 为空',
    );
    final query = request.query;
    expect(query['musician'], '0');
    expect(query['sextype'], '1');
    expect(query['showtype'], '2');
    expect(query['type'], '2');
    expect(query['hotsize'], '100');
  });

  test('解码：分组/卡片字段/封面 {size}→240/字符串 singerid/descibe 数字文本化', () async {
    adapter.bytes = jsonBytes(listsWire());
    final directory = await fetchArtistLists(
      session,
      const MusicArtistListsQuery(sex: 1, category: 2, musician: 3),
    );

    expect(directory.timestamp, 1699000000);
    final group = directory.groups.single;
    expect(group.label, '热');
    final first = group.artists.first;
    expect(first.id, '123');
    expect(first.title, '周杰伦');
    expect(first.creator, '');
    expect(first.coverUrl, 'http://imge.kugou.com/stdmusic/240/av.png');
    expect(first.metadata.albumCount, 45);
    expect(first.metadata.songCount, 300, reason: '字符串型数字宽容');
    expect(first.metadata.fansCount, 999999);
    expect(first.metadata.mvCount, 6);
    expect(first.metadata.introduction, '歌手简介');
    expect(first.metadata.description, '123', reason: 'descibe 数字 → 文本');
    expect(first.metadata.settledCode, 1);
    expect(first.metadata.heat, 88);
    expect(first.metadata.heatChange, -5);
    expect(first.metadata.sortChange, 3);
    expect(
      first.metadata.dynamicFrameUrl,
      'http://imge.kugou.com/dy/240/f.png',
    );
    expect(group.artists[1].id, '88', reason: '字符串 singerid 标量宽容');
  });

  test(
    '筛选：类型 id=key:musician 文本/decimal u32 域；性别 id=key、musician 恒 0',
    () async {
      adapter.bytes = jsonBytes(listsWire());
      final directory = await fetchArtistLists(
        session,
        const MusicArtistListsQuery(sex: 1, category: 2, musician: 3),
      );

      expect(directory.typeFilters[0].id, '1:0');
      expect(directory.typeFilters[0].label, '华语男歌手');
      expect(directory.typeFilters[0].category, 1);
      expect(directory.typeFilters[0].musician, 0);
      expect(directory.typeFilters[1].id, '2:');
      expect(directory.typeFilters[1].musician, isNull, reason: '空文本 → null');
      expect(
        directory.typeFilters[2].musician,
        isNull,
        reason: '超出 u32 域 → null（id 仍保留原文）',
      );
      expect(directory.typeFilters[2].id, '3:4294967296');

      expect(directory.sexFilters[0].id, '1');
      expect(directory.sexFilters[0].label, '男歌手');
      expect(directory.sexFilters[0].category, 1);
      expect(directory.sexFilters[0].musician, 0);
      expect(directory.sexFilters[1].id, '2');
    },
  );

  test('enu_list 缺省 → 空筛选（object 宽容）；info 空对象 {} → 空分组', () async {
    adapter.bytes = jsonBytes(
      listsWire(data: <String, Object?>{'info': <Object?>[], 'timestamp': 5}),
    );
    var directory = await fetchArtistLists(
      session,
      const MusicArtistListsQuery(sex: 0, category: 0, musician: 0),
    );
    expect(directory.groups, isEmpty);
    expect(directory.sexFilters, isEmpty);
    expect(directory.typeFilters, isEmpty);
    expect(directory.timestamp, 5);

    adapter.bytes = jsonBytes('{"status":1,"errcode":0,"data":{"info":{}}}');
    directory = await fetchArtistLists(
      session,
      const MusicArtistListsQuery(sex: 0, category: 0, musician: 0),
    );
    expect(directory.groups, isEmpty, reason: '空 object 按 list 宽容');
  });

  test('结构缺陷：singer 缺 singerid / types 缺 key / data 缺失 → decode', () async {
    adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"info":[{"singer":[{"singername":"无 id"}]}]}}',
    );
    await expectLater(
      fetchArtistLists(
        session,
        const MusicArtistListsQuery(sex: 0, category: 0, musician: 0),
      ),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );

    adapter.bytes = jsonBytes(
      '{"status":1,"errcode":0,"data":{"enu_list":{"types":[{"value":"缺 key"}]}}}',
    );
    await expectLater(
      fetchArtistLists(
        session,
        const MusicArtistListsQuery(sex: 0, category: 0, musician: 0),
      ),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );

    adapter.bytes = jsonBytes('{"status":1,"errcode":0}');
    await expectLater(
      fetchArtistLists(
        session,
        const MusicArtistListsQuery(sex: 0, category: 0, musician: 0),
      ),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('业务失败：errcode 非 0 → business 带码（含 20018，不映射 authentication）', () async {
    adapter.bytes = jsonBytes(listsWire(status: 0, errcode: 2001));
    await expectLater(
      fetchArtistLists(
        session,
        const MusicArtistListsQuery(sex: 0, category: 0, musician: 0),
      ),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 2001,
        ),
      ),
    );

    adapter.bytes = jsonBytes(listsWire(status: 1, errcode: 20018));
    await expectLater(
      fetchArtistLists(
        session,
        const MusicArtistListsQuery(sex: 0, category: 0, musician: 0),
      ),
      throwsA(
        predicate((Object e) {
          final error = e is KugouApiException ? e : null;
          return error != null &&
              error.kind == 'business' &&
              error.code == 20018;
        }),
      ),
      reason:
          '上游 decode() 过期探测只看 error_code 键，errcode=20018 走 success → business',
    );
  });

  test('input 校验：sex/category 越界、musician 非 0/3 拒绝；合法边界通过', () async {
    void expectInput(MusicArtistListsQuery query) {
      try {
        query.validate();
        fail('应当抛 input');
      } on KugouApiException catch (e) {
        expect(e.kind, 'input');
      }
    }

    expectInput(const MusicArtistListsQuery(sex: 4, category: 1, musician: 0));
    expectInput(const MusicArtistListsQuery(sex: 1, category: 9, musician: 0));
    expectInput(const MusicArtistListsQuery(sex: 1, category: 1, musician: 1));
    expectInput(const MusicArtistListsQuery(sex: -1, category: 1, musician: 0));
    // 合法边界。
    const MusicArtistListsQuery(sex: 3, category: 8, musician: 3).validate();
    const MusicArtistListsQuery(sex: 0, category: 0, musician: 0).validate();
  });
}
