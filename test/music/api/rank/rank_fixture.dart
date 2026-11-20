/// 榜单端点测试共用夹具：捕获 adapter + 匿名身份 + 假 MusicSession
/// （不联网；与 search_test 的装配断言同款）。
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';

import '../capture_adapter.dart';

/// 一套可注入响应的离线夹具；需要账号语义的端点用 [withIdentity] 覆盖身份。
class RankFixture {
  RankFixture({KugouIdentity? withIdentity}) {
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = withIdentity ?? KugouIdentity.anonymous();
    session = MusicSession(
      client: client,
      ensureDevice: () async => identity,
      loadIdentity: () async => identity,
      saveIdentity: (_) async {},
    );
  }

  final CaptureAdapter adapter = CaptureAdapter(Uint8List(0));
  late final KugouClient client;
  late final KugouIdentity identity;
  late final MusicSession session;
}
