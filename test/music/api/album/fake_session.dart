/// 专辑组测试共享：假 [MusicSession]（ensureDevice/loadIdentity 直接返回
/// identity，不联网）与固定身份（mid/dfid 稳定，签名自验可复现）。
library;

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';

/// 固定身份：匿名（userId=0/token=''），mid/dfid/guid 全部确定值。
KugouIdentity fixedIdentity() => KugouIdentity(
  userId: 0,
  token: '',
  t1: '',
  mid: 'a1b2c3d4e5f6a7b8a1b2c3d4e5f6a7b8',
  dfid: '-',
  uuid: '-',
  guid: '0123456789abcdef0123456789abcdef',
  mac: '02:00:00:00:00:00',
  deviceName: '',
  renderFingerprint: '',
);

/// 假会话；[ensureDevice] 可替换（如断言「动态封面绝不触发设备注册」）。
MusicSession fakeMusicSession(
  KugouClient client, {
  KugouIdentity? identity,
  Future<KugouIdentity> Function()? ensureDevice,
}) {
  final id = identity ?? fixedIdentity();
  return MusicSession(
    client: client,
    ensureDevice: ensureDevice ?? (() async => id),
    loadIdentity: () async => id,
    saveIdentity: (_) async {},
  );
}
