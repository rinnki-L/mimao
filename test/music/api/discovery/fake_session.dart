/// 发现/推荐组测试共享：假 MusicSession（规格 §6——不联网、ensureDevice
/// 直接返回注入身份）与带账号身份构造。
library;

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';

export 'package:mimao/music/api/session.dart' show MusicSession;

/// `ensureDevice: () async => identity` 的假会话。
MusicSession fakeMusicSession(KugouClient client, KugouIdentity identity) =>
    MusicSession(
      client: client,
      ensureDevice: () async => identity,
      loadIdentity: () async => identity,
      saveIdentity: (_) async {},
    );

/// 匿名设备身份（guid/mid 由 calculateMid 生成，dfid 还是 '-' 占位）。
KugouIdentity anonymousIdentity() => KugouIdentity.anonymous();

/// 带账号身份（personal_fm 的 require_account 需要）。
KugouIdentity accountIdentity() => const KugouIdentity(
  userId: 12345,
  token: 'token-abc',
  t1: '',
  mid: 'mid-1',
  dfid: 'dfid-1',
  uuid: '-',
  guid: 'guid-1',
  mac: '02:00:00:00:00:00',
  deviceName: '',
  renderFingerprint: '',
);
