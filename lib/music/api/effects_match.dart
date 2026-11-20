/// 耳机音效匹配——EchoMusicNext `crates/echo-api/src/module/effects_match.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 走公开音效目录（`request_effect_catalog` → `send_endpoint(cloud=false,
/// clear_defaults=true)`）；无 Query（上游 execute 只带 identity）。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/models/effects_models.dart';

/// GET /api/v5/earphone/match：服务端按当前设备匹配耳机型号音效；无匹配
/// → null（effects_match.rs `convert` 返回可选 Effect）。
Future<MusicEffect?> fetchEffectsMatch(MusicSession session) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    const KugouEndpoint(
      origin: KugouOrigin.effectsCatalog,
      path: '/api/v5/earphone/match',
      method: 'GET',
      params: <String, String>{'plat': '2', 'version': '12460'},
    ),
    clearDefaults: true,
  );
  return _convertMatch(response.bytes);
}

/// effects_match.rs `convert`：data.common 走 response.rs `optional`——common
/// 缺失/为 null/结构非法（缺 sound、缺 id、非 object）都吞成 null，不抛 decode。
MusicEffect? _convertMatch(Uint8List bytes) {
  final envelope = decodeEffectsEnvelope(bytes);
  final data = requiredWireMap(envelope.data, 'data');
  return effectsHeadphoneFromWire(data['common']);
}
