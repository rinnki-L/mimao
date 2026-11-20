/// 歌单读组测试辅助：假 MusicSession（ensureDevice 原样返回注入身份，
/// 不联网）+ 常用身份构造。
library;

import 'package:dio/dio.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';

/// 假会话：ensureDevice/loadIdentity 原样返回 [identity]，saveIdentity 空操作。
MusicSession fakeMusicSession(KugouIdentity identity, KugouClient client) =>
    MusicSession(
      client: client,
      ensureDevice: () async => identity,
      loadIdentity: () async => identity,
      saveIdentity: (_) async {},
    );

/// 带账号身份（userId/token 非空；设备字段仍是匿名占位）。
KugouIdentity accountIdentity() => KugouIdentity.anonymous().withAccount(
  userId: 12345,
  token: 'token-fixture',
);

/// 建好捕获 adapter 的客户端（不触碰网络）。
KugouClient capturedClient(CaptureAdapter adapter) =>
    KugouClient(dio: Dio()..httpClientAdapter = adapter);
