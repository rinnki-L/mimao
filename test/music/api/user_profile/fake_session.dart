/// 用户资料组测试共用：假 MusicSession（不联网）+ 固定时钟 + 常用身份。
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';

/// 固定时钟：1700000000000ms = 1700000000s（查询参数与 body 时间同源）。
const int kFixedMilliseconds = 1700000000000;
const int kFixedSeconds = 1700000000;

/// 带账号身份（真设备上下文 + 假凭证）。
KugouIdentity accountIdentity() => KugouIdentity.anonymous().withAccount(
  userId: 421337,
  token: 'fixture-token',
  nickname: '昵称',
);

/// 匿名身份（mid 就绪、dfid='-'，无账号）。
KugouIdentity anonymousIdentity() => KugouIdentity.anonymous();

/// 假会话：ensureDevice 直接回注入身份，绝不联网/落盘。
MusicSession fakeSession(KugouClient client, KugouIdentity identity) =>
    MusicSession(
      client: client,
      ensureDevice: () async => identity,
      loadIdentity: () async => identity,
      saveIdentity: (_) async {},
    );

/// 固定时钟的客户端（KugouClient.now 与端点 body 时间共用）。
KugouClient fixedClient(CaptureAdapter adapter) => KugouClient(
  dio: Dio()..httpClientAdapter = adapter,
  now: () =>
      DateTime.fromMillisecondsSinceEpoch(kFixedMilliseconds, isUtc: true),
);

/// 解码捕获的 JSON 请求体（键序 = wire 序，Dart 解析保持插入序）。
Map<String, Object?> capturedJsonBody(CapturedRequest request) =>
    Map<String, Object?>.from(jsonDecode(request.bodyText) as Map);

/// 端点 p 参数的期望值：user_portrait 是裸 RSA（无随机），可按明文复算。
String expectedPortrait(Map<String, Object?> plaintext) =>
    kugouUserPortrait(utf8.encode(jsonEncode(plaintext)));

/// 在字节里找子序列（multipart 断言用；bodyText 对二进制不可用）。
bool bytesContain(List<int> hay, List<int> needle) {
  if (needle.isEmpty || hay.length < needle.length) return false;
  outer:
  for (var start = 0; start <= hay.length - needle.length; start++) {
    for (var index = 0; index < needle.length; index++) {
      if (hay[start + index] != needle[index]) continue outer;
    }
    return true;
  }
  return false;
}
