/// G10 用户库测试共用件：假 `MusicSession`（ensureDevice 不联网）、带账号
/// 身份、Android 签名自验与主机捕获 adapter。不联网、不依赖真实时间。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/signature.dart';

import '../capture_adapter.dart';

/// 带账号的测试身份（64 位 userid 用足精度样本）。
KugouIdentity accountIdentity({int userId = 9007199254741005}) {
  return KugouIdentity.anonymous(
    random: Random(0),
  ).withAccount(userId: userId, token: 'token-sample-1');
}

/// 假会话：ensureDevice 直接返回注入的身份，不生成、不注册。
MusicSession sessionFor(KugouClient client, KugouIdentity identity) {
  return MusicSession(
    client: client,
    ensureDevice: () async => identity,
    loadIdentity: () async => identity,
    saveIdentity: (_) async {},
  );
}

/// 包装 [CaptureAdapter] 额外记录完整 URI（断言 origin 主机路由）。
class HostCaptureAdapter implements HttpClientAdapter {
  HostCaptureAdapter(this.inner);

  final CaptureAdapter inner;

  /// 每次请求的完整 URI（按发生顺序）。
  final List<Uri> uris = <Uri>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    uris.add(options.uri);
    return inner.fetch(options, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

/// 捕获 query 去掉 signature 后与请求体重新签名，断言与发送值一致
/// （Android salt；body 用实际发送字节）。
void expectValidAndroidSignature(CapturedRequest request) {
  final query = Map.of(request.query)..remove('signature');
  final body = utf8.encode(request.bodyText);
  expect(request.query['signature'], kugouSignatureAndroid(query, body));
}

/// 断言抛出指定 kind（与可选业务码）的 [KugouApiException]。
Matcher throwsKugou(String kind, {int? code}) => throwsA(
  isA<KugouApiException>()
      .having((error) => error.kind, 'kind', kind)
      .having((error) => error.code, 'code', code),
);
