/// 歌单写测试共享件：假 MusicSession、固定账号身份、固定时钟、响应密封。
///
/// 不联网：`ensureDevice` 直接返回注入身份；传输由 CaptureAdapter 捕获。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/session.dart';
import '../capture_adapter.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/client/kugou_error.dart';

/// 固定时钟：unix 秒 = 1700000000（上游 crypto.rs 黄金向量用同一时刻）。
final DateTime playlistWriteTestTime = DateTime.fromMillisecondsSinceEpoch(
  1700000000 * 1000,
);

/// 带账号的可用身份（设备字段沿用匿名档案）。
KugouIdentity playlistWriteIdentity() =>
    KugouIdentity.anonymous().withAccount(userId: 42, token: 'tok-1');

/// 不联网的假会话。
MusicSession fakePlaylistWriteSession(
  KugouClient client,
  KugouIdentity identity,
) => MusicSession(
  client: client,
  ensureDevice: () async => identity,
  loadIdentity: () async => identity,
  saveIdentity: (_) async {},
);

/// 固定时钟 + 捕获 adapter 的客户端。
KugouClient playlistWriteClient(HttpClientAdapter adapter) => KugouClient(
  dio: Dio()..httpClientAdapter = adapter,
  now: () => playlistWriteTestTime,
);

/// 服务端行为替身：用请求同款 seed 把 JSON 响应封成信封密文。
Uint8List sealCloudListResponse(String json, String seed) =>
    kugouAesCbcPkcs7(utf8.encode(json), seed, encrypt: true);

/// dio 捕获的 path 是完整 URL；取 URL 的 path 部分做断言。
String capturedPath(CapturedRequest request) => Uri.parse(request.path).path;

/// 断言异常 kind（与可选 code）的快捷谓词。
Matcher kugouError(String kind, {int? code}) => predicate(
  (Object e) =>
      e is KugouApiException &&
      e.kind == kind &&
      (code == null || e.code == code),
  'KugouApiException($kind${code == null ? '' : '/$code'})',
);
