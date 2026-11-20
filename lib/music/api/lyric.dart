/// 歌词下载端点——EchoMusicNext `crates/echo-api/src/module/lyric.rs` 的
/// 逐函数翻译。
///
/// 上游模块注释：Kugou 歌词下载信封与请求协议；**文档解码归 C++ 歌词
/// 服务**——这里只透传 base64 原文，不解 base64、不解析歌词文档。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/lyric_models.dart';

/// 歌词信封的成功 status——**200**，不是常规业务信封的 1（lyric.rs convert）。
const int _lyricStatusOk = 200;

/// content 字节预算（lyric.rs：`content.len() > 4 * 1024 * 1024` →
/// resource_limit）。
const int _lyricContentByteLimit = 4 * 1024 * 1024;

/// 下载输入（lyric.rs `Query`：id + accesskey 都必填）。
class MusicLyricDownloadQuery {
  const MusicLyricDownloadQuery({required this.id, required this.accesskey});

  final String id;
  final String accesskey;

  void validate() {
    // 上游按原始串判空（不 trim）：任一为空 → input「歌词标识不完整」。
    if (id.isEmpty || accesskey.isEmpty) {
      throw const KugouApiException('input', '歌词标识不完整');
    }
  }
}

/// GET /download（lyrics.kugou.com；普通签名请求路径——保留设备默认参数与
/// Android 签名，上游注释：Download uses the ordinary signed request path）。
Future<MusicLyricDownload> fetchLyricDownload(
  MusicSession session,
  MusicLyricDownloadQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.lyrics,
      path: '/download',
      method: 'GET',
      params: <String, String>{
        'ver': '1',
        'client': 'android',
        'id': query.id,
        'accesskey': query.accesskey,
        'fmt': 'krc',
        'charset': 'utf8',
      },
    ),
  );
  return _convertLyricDownload(response.bytes);
}

/// wire 解析（lyric.rs `convert` + `Wire`）。
MusicLyricDownload _convertLyricDownload(Uint8List bytes) {
  // request::decode：JSON 信封 + 登录过期先行（error_code=20018 / msg 含
  // 「登录已过期」→ authentication）。与 wire.decodeEnvelope 同语义；lyric
  // 信封还要取 contenttype/content，这里组内自带一份轻量解析。
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  if (decoded is! Map) {
    throw const KugouApiException('decode', '响应信封不是 JSON object');
  }
  final wire = Map<String, Object?>.from(decoded);
  final message = wire['msg'];
  final expiredMessage = message is String && message.contains('登录已过期');
  final rawErrorCode = optionalInt(wire['error_code']);
  if (expiredMessage || rawErrorCode == kugouErrorCodeAuthenticationExpired) {
    throw const KugouApiException('authentication', '登录已过期，请重新登录酷狗账号');
  }

  // Wire 结构体：status/error_code/contenttype 必填标量；content 是 text
  // （缺省/bool/复合 → ''）。
  int status;
  int errorCode;
  int contentType;
  try {
    status = requiredScalarInt(wire['status'], 'status');
    errorCode = requiredScalarInt(wire['error_code'], 'error_code');
    contentType = requiredScalarInt(wire['contenttype'], 'contenttype');
  } on KugouApiException catch (error) {
    if (error.kind != 'decode') rethrow;
    // decode_envelope(bytes, "error_code")：结构解析失败时只恢复业务码——
    // error_code 可解且非 0 → business(code)；status 可解为 u32 且为 0 →
    // business(0)；否则维持 decode。
    final recovered = _recoveredBusinessCode(wire);
    if (recovered != null) {
      throw KugouApiException('business', '歌词获取失败', code: recovered);
    }
    rethrow;
  }

  if (status != _lyricStatusOk || errorCode != 0) {
    throw KugouApiException('business', '歌词获取失败', code: errorCode);
  }

  // contenttype 0/1/2 → krc/lrc/text；其它 → unsupported。
  final String format = switch (contentType) {
    0 => 'krc',
    1 => 'lrc',
    2 => 'text',
    _ => throw const KugouApiException('unsupported', '暂不支持此歌词编码'),
  };

  final content = wireText(wire['content']);
  // Rust String::len() 是 UTF-8 字节数；base64 内容恒为 ASCII，这里按字节
  // 语义精确计算（超预算 → resource_limit，本仓库 kind 词表记为 limit）。
  if (utf8.encode(content).length > _lyricContentByteLimit) {
    throw const KugouApiException('limit', '接口资源超过解码内存预算');
  }
  return MusicLyricDownload(
    format: format,
    encoding: 'base64',
    content: content,
  );
}

/// decode_envelope 的业务码恢复（response.rs 语义）：error_code 解为 i64 且
/// 非 0 → 取它；否则 status 解为 u32 且等于 0 → 0；再否则返回 null（维持
/// decode）。
int? _recoveredBusinessCode(Map<String, Object?> wire) {
  final code = optionalInt(wire['error_code']);
  if (code != null && code != 0) {
    return code;
  }
  final status = optionalInt(wire['status']);
  if (status == 0) {
    return 0;
  }
  return null;
}
