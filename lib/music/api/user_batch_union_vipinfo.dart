/// 批量作者会员端点——EchoMusicNext
/// `crates/echo-api/src/module/user_batch_union_vipinfo.rs` 的翻译
/// （docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 匿名可查、走常规签名（request_endpoint）；产品对象里未消费的字段用
/// flatten 原样保留，未知条目不丢弃已知条目（response::object 语义）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/user_models.dart';

/// POST /v2/batch_union_vipinfo（vip 主机；query 走默认参数 + 签名）。
Future<List<MusicUserBatchAuthorProducts>> fetchUserBatchUnionVipinfo(
  MusicSession session,
  List<int> userIds,
) async {
  if (userIds.isEmpty || userIds.length > 20) {
    throw const KugouApiException('input', '作者会员每批最多20人');
  }
  if (userIds.any((id) => id < 0)) {
    // u64 域（上游 Query.user_ids: Vec<u64>，负数在入口即拒）。
    throw const KugouApiException('input', '作者用户 id 无效');
  }
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.vip,
      path: '/v2/batch_union_vipinfo',
      method: 'POST',
      // json! BTreeMap 字典序；get_type 是字符串"2"，clientappid 空串。
      body: encodeJsonBody(<String, Object?>{
        'busi_type': 'concept',
        'clientappid': '',
        'get_type': '2',
        'useridlist': List<int>.of(userIds),
      }),
      headers: const <(String, String)>[
        ('Content-Type', 'application/json; charset=utf-8'),
      ],
    ),
  );
  return _convertAuthorProducts(response.bytes);
}

/// wire 解析（user_batch_union_vipinfo.rs `convert`）。
///
/// 这里的 Wire 是平铺结构（status 必填、error_code 可缺省、data 走
/// response::object 缺省），不走通用 decodeEnvelope；过期判定保留传输层语义。
List<MusicUserBatchAuthorProducts> _convertAuthorProducts(Uint8List bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  final root = wireMap(decoded);
  if (root == null) {
    throw const KugouApiException('decode', '作者会员响应不是 JSON object');
  }
  final message = root['msg'];
  final expiredMessage = message is String && message.contains('登录已过期');
  if (expiredMessage ||
      optionalInt(root['error_code']) == kugouErrorCodeAuthenticationExpired) {
    throw const KugouApiException('authentication', '登录已过期，请重新登录酷狗账号');
  }
  final status = requiredScalarInt(root['status'], 'status');
  final errorCode = optionalInt(root['error_code']) ?? 0;
  ensureBusinessSuccess(status, errorCode, context: '作者会员');
  // data 缺省/不可读 → Data::default（response::object 的 unwrap_or_default）：
  // 空 busi_vip 成功返回，不判 decode。
  final data = wireMap(root['data']) ?? const <String, Object?>{};
  final byUser = wireMap(data['busi_vip']);
  if (byUser == null || byUser.isEmpty) {
    return const <MusicUserBatchAuthorProducts>[];
  }
  // BTreeMap 迭代按 key 字典序；任一 user 的条目不可解析 → 整个 data 回
  // 默认（空），不逐项丢弃。
  final result = <MusicUserBatchAuthorProducts>[];
  final userIds = byUser.keys.toList()..sort();
  for (final userId in userIds) {
    final rawItems = byUser[userId];
    if (rawItems is! List) {
      return const <MusicUserBatchAuthorProducts>[];
    }
    final products = <MusicUserBatchMembership>[];
    for (final item in rawItems) {
      final wire = wireMap(item);
      if (wire == null) {
        return const <MusicUserBatchAuthorProducts>[];
      }
      final isVip = optionalInt(wire['is_vip']);
      // flatten 捕获：除已消费的三个键外原样保留（含 null 值）。
      final extension = <String, Object?>{
        for (final entry in wire.entries)
          if (entry.key != 'product_type' &&
              entry.key != 'is_vip' &&
              entry.key != 'y_type')
            entry.key: entry.value,
      };
      products.add(
        MusicUserBatchMembership(
          product: wireText(wire['product_type']),
          activeCode: isVip,
          active: optionalBool(isVip),
          yearCode: optionalInt(wire['y_type']),
          extension: extension,
        ),
      );
    }
    result.add(
      MusicUserBatchAuthorProducts(userId: userId, products: products),
    );
  }
  return result;
}
