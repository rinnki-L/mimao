/// 品牌耳机型号音效端点测试（effects_brand_detail.rs + audio_effect.rs
/// `Headphone`）：请求装配 + 型号行解码（id 取嵌套 sound.id 而非 model_id）+
/// is_unlocked 分支 + 严格 list 元素 + input 校验。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/effects_brand_detail.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';
import 'package:mimao/music/models/effects_models.dart';
import 'package:mimao/music/models/music_models.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// audio_effect.rs `Sound` wire（id 必填 scalar）。
Map<String, Object?> defaultSound({Object? id = 5753, Object? privilege}) =>
    <String, Object?>{
      if (id != null) 'id': id,
      'name': 'HD560S 音效',
      'sound': 'https://down.kugou.com/hp/5753.wav',
      if (privilege != null) 'privilege': privilege,
    };

/// audio_effect.rs `Headphone` wire（sound 键缺席 → Rust 缺字段 decode）。
Map<String, Object?> headphoneRow({
  Object? model = 'HD 560S',
  Object? modelIcon = 'http://imge.kugou.com/hp/{size}/hd560s.png',
  Object? isUnlocked = 1,
  Object? modelId = 9001,
  Map<String, Object?>? sound,
}) => <String, Object?>{
  if (modelId != null) 'model_id': modelId,
  if (model != null) 'model': model,
  if (modelIcon != null) 'model_icon': modelIcon,
  if (isUnlocked != null) 'is_unlocked': isUnlocked,
  if (sound != null) 'sound': sound,
};

/// effects_brand_detail.rs `Wire`：ErrcodeEnvelope + Data{list,total}。
String getModelsWire({
  int status = 1,
  int errcode = 0,
  Object? data = const <String, Object?>{'list': <Object?>[]},
}) => jsonEncode(<String, Object?>{
  'status': status,
  'errcode': errcode,
  'data': data,
});

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes(getModelsWire()));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
  });

  Future<MusicPage<MusicEffect>> fetch(EffectsBrandDetailQuery query) =>
      fetchEffectsBrandDetail(fakeEffectsSession(client, identity), query);

  test('请求装配：effectsCatalog 主机/路径/brand_id 参数/clearDefaults/签名', () async {
    adapter.bytes = jsonBytes(
      getModelsWire(
        data: <String, Object?>{
          'list': <Object?>[headphoneRow(sound: defaultSound())],
        },
      ),
    );
    await fetch(
      const EffectsBrandDetailQuery(page: 1, pageSize: 20, brandId: 77),
    );

    final captured = adapter.requests.single;
    expect(captured.method, 'GET');
    expect(
      '${adapter.captured.uri}'.startsWith(
        'http://mobilecdngz.kugou.com/api/v5/earphone/get_model?',
      ),
      isTrue,
    );
    final query = captured.query;
    expect(query, <String, String>{
      'brand_id': '77',
      'page': '1',
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
        'brand_id': '77',
        'page': '1',
        'pagesize': '20',
      }, const <int>[]),
    );
    expect(captured.headers['clienttime'], isNull);
    expect(captured.headers['dfid'], identity.dfid);
    expect(captured.headers['mid'], identity.mid);
  });

  test(
    '解码：Headphone → MusicEffect（id 取 sound.id；model 覆盖 name；固定 intro）',
    () async {
      adapter.bytes = jsonBytes(
        getModelsWire(
          data: <String, Object?>{
            'list': <Object?>[headphoneRow(sound: defaultSound())],
            'total': 1,
          },
        ),
      );
      final page = await fetch(
        const EffectsBrandDetailQuery(page: 2, pageSize: 20, brandId: 77),
      );
      expect(page.page, 2);
      expect(page.pageSize, 20);
      expect(page.total, 1);
      final effect = page.items.single;
      // 上游 fixture 断言：id 来自嵌套 sound.id（5753），不是 model_id（9001）。
      expect(effect.id, 5753);
      expect(effect.name, 'HD 560S');
      expect(effect.author, '');
      expect(effect.intro, '针对对应耳机型号调校，请选择与你的设备一致的型号。');
      expect(effect.iconUrl, 'http://imge.kugou.com/hp/240/hd560s.png');
      expect(effect.labels, isEmpty);
      expect(effect.userCount, isNull);
      expect(effect.fileSize, isNull);
      expect(effect.source, 'headphone');
      expect(effect.soundUrls, <String>['https://down.kugou.com/hp/5753.wav']);
      expect(effect.unavailableReason, isNull, reason: 'is_unlocked=1 已解锁');
    },
  );

  test('is_unlocked 分支：!=1 → 未解锁；缺省/1 → 空；privilege>0 的覆写顺序', () async {
    Future<String?> reasonOf(Map<String, Object?> overrides) async {
      adapter.bytes = jsonBytes(
        getModelsWire(
          data: <String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                ...headphoneRow(sound: defaultSound()),
                ...overrides,
              },
            ],
          },
        ),
      );
      final page = await fetch(
        const EffectsBrandDetailQuery(page: 1, pageSize: 20, brandId: 77),
      );
      return page.items.single.unavailableReason;
    }

    expect(await reasonOf(<String, Object?>{'is_unlocked': 0}), '此耳机音效尚未解锁');
    expect(await reasonOf(<String, Object?>{'is_unlocked': 2}), '此耳机音效尚未解锁');
    expect(await reasonOf(<String, Object?>{'is_unlocked': null}), isNull);
    expect(await reasonOf(<String, Object?>{}), isNull);
    // base() 的授权限制在 is_unlocked=1 时保留。
    expect(
      await reasonOf(<String, Object?>{'sound': defaultSound(privilege: 1)}),
      '此音效需要上游授权，暂不支持下载',
    );
    // is_unlocked != 1 覆写 base 的授权限制（headphone() 后写）。
    expect(
      await reasonOf(<String, Object?>{
        'is_unlocked': 0,
        'sound': defaultSound(privilege: 1),
      }),
      '此耳机音效尚未解锁',
    );
  });

  test(
    'list 元素严格解码：缺 sound / sound 为 null / 缺 id / 非 object → 整页 decode',
    () async {
      Future<void> expectDecode(Object? row) async {
        adapter.bytes = jsonBytes(
          getModelsWire(
            data: <String, Object?>{
              'list': <Object?>[row],
            },
          ),
        );
        await expectLater(
          fetch(
            const EffectsBrandDetailQuery(page: 1, pageSize: 20, brandId: 77),
          ),
          throwsA(predicate((Object e) => '$e'.contains('decode'))),
        );
      }

      // Headphone.sound 必填：键缺席 / 显式 null / 非 object 都失败。
      await expectDecode(<String, Object?>{'model': 'X'});
      await expectDecode(<String, Object?>{'model': 'X', 'sound': null});
      await expectDecode(<String, Object?>{'model': 'X', 'sound': 'text'});
      // Sound.id 必填 scalar。
      await expectDecode(headphoneRow(sound: <String, Object?>{'name': 'x'}));
      await expectDecode('not-an-object-row');
    },
  );

  test('list 宽容：缺 list / 空 object → 空表；data 缺失 → decode', () async {
    adapter.bytes = jsonBytes(getModelsWire());
    var page = await fetch(
      const EffectsBrandDetailQuery(page: 1, pageSize: 20, brandId: 77),
    );
    expect(page.items, isEmpty);
    adapter.bytes = jsonBytes(
      getModelsWire(
        data: <String, Object?>{'list': <String, Object?>{}, 'total': 3},
      ),
    );
    page = await fetch(
      const EffectsBrandDetailQuery(page: 1, pageSize: 20, brandId: 77),
    );
    expect(page.items, isEmpty);
    expect(page.total, 3);
    adapter.bytes = jsonBytes(
      jsonEncode(<String, Object?>{'status': 1, 'errcode': 0}),
    );
    await expectLater(
      fetch(const EffectsBrandDetailQuery(page: 1, pageSize: 20, brandId: 77)),
      throwsA(predicate((Object e) => '$e'.contains('decode'))),
    );
  });

  test('业务失败：errcode 非零 → business 带码', () async {
    adapter.bytes = jsonBytes(getModelsWire(status: 1, errcode: 30005));
    await expectLater(
      fetch(const EffectsBrandDetailQuery(page: 1, pageSize: 20, brandId: 77)),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 30005,
        ),
      ),
    );
  });

  test('input：brandId 0 → 耳机品牌无效；分页越界 → 音效分页无效（paging 先判）', () async {
    await expectLater(
      fetch(const EffectsBrandDetailQuery(page: 1, pageSize: 20, brandId: 0)),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException &&
              e.kind == 'input' &&
              e.message.contains('耳机品牌无效'),
        ),
      ),
    );
    await expectLater(
      fetch(const EffectsBrandDetailQuery(page: 0, pageSize: 20, brandId: 77)),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException &&
              e.kind == 'input' &&
              e.message.contains('音效分页无效'),
        ),
      ),
    );
  });
}
