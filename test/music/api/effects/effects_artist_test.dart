/// 歌手音效端点测试（effects_artist.rs）：请求装配（effectsCatalog 主机 /
/// clearDefaults 语义 / Android 签名）+ CatalogRow 解码（audio_effect.rs）+
/// 信封分支 + input 校验。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/effects_artist.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';
import 'package:mimao/music/models/effects_models.dart';
import 'package:mimao/music/models/music_models.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// audio_effect.rs `CatalogRow` wire（flatten Sound + 行字段）。
Map<String, Object?> effectRow({
  int id = 17,
  Object? name = '歌手音效A',
  Object? sound = 'http://down.kugou.com/e/f17.wav',
  List<Object?> soundBk = const <Object?>[],
  Object? vpf,
  List<Object?> vpfBk = const <Object?>[],
  Object? privilege,
  Object? author = '调音师',
  Object? intro = '很带感',
  Object? iconUrl = 'http://imge.kugou.com/effect/{size}/f17.png',
  List<Object?> label = const <Object?>['燃'],
  Object? userCount,
  Object? filesize,
  Object? singerPrivilege,
}) => <String, Object?>{
  'id': id,
  if (name != null) 'name': name,
  if (sound != null) 'sound': sound,
  'sound_bk': soundBk,
  if (vpf != null) 'vpf': vpf,
  'vpf_bk': vpfBk,
  if (privilege != null) 'privilege': privilege,
  if (author != null) 'author': author,
  if (intro != null) 'intro': intro,
  if (iconUrl != null) 'icon_url': iconUrl,
  'label': label,
  if (userCount != null) 'user_count': userCount,
  if (filesize != null) 'filesize': filesize,
  if (singerPrivilege != null) 'singer_privilege': singerPrivilege,
};

/// audio_effect.rs `CatalogWire` 信封。
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

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes(catalogWire()));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
  });

  Future<MusicPage<MusicEffect>> fetch(EffectsArtistQuery query) =>
      fetchEffectsArtist(fakeEffectsSession(client, identity), query);

  test('请求装配：effectsCatalog 主机/路径/参数/clearDefaults/签名', () async {
    adapter.bytes = jsonBytes(catalogWire(data: <Object?>[effectRow()]));
    await fetch(const EffectsArtistQuery(page: 2, pageSize: 20));

    final captured = adapter.requests.single;
    expect(captured.method, 'GET');
    expect(
      '${adapter.captured.uri}'.startsWith(
        'http://mobilecdngz.kugou.com/api/v3/sound/list?',
      ),
      isTrue,
    );
    final query = captured.query;
    // query 恰好 = 端点参数 + signature（request_effect_catalog 的
    // clear_defaults=true：默认身份/应用字段一个都不注入）。
    expect(query, <String, String>{
      'plat': '2',
      'version': '12460',
      'apiver': '2',
      'sort': '1',
      'classify': '1',
      'page': '2',
      'pagesize': '20',
      'signature': query['signature']!,
    });
    for (final key in const <String>[
      'appid',
      'clientver',
      'clienttime',
      'dfid',
      'mid',
      'token',
      'userid',
      'uuid',
    ]) {
      expect(query.containsKey(key), isFalse, reason: 'clearDefaults 不注入 $key');
    }
    expect(
      query['signature'],
      kugouSignatureAndroid(<String, String>{
        'plat': '2',
        'version': '12460',
        'apiver': '2',
        'sort': '1',
        'classify': '1',
        'page': '2',
        'pagesize': '20',
      }, const <int>[]),
    );
    // 头：dfid/mid 是 send_endpoint 恒定头；clienttime 随默认清空而缺席；
    // 无 router（上游 Endpoint.router = None）。
    expect(captured.headers['dfid'], identity.dfid);
    expect(captured.headers['mid'], identity.mid);
    expect(captured.headers['clienttime'], isNull);
    expect(captured.headers['x-router'], isNull);
    expect(captured.headers['User-Agent'], kugouDefaultUserAgent);
  });

  test('解码：CatalogRow → MusicEffect（占位符/URL 升级去重/label/计数）', () async {
    adapter.bytes = jsonBytes(
      catalogWire(
        total: 88,
        data: <Object?>[
          effectRow(
            sound: 'http://down.kugou.com/e/f17.wav',
            soundBk: <Object?>[
              'https://down.kugou.com/e/f17.wav',
              'http://down.kugou.com/e/f17.wav',
              'http://down.kugou.com/e/f17_old.wav',
            ],
            vpf: 'http://down.kugou.com/v/f17.vpf',
            vpfBk: <Object?>['ftp://down.kugou.com/v/f17.vpf'],
            privilege: 0,
            userCount: 1234,
            filesize: 2048,
          ),
        ],
      ),
    );
    final page = await fetch(const EffectsArtistQuery(page: 3, pageSize: 20));
    expect(page.page, 3);
    expect(page.pageSize, 20);
    expect(page.total, 88);
    final effect = page.items.single;
    expect(effect.id, 17);
    expect(effect.name, '歌手音效A');
    expect(effect.author, '调音师');
    expect(effect.intro, '很带感');
    // domain.rs cover_url：{size} → 240。
    expect(effect.iconUrl, 'http://imge.kugou.com/effect/240/f17.png');
    expect(effect.labels, <String>['燃']);
    expect(effect.userCount, 1234);
    expect(effect.fileSize, 2048);
    expect(effect.source, 'artist');
    expect(effect.unavailableReason, isNull);
    // audio_effect.rs urls()：备用在前、主地址在后；http→https；去重保序。
    expect(effect.soundUrls, <String>[
      'https://down.kugou.com/e/f17.wav',
      'https://down.kugou.com/e/f17_old.wav',
    ]);
    // 非 https 备用（ftp）跳过，只剩升级后的主地址。
    expect(effect.vpfUrls, <String>['https://down.kugou.com/v/f17.vpf']);
  });

  test('授权限制：privilege/singer_privilege > 0 → 不可用；0/缺省 → 可用', () async {
    Future<String?> reasonOf(Map<String, Object?> extra) async {
      adapter.bytes = jsonBytes(
        catalogWire(
          data: <Object?>[
            <String, Object?>{...effectRow(), ...extra},
          ],
        ),
      );
      final page = await fetch(const EffectsArtistQuery(page: 1, pageSize: 20));
      return page.items.single.unavailableReason;
    }

    expect(await reasonOf(const <String, Object?>{}), isNull);
    expect(await reasonOf(<String, Object?>{'privilege': 0}), isNull);
    expect(
      await reasonOf(<String, Object?>{'privilege': 1}),
      '此音效需要上游授权，暂不支持下载',
    );
    expect(
      await reasonOf(<String, Object?>{'singer_privilege': 1}),
      '此音效需要上游授权，暂不支持下载',
    );
    expect(await reasonOf(<String, Object?>{'singer_privilege': 0}), isNull);
  });

  test('list 宽容：data 缺失/null/空 object → 空表；非空 object → decode', () async {
    for (final wire in <String>[
      jsonEncode(<String, Object?>{'status': 1, 'errcode': 0, 'total': 7}),
      jsonEncode(<String, Object?>{
        'status': 1,
        'errcode': 0,
        'total': 7,
        'data': null,
      }),
      jsonEncode(<String, Object?>{
        'status': 1,
        'errcode': 0,
        'total': 7,
        'data': <String, Object?>{},
      }),
    ]) {
      adapter.bytes = jsonBytes(wire);
      final page = await fetch(const EffectsArtistQuery(page: 1, pageSize: 20));
      expect(page.items, isEmpty);
      expect(page.total, 7);
    }
    adapter.bytes = jsonBytes(
      jsonEncode(<String, Object?>{
        'status': 1,
        'errcode': 0,
        'data': <String, Object?>{'x': 1},
      }),
    );
    await expectLater(
      fetch(const EffectsArtistQuery(page: 1, pageSize: 20)),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('text/optional 宽容：bool 文本 → 空串/空；数字文本互换；必填 id 缺失 → decode', () async {
    // text 字段收到 bool → ''（不制造 'true'）；optional 收到 bool → null。
    adapter.bytes = jsonBytes(
      catalogWire(
        total: true,
        data: <Object?>[
          effectRow(
            name: true,
            author: false,
            userCount: true,
            filesize: '999',
          ),
        ],
      ),
    );
    var page = await fetch(const EffectsArtistQuery(page: 1, pageSize: 20));
    expect(page.total, isNull, reason: 'optional 的 bool 非法值 → null');
    var effect = page.items.single;
    expect(effect.name, '');
    expect(effect.author, '');
    expect(effect.userCount, isNull);
    expect(effect.fileSize, 999, reason: '数字字符串按 exact 解析');

    // label：数字元素 → 文本；bool/object 元素 → decode（不静默丢弃）。
    adapter.bytes = jsonBytes(
      catalogWire(
        data: <Object?>[
          effectRow(label: <Object?>[1, 'x']),
        ],
      ),
    );
    page = await fetch(const EffectsArtistQuery(page: 1, pageSize: 20));
    expect(page.items.single.labels, <String>['1', 'x']);

    adapter.bytes = jsonBytes(
      catalogWire(
        data: <Object?>[
          effectRow(label: <Object?>[<String, Object?>{}]),
        ],
      ),
    );
    await expectLater(
      fetch(const EffectsArtistQuery(page: 1, pageSize: 20)),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );

    // Sound.id 是必填 scalar：缺失或 bool 都 decode 失败。
    adapter.bytes = jsonBytes(
      catalogWire(
        data: <Object?>[
          <String, Object?>{'name': 'x'},
        ],
      ),
    );
    await expectLater(
      fetch(const EffectsArtistQuery(page: 1, pageSize: 20)),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
    adapter.bytes = jsonBytes(
      catalogWire(
        data: <Object?>[
          <String, Object?>{'id': true, 'name': 'x'},
        ],
      ),
    );
    await expectLater(
      fetch(const EffectsArtistQuery(page: 1, pageSize: 20)),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('信封：errcode 非零 → business 带码；errcode=20018 仍是 business', () async {
    adapter.bytes = jsonBytes(
      jsonEncode(<String, Object?>{'status': 1, 'errcode': 30005, 'data': []}),
    );
    await expectLater(
      fetch(const EffectsArtistQuery(page: 1, pageSize: 20)),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 30005,
        ),
      ),
    );
    // effects 信封用 errcode：上游 authentication_expiration 只看 error_code/
    // msg 字段，所以 errcode=20018 走 success() → business(20018)。
    adapter.bytes = jsonBytes(
      jsonEncode(<String, Object?>{'status': 1, 'errcode': 20018, 'data': []}),
    );
    await expectLater(
      fetch(const EffectsArtistQuery(page: 1, pageSize: 20)),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 20018,
        ),
      ),
    );
  });

  test('信封：error_code=20018 或 msg 含「登录已过期」→ authentication', () async {
    adapter.bytes = jsonBytes(
      jsonEncode(<String, Object?>{
        'status': 1,
        'errcode': 0,
        'error_code': 20018,
        'data': [],
      }),
    );
    await expectLater(
      fetch(const EffectsArtistQuery(page: 1, pageSize: 20)),
      throwsA(
        predicate(
          (Object e) => e is KugouApiException && e.kind == 'authentication',
        ),
      ),
    );
    adapter.bytes = jsonBytes(
      jsonEncode(<String, Object?>{
        'status': 0,
        'errcode': 1,
        'msg': '用户登录已过期，请重新登录',
      }),
    );
    await expectLater(
      fetch(const EffectsArtistQuery(page: 1, pageSize: 20)),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException &&
              e.kind == 'authentication' &&
              // authentication_expiration 只从 error_code 字段取码；msg 路径
              // 的 errcode 不进 code（上游 error.code = None）。
              e.code == null,
        ),
      ),
    );
  });

  test('信封恢复：status 缺失但 errcode 非零 → business；全缺/非 JSON → decode', () async {
    // decode_envelope 恢复分支：结构解码失败时 errcode 非零 → business。
    adapter.bytes = jsonBytes(jsonEncode(<String, Object?>{'errcode': 30005}));
    await expectLater(
      fetch(const EffectsArtistQuery(page: 1, pageSize: 20)),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 30005,
        ),
      ),
    );
    adapter.bytes = jsonBytes(jsonEncode(<String, Object?>{'status': 0}));
    await expectLater(
      fetch(const EffectsArtistQuery(page: 1, pageSize: 20)),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 0,
        ),
      ),
    );
    adapter.bytes = jsonBytes(jsonEncode(<String, Object?>{'data': []}));
    await expectLater(
      fetch(const EffectsArtistQuery(page: 1, pageSize: 20)),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
    adapter.bytes = jsonBytes('not-json');
    await expectLater(
      fetch(const EffectsArtistQuery(page: 1, pageSize: 20)),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('input：page/pageSize 越界 → 音效分页无效；pageSize 50 合法', () async {
    for (final query in const <EffectsArtistQuery>[
      EffectsArtistQuery(page: 0, pageSize: 20),
      EffectsArtistQuery(page: -1, pageSize: 20),
      EffectsArtistQuery(page: 1, pageSize: 0),
      EffectsArtistQuery(page: 1, pageSize: 51),
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
    const EffectsArtistQuery(page: 1, pageSize: 50).validate();
  });
}
