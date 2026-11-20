/// 踢出登录设备端点——EchoMusicNext `crates/echo-api/src/module/login_device_kick.rs`
/// 的逐函数翻译。
///
/// `p` 参数是 `moc.uoguk.59::<token>` 画像的 RSA hex（前缀 `h5`）；走
/// userservice 的 dev_logout（origin DeviceLogout，web 签名由传输层注入）；
/// 只允许移除「其它」设备。
library;

import 'dart:convert';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/auth_models.dart';

/// 踢出目标（login_device_kick.rs `Query`；字段全部来自设备列表行）。
class MusicDeviceKickQuery {
  const MusicDeviceKickQuery({
    required this.targetMid,
    required this.activeAtSeconds,
    required this.appId,
    required this.clientVersion,
    this.transportFingerprint = '',
  });

  /// 目标设备 mid（必须不是当前设备）。
  final String targetMid;
  final int activeAtSeconds;
  final int appId;
  final int clientVersion;

  /// 目标设备指纹（wire `mt`）；空串按上游约定送 '-'。
  final String transportFingerprint;

  /// 组合校验（依赖当前身份 mid，见 [fetchLoginDeviceKick]）。
  void validate(String ownMid) {
    if (targetMid.isEmpty ||
        targetMid == ownMid ||
        activeAtSeconds == 0 ||
        appId == 0 ||
        clientVersion == 0) {
      throw const KugouApiException('input', '请选择可移除的其它登录设备');
    }
  }
}

/// /loginservice/v1/dev_logout（origin DeviceLogout；web 签名）。
///
/// `timestampMs` 仅供测试注入。
Future<MusicDeviceKickResult> fetchLoginDeviceKick(
  MusicSession session,
  MusicDeviceKickQuery query, {
  int? timestampMs,
}) async {
  final identity = await session.ensureDevice();
  requireMusicAccount(identity);
  query.validate(identity.mid);
  final token =
      'h5${kugouUserPortrait(utf8.encode('moc.uoguk.59::${identity.token}'))}';
  final time = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.deviceLogout,
      path: '/loginservice/v1/dev_logout',
      method: 'GET',
      params: <String, String>{
        'token': token,
        'clienttime': '$time',
        'srcappid': '2919',
        'plat': '1',
        't_mid': query.targetMid,
        't': '${query.activeAtSeconds}',
        't_appid': '${query.appId}',
        't_clientver': '${query.clientVersion}',
        'dfid': query.transportFingerprint.isEmpty
            ? '-'
            : query.transportFingerprint,
        'uuid': '-',
      },
    ),
  );
  // AckEnvelope：只有 status/error_code（20018 由 decodeEnvelope 统一判）。
  final envelope = decodeEnvelope(response.bytes);
  if (envelope.errorCode == 20018) {
    throw const KugouApiException('authentication', '登录已过期，请重新登录酷狗账号');
  }
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '踢出设备');
  return const MusicDeviceKickResult(removed: true);
}
