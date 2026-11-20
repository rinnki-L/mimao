/// 验证码发送端点测试：请求装配（匿名身份改写 / router / body）+ 成功、
/// 业务失败、解码宽容与输入校验分支（CaptureAdapter 离线全链路）。
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/captcha_sent.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/verify_api.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

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

void main() {
  test('全链路：成功返回 true；请求只保留 mid（清账号、dfid 置 -）', () async {
    final adapter = CaptureAdapter(jsonBytes('{"status":1,"error_code":0}'));
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    final identity = _registeredIdentity();

    final sent = await fetchCaptchaSent(
      _session(client, identity),
      const MusicCaptchaSentQuery(mobile: '13912345678'),
    );

    expect(sent, isTrue);
    expect(adapter.requests, hasLength(1));
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(
      '${adapter.captured.uri}'.startsWith('https://gateway.kugou.com/'),
      isTrue,
    );
    expect(request.path.endsWith('/v7/send_mobile_code'), isTrue);
    // router：login.user.kugou.com（x-router 头）。
    expect(request.headers['x-router'], 'login.user.kugou.com');
    // 匿名改写：userid/token/t1 清空、dfid 置 "-"；mid 原样保留。
    expect(request.query['dfid'], '-');
    expect(request.query['mid'], 'midX');
    expect(request.query.containsKey('token'), isFalse);
    expect(request.query.containsKey('userid'), isFalse);
    expect(request.headers['dfid'], '-');
    expect(request.headers['mid'], 'midX');
    expect(request.query['signature'], isNotNull);
    // body：{businessid:5, mobile, plat:3}（serde_json BTreeMap 键序）。
    expect(
      request.bodyText,
      '{"businessid":5,"mobile":"13912345678","plat":3}',
    );
  });

  test('匿名身份同样发码（session 走组接口 KugouVerifyApi）', () async {
    final adapter = CaptureAdapter(jsonBytes('{"status":1,"error_code":0}'));
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    final api = KugouVerifyApi(_session(client, KugouIdentity.anonymous()));

    final sent = await api.captchaSent(
      const MusicCaptchaSentQuery(mobile: '15900000000'),
    );

    expect(sent, isTrue);
    expect(adapter.requests.single.query['dfid'], '-');
    expect(adapter.requests.single.query['mid'], isNotNull);
    expect(adapter.requests.single.query['mid'], isNot(''));
  });

  test('手机号非法（位数 / 前缀 / 非数字）→ input，且不发请求', () async {
    final adapter = CaptureAdapter(jsonBytes('{"status":1,"error_code":0}'));
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    final session = _session(client, KugouIdentity.anonymous());
    for (final mobile in <String>[
      '1391234567', // 10 位
      '139123456789', // 12 位
      '23912345678', // 非 1 开头
      '1391234567a', // 含字母
      '1391234 678', // 含空白
    ]) {
      await expectLater(
        fetchCaptchaSent(session, MusicCaptchaSentQuery(mobile: mobile)),
        throwsA(
          predicate(
            (Object e) =>
                e is KugouApiException &&
                e.kind == 'input' &&
                e.message == '请输入正确的手机号码',
          ),
        ),
        reason: 'mobile=$mobile',
      );
    }
    expect(adapter.requests, isEmpty);
  });

  test('业务失败（status=0）→ business 带 error_code', () async {
    final adapter = CaptureAdapter(
      jsonBytes('{"status":0,"error_code":30001,"data":null}'),
    );
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    await expectLater(
      fetchCaptchaSent(
        _session(client, KugouIdentity.anonymous()),
        const MusicCaptchaSentQuery(mobile: '13912345678'),
      ),
      throwsA(
        predicate(
          (Object e) =>
              e is KugouApiException && e.kind == 'business' && e.code == 30001,
        ),
      ),
    );
  });

  test('登录过期（error_code=20018）→ authentication', () async {
    final adapter = CaptureAdapter(
      jsonBytes('{"status":0,"error_code":20018}'),
    );
    final client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    await expectLater(
      fetchCaptchaSent(
        _session(client, KugouIdentity.anonymous()),
        const MusicCaptchaSentQuery(mobile: '13912345678'),
      ),
      throwsA(
        predicate(
          (Object e) => e is KugouApiException && e.kind == 'authentication',
        ),
      ),
    );
  });

  test('解码： AckEnvelope 必填标量缺失/类型错 → decode；数字字符串宽容', () async {
    final client = KugouClient(
      dio: Dio()..httpClientAdapter = CaptureAdapter(jsonBytes('{}')),
    );
    await expectLater(
      fetchCaptchaSent(
        _session(client, KugouIdentity.anonymous()),
        const MusicCaptchaSentQuery(mobile: '13912345678'),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'decode'),
      ),
    );

    // status/error_code 允许数字字符串（scalar 宽容面）。
    final tolerant = CaptureAdapter(
      jsonBytes('{"status":"1","error_code":"0"}'),
    );
    final ok = await fetchCaptchaSent(
      _session(
        KugouClient(dio: Dio()..httpClientAdapter = tolerant),
        KugouIdentity.anonymous(),
      ),
      const MusicCaptchaSentQuery(mobile: '13912345678'),
    );
    expect(ok, isTrue);

    final boolStatus = CaptureAdapter(
      jsonBytes('{"status":true,"error_code":0}'),
    );
    await expectLater(
      fetchCaptchaSent(
        _session(
          KugouClient(dio: Dio()..httpClientAdapter = boolStatus),
          KugouIdentity.anonymous(),
        ),
        const MusicCaptchaSentQuery(mobile: '13912345678'),
      ),
      throwsA(
        predicate((Object e) => e is KugouApiException && e.kind == 'decode'),
      ),
    );
  });
}
