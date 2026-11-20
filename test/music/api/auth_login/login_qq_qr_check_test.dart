/// login_qq_qr_check（QQ 扫码轮询）测试：回调文法解析（转义/错误结构）+
/// 状态映射 + 凭证提取（auth:// fragment / 跳转链 / HTML）。
library;

import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/login_qq_qr_check.dart';
import 'package:mimao/music/api/login_openplat.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/auth_models.dart';

import 'test_support.dart';

const MusicQqQrSession _session = MusicQqQrSession(
  xloginUrl: 'https://xui.ptlogin2.qq.com/cgi-bin/xlogin?client_id=101706348',
  ptLoginSig: 'SIG1',
  qrsig: 'QRSIG1',
  cookie: 'pt_login_sig=SIG1; qrsig=QRSIG1',
  ptqrtoken: 123456,
  openloginData: 'client_id=101706348&response_type=token',
  imageDataUrl: '',
);

void main() {
  late ProviderStubAdapter adapter;
  late KugouClient client;
  late MusicSession session;

  setUp(() {
    adapter = ProviderStubAdapter()
      ..enqueue(200, "ptuiCB('66','0','','0','未扫描','');");
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    session = fakeSession(client, fixtureIdentity());
  });

  Future<MusicQqQrCheckResult> run() =>
      fetchLoginQqQrCheck(session, _session, random: FixedRandom());

  test('请求装配：ptqrlogin 参数序/Referer/Cookie 原样', () async {
    final result = await run();

    final request = adapter.requests.single;
    expect(request.path, 'https://xui.ptlogin2.qq.com/ssl/ptqrlogin');
    expect(request.query.keys.toList(), <String>[
      'u1',
      'from_ui',
      'type',
      'ptlang',
      'ptqrtoken',
      'daid',
      'aid',
      'pt_3rd_aid',
      'pt_openlogin_data',
      'device',
      'ptopt',
      'pt_uistyle',
      'jsver',
      'login_sig',
      'r',
    ]);
    expect(request.query['ptqrtoken'], '123456');
    expect(request.query['aid'], '716027609');
    expect(request.query['pt_3rd_aid'], '101706348');
    expect(request.query['pt_openlogin_data'], _session.openloginData);
    expect(request.query['login_sig'], 'SIG1');
    expect(request.query['r'], startsWith('0.'));
    expect(request.headers['Cookie'], _session.cookie);
    expect(request.headers['Referer'], _session.xloginUrl);
    expect(request.headers['User-Agent'], kQqUserAgent);
    expect(request.query.containsKey('signature'), isFalse);
    expect(result.state, MusicQqQrCheckResult.stateWaiting);
  });

  test('状态映射：66/65/67/0/其它', () async {
    final states = <String, String?>{
      '66': MusicQqQrCheckResult.stateWaiting,
      '65': MusicQqQrCheckResult.stateExpired,
      '67': MusicQqQrCheckResult.stateScanned,
    };
    for (final entry in states.entries) {
      adapter
        ..clear()
        ..enqueue(200, "ptuiCB('${entry.key}','0','','0','t','');");
      final result = await run();
      expect(result.state, entry.value);
      expect(result.authorization, isNull);
    }

    adapter
      ..clear()
      ..enqueue(200, "ptuiCB('99','0','','0','t','');");
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'provider')
            .having((error) => error.message, 'message', 'QQ扫码失败，请重新获取二维码'),
      ),
    );
  });

  test('回调文法：转义名字（引号、u 代理对、x）与错误结构', () {
    // 上游同款样例：转义引号 + UTF-16 代理对。
    final fields = kugouParseQrCallback(
      utf8Bytes(
        "ptuiCB('0','0','auth://tauth.qq.com/#openid=a&access_token=b','0','ok','O\\'Connor \\uD83D\\uDE00');",
      ),
    );
    expect(fields[2], 'auth://tauth.qq.com/#openid=a&access_token=b');
    expect(fields[5], "O'Connor \u{1F600}");

    expect(
      kugouParseQrCallback(utf8Bytes("ptuiCB('a\\x20b','','','','','');"))[0],
      'a b',
    );
    expect(
      kugouParseQrCallback(
        utf8Bytes("ptuiCB('a\\\"b\\\\c','','','','','');"),
      )[0],
      'a"b\\c',
    );

    // 尾逗号 / 分号分隔 / 外挂代码 / 前缀不符 → decode。
    for (final bad in <String>[
      "ptuiCB('66','0','','0','unit','',)",
      "ptuiCB('66';'0','','0','unit','')",
      "ptuiCB('66','0','','0','unit','');other()",
      'not-a-callback',
    ]) {
      expect(
        () => kugouParseQrCallback(utf8Bytes(bad)),
        throwsA(
          isA<KugouApiException>().having(
            (error) => error.kind,
            'kind',
            'decode',
          ),
        ),
        reason: bad,
      );
    }
  });

  test('input：会话字段缺失/超长 cookie（无请求）', () async {
    const empty = MusicQqQrSession(
      xloginUrl: '',
      ptLoginSig: '',
      qrsig: '',
      cookie: '',
      ptqrtoken: 0,
      openloginData: '',
      imageDataUrl: '',
    );
    await expectLater(
      fetchLoginQqQrCheck(session, empty, random: FixedRandom()),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'input')
            .having((error) => error.message, 'message', 'QQ二维码会话无效'),
      ),
    );
    final longCookie = MusicQqQrSession(
      xloginUrl: _session.xloginUrl,
      ptLoginSig: _session.ptLoginSig,
      qrsig: _session.qrsig,
      cookie: 'k=${'v' * 33000}',
      ptqrtoken: _session.ptqrtoken,
      openloginData: _session.openloginData,
      imageDataUrl: '',
    );
    await expectLater(
      fetchLoginQqQrCheck(session, longCookie, random: FixedRandom()),
      throwsA(
        isA<KugouApiException>().having((error) => error.kind, 'kind', 'input'),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('授权成功：auth:// fragment 直接取凭证（不再发请求）', () async {
    adapter
      ..clear()
      ..enqueue(
        200,
        "ptuiCB('0','0','auth://tauth.qq.com/#openid=OID9&access_token=AT9','0','ok','昵称');",
      );
    final result = await run();
    expect(result.state, MusicQqQrCheckResult.stateProviderAuthorized);
    expect(result.authorization!.openid, 'OID9');
    expect(result.authorization!.accessToken, 'AT9');
    expect(adapter.requests, hasLength(1), reason: 'fragment 凭证无需跳转链');
  });

  test('授权成功：跳转链 Location + HTML 兜底取凭证（白名单内）', () async {
    adapter
      ..clear()
      ..enqueue(
        200,
        "ptuiCB('0','0','ssl.ptlogin2.qq.com/check_sig?x=1','0','ok','');",
      )
      ..enqueue(200, '<html>redirecting</html>', <String, String>{
        'location': 'https://graph.qq.com/oauth2.0/me',
        'set-cookie': 'new_cookie=NC',
      })
      ..enqueue(
        200,
        '<html>openid: "OID-HTML"  access_token: "AT-HTML"</html>',
      );
    final result = await run();

    expect(adapter.requests, hasLength(3));
    final second = adapter.requests[1];
    expect(second.path, 'https://ssl.ptlogin2.qq.com/check_sig?x=1');
    expect(
      second.headers['Cookie'],
      'pt_login_sig=SIG1; qrsig=QRSIG1',
      reason: '初始 jar 来自会话 cookie',
    );
    final third = adapter.requests[2];
    expect(third.path, 'https://graph.qq.com/oauth2.0/me');
    expect(
      third.headers['Cookie'],
      'new_cookie=NC; pt_login_sig=SIG1; qrsig=QRSIG1',
      reason: '轮询响应的 set-cookie 并入 jar（BTreeMap 键序）',
    );
    expect(result.authorization!.openid, 'OID-HTML');
    expect(result.authorization!.accessToken, 'AT-HTML');
  });

  test('跳转链失败：非白名单主机 / HTML 无凭证 / 空跳转地址', () async {
    adapter
      ..clear()
      ..enqueue(
        200,
        "ptuiCB('0','0','https://evil.example.com/x','0','ok','');",
      )
      ..enqueue(200, '<html></html>');
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'provider')
            .having((error) => error.message, 'message', 'QQ授权地址无效'),
      ),
    );

    adapter
      ..clear()
      ..enqueue(200, "ptuiCB('0','0','ssl.ptlogin2.qq.com/check','0','ok','');")
      ..enqueue(200, '<html>nothing here</html>');
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'provider')
            .having((error) => error.message, 'message', 'QQ授权凭证获取失败，请重新扫码'),
      ),
    );

    adapter
      ..clear()
      ..enqueue(200, "ptuiCB('0','0','','0','ok','');");
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'provider')
            .having((error) => error.message, 'message', 'QQ授权未返回跳转地址'),
      ),
    );
  });

  test('credentials_url：query 与 fragment 合并、重复键取后者', () {
    final fromQuery = kugouQrCredentialsUrl(
      'https://graph.qq.com/me?openid=Q1&access_token=Q2',
    );
    expect(fromQuery!.openid, 'Q1');
    expect(fromQuery.accessToken, 'Q2');

    // query 与 fragment 同时存在 → fragment 覆盖。
    final merged = kugouQrCredentialsUrl(
      'https://graph.qq.com/me?openid=Q1&access_token=Q2#openid=F1&access_token=F2',
    );
    expect(merged!.openid, 'F1');
    expect(merged.accessToken, 'F2');

    expect(kugouQrCredentialsUrl('https://graph.qq.com/me?openid=Q1'), isNull);
    expect(
      kugouQrCredentialsUrl('https://graph.qq.com/me?openid=&access_token=AT'),
      isNull,
      reason: '空凭证不算授权',
    );
  });

  test('html_value：首个出现/裁剪前导/分隔截断/空值', () {
    // 首次出现语义（与上游一致）：'xopenid' 里的子串也算出现。
    const text = 'openid="OID"&access_token:\'AT\',tail openid=ignored';
    expect(kugouHtmlValue(text, 'openid'), 'OID');
    expect(kugouHtmlValue(text, 'access_token'), 'AT');
    expect(kugouHtmlValue('xopenid=1&openid="OID"', 'openid'), '1');
    expect(kugouHtmlValue('openid=', 'openid'), isNull);
    expect(kugouHtmlValue('nothing', 'openid'), isNull);
  });
}

/// 固定随机源。
class FixedRandom implements Random {
  @override
  bool nextBool() => true;

  @override
  double nextDouble() => 0.25;

  @override
  int nextInt(int max) => 7;
}
