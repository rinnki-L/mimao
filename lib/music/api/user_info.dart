/// 用户身份展示端点——EchoMusicNext `crates/echo-api/src/module/user_info.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 只取学生身份与展示标签白名单；联系方式与关联 Provider 的私密字段在
/// 上游就刻意丢弃（文件头注释），这里同样不收。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/user_models.dart';

/// 标签拆分（user_info.rs `identity_labels`，user_detail 复用）：
/// 按中英文逗号/顿号/分号/换行拆开、去首尾空白、丢弃空段并按原顺序去重。
List<String> userIdentityLabels(String text) {
  final labels = <String>[];
  for (final part in text.split(RegExp('[,，、;；\n]'))) {
    final label = part.trim();
    if (label.isEmpty || labels.contains(label)) continue;
    labels.add(label);
  }
  return labels;
}

/// POST /v1/get_my_userinfo（网关 + x-router=relation.user.kugou.com）。
///
/// 协议要点（user_info.rs `execute`）：body 认证在 key/p（固定盐 + **毫秒**）
/// ——与云歌单 keyed_time 同盐但传毫秒（util/user_protocol.rs timestamp_key）。
Future<MusicUserIdentityTags> fetchUserInfo(MusicSession session) async {
  final identity = await session.ensureDevice();
  requireMusicAccount(identity);
  final time = _clock(session).millisecondsSinceEpoch;
  final portrait = kugouUserPortrait(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'clienttime': time,
        'token': identity.token,
      }),
    ),
  );
  // json! 序列化按 BTreeMap 字典序：键序必须逐字对齐（参与签名与服务端校验）。
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v1/get_my_userinfo',
      router: 'relation.user.kugou.com',
      method: 'POST',
      body: encodeJsonBody(<String, Object?>{
        'appid': 3116,
        'clienttime': time,
        'clientver': 11440,
        'key': kugouCloudListKeyedTime(time),
        'mid': identity.mid,
        'p': portrait,
        'source': 0,
        'userid': identity.userId,
        'uuid': '-',
      }),
    ),
  );
  return _convertUserIdentity(response.bytes);
}

/// wire 解析（user_info.rs `convert`）。
MusicUserIdentityTags _convertUserIdentity(Uint8List bytes) {
  final envelope = decodeBusinessEnvelope(bytes, context: '用户身份');
  // Data 是必填 object：data:null（失效 token 的真实形态）→ decode，
  // 不能静默回退成空资料（上游 from_value 同语义）。
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '用户身份响应 data 不是 object');
  }
  return MusicUserIdentityTags(
    studentStatus: optionalInt(data['student_status']),
    studentSchool: wireText(data['student_school']),
    studentExpireTime: wireText(data['student_expire_time']),
    tags: userIdentityLabels(wireText(data['tags'])),
  );
}

/// 端点自用时钟：与 KugouClient 的查询时间戳共用同一注入缝（测试固定时间）。
DateTime _clock(MusicSession session) =>
    session.client.now?.call() ?? DateTime.now();
