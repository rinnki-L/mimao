/// 音效商城目录端点测试（get_model.rs）：sort 白名单/paging 校验、请求装配
/// （普通签名请求——默认字段不清理，区别于 G6 的 clearDefaults 目录）、
/// 复用 effects_models 的 market 目录解码。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/get_model.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';
import 'package:mimao/music/models/effects_models.dart';
import 'package:mimao/music/models/music_models.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// audio_effect.rs `CatalogWire` 信封 + CatalogRow 行。
String catalogWire({
  int status = 1,
  int errcode = 0,
  Object? total = 88,
  Object? data = const <Object?>[],
}) => jsonEncode(<String, Object?>{
  'status': status,
  'errcode': errcode,
  if (total != null) 'total': total,
  'data': data,
});

Map<String, Object?> marketRow({
  int id = 17,
  String name = '商城音效A',
  String author = '调音师',
  String intro = '很带感',
  String iconUrl = 'http://imge.kugou.com/effect/{size}/f17.png',
}) => <String, Object?>{
  'id': id,
  'name': name,
  'sound': 'http://down.kugou.com/e/f17.wav',
  'sound_bk': <Object?>['ftp://down.kugou.com/e/f17.wav'],
  'vpf': 'http://down.kugou.com/v/f17.vpf',
  'vpf_bk': <Object?>[],
  'privilege': 0,
  'author': author,
  'intro': intro,
  'icon_url': iconUrl,
  'label': <Object?>['燃'],
  'user_count': 1234,
  'filesize': 2048,
  'singer_privilege': 0,
};

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes(catalogWire()));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
  });

  Future<MusicPage<MusicEffect>> fetch(GetModelQuery query) =>
      fetchGetModel(fakePlaybackSession(client, identity), query);

  test('input：sort 只允许 2/3/4；paging 复用 audio_effect 校验', () async {
    for (final sort in <int>[1, 5, 0, -1]) {
      await expectLater(
        fetch(GetModelQuery(page: 1, pageSize: 20, sort: sort)),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'input' &&
                e.message.contains('音效排序无效'),
          ),
        ),
      );
    }
    for (final query in <GetModelQuery>[
      const GetModelQuery(page: 0, pageSize: 20, sort: 2),
      const GetModelQuery(page: 1, pageSize: 0, sort: 2),
      const GetModelQuery(page: 1, pageSize: 51, sort: 2),
    ]) {
      await expectLater(
        fetch(query),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'input' &&
                e.message.contains('音效分页无效'),
          ),
        ),
      );
    }
  });

  test('请求装配：GET 网关路径/9 个端点参数/普通签名注入默认字段（无 clearDefaults）', () async {
    adapter.bytes = jsonBytes(catalogWire(data: <Object?>[marketRow()]));
    await fetch(const GetModelQuery(page: 2, pageSize: 30, sort: 4));

    final captured = adapter.requests.single;
    expect(captured.method, 'GET');
    expect(captured.path, 'https://gateway.kugou.com/ocean/v6/sound/list');
    expect(captured.headers['x-router'], isNull);
    final query = captured.query;
    // 端点参数逐键对齐（pagesize 而非 page_size）。
    expect(query['super_vip'], '1');
    expect(query['sound_ver'], '2');
    expect(query['apiver'], '3');
    expect(query['classify'], '2,3');
    expect(query['plat'], '2');
    expect(query['privilege'], '1');
    expect(query['page'], '2');
    expect(query['pagesize'], '30');
    expect(query['sort'], '4');
    // 普通 client.request：默认字段全部注入（clearDefaults=false 的语义差异）。
    expect(query['appid'], '3116');
    expect(query['clientver'], '11440');
    expect(query['clienttime'], matches(RegExp(r'^\d+$')));
    expect(query['dfid'], identity.dfid);
    expect(query['mid'], identity.mid);
    expect(query['uuid'], '-');
    final unsigned = <String, String>{...query}..remove('signature');
    expect(query['signature'], kugouSignatureAndroid(unsigned, const <int>[]));
    expect(query.containsKey('token'), isFalse);
    expect(query.containsKey('userid'), isFalse);
  });

  test('解码：market 目录行 → MusicEffect（source=market）；errcode 业务失败', () async {
    adapter.bytes = jsonBytes(
      catalogWire(total: 88, data: <Object?>[marketRow()]),
    );
    final page = await fetch(
      const GetModelQuery(page: 3, pageSize: 30, sort: 3),
    );
    expect(page.page, 3);
    expect(page.pageSize, 30);
    expect(page.total, 88);
    final effect = page.items.single;
    expect(effect.id, 17);
    expect(effect.name, '商城音效A');
    expect(effect.author, '调音师');
    expect(effect.intro, '很带感');
    expect(effect.iconUrl, 'http://imge.kugou.com/effect/240/f17.png');
    expect(effect.source, 'market');
    expect(effect.userCount, 1234);
    expect(effect.fileSize, 2048);
    expect(effect.unavailableReason, isNull);
    // 非 https 备用被跳过，主地址升级 https。
    expect(effect.soundUrls, <String>['https://down.kugou.com/e/f17.wav']);

    adapter.bytes = jsonBytes(
      jsonEncode(<String, Object?>{'status': 1, 'errcode': 30005, 'data': []}),
    );
    await expectLater(
      fetch(const GetModelQuery(page: 1, pageSize: 20, sort: 2)),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 30005,
        ),
      ),
    );
  });
}
