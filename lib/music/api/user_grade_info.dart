/// 听歌等级端点——EchoMusicNext `crates/echo-api/src/module/user_grade_info.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 查询其它账号的等级保持匿名、绝不采用他人凭证（上游文件头注释）；本端点
/// 不做登录预判——user_id 缺省取当前账号，取 0 时本地拒绝「账号不存在」。
/// 听歌上报（report/progress 分支）归 G14，不在此文件。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/user_models.dart';

/// 等级协议的时间键盐（user_grade_info.rs `execute`：clientver 10597 变体，
/// 注意与云歌单 11440 盐不同）。
const String _kGradeKeySalt = '3116LnT6xpN3khm36zse0QzvmgTZ3waWdRSA10597';

/// 查询输入（user_grade_info.rs `Query`）：null=查当前账号。
class MusicUserGradeQuery {
  const MusicUserGradeQuery({this.userId});

  final int? userId;
}

/// POST /v2/get_grade_info（网关 + x-router=userinfo.user.kugou.com）。
///
/// request_grade 语义（cloud+clearDefaults）：URL 只带 dfid、无签名；
/// 认证在 body 的 p（user_portrait）与 key（10597 盐 + 秒）。
Future<MusicUserGradeInfo> fetchUserGradeInfo(
  MusicSession session,
  MusicUserGradeQuery query, {
  Random? random,
}) async {
  final identity = await session.ensureDevice();
  final userId = query.userId ?? identity.userId;
  if (userId < 0) {
    // u64 域（上游 Query.user_id: Option<u64>，负数在入口即拒）。
    throw const KugouApiException('input', '用户 id 无效');
  }
  if (userId == 0) {
    throw const KugouApiException('input', '账号不存在');
  }
  final time = _clock(session).millisecondsSinceEpoch ~/ 1000;
  final portrait = kugouUserPortrait(
    utf8.encode(
      jsonEncode(<String, Object?>{'clienttime': time, 'userid': userId}),
    ),
  );
  // json! 的 appid/clientver 在此端点是**字符串**（与 user_info 的数字不同）。
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v2/get_grade_info',
      router: 'userinfo.user.kugou.com',
      method: 'POST',
      params: <String, String>{'dfid': identity.dfid},
      body: encodeJsonBody(<String, Object?>{
        'appid': '3116',
        'clienttime': time,
        'clientver': '10597',
        'key': md5.convert(utf8.encode('$_kGradeKeySalt$time')).toString(),
        'mid': identity.mid,
        'p': portrait,
        'type': 1,
        'userid': userId,
        'uuid': identity.uuid,
      }),
      headers: <(String, String)>[
        ('Content-Type', 'text/plain; charset=ISO-8859-1'),
        ('User-Agent', 'Android15-1070-10597-201-0-get_user_grade_info-wifi'),
        ('KG-Rec', '1'),
        ('KG-RC', '1'),
        ('KG-THash', _traceHash(random ?? Random.secure())),
      ],
    ),
    cloud: true,
    clearDefaults: true,
  );
  return _convertUserGradeInfo(response.bytes);
}

/// 追踪哈希（user_grade_info.rs：u32 & 0x0fff_ffff → 7 位小写 hex）。
String _traceHash(Random random) {
  final value =
      (random.nextInt(256) << 24) |
      (random.nextInt(256) << 16) |
      (random.nextInt(256) << 8) |
      random.nextInt(256);
  return (value & 0x0FFFFFFF).toRadixString(16).padLeft(7, '0');
}

/// wire 解析（user_grade_info.rs `convert`）。
MusicUserGradeInfo _convertUserGradeInfo(Uint8List bytes) {
  final envelope = decodeBusinessEnvelope(bytes, context: '听歌等级');
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '听歌等级响应 data 不是 object');
  }
  return MusicUserGradeInfo(
    userId: optionalInt(data['userid']),
    grade: optionalInt(data['p_grade']),
    listeningSeconds: optionalInt(data['d_sec']),
    currentPoints: optionalInt(data['p_current_point']),
    gradePoints: optionalInt(data['p_grade_point']),
    nextGradePoints: optionalInt(data['p_next_grade_point']),
    nextGrade: optionalInt(data['p_next_grade']),
  );
}

/// 端点自用时钟：与 KugouClient 的查询时间戳共用同一注入缝（测试固定时间）。
DateTime _clock(MusicSession session) =>
    session.client.now?.call() ?? DateTime.now();
