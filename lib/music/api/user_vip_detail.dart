/// 联合会员端点——EchoMusicNext `crates/echo-api/src/module/user_vip_detail.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 独立于资料响应解析；时间文本是 provider 的本地时间（无时区），只把
/// 「YYYY-MM-DD HH:MM:SS」的空格换成 T，不臆造 UTC。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/user_models.dart';

/// GET /v1/get_union_vip（vip 主机，query busi_type=concept）。
Future<MusicUserVipMemberships> fetchUserVipDetail(MusicSession session) async {
  final identity = await session.ensureDevice();
  requireMusicAccount(identity);
  final response = await session.client.sendEndpoint(
    identity,
    const KugouEndpoint(
      origin: KugouOrigin.vip,
      path: '/v1/get_union_vip',
      method: 'GET',
      params: <String, String>{'busi_type': 'concept'},
    ),
  );
  return _convertUserVipDetail(response.bytes);
}

/// wire 解析（user_vip_detail.rs `convert`）。
MusicUserVipMemberships _convertUserVipDetail(Uint8List bytes) {
  final envelope = decodeBusinessEnvelope(bytes, context: '会员信息');
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '会员信息响应 data 不是 object');
  }
  final products = <MusicUserVipMembershipProduct>[];
  for (final raw in wireList(data['busi_vip'], 'busi_vip')) {
    final wire = wireMap(raw);
    if (wire == null) {
      throw const KugouApiException('decode', '会员产品项不是 object');
    }
    final isVip = optionalInt(wire['is_vip']);
    products.add(
      MusicUserVipMembershipProduct(
        // active=展示布尔（0/1），active_code 保留原始码（numeric::boolean 链）。
        active: optionalBool(isVip),
        activeCode: isVip,
        product: wireText(wire['product_type']),
        business: wireText(wire['busi_type']),
        beginsAt: _expiry(wireText(wire['vip_begin_time'])),
        expiresAt: _expiry(wireText(wire['vip_end_time'])),
      ),
    );
  }
  return MusicUserVipMemberships(
    userId: optionalInt(data['userid']),
    vipTypeCode: optionalInt(data['vip_type']),
    userTypeCode: optionalInt(data['user_type']),
    deluxeBeginsAt: _expiry(wireText(data['vip_begin_time'])),
    superBeginsAt: _expiry(wireText(data['su_vip_begin_time'])),
    deluxeExpiresAt: _expiry(wireText(data['vip_end_time'])),
    superExpiresAt: _expiry(wireText(data['su_vip_end_time'])),
    products: products,
  );
}

/// 时间文本 → ISO 本地时间（user_vip_detail.rs `expiry`）。
String? _expiry(String value) {
  if (value.isEmpty) return null;
  final iso = value;
  // 仅纯 ASCII 且第 11 个字节是空格时替换为 T（避免破坏多字节文本）。
  final ascii = value.codeUnits.every((unit) => unit >= 0 && unit <= 0x7f);
  if (ascii && value.length > 10 && value.codeUnitAt(10) == 0x20) {
    return iso.replaceRange(10, 11, 'T');
  }
  return iso;
}
