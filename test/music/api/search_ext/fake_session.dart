/// 测试用假 MusicSession——不联网：ensureDevice/loadIdentity 直接回注入身份
/// （规格第 6 节；CaptureAdapter 负责请求捕获）。
library;

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';

MusicSession fakeMusicSession(KugouClient client, KugouIdentity identity) =>
    MusicSession(
      client: client,
      ensureDevice: () async => identity,
      loadIdentity: () async => identity,
      saveIdentity: (_) async {},
    );
