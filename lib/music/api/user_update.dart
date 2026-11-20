/// 资料更新端点——EchoMusicNext `crates/echo-api/src/module/user_update.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 字段是类型化的差量补丁：空 signature/birthday 表示清除，其余字段空值
/// 直接拒绝；响应是 `data=""/status1/error0` 的确认信封（AckEnvelope）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/user_models.dart';

/// 资料更新的差量输入（user_update.rs `Query`，deny_unknown_fields）。
class MusicUserUpdateQuery {
  const MusicUserUpdateQuery({
    this.nickname,
    this.gender,
    this.birthday,
    this.signature,
    this.province,
    this.city,
  });

  final String? nickname;

  /// 0/1/2（wire `sex`）；null 表示不改。
  final int? gender;
  final String? birthday;

  /// 个性签名；空串=清空（唯一允许空值的文本字段之一）。
  final String? signature;
  final String? province;
  final String? city;

  /// 字段校验与差量装配（user_update.rs `fields`）。
  Map<String, String> collectFields() {
    final fields = <String, String>{};
    final gender = this.gender;
    if (gender != null) {
      // 上游是 u32：负数在入口反序列化就会被拒，这里按同域拒绝。
      if (gender < 0 || gender > 2) {
        throw const KugouApiException('input', '性别无效');
      }
      fields['sex'] = '$gender';
    }
    // 字段顺序与 Rust fields() 的循环一致（BTreeMap 序列化时仍按字典序）。
    for (final (key, value) in <(String, String?)>[
      ('nickname', nickname),
      ('birthday', birthday),
      ('signature', signature),
      ('province', province),
      ('city', city),
    ]) {
      if (value == null) continue;
      // signature/birthday 允许空串（语义=清除）；其余字段空串直接拒绝。
      if (value.isEmpty && key != 'signature' && key != 'birthday') {
        throw const KugouApiException('input', '资料字段不能为空');
      }
      // Rust encode_utf16().count()：按 UTF-16 码元数计量。
      if (key == 'signature' && value.codeUnits.length > 120) {
        throw const KugouApiException('input', '个性签名最多120个字符');
      }
      fields[key] = value;
    }
    if (fields.isEmpty) {
      throw const KugouApiException('input', '资料没有变化');
    }
    return fields;
  }
}

/// POST /v1/update_userinfo（网关 + x-router=update.user.kugou.com）。
Future<MusicUserUpdateResult> fetchUserUpdate(
  MusicSession session,
  MusicUserUpdateQuery query,
) async {
  final identity = await session.ensureDevice();
  final data = query.collectFields();
  final bytes = await submitUserFields(session, identity, data);
  return _convertUserUpdate(bytes);
}

/// 账号写入共享协议（user_update.rs `submit_fields`，pub(crate)——组内
/// user_update_avatar 复用；认证在 body 的 key/p，URL 无默认参数、无签名）。
Future<Uint8List> submitUserFields(
  MusicSession session,
  KugouIdentity identity,
  Map<String, String> data,
) async {
  requireMusicAccount(identity);
  final time = _clock(session).millisecondsSinceEpoch ~/ 1000;
  final portrait = kugouUserPortrait(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'clienttime': time,
        'token': identity.token,
      }),
    ),
  );
  // data 是 BTreeMap：序列化键序按字典序（参与服务端校验）。
  final sortedData = <String, String>{
    for (final key in data.keys.toList()..sort()) key: data[key]!,
  };
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v1/update_userinfo',
      router: 'update.user.kugou.com',
      method: 'POST',
      // request_grade：cloud+clearDefaults → URL 不带默认参数、无签名。
      body: encodeJsonBody(<String, Object?>{
        'appid': 3116,
        'clienttime': time,
        'clientver': 11440,
        'data': sortedData,
        'key': kugouCloudListKeyedTime(time),
        'mid': identity.mid,
        'p': portrait,
        'userid': identity.userId,
        'uuid': '-',
      }),
    ),
    cloud: true,
    clearDefaults: true,
  );
  return response.bytes;
}

/// wire 解析（user_update.rs `convert`）：确认信封，成功即 updated=true。
MusicUserUpdateResult _convertUserUpdate(Uint8List bytes) {
  decodeBusinessEnvelope(bytes, context: '资料更新');
  return const MusicUserUpdateResult(updated: true);
}

/// 端点自用时钟：与 KugouClient 的查询时间戳共用同一注入缝（测试固定时间）。
DateTime _clock(MusicSession session) =>
    session.client.now?.call() ?? DateTime.now();
