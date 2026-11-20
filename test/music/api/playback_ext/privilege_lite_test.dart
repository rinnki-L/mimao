/// 歌曲权益查询端点测试（privilege_lite.rs）：入参校验（1..100/32 位 hex/
/// 小写去重）、请求装配（router/body 键序/qualities 9 档/album_id 回退 0）、
/// 解码（primary + relate_goods/ogg/preview/qualitymap/extension 保留）、
/// 信封恢复与登录过期分支。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/privilege_lite.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';
import 'package:mimao/music/models/playback_ext_models.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

const String kHashA = '0123456789abcdef0123456789abcdef';
const String kHashB = 'FEDCBA9876543210FEDCBA9876543210';

/// 权益资源行 wire（privilege_lite.rs `Resource`：flatten Variant + 行字段）。
Map<String, Object?> resourceWire({
  Object? id = 730888,
  String albumId = '14421203',
  Object? albumAudioId = 339415062,
  String name = '稻香',
  String singername = '周杰伦',
  Object? albumname = '魔杰座',
  String hash = 'PRIMARYHASH0000000000000000AA',
  String quality = '128',
  Object? level = 1,
  Object? privilege = 10,
  Object? status = 0,
  Object? failProcess = 0,
  Object? payType = 3,
  Object? price = 0,
  Object? info = const <String, Object?>{
    'duration': 265430,
    'filesize': 100,
    'bitrate': 128,
    'extname': 'mp3',
    'image': 'http://imge.kugou.com/standard/{size}/a.png',
  },
  Object? errno = 0,
  Object? msg = 'ok',
  Object? transParam = const <String, Object?>{
    'language': '国语',
    'cid': '42',
    'ogg_128_hash': 'OGGAHASH0000000000000000000000',
    'ogg_128_filesize': 111,
    'hash_offset': <String, Object?>{
      'start_byte': 0,
      'end_byte': 65536,
      'start_ms': 0,
      'end_ms': 30000,
      'offset_hash': 'PREVIEWHASH00000000000000000000',
      'file_type': 0,
      'clip_hash': 'CLIPHASH0000000000000000000000AA',
    },
    'qualitymap': <String, Object?>{'attr0': 0, 'attr1': 2, 'bits': '0101'},
  },
  List<Object?> relateGoods = const <Object?>[
    <String, Object?>{
      '_msg': '',
      '_errno': 0,
      'hash': 'FLACHASH00000000000000000000AA',
      'quality': 'flac',
      'level': 3,
      'privilege': 10,
      'status': 0,
      'fail_process': 0,
      'pay_type': 3,
      'price': 0,
      'info': <String, Object?>{
        'duration': 265430,
        'filesize': 25325000,
        'bitrate': 900,
        'extname': 'flac',
        'image': 'http://imge.kugou.com/flac/{size}/a.png',
      },
    },
    <String, Object?>{
      '_msg': ' vip only ',
      '_errno': 20016,
      'hash': 'VIPERHASH00000000000000000000',
      'quality': 'viper_tape',
      'info': <String, Object?>{},
    },
  ],
}) => <String, Object?>{
  if (id != null) 'id': id,
  'album_id': albumId,
  if (albumAudioId != null) 'album_audio_id': albumAudioId,
  'name': name,
  'singername': singername,
  if (albumname != null) 'albumname': albumname,
  'hash': hash,
  'quality': quality,
  if (level != null) 'level': level,
  if (privilege != null) 'privilege': privilege,
  if (status != null) 'status': status,
  if (failProcess != null) 'fail_process': failProcess,
  if (payType != null) 'pay_type': payType,
  if (price != null) 'price': price,
  'info': info,
  'trans_param': transParam,
  'relate_goods': relateGoods,
  if (errno != null) '_errno': errno,
  if (msg != null) '_msg': msg,
};

String privilegeWire({
  int status = 1,
  int errorCode = 0,
  Object? data = const <Object?>[],
}) => jsonEncode(<String, Object?>{
  'status': status,
  'error_code': errorCode,
  'data': data,
});

PrivilegeLiteQuery queryOf({
  List<PrivilegeLiteResource> resources = const <PrivilegeLiteResource>[
    PrivilegeLiteResource(hash: kHashA),
  ],
}) => PrivilegeLiteQuery(resources: resources);

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes(privilegeWire()));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
  });

  Future<List<MusicResourcePrivileges>> fetch(PrivilegeLiteQuery query) =>
      fetchPrivilegeLite(fakePlaybackSession(client, identity), query);

  test('input：空/超 100/非法 hash/负 albumId → 参数无效；大小写归一后的重复 → 重复查询', () async {
    List<PrivilegeLiteResource> many(int count) => List.generate(
      count,
      (i) => PrivilegeLiteResource(hash: '$i'.padLeft(8, '0') * 4),
    );
    for (final query in <PrivilegeLiteQuery>[
      const PrivilegeLiteQuery(resources: <PrivilegeLiteResource>[]),
      PrivilegeLiteQuery(resources: many(101)),
      const PrivilegeLiteQuery(
        resources: <PrivilegeLiteResource>[
          PrivilegeLiteResource(hash: '0123456789ABCDEF'),
        ],
      ),
      PrivilegeLiteQuery(
        resources: <PrivilegeLiteResource>[
          PrivilegeLiteResource(hash: '$kHashA?'),
        ],
      ),
      const PrivilegeLiteQuery(
        resources: <PrivilegeLiteResource>[
          PrivilegeLiteResource(hash: kHashA, albumId: -1),
        ],
      ),
    ]) {
      await expectLater(
        fetch(query),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'input' &&
                e.message.contains('歌曲权益查询参数无效'),
          ),
        ),
      );
    }
    // BTreeSet 小写去重：仅大小写不同的两条 → 重复。
    await expectLater(
      fetch(
        PrivilegeLiteQuery(
          resources: <PrivilegeLiteResource>[
            PrivilegeLiteResource(hash: kHashA),
            PrivilegeLiteResource(hash: kHashA.toUpperCase()),
          ],
        ),
      ),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.message.contains('重复的歌曲权益查询'),
        ),
      ),
    );
    // 边界合法：恰好 100 条、albumId=0。
    await expectLater(
      fetch(
        PrivilegeLiteQuery(
          resources: List.generate(
            100,
            (i) => PrivilegeLiteResource(
              hash: '$i'.padLeft(4, '0') * 8,
              albumId: 0,
            ),
          ),
        ),
      ),
      completes,
    );
  });

  test('请求装配：POST/router/body 键序与值/hash 小写/album_id 回退 0/默认参数+签名', () async {
    await fetch(
      PrivilegeLiteQuery(
        resources: <PrivilegeLiteResource>[
          const PrivilegeLiteResource(hash: kHashA),
          PrivilegeLiteResource(hash: kHashB.toUpperCase(), albumId: 14421203),
        ],
      ),
    );

    final captured = adapter.requests.single;
    expect(captured.method, 'POST');
    expect(
      captured.path,
      'https://gateway.kugou.com/v2/get_res_privilege/lite',
    );
    expect(captured.headers['x-router'], 'media.store.kugou.com');
    // Body 键序 = serde 声明序；album_id：缺省 → 数字 0，已知 → 字符串；
    // hash 统一小写。
    expect(
      captured.bodyText,
      jsonEncode(<String, Object?>{
        'appid': 3116,
        'area_code': 1,
        'behavior': 'play',
        'clientver': 11440,
        'need_hash_offset': 1,
        'relate': 1,
        'support_verify': 1,
        'resource': <Object?>[
          <String, Object?>{
            'type': 'audio',
            'page_id': 0,
            'hash': kHashA,
            'album_id': 0,
          },
          <String, Object?>{
            'type': 'audio',
            'page_id': 0,
            'hash': kHashB.toLowerCase(),
            'album_id': '14421203',
          },
        ],
        'qualities': <String>[
          '128',
          '320',
          'flac',
          'high',
          'viper_atmos',
          'viper_tape',
          'viper_clear',
          'super',
          'multitrack',
        ],
      }),
    );
    // 普通 client.request：默认字段 + Android 签名（query 无端点参数）。
    final query = captured.query;
    expect(query['appid'], '3116');
    expect(query['clientver'], '11440');
    expect(query['dfid'], identity.dfid);
    expect(query['mid'], identity.mid);
    expect(query['uuid'], '-');
    final unsigned = <String, String>{...query}..remove('signature');
    expect(
      query['signature'],
      kugouSignatureAndroid(unsigned, utf8.encode(captured.bodyText)),
    );
    expect(query.containsKey('token'), isFalse);
    expect(query.containsKey('userid'), isFalse);
    expect(captured.headers['Content-Type'], 'application/json');
    expect(captured.headers['User-Agent'], kugouDefaultUserAgent);
  });

  test(
    '解码：primary（flatten 语义）+ relate_goods 档位 + ogg/preview/qualitymap/extension',
    () async {
      adapter.bytes = jsonBytes(privilegeWire(data: <Object?>[resourceWire()]));
      final resources = await fetch(queryOf());
      expect(resources, hasLength(1));
      final r = resources.single;
      expect(r.id, 730888);
      expect(r.albumId, '14421203');
      expect(r.songId, 339415062);
      expect(r.hash, 'PRIMARYHASH0000000000000000AA');
      expect(r.displayName, '稻香');
      expect(r.artistText, '周杰伦');
      expect(r.albumTitle, '魔杰座');
      // serde flatten：资源级 _msg/_errno 由 Resource 显式字段接住，primary 的
      // message/error_code 恒空（上游同构）。
      expect(r.primary.message, '');
      expect(r.primary.errorCode, isNull);
      expect(r.primary.hash, r.hash);
      expect(r.primary.quality, '128');
      expect(r.primary.level, 1);
      expect(r.primary.privilege, 10);
      expect(r.primary.serviceStatus, 0);
      expect(r.primary.failureCode, 0);
      expect(r.primary.paymentType, 3);
      expect(r.primary.priceUnits, 0);
      expect(r.primary.durationMs, 265430);
      expect(r.primary.sizeBytes, 100);
      expect(r.primary.bitRateBps, 128000);
      expect(r.primary.extension, 'mp3');
      expect(r.primary.coverUrl, 'http://imge.kugou.com/standard/240/a.png');
      // relate_goods 行的 _msg/_errno 归档位自身。
      expect(r.variants, hasLength(2));
      final flac = r.variants[0];
      expect(flac.quality, 'flac');
      expect(flac.errorCode, 0);
      expect(flac.privilege, 10);
      expect(flac.serviceStatus, 0);
      expect(flac.paymentType, 3);
      expect(flac.bitRateBps, 900000);
      expect(flac.coverUrl, 'http://imge.kugou.com/flac/240/a.png');
      final viper = r.variants[1];
      expect(viper.quality, 'viper_tape');
      expect(viper.errorCode, 20016);
      expect(viper.message, ' vip only ');
      expect(viper.durationMs, isNull);
      // ogg 文件事实。
      expect(r.oggStandard!.hash, 'OGGAHASH0000000000000000000000');
      expect(r.oggStandard!.sizeBytes, 111);
      expect(r.oggHigh, isNull);
      // preview/qualitymap/resource 级错误与语言。
      expect(r.preview!.endMs, 30000);
      expect(r.qualityMap!.attr1, 2);
      expect(r.resourceError, 0);
      expect(r.resourceMessage, 'ok');
      expect(r.language, '国语');
      // trans_param 未映射键（cid）保留进 presentation_extension。
      expect(r.presentationExtension, <String, Object?>{'cid': '42'});
    },
  );

  test(
    '解码宽容：relate_goods 缺失/空 object → 空表；info/trans_param 垃圾 → 默认；_errno 负数保留',
    () async {
      adapter.bytes = jsonBytes(
        privilegeWire(
          data: <Object?>[
            resourceWire(
              relateGoods: const <Object?>[],
              info: 'garbage',
              transParam: 42,
              errno: -7,
              msg: null,
              albumname: null,
              status: null,
            ),
          ],
        ),
      );
      final resources = await fetch(queryOf());
      final r = resources.single;
      expect(r.variants, isEmpty);
      expect(r.primary.durationMs, isNull);
      expect(r.primary.bitRateBps, isNull);
      expect(r.primary.extension, '');
      expect(r.primary.serviceStatus, isNull);
      expect(r.language, '');
      expect(r.oggStandard, isNull);
      expect(r.preview, isNull);
      expect(r.qualityMap, isNull);
      expect(r.presentationExtension, isEmpty);
      expect(r.resourceError, -7);
      expect(r.resourceMessage, '');
      expect(r.albumTitle, isNull);

      // data 缺失/null/空 object → 空资源表。
      for (final wire in <String>[
        jsonEncode(<String, Object?>{'status': 1, 'error_code': 0}),
        jsonEncode(<String, Object?>{
          'status': 1,
          'error_code': 0,
          'data': null,
        }),
        jsonEncode(<String, Object?>{
          'status': 1,
          'error_code': 0,
          'data': <String, Object?>{},
        }),
      ]) {
        adapter.bytes = jsonBytes(wire);
        expect(await fetch(queryOf()), isEmpty);
      }
    },
  );

  test('分支：业务失败/status 缺失恢复/20018 认证/relate_goods 行垃圾 → decode', () async {
    // status=0 + error_code=30005 → business(30005)。
    adapter.bytes = jsonBytes(privilegeWire(status: 0, errorCode: 30005));
    await expectLater(
      fetch(queryOf()),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 30005,
        ),
      ),
    );
    // decode_envelope 恢复：status 缺失但 error_code 非零 → business。
    adapter.bytes = jsonBytes(
      jsonEncode(<String, Object?>{'error_code': 30021}),
    );
    await expectLater(
      fetch(queryOf()),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 30021,
        ),
      ),
    );
    // 恢复：status=0 且 error_code 缺失 → business(0)。
    adapter.bytes = jsonBytes(jsonEncode(<String, Object?>{'status': 0}));
    await expectLater(
      fetch(queryOf()),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 0,
        ),
      ),
    );
    // error_code 必填：status=1 但缺 error_code → decode。
    adapter.bytes = jsonBytes(
      jsonEncode(<String, Object?>{'status': 1, 'data': []}),
    );
    await expectLater(
      fetch(queryOf()),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
    // 登录过期 → authentication（码值跟随 error_code）。
    adapter.bytes = jsonBytes(
      jsonEncode(<String, Object?>{'status': 1, 'error_code': 20018}),
    );
    await expectLater(
      fetch(queryOf()),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException &&
              e.kind == 'authentication' &&
              e.code == 20018,
        ),
      ),
    );
    // relate_goods 行非 object → 结构解码失败 → decode（error_code=0 不触发恢复）。
    adapter.bytes = jsonBytes(
      privilegeWire(
        data: <Object?>[
          resourceWire(relateGoods: <Object?>['garbage']),
        ],
      ),
    );
    await expectLater(
      fetch(queryOf()),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
    // 非 JSON → decode。
    adapter.bytes = jsonBytes('not-json');
    await expectLater(
      fetch(queryOf()),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });
}
