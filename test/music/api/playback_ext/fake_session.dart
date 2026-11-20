/// playback_ext 组测试共享：假 MusicSession（ensureDevice/loadIdentity 直接
/// 返回 identity，不联网、不落盘）。
library;

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';

MusicSession fakePlaybackSession(KugouClient client, KugouIdentity identity) =>
    MusicSession(
      client: client,
      ensureDevice: () async => identity,
      loadIdentity: () async => identity,
      saveIdentity: (_) async {},
    );
