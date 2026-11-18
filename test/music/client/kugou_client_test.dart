/// 传输层测试：用捕获型 HttpClientAdapter 验证 request.rs send_endpoint 的
/// 装配语义（默认参数、签名、主机表、头、registration 固定参数序）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';

/// 捕获请求并按序回放预设响应的假 adapter。
class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter();

  final RequestOptions captured = RequestOptions(path: '/');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _copyInto(captured, options);
    return ResponseBody.fromBytes(utf8.encode('{"ok":true}'), 200);
  }

  void _copyInto(RequestOptions target, RequestOptions source) {
    target
      ..method = source.method
      ..baseUrl = source.baseUrl
      ..path = source.path
      ..queryParameters = source.queryParameters
      ..headers = source.headers
      ..data = source.data
      ..responseType = source.responseType;
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _CapturingAdapter adapter;
  late KugouClient client;

  setUp(() {
    adapter = _CapturingAdapter();
    client = KugouClient(
      dio: Dio()..httpClientAdapter = adapter,
      now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
  });

  Map<String, String> queryOf(RequestOptions options) =>
      options.queryParameters.map((key, value) => MapEntry(key, '$value'));

  test('匿名搜索：默认参数 + 端点覆盖 + android 签名 + 网关主机 + 固定头', () async {
    final identity = KugouIdentity.anonymous();
    await client.sendEndpoint(
      identity,
      const KugouEndpoint(
        origin: KugouOrigin.gateway,
        path: '/v2/search/song',
        router: 'complexsearch.kugou.com',
        method: 'GET',
        params: {
          'keyword': '周杰伦',
          'page': '1',
          'pagesize': '30',
          'platform': 'AndroidFilter',
          'iscorrection': '1',
          'userid': '0',
          'clientver': '201',
          'privilegefilter': '0',
          'area_code': '1',
          'dopicfull': '1',
        },
      ),
    );

    final captured = adapter.captured;
    expect(
      '${captured.uri}'.startsWith('https://gateway.kugou.com/v2/search/song'),
      isTrue,
    );
    expect(captured.method, 'GET');
    final query = queryOf(captured);
    // 默认值。
    expect(query['appid'], '3116');
    expect(query['clientver'], '201', reason: '端点参数覆盖默认 11440');
    expect(query['clienttime'], '1700000000');
    expect(query['dfid'], identity.dfid);
    expect(query['mid'], identity.mid);
    expect(query['uuid'], '-');
    // 匿名身份不注入 token/userid，但端点显式给了 userid=0。
    expect(query.containsKey('token'), isFalse);
    expect(query['userid'], '0');
    // 签名可由 query 自验（除 signature 外重算 android 签名）。
    final withoutSignature = Map<String, String>.from(query)
      ..remove('signature');
    expect(
      query['signature'],
      kugouSignatureAndroid(withoutSignature, const <int>[]),
    );
    // 头。
    expect(captured.headers['User-Agent'], kugouDefaultUserAgent);
    expect(captured.headers['dfid'], identity.dfid);
    expect(captured.headers['mid'], identity.mid);
    expect(captured.headers['clienttime'], '1700000000');
    expect(captured.headers['x-router'], 'complexsearch.kugou.com');
  });

  test('登录态身份：token/userid 注入默认参数', () async {
    final anonymous = KugouIdentity.anonymous();
    final identity = KugouIdentity(
      userId: 42,
      token: 'tok',
      t1: '',
      mid: anonymous.mid,
      dfid: anonymous.dfid,
      uuid: '-',
      guid: anonymous.guid,
      mac: anonymous.mac,
      deviceName: '',
      renderFingerprint: '',
    );
    await client.sendEndpoint(
      identity,
      const KugouEndpoint(
        origin: KugouOrigin.gateway,
        path: '/v2/search/song',
        method: 'GET',
        params: {'keyword': 'k', 'userid': '42'},
      ),
    );
    final query = queryOf(adapter.captured);
    expect(query['token'], 'tok');
    expect(query['userid'], '42');
    final withoutSignature = Map<String, String>.from(query)
      ..remove('signature');
    expect(
      query['signature'],
      kugouSignatureAndroid(withoutSignature, const <int>[]),
    );
  });

  test('registration origin：固定参数序 + signature 恒最后 + userservice 主机', () async {
    final identity = KugouIdentity.anonymous();
    await client.sendEndpoint(
      identity,
      const KugouEndpoint(
        origin: KugouOrigin.registration,
        path: '/risk/v3/r_register_dev',
        method: 'POST',
        params: {'part': '1', 'platid': '1', 'p': 'PORTRAIT'},
        body: <int>[1, 2, 3],
        headers: [
          ('Content-Type', 'application/x-www-form-urlencoded'),
          ('kg-rc', '1'),
        ],
      ),
    );

    final captured = adapter.captured;
    expect(
      '${captured.uri}'.startsWith('https://userservice.kugou.com/'),
      isTrue,
    );
    final keys = captured.queryParameters.keys.toList();
    // ORDER：dfid, mid, uuid, appid, clientver, clienttime, part, platid, p
    // …其余按字典序…signature 最后。
    expect(keys, <String>[
      'dfid',
      'mid',
      'uuid',
      'appid',
      'clientver',
      'clienttime',
      'part',
      'platid',
      'p',
      'signature',
    ]);
    final query = queryOf(captured);
    expect(query['p'], 'PORTRAIT');
    expect(
      query['signature'],
      kugouSignatureAndroid(
        Map<String, String>.from(query)..remove('signature'),
        const <int>[1, 2, 3],
      ),
    );
    // Content-Type 取端点声明值。
    expect(
      captured.headers['Content-Type'],
      'application/x-www-form-urlencoded',
    );
  });

  test('qrLogin origin 走 web 签名 + login-user 主机', () async {
    final identity = KugouIdentity.anonymous();
    await client.sendEndpoint(
      identity,
      const KugouEndpoint(
        origin: KugouOrigin.qrLogin,
        path: '/v5/login/qrcode/key',
        method: 'GET',
        params: {'t1': 'a'},
      ),
    );
    final query = queryOf(adapter.captured);
    expect(
      '${adapter.captured.uri}'.startsWith('https://login-user.kugou.com/'),
      isTrue,
    );
    final withoutSignature = Map<String, String>.from(query)
      ..remove('signature');
    expect(
      query['signature'],
      kugouSignatureWeb(withoutSignature, const <int>[]),
    );
  });

  test('origin → 主机表（抽查非网关分支）', () {
    expect(kugouOriginHost(KugouOrigin.lyrics), 'https://lyrics.kugou.com');
    expect(
      kugouOriginHost(KugouOrigin.tracker),
      'https://trackercdngz.kugou.com',
    );
    expect(
      kugouOriginHost(KugouOrigin.userService),
      'https://userservice.kugou.com',
    );
    expect(
      kugouOriginHost(KugouOrigin.effectsCatalog),
      'http://mobilecdngz.kugou.com',
    );
    expect(kugouOriginHost(KugouOrigin.sumComment), kugouGatewayBaseUrl);
  });

  test('身份不可用（mid 空）→ input 异常，不发请求', () async {
    final broken = KugouIdentity(
      userId: 0,
      token: '',
      t1: '',
      mid: '',
      dfid: '-',
      uuid: '-',
      guid: 'g',
      mac: '',
      deviceName: '',
      renderFingerprint: '',
    );
    await expectLater(
      client.sendEndpoint(
        broken,
        const KugouEndpoint(
          origin: KugouOrigin.gateway,
          path: '/x',
          method: 'GET',
        ),
      ),
      throwsA(
        predicate((Object e) => '$e'.contains('input'), 'kind=input 的异常'),
      ),
    );
  });

  test('非 2xx → http 异常（Rust receive() 语义），字节不透传', () async {
    final dio = Dio(BaseOptions(responseType: ResponseType.bytes))
      ..httpClientAdapter = _StatusAdapter(500);
    final raw = KugouClient(dio: dio);
    await expectLater(
      raw.sendEndpoint(
        KugouIdentity.anonymous(),
        const KugouEndpoint(
          origin: KugouOrigin.gateway,
          path: '/x',
          method: 'GET',
        ),
      ),
      throwsA(
        predicate((Object e) => '$e'.contains('http') && '$e'.contains('500')),
      ),
    );
  });

  test('2xx 一律放行（如 204），字节原样返回', () async {
    final dio = Dio(BaseOptions(responseType: ResponseType.bytes))
      ..httpClientAdapter = _StatusAdapter(204);
    final raw = KugouClient(dio: dio);
    final response = await raw.sendEndpoint(
      KugouIdentity.anonymous(),
      const KugouEndpoint(
        origin: KugouOrigin.gateway,
        path: '/x',
        method: 'GET',
      ),
    );
    expect(response.statusCode, 204);
    expect(response.bytes, isEmpty);
  });
}

/// 固定回状态码的 adapter。
class _StatusAdapter implements HttpClientAdapter {
  _StatusAdapter(this.status);

  final int status;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromBytes(const <int>[], status);

  @override
  void close({bool force = false}) {}
}
