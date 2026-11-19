/// 扫码登录端点测试：请求装配（匿名身份 + web 签名 + 精确参数）、
/// 四态映射、凭证缺失与 key 校验。全部离线（捕获型 adapter）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/login_qr.dart';
import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';

class _CaptureAdapter implements HttpClientAdapter {
  _CaptureAdapter(this.response);

  Uint8List response;
  int calls = 0;
  final RequestOptions captured = RequestOptions(path: '/');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    captured
      ..method = options.method
      ..baseUrl = options.baseUrl
      ..path = options.path
      ..queryParameters = options.queryParameters
      ..headers = options.headers;
    return ResponseBody.fromBytes(response, 200);
  }

  @override
  void close({bool force = false}) {}
}

Uint8List wire(Object? data) => Uint8List.fromList(
  utf8.encode(
    jsonEncode(<String, Object?>{'status': 1, 'error_code': 0, 'data': data}),
  ),
);

Future<KugouApiException> captureError(Future<void> Function() action) async {
  try {
    await action();
  } on KugouApiException catch (error) {
    return error;
  }
  fail('应当抛 KugouApiException');
}

void main() {
  late _CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity device;

  setUp(() {
    adapter = _CaptureAdapter(wire(const <String, Object?>{}));
    client = KugouClient(
      dio: Dio()..httpClientAdapter = adapter,
      now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    device = KugouIdentity.anonymous().withDfid('dfid-device');
  });

  Map<String, String> queryOf() => adapter.captured.queryParameters.map(
    (key, value) => MapEntry(key, '$value'),
  );

  test('startQrLogin：路径/主机/参数逐项对齐 + 匿名身份 + web 签名', () async {
    adapter.response = wire(<String, Object?>{
      'qrcode': 'KEY-1',
      'qrcode_img': 'data:image/png;base64,AAAA',
    });
    // 已登录身份也要先匿名化（token/t1/userid 都不许出现在二维码请求里）。
    final identity = device.withAccount(
      userId: 42,
      token: 'SECRET-TOKEN',
      t1: 'STALE-T1',
    );

    final session = await startQrLogin(client, identity);
    expect(session.key, 'KEY-1');
    expect(session.imageDataUrl, 'data:image/png;base64,AAAA');

    expect(
      '${adapter.captured.uri}'.startsWith(
        'https://login-user.kugou.com/v2/qrcode?',
      ),
      isTrue,
    );
    expect(adapter.captured.method, 'GET');
    final query = queryOf();
    expect(query['appid'], '1001');
    expect(query['type'], '1');
    expect(query['plat'], '4');
    expect(query['srcappid'], '2919');
    expect(
      query['qrcode_txt'],
      'https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=3116&',
      reason: '末尾 & 是上游原样常量',
    );
    expect(query.containsKey('token'), isFalse);
    expect(query.containsKey('userid'), isFalse);
    expect(query.containsKey('t1'), isFalse);
    expect(query['mid'], identity.mid);
    expect(query['dfid'], identity.dfid);

    final signed = Map<String, String>.from(query)..remove('signature');
    expect(query['signature'], kugouSignatureWeb(signed, const <int>[]));
  });

  test('startQrLogin：数字型 key/img 宽容转字符串（scalar 语义）', () async {
    adapter.response = wire(<String, Object?>{
      'qrcode': 987654321,
      'qrcode_img': 12345,
    });
    final session = await startQrLogin(client, device);
    expect(session.key, '987654321');
    expect(session.imageDataUrl, '12345');
  });

  test('startQrLogin：字段缺失或类型错 → decode', () async {
    adapter.response = wire(<String, Object?>{'qrcode': 'k'});
    var error = await captureError(() => startQrLogin(client, device));
    expect(error.kind, 'decode');
    expect(error.message, contains('qrcode_img'));

    adapter.response = wire(<String, Object?>{
      'qrcode': true,
      'qrcode_img': 'img',
    });
    error = await captureError(() => startQrLogin(client, device));
    expect(error.kind, 'decode');
  });

  test('pollQrLogin：status 0/1/2/4 四态逐一映射', () async {
    final cases = <(int, QrLoginState)>[
      (0, QrLoginState.expired),
      (1, QrLoginState.waiting),
      (2, QrLoginState.scanned),
    ];
    for (final (status, state) in cases) {
      adapter.response = wire(<String, Object?>{'status': status});
      final result = await pollQrLogin(client, device, 'KEY');
      expect(result.state, state, reason: 'status=$status');
      expect(result.authorization, isNull);
    }

    adapter.response = wire(<String, Object?>{
      'status': 4,
      'userid': '42',
      'token': 'TOK',
      'nickname': '小明',
      'pic': 'https://img/a.png',
    });
    final authorized = await pollQrLogin(client, device, 'KEY');
    expect(authorized.state, QrLoginState.authorized);
    expect(authorized.authorization!.userId, 42);
    expect(authorized.authorization!.token, 'TOK');
    expect(authorized.authorization!.nickname, '小明');
    expect(authorized.authorization!.avatarUrl, 'https://img/a.png');
  });

  test('pollQrLogin：授权态缺 userid 或空 token → authentication', () async {
    adapter.response = wire(<String, Object?>{'status': 4, 'token': 'TOK'});
    var error = await captureError(() => pollQrLogin(client, device, 'KEY'));
    expect(error.kind, 'authentication');
    expect(error.message, '服务未返回有效登录凭证');

    adapter.response = wire(<String, Object?>{
      'status': 4,
      'userid': '42',
      'token': '',
    });
    error = await captureError(() => pollQrLogin(client, device, 'KEY'));
    expect(error.kind, 'authentication');

    // userid=0 同样视为无凭证（上游判 0）。
    adapter.response = wire(<String, Object?>{
      'status': 4,
      'userid': 0,
      'token': 'TOK',
    });
    error = await captureError(() => pollQrLogin(client, device, 'KEY'));
    expect(error.kind, 'authentication');
  });

  test('pollQrLogin：其它 status → business 且 code=status', () async {
    adapter.response = wire(<String, Object?>{'status': 3});
    final error = await captureError(() => pollQrLogin(client, device, 'KEY'));
    expect(error.kind, 'business');
    expect(error.code, 3);
  });

  test('pollQrLogin：请求参数（appid/srcappid/plat/qrcode/dev）与匿名身份', () async {
    adapter.response = wire(<String, Object?>{'status': 1});
    await pollQrLogin(client, device, 'KEY-ABC');
    expect(
      '${adapter.captured.uri}'.startsWith(
        'https://login-user.kugou.com/v2/get_userinfo_qrcode?',
      ),
      isTrue,
    );
    final query = queryOf();
    expect(query['appid'], '3116');
    expect(query['srcappid'], '2919');
    expect(query['plat'], '4');
    expect(query['qrcode'], 'KEY-ABC');
    expect(query['dev'], device.deviceName);
    expect(query.containsKey('token'), isFalse);
    expect(query.containsKey('userid'), isFalse);
    final signed = Map<String, String>.from(query)..remove('signature');
    expect(query['signature'], kugouSignatureWeb(signed, const <int>[]));
  });

  test('pollQrLogin：key 为空/超 4096 → input 且不发请求', () async {
    for (final key in <String>['', '   ', 'x' * 4097]) {
      final error = await captureError(() => pollQrLogin(client, device, key));
      expect(error.kind, 'input');
    }
    expect(adapter.calls, 0);
  });

  test('pollQrLogin：状态字段缺失 → decode', () async {
    adapter.response = wire(<String, Object?>{'nickname': 'x'});
    final error = await captureError(() => pollQrLogin(client, device, 'KEY'));
    expect(error.kind, 'decode');
  });
}
