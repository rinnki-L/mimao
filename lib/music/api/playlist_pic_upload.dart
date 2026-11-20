/// 歌单封面上传端点——EchoMusicNext
/// `crates/echo-api/src/module/playlist_pic_upload.rs` 的翻译
/// （docs/architecture.md §4.3：`music/api/` ← module）。
///
/// 图片服务是与账号无关的 HTTP 裸传输（该主机没有匹配的 HTTPS 证书——上游
/// 注释：这是观察到的上传协议，不是 TLS 回退）。校验和用的是**本地日历日**
/// （旧校验和走本地时间，不是 UTC）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/playlist_write_models.dart';

/// 8 MB 上限（playlist_pic_upload.rs `MAX_PNG_BYTES`）。
const int maxPlaylistPngBytes = 8 * 1024 * 1024;

/// 上传入参（`Query::from_png`：二进制边界自带 PNG 字节与本地日历日）。
class PlaylistPicUploadQuery {
  const PlaylistPicUploadQuery({required this.png, required this.localDate});

  /// PNG 原始字节（仅做帧校验，不做图像解码——上游注释）。
  final Uint8List png;

  /// `yyyyMMdd` 本地日历日（校验和按本地时间，不是 UTC）。
  final String localDate;
}

/// 上传歌单封面（POST http://imgphp.kugou.com/imageupload/stream.php）。
Future<MusicUploadedPlaylistCover> fetchPlaylistPicUpload(
  MusicSession session,
  PlaylistPicUploadQuery query,
) async {
  // 先校验日期（上游 checksum 在 PNG 帧校验之前）。
  final key = kugouImageChecksum(query.localDate);
  final png = query.png;
  // 只做帧校验：截断的签名绝不能发起 HTTP 上传（上游注释）。
  if (png.length > maxPlaylistPngBytes ||
      png.length < 33 ||
      !_hasPngSignature(png) ||
      png[8] != 0 || // 13u32.to_be_bytes() = [0,0,0,13]（IHDR 长度）
      png[9] != 0 ||
      png[10] != 0 ||
      png[11] != 13 ||
      !_hasIhdrTag(png)) {
    throw const KugouApiException('input', '请选择有效的 PNG 封面');
  }
  final response = await session.client.sendRaw(
    url: 'http://imgphp.kugou.com/imageupload/stream.php',
    method: 'POST',
    params: <String, String>{
      'type': 'custom',
      'extendName': '.png',
      'md5': key,
      'jsonResponse': '1',
    },
    headers: const <String, String>{'Content-Type': 'application/octet-stream'},
    body: png,
  );
  return _convertUploadedCover(response.bytes);
}

/// PNG 8 字节签名 `\x89PNG\r\n\x1a\n`。
bool _hasPngSignature(List<int> png) =>
    png[0] == 0x89 &&
    png[1] == 0x50 &&
    png[2] == 0x4E &&
    png[3] == 0x47 &&
    png[4] == 0x0D &&
    png[5] == 0x0A &&
    png[6] == 0x1A &&
    png[7] == 0x0A;

/// 首块类型必须是 `IHDR`。
bool _hasIhdrTag(List<int> png) =>
    png[12] == 0x49 && png[13] == 0x48 && png[14] == 0x44 && png[15] == 0x52;

/// 文件名规则（playlist_pic_upload.rs `valid_file_name`，playlist_update 的
/// cover_reference 校验也用它）：≤255 字节，`.png` 后缀，主名非空且只含
/// ASCII 字母数字/下划线/连字符。
bool isValidPlaylistCoverFileName(String name) {
  if (utf8.encode(name).length > 255 || !name.endsWith('.png')) {
    return false;
  }
  final base = name.substring(0, name.length - '.png'.length);
  if (base.isEmpty) {
    return false;
  }
  for (final code in base.codeUnits) {
    final isDigit = code >= 0x30 && code <= 0x39;
    final isLower = code >= 0x61 && code <= 0x7A;
    final isUpper = code >= 0x41 && code <= 0x5A;
    if (!isDigit && !isLower && !isUpper && code != 0x5F && code != 0x2D) {
      return false;
    }
  }
  return true;
}

/// wire 解析（playlist_pic_upload.rs `convert`）。
MusicUploadedPlaylistCover _convertUploadedCover(Uint8List bytes) {
  // 图片服务不走 {status,error_code} 信封：IsSuccess 是必填标量布尔
  // （scalar：bool/"true"/"false"/0/1），FileName 是 text。
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  final wire = wireMap(decoded);
  if (wire == null) {
    throw const KugouApiException('decode', '封面响应不是 JSON object');
  }
  if (!_scalarBool(wire['IsSuccess'])) {
    throw const KugouApiException('business', '图片服务拒绝了封面上传');
  }
  final fileName = wireText(wire['FileName']);
  return MusicUploadedPlaylistCover(
    fileName: fileName,
    reference: 'custom/$fileName',
  );
}

/// `response::scalar` 的 bool 语义：bool/字符串 true/false/0/1；其它 → decode。
bool _scalarBool(Object? value) {
  if (value is bool) return value;
  if (value is String && (value == 'true' || value == 'false')) {
    return value == 'true';
  }
  final numeric = optionalInt(value);
  if (numeric == 0) return false;
  if (numeric == 1) return true;
  throw const KugouApiException('decode', '响应字段 IsSuccess 缺失或不是标量布尔');
}
