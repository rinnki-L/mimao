/// 歌曲关联歌手图片端点——EchoMusicNext `crates/echo-api/src/module/images_audio.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 走 `request_audio_images`（`send_endpoint(cloud=false, clear_defaults=
/// true)`）：公开 CDN 查询只签端点参数，appid/clientver/count/data/isCdn/
/// publish_time/show_authors 一个不多；不注入任何账号/设备默认字段。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/playback_ext_models.dart';

/// 图片查询资源（images_audio.rs `Resource`；serde 序列化按声明序：
/// audio_id/hash/album_audio_id/filename；上游注释——服务商对这段 JSON 精确
/// 签名，id 为 0 时序列化成数字 0，非 0 序列化成十进制字符串）。
class ImagesAudioResource {
  const ImagesAudioResource({
    this.audioId = 0,
    required this.hash,
    this.albumAudioId = 0,
    this.filename = '',
  });

  final int audioId;
  final String hash;
  final int albumAudioId;
  final String filename;
}

/// 图片查询输入（images_audio.rs `Query`；count 缺省 5）。
class ImagesAudioQuery {
  const ImagesAudioQuery({required this.resources, this.count = 5});

  final List<ImagesAudioResource> resources;

  /// 每个资源返回的图片组数量上限（1..=50）。
  final int count;

  /// images_audio.rs `parameters()` 的入参校验。
  void validate() {
    if (resources.isEmpty ||
        resources.length > 100 ||
        !(count >= 1 && count <= 50) ||
        resources.any(
          (r) => !_isValidHash(r.hash) || _utf8Length(r.filename) > 16384,
        )) {
      throw const KugouApiException('input', '歌曲图片查询参数无效');
    }
  }

  /// song_climax.rs `valid_hash`：32 位 ASCII 十六进制。
  static bool _isValidHash(String hash) {
    if (hash.length != 32) return false;
    for (final code in hash.codeUnits) {
      final isDigit = code >= 0x30 && code <= 0x39;
      final isUpperHex = code >= 0x41 && code <= 0x46;
      final isLowerHex = code >= 0x61 && code <= 0x66;
      if (!isDigit && !isUpperHex && !isLowerHex) return false;
    }
    return true;
  }

  /// Rust `filename.len()` 是字节数（UTF-8）。
  static int _utf8Length(String text) => utf8.encode(text).length;
}

/// 资源行的请求 wire（id_or_zero：0 → 数字，非 0 → 字符串；声明序）。
Map<String, Object?> _resourceWire(
  ImagesAudioResource resource,
) => <String, Object?>{
  'audio_id': resource.audioId == 0 ? 0 : '${resource.audioId}',
  'hash': resource.hash,
  'album_audio_id': resource.albumAudioId == 0 ? 0 : '${resource.albumAudioId}',
  'filename': resource.filename,
};

/// GET /v2/author_image/audio（ArtistImages 主机 expendablekmr.kugou.com）。
Future<List<List<MusicAuthorImages>>> fetchImagesAudio(
  MusicSession session,
  ImagesAudioQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.artistImages,
      path: '/v2/author_image/audio',
      method: 'GET',
      params: <String, String>{
        'appid': '3116',
        'clientver': '11440',
        'count': query.count.toString(),
        // serde 序列化保持声明序，服务端对这段 JSON 精确签名（上游注释）。
        'data': jsonEncode([for (final r in query.resources) _resourceWire(r)]),
        'isCdn': '1',
        'publish_time': '1',
        'show_authors': '1',
      },
    ),
    // request_audio_images：clear_defaults=true——公开查询不带账号/设备默认。
    clearDefaults: true,
  );
  return convertArtistImages(response.bytes);
}

/// images_audio.rs `convert`：外层分组保持请求顺序（含空组）。
List<List<MusicAuthorImages>> convertArtistImages(Uint8List bytes) {
  final root = decodePlaybackRoot(bytes);
  try {
    // Wire{status/error_code 必填, data 走 list 宽容（Vec<Vec<WireArtist>>）}。
    final status = playbackOptionalUnsigned(root['status']);
    if (status == null) {
      throw const KugouApiException('decode', '响应字段 status 缺失或不是标量数字');
    }
    final errorCode = requiredScalarInt(root['error_code'], 'error_code');
    final groups = wireList(root['data'], 'data');
    final converted = groups.map(_convertGroup).toList();
    if (status != 1) {
      throw KugouApiException('business', '音乐服务返回失败（歌手图片）', code: errorCode);
    }
    return converted;
  } on KugouApiException catch (error) {
    if (error.kind != 'decode') rethrow;
    // decode_envelope 恢复分支：结构失败时 errcode 非零或 status==0 → business。
    final code = optionalInt(root['error_code']);
    final rejected = optionalInt(root['status']) == 0;
    if ((code != null && code != 0) || rejected) {
      throw KugouApiException('business', '音乐服务返回失败（歌手图片）', code: code ?? 0);
    }
    rethrow;
  }
}

/// 一组（一个资源行的歌手列表）。
List<MusicAuthorImages> _convertGroup(Object? value) {
  final rows = wireList(value, 'data');
  return rows.map(_convertArtist).toList();
}

/// images_audio.rs `WireArtist` → `ArtistImages`。
MusicAuthorImages _convertArtist(Object? value) {
  final wire = wireMap(value);
  if (wire == null) {
    throw const KugouApiException('decode', '歌手图片行不是 object');
  }
  // imgs：optional_map——非对象 → null；每类键值宽容（非法 → 空列表）。
  final imgsWire = wireMap(wire['imgs']);
  final images = <String, List<MusicPortrait>>{
    for (final entry in (imgsWire ?? const <String, Object?>{}).entries)
      entry.key: _portraitsOf(entry.value),
  };
  return MusicAuthorImages(
    artistId: optionalText(wire['author_id']),
    name: optionalText(wire['author_name']),
    publishStatus: optionalInt(wire['is_publish']),
    resourceHash: optionalText(wire['res_hash']),
    avatar: optionalText(wire['avatar']),
    avatarUrl: playbackImageUrl(wire['sizable_avatar']),
    audioPublishDate: optionalText(wire['audio_publish_date']),
    images: images,
  );
}

/// 类别键下的写真列表（optional_map 语义）：值非数组或任一行非 object →
/// 整条类别解码失败 → None → 空列表（不丢弃其它类别）。
List<MusicPortrait> _portraitsOf(Object? value) {
  if (value is! List) return const <MusicPortrait>[];
  final portraits = <MusicPortrait>[];
  for (final row in value) {
    final wire = wireMap(row);
    if (wire == null) return const <MusicPortrait>[];
    portraits.add(
      MusicPortrait(
        id: optionalText(wire['id']),
        fileHash: optionalText(wire['file_hash']),
        url: playbackImageUrl(wire['sizable_portrait']),
        filename: optionalText(wire['filename']),
        publishTime: optionalText(wire['publish_time']),
        source: optionalInt(wire['source']),
      ),
    );
  }
  return portraits;
}
