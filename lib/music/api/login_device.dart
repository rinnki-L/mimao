/// 登录设备列表端点——EchoMusicNext `crates/echo-api/src/module/login_device.rs`
/// 的逐函数翻译。
///
/// 加密 token 信封保持纯协议用途（`kugouLoginEnvelope`），本层只把
/// data.li 的设备行模型化；当前设备标记按 mid 相等判定，排序为「当前设备
/// 优先、其余按活跃时间倒序」。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/login.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/auth_models.dart';

/// /v2/get_dev（网关 + x-router=userinfoservice.kugou.com）。
///
/// `timestampMs`/`seed` 仅供测试注入。
Future<List<MusicLoginDevice>> fetchLoginDevice(
  MusicSession session, {
  int? timestampMs,
  String? seed,
}) async {
  final identity = await session.ensureDevice();
  requireMusicAccount(identity);
  final time = timestampMs ?? DateTime.now().millisecondsSinceEpoch;
  final envelope = kugouLoginEnvelope(
    <String, Object?>{'token': identity.token},
    time,
    seed: seed,
  );
  // serde_json BTreeMap 键序。
  final body = <String, Object?>{
    'clienttime_ms': time,
    'params': envelope.params,
    'pk': envelope.portrait,
    'plat': 1,
    'userid': identity.userId,
  };
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v2/get_dev',
      router: 'userinfoservice.kugou.com',
      method: 'POST',
      body: encodeJsonBody(body),
    ),
  );
  return _convert(response.bytes, identity.mid);
}

/// wire 解析（login_device.rs `convert`）。
List<MusicLoginDevice> _convert(Uint8List bytes, String currentMid) {
  final envelope = decodeEnvelope(bytes);
  if (envelope.errorCode == 20018) {
    throw const KugouApiException('authentication', '登录已过期，请重新登录酷狗账号');
  }
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '登录设备');
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '登录设备响应 data 不是 object');
  }
  final rows = wireList(data['li'], 'li');
  final devices = <MusicLoginDevice>[];
  for (final row in rows) {
    final map = wireMap(row);
    if (map == null) {
      throw const KugouApiException('decode', '登录设备行不是 object');
    }
    devices.add(
      MusicLoginDevice(
        id: wireText(map['mid']),
        transportFingerprint: wireText(map['mt']),
        model: wireText(map['dev']),
        platform: wireText(map['app']),
        location: wireText(map['loc']),
        // 本地刷新的临时会话上报 -1，未知码保留（上游注释）。
        loginType: authOptionalI64(map['login_type']),
        activeAtSeconds: authOptionalU64(map['t']),
        newAtSeconds: authOptionalU64(map['new']),
        appId: authOptionalU64(map['appid']),
        clientVersion: authOptionalU64(map['ver']),
        current: wireText(map['mid']) == currentMid,
      ),
    );
  }
  // 排序：当前设备优先，其余按活跃时间倒序；并列时保持行序（上游稳定排序）。
  final index = List<int>.generate(devices.length, (i) => i);
  index.sort((a, b) {
    final left = devices[a];
    final right = devices[b];
    final byCurrent = (right.current ? 1 : 0).compareTo(left.current ? 1 : 0);
    if (byCurrent != 0) return byCurrent;
    final byActive = _optionDesc(left.activeAtSeconds, right.activeAtSeconds);
    if (byActive != 0) return byActive;
    return a.compareTo(b);
  });
  return <MusicLoginDevice>[for (final i in index) devices[i]];
}

/// Option 的时间倒序（Rust `b.active_at_seconds.cmp(&a.active_at_seconds)`；
/// None < Some）。
int _optionDesc(int? a, int? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1; // a(None) 排后面
  if (b == null) return -1;
  return b.compareTo(a);
}
