/// 头像图片上传端点——EchoMusicNext
/// `crates/echo-api/src/module/user_avatar_upload.rs` 的翻译
/// （docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 只做 multipart 上传（账号变更归 user_update_avatar）；走固定图片主机的
/// 裸传输（无身份默认参数、无签名、无 cookie——request.rs `upload_avatar`）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/user_models.dart';

/// 原始字节上限（user_avatar_upload.rs `LIMIT`）。
const int _kImageLimit = 8 * 1024 * 1024;

/// base64 文本长度上界（`LIMIT.div_ceil(3) * 4`，解码前先行拒绝）。
const int _kBase64Limit = (_kImageLimit + 2) ~/ 3 * 4;

/// 上传头像图片（user_avatar_upload.rs `execute`）。
Future<MusicUserAvatarUpload> fetchUserAvatarUpload(
  MusicSession session, {
  required String imageBase64,
  required String localDate,
}) async {
  final identity = await session.ensureDevice();
  requireMusicAccount(identity);
  if (imageBase64.length > _kBase64Limit) {
    throw const KugouApiException('input', '头像图片不能超过 8 MB');
  }
  final image = _decodeImage(imageBase64);
  if (image.isEmpty || image.length > _kImageLimit) {
    throw const KugouApiException('input', '头像图片不能超过 8 MB');
  }
  final (extension, mime) = _imageKind(image);
  final checksum = kugouImageChecksum(localDate);
  // 无 base64 的 multipart 传输；边界必须不出现在图片字节里（上游注释）。
  var boundary = 'EchoMusicAvatarBoundary';
  // latin1 与字节一一对应，ASCII 边界匹配等价于字节匹配。
  final imageText = latin1.decode(image);
  while (imageText.contains(boundary)) {
    boundary += 'x';
  }
  final body = BytesBuilder(copy: false)
    ..add(
      utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="type"\r\n\r\n'
        'kugouicon\r\n'
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="md5"\r\n\r\n'
        '$checksum\r\n'
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; '
        'filename="avatar.$extension"\r\n'
        'Content-Type: $mime\r\n\r\n',
      ),
    )
    ..add(image)
    ..add(utf8.encode('\r\n--$boundary--\r\n'));
  final response = await session.client.sendRaw(
    url: 'http://imgphp.kugou.com/imageupload/post.php',
    method: 'POST',
    body: body.toBytes(),
    headers: <String, String>{
      'Content-Type': 'multipart/form-data; boundary=$boundary',
    },
  );
  return MusicUserAvatarUpload(fileName: _convertUploadedFile(response.bytes));
}

/// STANDARD base64（带 padding、拒绝 URL-safe 字母表）：非法 → input。
Uint8List _decodeImage(String imageBase64) {
  try {
    // 与 Rust STANDARD 引擎对齐：仅标准字母表 + 规整 padding。
    if (imageBase64.length % 4 != 0 ||
        !RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(imageBase64)) {
      throw const FormatException('base64');
    }
    return base64.decode(imageBase64);
  } on Object {
    throw const KugouApiException('input', '图片数据无效');
  }
}

/// 魔数识别（user_avatar_upload.rs `execute` 的三段 starts_with）。
(String, String) _imageKind(Uint8List image) {
  bool startsWith(List<int> magic) {
    if (image.length < magic.length) return false;
    for (var index = 0; index < magic.length; index++) {
      if (image[index] != magic[index]) return false;
    }
    return true;
  }

  const pngMagic = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (startsWith(pngMagic)) return ('png', 'image/png');
  if (startsWith('GIF87a'.codeUnits) || startsWith('GIF89a'.codeUnits)) {
    return ('gif', 'image/gif');
  }
  if (startsWith(const <int>[0xFF, 0xD8, 0xFF])) return ('jpg', 'image/jpeg');
  throw const KugouApiException('input', '请选择 JPEG、PNG 或 GIF 图片');
}

/// wire 解析（user_avatar_upload.rs `uploaded_file`）。
///
/// 上传响应没有 status/error_code 信封（UploadWire 只认 IsSuccess/FileName），
/// 因此不走 decodeEnvelope，只保留传输层的过期判定（request.rs `decode`）。
String _convertUploadedFile(Uint8List bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  final root = wireMap(decoded);
  if (root == null) {
    throw const KugouApiException('decode', '头像上传响应不是 JSON object');
  }
  final message = root['msg'];
  final expiredMessage = message is String && message.contains('登录已过期');
  if (expiredMessage ||
      optionalInt(root['error_code']) == kugouErrorCodeAuthenticationExpired) {
    throw const KugouApiException('authentication', '登录已过期，请重新登录酷狗账号');
  }
  // scalar<bool>：布尔/“true”“false”/0、1；其它或缺省 → decode。
  if (!_requiredScalarBool(root['IsSuccess'])) {
    throw const KugouApiException('business', '头像上传失败');
  }
  // list<String>：非文本项按 decode 失败，不静默丢弃（song_url_auth 同语义）。
  final files = <String>[];
  for (final item in wireList(root['FileName'], 'FileName')) {
    final text = optionalText(item);
    if (text == null) {
      throw const KugouApiException('decode', '响应字段 FileName 含非文本项');
    }
    files.add(text);
  }
  // 首个非空文件名；没有 → decode（不杜撰引用）。
  final file = files.isEmpty || files.first.isEmpty ? null : files.first;
  if (file == null) {
    throw const KugouApiException('decode', '头像上传响应未返回文件名');
  }
  return file;
}

/// ResponseValue::deserialize_bool：Bool / "true"、"false" / 0、1；其余 decode。
bool _requiredScalarBool(Object? value) {
  if (value is bool) return value;
  if (value is String && (value == 'true' || value == 'false')) {
    return value == 'true';
  }
  return switch (optionalInt(value)) {
    0 => false,
    1 => true,
    _ => throw const KugouApiException('decode', '响应字段 IsSuccess 缺失或不是标量布尔'),
  };
}
