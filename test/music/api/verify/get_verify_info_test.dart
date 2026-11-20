/// 验证挑战配置端点测试：请求装配（网关 / 无 router / body 字段）+ 成功解码
/// （provider/vendor 映射、list/optional 宽容）+ 业务失败与输入校验分支。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/get_verify_info.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/verify_models.dart';

import '../capture_adapter.dart';

/// 假会话：ensureDevice 直接返回给定身份，不联网、不落盘。
MusicSession _session(KugouClient client, KugouIdentity identity) =>
    MusicSession(
      client: client,
      ensureDevice: () async => identity,
      loadIdentity: () async => identity,
      saveIdentity: (_) async {},
    );

KugouIdentity _registeredIdentity() => KugouIdentity(
  userId: 42,
  token: 'tok',
  t1: 't1x',
  mid: 'midX',
  dfid: 'realDfid009',
  uuid: 'uuidX',
  guid: 'guidX',
  mac: '02:00:00:00:00:00',
  deviceName: '',
  renderFingerprint: '',
);

/// 最小可信 sms 挑战配置（v_type=32）。
String _smsEnvelope({Object? data}) =>
    jsonEncode(<String, Object?>{'status': 1, 'error_code': 0, 'data': data});

Map<String, Object?> _smsData() => <String, Object?>{
  'show': <String, Object?>{'msg': '请完成短信验证'},
  'verify_info': <String, Object?>{'scene': 'login'},
  'extinfo': <String, Object?>{},
  'v_type_list': <Object?>[32, 34],
  'partnerid_map': <String, Object?>{'partner1': 5, 'partner2': '-3'},
  'sessionid': 'sess-1',
  'txappid': 'tx-app-1',
  'url': 'KGCodeGT|captcha.gif|',
  'business': 3001,
  'v_type': 32,
  'vde': 7,
};

void main() {
  test('全链路：POST 网关无 router，body 带全字段并随身份带 userid', () async {
    final adapter = CaptureAdapter(jsonBytes(_smsEnvelope(data: _smsData())));
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    final identity = _registeredIdentity();

    final config = await fetchVerifyInfo(
      _session(client, identity),
      const MusicVerifyInfoQuery(eventId: 'evt-1'),
    );

    expect(config.provider, 'sms');
    expect(adapter.requests, hasLength(1));
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(
      '${adapter.captured.uri}'.startsWith('https://gateway.kugou.com/'),
      isTrue,
    );
    expect(request.path.endsWith('/verifyservice/v3/get_verify_info'), isTrue);
    // 无 x-router（上游 router=None）。
    expect(request.headers.containsKey('x-router'), isFalse);
    // 身份不走匿名改写：query 带账号字段，dfid 保持真值。
    expect(request.query['userid'], '42');
    expect(request.query['token'], 'tok');
    expect(request.query['dfid'], 'realDfid009');
    expect(request.query['signature'], isNotNull);
    // body：serde_json BTreeMap 键序；userid 用当前身份。
    expect(
      request.bodyText,
      '{"edt":"","eventid":"evt-1","i":"","platid":2,'
      '"rtype":1,"sid":"","userid":42,"wasm":1}',
    );
  });

  test('成功解码：字段逐条映射（vendor/vendor 前缀大小写、partner 负数）', () async {
    final adapter = CaptureAdapter(jsonBytes(_smsEnvelope(data: _smsData())));
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    final config = await fetchVerifyInfo(
      _session(client, KugouIdentity.anonymous()),
      const MusicVerifyInfoQuery(eventId: 'evt-1'),
    );
    expect(config.provider, 'sms');
    expect(config.vendor, 'GT');
    expect(config.appId, 'tx-app-1');
    expect(config.displayMessage, '请完成短信验证');
    expect(config.verificationType, 32);
    expect(config.availableTypes, <int>[32, 34]);
    expect(config.businessId, 3001);
    expect(config.sessionId, 'sess-1');
    expect(config.partnerStatus, <String, int>{'partner1': 5, 'partner2': -3});
    expect(config.protocolFlag, 7);
  });

  test('provider/vendor 映射分支（已知 v_type、KGCodeTX 前缀、未知、大小写）', () async {
    Object? dataWith(int vType, String url) => <String, Object?>{
      'v_type': vType,
      'url': url,
    };
    Future<MusicVerificationConfiguration> fetch(Object? data) async {
      final adapter = CaptureAdapter(jsonBytes(_smsEnvelope(data: data)));
      return fetchVerifyInfo(
        _session(
          KugouClient(dio: Dio()..httpClientAdapter = adapter),
          KugouIdentity.anonymous(),
        ),
        const MusicVerifyInfoQuery(eventId: 'evt-1'),
      );
    }

    expect((await fetch(dataWith(34, ''))).provider, 'real_name');
    expect((await fetch(dataWith(36, ''))).provider, 'bind_phone');
    expect((await fetch(dataWith(38, ''))).provider, 'login');
    expect((await fetch(dataWith(51, ''))).provider, 'account_risk');
    // tencent 只认**未 trim** url 的 `KGCodeTX|` 前缀；已知 v_type 优先。
    expect((await fetch(dataWith(99, 'KGCodeTX|x'))).provider, 'tencent');
    expect((await fetch(dataWith(99, ' KGCodeTX|x'))).provider, 'unsupported');
    expect((await fetch(dataWith(99, ''))).provider, 'unsupported');
    // vendor：trim 后取 `|` 前缀大写；不在名单（含无 `|`）→ UNKNOWN。
    expect((await fetch(dataWith(32, 'kgcodesm|a'))).vendor, 'SM');
    expect((await fetch(dataWith(32, ' KGCODEKG2|b'))).vendor, 'KG2');
    expect((await fetch(dataWith(32, 'KGCodeYD|c'))).vendor, 'YD');
    expect((await fetch(dataWith(32, 'kgcodekg|d'))).vendor, 'KG');
    expect((await fetch(dataWith(32, 'unknownvendor|e'))).vendor, 'UNKNOWN');
    expect((await fetch(dataWith(32, 'noseparator'))).vendor, 'UNKNOWN');
  });

  test(
    'list/optional 宽容：v_type_list 空 object、缺省；business/sessionid 非法',
    () async {
      Object? data() => <String, Object?>{
        'show': <String, Object?>{'msg': 123}, // msg 只认字符串 → ''
        'v_type_list': <String, Object?>{}, // 空 object → 空表
        'partnerid_map': <String, Object?>{},
        'sessionid': 456, // 数字 → 字符串
        'business': 'abc', // 不可解 → null
        'vde': null, // 显式 null → null
        'v_type': '51', // 数字字符串（scalar 宽容）
        // txappid / url 缺省 → ''
      };
      final adapter = CaptureAdapter(jsonBytes(_smsEnvelope(data: data())));
      final config = await fetchVerifyInfo(
        _session(
          KugouClient(dio: Dio()..httpClientAdapter = adapter),
          KugouIdentity.anonymous(),
        ),
        const MusicVerifyInfoQuery(eventId: 'evt-1'),
      );
      expect(config.provider, 'account_risk');
      expect(config.availableTypes, isEmpty);
      expect(config.partnerStatus, isEmpty);
      expect(config.sessionId, '456');
      expect(config.businessId, isNull);
      expect(config.protocolFlag, isNull);
      expect(config.appId, '');
      expect(config.displayMessage, '');
      // url 缺省 '' → vendor UNKNOWN。
      expect(config.vendor, 'UNKNOWN');
    },
  );

  test('input 校验：事件 trim 空 / 字节超长 → 验证事件无效，且不发请求', () async {
    final adapter = CaptureAdapter(jsonBytes(_smsEnvelope(data: _smsData())));
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    final session = _session(client, KugouIdentity.anonymous());
    for (final eventId in <String>['', '   ', 'a' * 4097, '中' * 1366]) {
      await expectLater(
        fetchVerifyInfo(session, MusicVerifyInfoQuery(eventId: eventId)),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'input' &&
                e.message == '验证事件无效',
          ),
        ),
        // 「中」是 3 字节：1366 个 = 4098 字节 > 4096（Dart length 只有 1366）。
        reason: 'eventId 字节数=${utf8.encode(eventId).length}',
      );
    }
    // 4096 字节内（1365 个「中」= 4095 字节）不超限——请求正常发出。
    final boundary = CaptureAdapter(jsonBytes(_smsEnvelope(data: _smsData())));
    await fetchVerifyInfo(
      _session(
        KugouClient(dio: Dio()..httpClientAdapter = boundary),
        KugouIdentity.anonymous(),
      ),
      MusicVerifyInfoQuery(eventId: '中' * 1365),
    );
    expect(boundary.requests, hasLength(1));
    expect(adapter.requests, isEmpty);
  });

  test('业务失败：status=0 error_code=20028 → business（事件不存在）', () async {
    final adapter = CaptureAdapter(
      jsonBytes('{"status":0,"error_code":20028,"data":null}'),
    );
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    await expectLater(
      fetchVerifyInfo(
        _session(client, KugouIdentity.anonymous()),
        const MusicVerifyInfoQuery(eventId: 'evt-1'),
      ),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 20028,
        ),
      ),
    );
  });

  test('登录过期（msg 含「登录已过期」）→ authentication', () async {
    final adapter = CaptureAdapter(
      jsonBytes('{"status":0,"msg":"用户登录已过期，请重新登录"}'),
    );
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    await expectLater(
      fetchVerifyInfo(
        _session(client, KugouIdentity.anonymous()),
        const MusicVerifyInfoQuery(eventId: 'evt-1'),
      ),
      throwsA(
        predicate(
          (Object e) => e is KugouApiException && e.kind == 'authentication',
        ),
      ),
    );
  });

  test('解码分支：data 非 object / v_type 缺失 / map 容器非法 → decode', () async {
    Future<Object?> decodeKind(Object? data) async {
      final adapter = CaptureAdapter(jsonBytes(_smsEnvelope(data: data)));
      try {
        await fetchVerifyInfo(
          _session(
            KugouClient(dio: Dio()..httpClientAdapter = adapter),
            KugouIdentity.anonymous(),
          ),
          const MusicVerifyInfoQuery(eventId: 'evt-1'),
        );
      } on KugouApiException catch (error) {
        return error.kind;
      }
      return null;
    }

    // data:null（事件无效的服务端形态）按 decode 处理——但上游是先判
    // success 再解 data，status=0 时仍是 business（上一用例）。
    expect(await decodeKind(null), 'decode');
    expect(await decodeKind(<Object?>[]), 'decode');
    // v_type 必填。
    expect(
      await decodeKind(<String, Object?>{'v_type_list': <Object?>[]}),
      'decode',
    );
    // show 出现但不是 object（含 null）。
    expect(
      await decodeKind(<String, Object?>{'v_type': 32, 'show': 3}),
      'decode',
    );
    expect(
      await decodeKind(<String, Object?>{'v_type': 32, 'show': null}),
      'decode',
    );
    // v_type_list 元素非法。
    expect(
      await decodeKind(<String, Object?>{
        'v_type': 32,
        'v_type_list': <Object?>[true],
      }),
      'decode',
    );
    // partnerid_map 容器/值非法。
    expect(
      await decodeKind(<String, Object?>{
        'v_type': 32,
        'partnerid_map': <Object?>[],
      }),
      'decode',
    );
    expect(
      await decodeKind(<String, Object?>{
        'v_type': 32,
        'partnerid_map': <String, Object?>{'p': true},
      }),
      'decode',
    );
    // txappid 出现但不是标量。
    expect(
      await decodeKind(<String, Object?>{
        'v_type': 32,
        'txappid': <String, Object?>{},
      }),
      'decode',
    );
  });
}
