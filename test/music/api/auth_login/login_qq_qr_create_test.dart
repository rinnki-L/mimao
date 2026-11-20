/// login_qq_qr_create（QQ 扫码创建）测试：三段 provider 装配（m_authorize 签名
/// → xlogin HTML 解码 → ptqrshow PNG/cookie）+ decode 分支。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:mimao/music/api/login_qq_qr_create.dart';
import 'package:mimao/music/api/login_openplat.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/models/auth_models.dart';
import 'package:mimao/music/client/kugou_error.dart';

import 'test_support.dart';

const String _htmlWithSrc =
    '<html><script>var src = "https\\x3A\\x2F\\x2Fxui.ptlogin2.qq.com\\x2Fcgi-bin\\x2Fxlogin'
    '\\x3Fclient_id\\x3D101706348\\x26response_type\\x3Dtoken";</script></html>';

List<int> _pngBytes() => <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  1,
  2,
  3,
  4,
];

void main() {
  late ProviderStubAdapter adapter;
  late KugouClient client;
  late MusicSession session;

  setUp(() {
    adapter = ProviderStubAdapter()
      ..enqueue(200, _htmlWithSrc)
      ..enqueue(200, 'ok', <String, String>{
        'set-cookie': 'pt_login_sig=SIG1; Path=/; Secure',
      })
      ..enqueueBytes(200, _pngBytes(), <String, String>{
        'set-cookie': 'qrsig=QRSIG1; Path=/',
        'content-type': 'image/png',
      });
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    session = fakeSession(client, fixtureIdentity());
  });

  Future<MusicQqQrSession> run() => fetchLoginQqQrCreate(
    session,
    timestampSeconds: 1760000000,
    random: RandomStub(),
  );

  test('请求装配：m_authorize 签名/xlogin 解码/ptqrshow 参数与 Cookie', () async {
    final result = await run();

    expect(adapter.requests, hasLength(3));

    // 1) m_authorize：19 个参数 + sign = md5(固定盐_秒)。
    final authorize = adapter.requests[0];
    expect(authorize.path, 'https://openmobile.qq.com/oauth2.0/m_authorize');
    expect(authorize.query.keys.toList(), <String>[
      'cancel_display',
      'sdkp',
      'display',
      'format',
      'sign',
      'sdkv',
      'response_type',
      'status_os',
      'client_id',
      'switch',
      'status_version',
      'show_download_ui',
      'pf',
      'scope',
      'compat_v',
      'status_machine',
      'style',
      'time',
      'redirect_uri',
    ]);
    expect(
      authorize.query['sign'],
      md5
          .convert(utf8.encode('fe4a24d80fcf253a00676a808f62c2c6_1760000000'))
          .toString(),
    );
    expect(authorize.query['client_id'], '101706348');
    expect(authorize.query['time'], '1760000000');
    expect(authorize.query['redirect_uri'], 'auth://tauth.qq.com/');
    expect(authorize.headers['User-Agent'], kQqUserAgent);
    expect(authorize.headers['Referer'], 'https://xui.ptlogin2.qq.com/');

    // 2) xlogin：解码 \x 转义后的完整 URL，原样请求。
    final xlogin = adapter.requests[1];
    expect(
      xlogin.path,
      'https://xui.ptlogin2.qq.com/cgi-bin/xlogin?client_id=101706348&response_type=token',
    );
    expect(xlogin.query, isEmpty, reason: 'query 已含在 URL 里，不再重复拼参');
    expect(xlogin.headers['User-Agent'], kQqUserAgent);
    expect(xlogin.headers['Referer'], 'https://xui.ptlogin2.qq.com/');

    // 3) ptqrshow：带会话 Cookie（BTreeMap 键序）与 Referer=xlogin。
    final qrshow = adapter.requests[2];
    expect(qrshow.path, 'https://xui.ptlogin2.qq.com/ssl/ptqrshow');
    expect(qrshow.query.keys.toList(), <String>[
      's',
      'e',
      'appid',
      'type',
      't',
      'daid',
      'pt_3rd_aid',
    ]);
    expect(qrshow.query['appid'], '716027609');
    expect(qrshow.query['pt_3rd_aid'], '101706348');
    expect(qrshow.query['t'], startsWith('0.'));
    expect(qrshow.headers['Cookie'], 'pt_login_sig=SIG1');
    expect(qrshow.headers['Referer'], xlogin.path);
    expect(qrshow.headers['User-Agent'], kQqUserAgent);

    for (final request in adapter.requests) {
      expect(
        request.query.containsKey('signature'),
        isFalse,
        reason: 'provider 无酷狗签名',
      );
      expect(request.headers.containsKey('dfid'), isFalse);
      expect(request.headers.containsKey('mid'), isFalse);
    }

    expect(result.xloginUrl, xlogin.path);
    expect(result.ptLoginSig, 'SIG1');
    expect(result.qrsig, 'QRSIG1');
    expect(result.ptqrtoken, kugouQqHash33('QRSIG1'));
    expect(
      result.cookie,
      'pt_login_sig=SIG1; qrsig=QRSIG1',
      reason: 'BTreeMap 键序',
    );
    expect(result.openloginData, 'client_id=101706348&response_type=token');
    expect(result.imageDataUrl, startsWith('data:image/png;base64,'));
    expect(
      base64Decode(
        result.imageDataUrl.substring('data:image/png;base64,'.length),
      ),
      Uint8List.fromList(_pngBytes()),
    );
  });

  test('decode：HTML 缺 src / 主机或路径不符', () async {
    adapter
      ..clear()
      ..enqueue(200, '<html>no source</html>');
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'decode')
            .having((error) => error.message, 'message', '授权页缺少跳转地址'),
      ),
    );

    adapter
      ..clear()
      ..enqueue(
        200,
        'src = "https\\x3A\\x2F\\x2Fssl.ptlogin2.qq.com\\x2Fcgi-bin\\x2Fxlogin"',
      );
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'decode',
        ),
      ),
    );

    adapter
      ..clear()
      ..enqueue(
        200,
        'src = "https\\x3A\\x2F\\x2Fxui.ptlogin2.qq.com\\x2Fother"',
      );
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>().having(
          (error) => error.kind,
          'kind',
          'decode',
        ),
      ),
    );
  });

  test('decode：缺 pt_login_sig / 缺 qrsig / 非 PNG', () async {
    adapter
      ..clear()
      ..enqueue(200, _htmlWithSrc)
      ..enqueue(200, 'ok'); // 无 set-cookie
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'decode')
            .having((error) => error.message, 'message', '授权会话缺少 pt_login_sig'),
      ),
    );

    adapter
      ..clear()
      ..enqueue(200, _htmlWithSrc)
      ..enqueue(200, 'ok', <String, String>{'set-cookie': 'pt_login_sig=SIG1'})
      ..enqueueBytes(200, _pngBytes()); // 无 qrsig cookie
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'decode')
            .having((error) => error.message, 'message', '二维码会话缺少 qrsig'),
      ),
    );

    adapter
      ..clear()
      ..enqueue(200, _htmlWithSrc)
      ..enqueue(200, 'ok', <String, String>{'set-cookie': 'pt_login_sig=SIG1'})
      ..enqueueBytes(
        200,
        <int>[1, 2, 3],
        <String, String>{'set-cookie': 'qrsig=Q'},
      );
    await expectLater(
      run(),
      throwsA(
        isA<KugouApiException>()
            .having((error) => error.kind, 'kind', 'decode')
            .having((error) => error.message, 'message', '二维码不是 PNG 图片'),
      ),
    );
  });

  test('hash33：u32 wrapping 折叠（上游同构）', () {
    // 逐字符 (sum*33+c) mod 2^32，最后 & 0x7fffffff。
    var sum = 0;
    for (final unit in 'QRSIG1'.codeUnits) {
      sum = (sum * 33 + unit) & 0xFFFFFFFF;
    }
    expect(kugouQqHash33('QRSIG1'), sum & 0x7FFFFFFF);
    expect(kugouQqHash33(''), 0);
  });
}

/// 固定随机源（nonce 形态断言用，不参与协议）。
class RandomStub implements Random {
  @override
  bool nextBool() => true;

  @override
  double nextDouble() => 0.5;

  @override
  int nextInt(int max) => 12345;
}
