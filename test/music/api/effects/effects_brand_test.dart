/// 耳机品牌列表端点测试（effects_brand.rs）：请求装配 + Brand 行解码 +
/// 边界/业务失败/input 校验。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/effects_brand.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';
import 'package:mimao/music/models/effects_models.dart';
import 'package:mimao/music/models/music_models.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

/// effects_brand.rs `BrandWire` wire。
Map<String, Object?> brandRow({
  Object? brandId = 77,
  Object? brand = '森海塞尔',
  Object? logo = 'http://imge.kugou.com/brand/{size}/b77.png',
  Object? modelCount = 12,
}) => <String, Object?>{
  if (brandId != null) 'brand_id': brandId,
  if (brand != null) 'brand': brand,
  if (logo != null) 'logo': logo,
  if (modelCount != null) 'model_count': modelCount,
};

/// effects_brand.rs `Wire = ErrcodeEnvelope<Value>`。
String brandWire({
  int status = 1,
  int errcode = 0,
  Object? data = const <String, Object?>{'list': <Object?>[], 'total': 0},
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
    adapter = CaptureAdapter(jsonBytes(brandWire()));
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = KugouIdentity.anonymous();
  });

  Future<MusicPage<MusicEarphoneBrand>> fetch(EffectsBrandQuery query) =>
      fetchEffectsBrand(fakeEffectsSession(client, identity), query);

  test('请求装配：effectsCatalog 主机/路径/参数/clearDefaults/签名', () async {
    adapter.bytes = jsonBytes(
      brandWire(
        data: <String, Object?>{
          'list': <Object?>[brandRow()],
          'total': 2,
        },
      ),
    );
    await fetch(const EffectsBrandQuery(page: 1, pageSize: 20));

    final captured = adapter.requests.single;
    expect(captured.method, 'GET');
    expect(
      '${adapter.captured.uri}'.startsWith(
        'http://mobilecdngz.kugou.com/api/v5/earphone/get_brand?',
      ),
      isTrue,
    );
    final query = captured.query;
    // 只有 sort/page/pagesize + signature（clearDefaults：无默认注入）。
    expect(query, <String, String>{
      'sort': '1',
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
        'sort': '1',
        'page': '1',
        'pagesize': '20',
      }, const <int>[]),
    );
    expect(captured.headers['clienttime'], isNull);
    expect(captured.headers['dfid'], identity.dfid);
    expect(captured.headers['mid'], identity.mid);
  });

  test('解码：BrandWire → MusicEarphoneBrand（占位符/数字字符串 id/可选计数）', () async {
    adapter.bytes = jsonBytes(
      brandWire(
        data: <String, Object?>{
          'list': <Object?>[
            brandRow(),
            brandRow(brandId: '88', brand: '铁三角', logo: '', modelCount: null),
          ],
          'total': '13',
        },
      ),
    );
    final page = await fetch(const EffectsBrandQuery(page: 4, pageSize: 20));
    expect(page.page, 4);
    expect(page.pageSize, 20);
    expect(page.total, 13, reason: 'total 是 optional：数字字符串按 exact 解析');
    final first = page.items[0];
    expect(first.id, 77);
    expect(first.name, '森海塞尔');
    expect(first.iconUrl, 'http://imge.kugou.com/brand/240/b77.png');
    expect(first.modelCount, 12);
    final second = page.items[1];
    expect(second.id, 88, reason: 'brand_id 是 scalar：数字字符串精确解码');
    expect(second.modelCount, isNull, reason: 'model_count 缺省 → null');
  });

  test(
    '边界：data 缺失/非 object → decode；list 空 object → 空表；行缺 brand_id → decode',
    () async {
      // ErrcodeEnvelope.data 是 from_value::<Data>：缺 data / null / 数组都失败。
      for (final wire in <String>[
        jsonEncode(<String, Object?>{'status': 1, 'errcode': 0}),
        jsonEncode(<String, Object?>{'status': 1, 'errcode': 0, 'data': null}),
        jsonEncode(<String, Object?>{'status': 1, 'errcode': 0, 'data': []}),
      ]) {
        adapter.bytes = jsonBytes(wire);
        await expectLater(
          fetch(const EffectsBrandQuery(page: 1, pageSize: 20)),
          throwsA(predicate((Object e) => '$e'.contains('decode'))),
        );
      }
      // list 缺失/空 object → 空 brand 表（total 保留）。
      adapter.bytes = jsonBytes(brandWire(data: <String, Object?>{'total': 5}));
      var page = await fetch(const EffectsBrandQuery(page: 1, pageSize: 20));
      expect(page.items, isEmpty);
      expect(page.total, 5);
      adapter.bytes = jsonBytes(
        brandWire(
          data: <String, Object?>{'list': <String, Object?>{}, 'total': 5},
        ),
      );
      page = await fetch(const EffectsBrandQuery(page: 1, pageSize: 20));
      expect(page.items, isEmpty);
      // 行缺 brand_id（必填 scalar）→ decode。
      adapter.bytes = jsonBytes(
        brandWire(
          data: <String, Object?>{
            'list': <Object?>[<String, Object?>{}],
            'total': 1,
          },
        ),
      );
      await expectLater(
        fetch(const EffectsBrandQuery(page: 1, pageSize: 20)),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
      // text 字段 bool → ''；optional 字段负数超出 u64 域 → null。
      adapter.bytes = jsonBytes(
        brandWire(
          data: <String, Object?>{
            'list': <Object?>[
              <String, Object?>{
                'brand_id': 77,
                'brand': true,
                'model_count': -1,
              },
            ],
          },
        ),
      );
      page = await fetch(const EffectsBrandQuery(page: 1, pageSize: 20));
      expect(page.items.single.name, '');
      expect(page.items.single.modelCount, isNull);
    },
  );

  test('业务失败：status=0/errcode 非零 → business 带码', () async {
    adapter.bytes = jsonBytes(brandWire(status: 0, errcode: 6));
    await expectLater(
      fetch(const EffectsBrandQuery(page: 1, pageSize: 20)),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 6,
        ),
      ),
    );
  });

  test('input：分页越界 → 音效分页无效', () async {
    await expectLater(
      fetch(const EffectsBrandQuery(page: 0, pageSize: 20)),
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
