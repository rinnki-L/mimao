/// 个人主页资料端点——EchoMusicNext `crates/echo-api/src/module/user_detail.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 账号 id 来自调用方身份快照（上游注释：/user/detail 的 ID comes from the
/// caller context）；省市是可编辑偏好，loc 只是 IP 属地展示文本。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/user_info.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/user_models.dart';

/// POST /v3/get_my_info（网关 + x-router=usercenter.kugou.com，query plat=1）。
///
/// 协议要点（user_detail.rs `execute`）：p 的明文是 **struct 序**
/// `{"token":…,"clienttime":…}`（serde 结构体按声明序，不走 BTreeMap）；
/// body 字段序 `visit_time/usertype/p/userid`；时间用**秒**。
Future<MusicUserProfile> fetchUserDetail(MusicSession session) async {
  final identity = await session.ensureDevice();
  requireMusicAccount(identity);
  final timestamp = _clock(session).millisecondsSinceEpoch ~/ 1000;
  final portrait = kugouUserPortrait(
    utf8.encode(
      // Portrait struct 声明序：token 在前、clienttime 在后。
      jsonEncode(<String, Object?>{
        'token': identity.token,
        'clienttime': timestamp,
      }),
    ),
  );
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v3/get_my_info',
      router: 'usercenter.kugou.com',
      method: 'POST',
      params: const <String, String>{'plat': '1'},
      // Body struct 声明序（user_detail.rs `Body`）。
      body: encodeJsonBody(<String, Object?>{
        'visit_time': timestamp,
        'usertype': 1,
        'p': portrait,
        'userid': identity.userId,
      }),
    ),
  );
  return _convertUserProfile(response.bytes, identity.userId);
}

/// wire 解析（user_detail.rs `convert`）。
MusicUserProfile _convertUserProfile(Uint8List bytes, int userId) {
  final envelope = decodeEnvelope(bytes);
  // 上游在 success 之前单列「status=0 + 20018」防 data:null 变 decode——
  // decodeEnvelope 已按传输层语义把 error_code=20018 映射为 authentication，
  // 这里无需重复分支；其余失败统一 business。
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '用户资料');
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '用户资料响应 data 不是 object');
  }
  final actorStatus = optionalInt(data['actor_status']);
  final businessStatus = optionalInt(data['biz_status']);
  final starStatus = optionalInt(data['tme_star_status']);
  final singerStatus = optionalInt(data['singer_status']);
  final legacyStar = optionalInt(data['is_star']);
  return MusicUserProfile(
    id: userId,
    nickname: wireText(data['nickname']),
    avatarUrl: wireText(data['pic']),
    gender: optionalInt(data['gender']),
    vipType: optionalInt(data['vip_type']),
    follows: optionalInt(data['follows']),
    fans: optionalInt(data['fans']),
    biography: wireText(data['descri']),
    friends: optionalInt(data['friends']),
    grade: optionalInt(data['p_grade']),
    listeningMinutes: optionalInt(data['duration']),
    visitors: optionalInt(data['hvisitors']),
    registeredAtSeconds: optionalInt(data['rtime']),
    province: wireText(data['province']),
    city: wireText(data['city']),
    ipLocation: wireText(data['loc']),
    birthday: wireText(data['birthday']),
    identity: MusicUserProfileIdentity(
      actorCode: actorStatus,
      businessCode: businessStatus,
      starCode: starStatus,
      singerCode: singerStatus,
      legacyStarCode: legacyStar,
      talentBits: optionalInt(data['kq_talent']),
      actor: actorStatus == 1,
      business: businessStatus == 1,
      star: starStatus == 1,
      // 新旧歌手标志任一为 1（user_detail.rs `singer`）。
      singer: singerStatus == 1 || legacyStar == 1,
      authorizations: userIdentityLabels(wireText(data['auth_info'])),
      talentAuthorizations: userIdentityLabels(
        wireText(data['auth_info_talent']),
      ),
      singerAuthorizations: userIdentityLabels(
        wireText(data['auth_info_singer']),
      ),
    ),
  );
}

/// 端点自用时钟：与 KugouClient 的查询时间戳共用同一注入缝（测试固定时间）。
DateTime _clock(MusicSession session) =>
    session.client.now?.call() ?? DateTime.now();
