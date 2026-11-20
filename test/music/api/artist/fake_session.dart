/// 歌手端点测试共享夹具：假 `MusicSession`（ensureDevice/loadIdentity 直接
/// 返回身份，不联网）+ `CaptureAdapter` 客户端。
library;

import 'package:dio/dio.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';

/// 匿名身份（不触 path_provider、不注册设备）。
KugouIdentity artistTestIdentity() => KugouIdentity.anonymous();

/// 捕获型客户端。
KugouClient artistTestClient(CaptureAdapter adapter) =>
    KugouClient(dio: Dio()..httpClientAdapter = adapter);

/// 假会话：身份读写都是内存直通。
MusicSession fakeMusicSession(KugouClient client, KugouIdentity identity) =>
    MusicSession(
      client: client,
      ensureDevice: () async => identity,
      loadIdentity: () async => identity,
      saveIdentity: (_) async {},
    );
