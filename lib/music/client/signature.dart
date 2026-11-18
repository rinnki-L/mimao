/// 酷狗签名算法——EchoMusicNext `crates/echo-api/src/util/signature.rs` 的
/// 逐函数翻译（docs/architecture.md §4.3：`music/client/` ← util，Rust 只读）。
///
/// 协议常数与字节序已由上游对照 EchoMusic 的 server/util/helper.js 验证；
/// 这里再以独立 Python 实现生成的黄金向量交叉验证（test/music/client/）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Android 网关签名：salt + 按 key 排序的 `key=value` 连接串 + 请求体 + salt，
/// 取 MD5 小写 hex。[params] 必须是**未编码**的原始值；body 用实际发送的字节。
String kugouSignatureAndroid(Map<String, String> params, List<int> body) {
  return _md5Signature(
    utf8.encode('LnT6xpN3khm36zse0QzvmgTZ3waWdRSA'),
    params,
    body,
  );
}

/// H5/二维码登录等端点的签名（同字节序，不同 salt）。
String kugouSignatureWeb(Map<String, String> params, List<int> body) {
  return _md5Signature(
    utf8.encode('NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt'),
    params,
    body,
  );
}

/// 标准版/移动端 CDN 封面签名——该端点忽略 lite 身份。
String kugouSignatureAlbumCover(Map<String, String> params) {
  return _md5Signature(
    utf8.encode('OIlwieks28dk2k092lksi2UIkp'),
    params,
    const <int>[],
  );
}

/// 私有 tracker 的 key：自带 lite salt，且包含确切的请求 hash/mid。
String kugouTrackerKey(String hash, String mid, int userId) {
  return _md5Hex(
    utf8.encode(
      '$hash'
      '185672dd44712f60bb1736df5a377e823116'
      '$mid$userId',
    ),
  );
}

/// 云盘接口的 key。
String kugouCloudKey(String hash) {
  return _md5Hex(
    utf8.encode(
      'musicclound$hash'
      '20026ebd1ac3134c880bda6a2194537843caa0162e2e7',
    ),
  );
}

/// 共同字节序：salt + 排序后的 `key=value` 连接 + body + salt → MD5。
String _md5Signature(
  List<int> salt,
  Map<String, String> params,
  List<int> body,
) {
  final builder = BytesBuilder(copy: false);
  builder.add(salt);
  // BTreeMap 语义 = 按 key 字节序排序；协议参数 key 全部是 ASCII，
  // Dart 字符串比较（UTF-16 码元序）对 ASCII 等价。
  final keys = params.keys.toList()..sort();
  for (final key in keys) {
    builder.add(utf8.encode(key));
    builder.add(utf8.encode('='));
    builder.add(utf8.encode(params[key]!));
  }
  builder.add(body);
  builder.add(salt);
  return _md5Hex(builder.toBytes());
}

String _md5Hex(List<int> bytes) => md5.convert(bytes).toString();
