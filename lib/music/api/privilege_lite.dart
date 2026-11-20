/// 歌曲权益查询端点——EchoMusicNext `crates/echo-api/src/module/privilege_lite.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 读的是 mediastore 在旧模块加 quality_vip 映射**之前**的响应：权益事实与
/// 编码文件保持分离——真实样本里 status=0 也可能同时拿到 tracker 授权地址，
/// 不要从这些字段自行推断「可播/免费/VIP」结论（上游注释）。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/playback_ext_models.dart';

/// 单个权益查询资源（privilege_lite.rs `ResourceQuery`）。
class PrivilegeLiteResource {
  const PrivilegeLiteResource({required this.hash, this.albumId});

  /// 32 位十六进制文件 hash（大小写不限，请求时统一小写）。
  final String hash;

  /// 可选专辑 id（u64）；缺省时请求体 album_id 写数字 0。
  final int? albumId;
}

/// 权益查询输入（privilege_lite.rs `Query`）。
class PrivilegeLiteQuery {
  const PrivilegeLiteQuery({required this.resources});

  final List<PrivilegeLiteResource> resources;

  /// privilege_lite.rs `execute` 的入参校验：1..=100 条；hash 必须 32 位
  /// ASCII 十六进制；小写去重后数量不变（重复 → 专属 input 错误）。
  void validate() {
    bool invalidHash(String hash) {
      if (hash.length != 32) return true;
      for (final code in hash.codeUnits) {
        final isDigit = code >= 0x30 && code <= 0x39;
        final isUpperHex = code >= 0x41 && code <= 0x46;
        final isLowerHex = code >= 0x61 && code <= 0x66;
        if (!isDigit && !isUpperHex && !isLowerHex) return true;
      }
      return false;
    }

    if (resources.isEmpty ||
        resources.length > 100 ||
        resources.any(
          (r) => invalidHash(r.hash) || (r.albumId != null && r.albumId! < 0),
        )) {
      throw const KugouApiException('input', '歌曲权益查询参数无效');
    }
    final lowered = resources.map((r) => r.hash.toLowerCase()).toSet();
    if (lowered.length != resources.length) {
      throw const KugouApiException('input', '重复的歌曲权益查询');
    }
  }
}

/// POST /v2/get_res_privilege/lite（网关 + x-router=media.store.kugou.com）。
Future<List<MusicResourcePrivileges>> fetchPrivilegeLite(
  MusicSession session,
  PrivilegeLiteQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  // serde 序列化按声明序：appid/area_code/behavior/clientver/need_hash_offset/
  // relate/support_verify/resource/qualities；资源行 type/page_id/hash/album_id。
  final body = <String, Object?>{
    'appid': 3116,
    'area_code': 1,
    'behavior': 'play',
    'clientver': 11440,
    'need_hash_offset': 1,
    'relate': 1,
    'support_verify': 1,
    'resource': [
      for (final resource in query.resources)
        <String, Object?>{
          'type': 'audio',
          'page_id': 0,
          'hash': resource.hash.toLowerCase(),
          'album_id': resource.albumId == null
              ? 0
              : resource.albumId.toString(),
        },
    ],
    'qualities': const <String>[
      '128',
      '320',
      'flac',
      'high',
      'viper_atmos',
      'viper_tape',
      'viper_clear',
      'super',
      'multitrack',
    ],
  };
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v2/get_res_privilege/lite',
      router: 'media.store.kugou.com',
      method: 'POST',
      body: encodeJsonBody(body),
    ),
  );
  return convertPrivilegeResources(response.bytes);
}

/// privilege_lite.rs `convert`。
///
/// 信封走 `request::decode_envelope("error_code")`：结构解码（含 data 行）
/// 失败时按宽松码值恢复（error_code 非零或 status==0 → business）；结构成功
/// 后才过 `request::success`（status==1 且 code==0）。
List<MusicResourcePrivileges> convertPrivilegeResources(Uint8List bytes) {
  final root = decodePlaybackRoot(bytes);
  try {
    // Wire{status 必填 scalar, error_code 必填 scalar, data 走 list 宽容}。
    final envelope = _envelopeOf(root);
    final rows = wireList(root['data'], 'data');
    final resources = rows.map(_convertResource).toList();
    ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '歌曲权益');
    return resources;
  } on KugouApiException catch (error) {
    if (error.kind != 'decode') rethrow;
    // decode_envelope 恢复分支：结构失败时 errcode 非零或 status==0 → business。
    final code = optionalInt(root['error_code']);
    final rejected = optionalInt(root['status']) == 0;
    if ((code != null && code != 0) || rejected) {
      throw KugouApiException('business', '音乐服务返回失败（歌曲权益）', code: code ?? 0);
    }
    rethrow;
  }
}

/// 信封标量解码（status u32 域 / error_code i64，都必填）。
MusicPlaybackEnvelope _envelopeOf(Map<String, Object?> root) {
  final status = playbackOptionalUnsigned(root['status']);
  if (status == null) {
    throw const KugouApiException('decode', '响应字段 status 缺失或不是标量数字');
  }
  final errorCode = requiredScalarInt(root['error_code'], 'error_code');
  return MusicPlaybackEnvelope(status, errorCode, root);
}

/// privilege_lite.rs `Resource` → `ResourcePrivileges`。
MusicResourcePrivileges _convertResource(Object? value) {
  final wire = wireMap(value);
  if (wire == null) {
    throw const KugouApiException('decode', '歌曲权益资源行不是 object');
  }
  // serde flatten：资源级 _msg/_errno 被 Resource 的显式字段接住，主档位
  // （flattened Variant）的 message/error_code 保持默认空值。
  final primary = _variantOf(wire, message: '', errorCode: null);
  final variants = wireList(
    wire['relate_goods'],
    'relate_goods',
  ).map(_convertVariantRow).toList();
  final trans = _Trans.of(wireMap(wire['trans_param']));
  final oggStandard = _encodedFile(
    optionalText(trans.wire['ogg_128_hash']),
    playbackOptionalUnsigned(trans.wire['ogg_128_filesize']),
  );
  final oggHigh = _encodedFile(
    optionalText(trans.wire['ogg_320_hash']),
    playbackOptionalUnsigned(trans.wire['ogg_320_filesize']),
  );
  return MusicResourcePrivileges(
    id: playbackOptionalUnsigned(wire['id']),
    albumId: wireText(wire['album_id']),
    songId: playbackOptionalUnsigned(wire['album_audio_id']),
    hash: primary.hash,
    displayName: wireText(wire['name']),
    artistText: wireText(wire['singername']),
    albumTitle: optionalText(wire['albumname']),
    primary: primary,
    variants: variants,
    oggStandard: oggStandard,
    oggHigh: oggHigh,
    preview: playbackPreviewRange(trans.wire['hash_offset']),
    qualityMap: playbackQualityMap(trans.wire['qualitymap']),
    resourceError: optionalInt(wire['_errno']),
    resourceMessage: wireText(wire['_msg']),
    language: trans.language,
    presentationExtension: trans.extension,
  );
}

/// privilege_lite.rs `variant()`：Variant wire → `QualityVariant`。
MusicQualityVariant _variantOf(
  Map<String, Object?> wire, {
  required String message,
  required int? errorCode,
}) {
  final info = wireMap(wire['info']) ?? const <String, Object?>{};
  final bitrate = playbackOptionalUnsigned(info['bitrate']);
  return MusicQualityVariant(
    message: message,
    errorCode: errorCode,
    hash: wireText(wire['hash']),
    quality: wireText(wire['quality']),
    level: playbackOptionalUnsigned(wire['level']),
    privilege: playbackOptionalUnsigned(wire['privilege']),
    serviceStatus: playbackOptionalUnsigned(wire['status']),
    failureCode: playbackOptionalUnsigned(wire['fail_process']),
    paymentType: playbackOptionalUnsigned(wire['pay_type']),
    priceUnits: playbackOptionalUnsigned(wire['price']),
    durationMs: playbackOptionalUnsigned(info['duration']),
    sizeBytes: playbackOptionalUnsigned(info['filesize']),
    // bit_rate_bps = bitrate × 1000（上游 checked_mul）。
    bitRateBps: bitrate == null ? null : bitrate * 1000,
    extension: wireText(info['extname']),
    coverUrl: coverUrl(wireText(info['image'])),
  );
}

/// relate_goods 行（privilege_lite.rs `Variant`）：行内 _msg/_errno 归档位。
MusicQualityVariant _convertVariantRow(Object? value) {
  final wire = wireMap(value);
  if (wire == null) {
    throw const KugouApiException('decode', '歌曲权益音质行不是 object');
  }
  return _variantOf(
    wire,
    message: wireText(wire['_msg']),
    errorCode: optionalInt(wire['_errno']),
  );
}

/// privilege_lite.rs `file()`：hash/size 全空 → null，否则保留 EncodedFile。
MusicEncodedFile? _encodedFile(String? hash, int? sizeBytes) {
  if (hash == null && sizeBytes == null) return null;
  return MusicEncodedFile(hash: hash, sizeBytes: sizeBytes);
}

/// privilege_lite.rs `Trans`：trans_param 的 known 字段 + flatten extension
/// （未映射键原样保留进 presentation_extension）。response::object 容忍一切
/// 非对象输入 → 空默认。
class _Trans {
  _Trans.of(Map<String, Object?>? wire)
    : wire = wire ?? const <String, Object?>{} {
    const consumed = <String>{
      'language',
      'ogg_128_hash',
      'ogg_128_filesize',
      'ogg_320_hash',
      'ogg_320_filesize',
      'hash_offset',
      'qualitymap',
    };
    extension = <String, Object?>{
      for (final entry in this.wire.entries)
        if (!consumed.contains(entry.key)) entry.key: entry.value,
    };
    language = wireText(this.wire['language']);
  }

  final Map<String, Object?> wire;
  late final Map<String, Object?> extension;
  late final String language;
}
