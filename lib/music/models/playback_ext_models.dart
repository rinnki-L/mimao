/// 播放补全端点组的模型与共享解码辅助——EchoMusicNext `crates/echo-api/src`
/// 里 `module/privilege_lite.rs` / `images_audio.rs` / `krm_audio.rs` 的产物
/// 模型（docs/architecture.md §4.3：models ← domain）。
///
/// `domain/discovery.rs` 的 CatalogSongFacts / CatalogRights 与
/// `privilege_lite.rs` 的 PreviewRange / QualityMap 是权益等端点共用的
/// 事实结构；`util/response.rs` 的 scalar/text/list/optional 宽容语义沿用
/// `wire.dart`，这里只补该组用到的差量（无符号域、有限浮点、https 图片）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';

/// response.rs `optional<u32/u64>` 的无符号域：负数在 Rust `from_value` 失败
/// → None；共享层 `optionalInt` 不查范围，本组统一用本函数补齐。
int? playbackOptionalUnsigned(Object? value) {
  final parsed = optionalInt(value);
  if (parsed == null || parsed < 0) return null;
  return parsed;
}

/// response.rs `optional<f64>`：非有限值（JSON 不该出现，字符串可解析出
/// Infinity）在 Rust 反序列化层就被拒 → null。
double? playbackOptionalFiniteDouble(Object? value) {
  final parsed = optionalDouble(value);
  if (parsed == null || !parsed.isFinite) return null;
  return parsed;
}

/// response.rs `list<String>`：元素经 ResponseValue 字符串解码（数字 → 文本；
/// bool/object → decode 失败，不静默丢弃）。
List<String> playbackTextList(Object? value, String field) {
  final items = wireList(value, field);
  final result = <String>[];
  for (final item in items) {
    final text = optionalText(item);
    if (text == null) {
      throw KugouApiException('decode', '响应字段 $field 含非法文本项');
    }
    result.add(text);
  }
  return result;
}

/// privilege_lite.rs `PreviewRange` wire → 模型。字段全走 optional 宽容；
/// 非对象 → null。
MusicPreviewRange? playbackPreviewRange(Object? value) {
  final wire = wireMap(value);
  if (wire == null) return null;
  return MusicPreviewRange(
    startByte: playbackOptionalUnsigned(wire['start_byte']),
    endByte: playbackOptionalUnsigned(wire['end_byte']),
    startMs: playbackOptionalUnsigned(wire['start_ms']),
    endMs: playbackOptionalUnsigned(wire['end_ms']),
    offsetHash: optionalText(wire['offset_hash']),
    fileType: playbackOptionalUnsigned(wire['file_type']),
    clipHash: optionalText(wire['clip_hash']),
  );
}

/// privilege_lite.rs `QualityMap` wire → 模型（attr0/attr1 用 optional 解码，
/// 不经浮点；非对象 → null）。
MusicQualityMap? playbackQualityMap(Object? value) {
  final wire = wireMap(value);
  if (wire == null) return null;
  return MusicQualityMap(
    attr0: playbackOptionalUnsigned(wire['attr0']),
    attr1: playbackOptionalUnsigned(wire['attr1']),
    bits: optionalText(wire['bits']),
  );
}

/// discovery.rs `EncodedMap` wire → 模型（非对象 → null）。
MusicEncodedMap? playbackEncodedMap(Object? value) {
  final wire = wireMap(value);
  if (wire == null) return null;
  return MusicEncodedMap(
    attr0: playbackOptionalUnsigned(wire['attr0']),
    bits: optionalText(wire['bits']),
  );
}

/// request.rs `decode` 的前半段：JSON 解析 + 登录过期探测 → 根对象。
/// 结构解码与恢复分支由各端点按上游变体自行编排（privilege_lite/images_audio
/// 走 decode_envelope、krm_audio 走 decode_value）。
Map<String, Object?> decodePlaybackRoot(Uint8List bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  final root = wireMap(decoded);
  if (root == null) {
    throw const KugouApiException('decode', '响应信封不是 JSON object');
  }
  _ensureNotAuthenticationExpired(root);
  return root;
}

/// 情报类图片地址（images_audio.rs `image_url`）：去除首尾空白；`http://`
/// 前缀升级为 `https://`；解析后必须仍是 https 且有主机，否则 null。
String? playbackImageUrl(Object? value) {
  final raw = optionalText(value);
  if (raw == null) return null;
  var text = raw.trim();
  if (text.startsWith('http://')) {
    text = 'https://${text.substring('http://'.length)}';
  }
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return text;
}

/// {status, error_code, ...} 信封解码结果（privilege_lite 端点使用）。
class MusicPlaybackEnvelope {
  const MusicPlaybackEnvelope(this.status, this.errorCode, this.root);

  final int status;
  final int errorCode;
  final Map<String, Object?> root;

  Object? get data => root['data'];
}

/// request.rs `authentication_expiration`：error_code=20018 或 msg 文本含
/// 「登录已过期」→ authentication；码值跟随 error_code 字段（msg-only 路径
/// 无码）。共享层 `decodeEnvelopeWithFields` 会丢弃该码值，因此本组自带。
void _ensureNotAuthenticationExpired(Map<String, Object?> root) {
  final code = optionalInt(root['error_code']);
  final message = root['msg'];
  final expired = message is String && message.contains('登录已过期');
  if (code == kugouErrorCodeAuthenticationExpired || expired) {
    throw KugouApiException('authentication', '账号认证无效，请重新登录', code: code);
  }
}

/// privilege_lite.rs `PreviewRange`（试听/预览区间；全空表示无预览事实）。
class MusicPreviewRange {
  const MusicPreviewRange({
    this.startByte,
    this.endByte,
    this.startMs,
    this.endMs,
    this.offsetHash,
    this.fileType,
    this.clipHash,
  });

  final int? startByte;
  final int? endByte;
  final int? startMs;
  final int? endMs;

  /// wire `offset_hash`（文本）。
  final String? offsetHash;
  final int? fileType;
  final String? clipHash;

  /// privilege_lite.rs `PreviewRange::is_empty`。
  bool get isEmpty =>
      startByte == null &&
      endByte == null &&
      startMs == null &&
      endMs == null &&
      offsetHash == null &&
      fileType == null &&
      clipHash == null;
}

/// privilege_lite.rs `QualityMap`（qualitymap 版权位图；attr 用精确整数解码）。
class MusicQualityMap {
  const MusicQualityMap({this.attr0, this.attr1, this.bits});

  final int? attr0;
  final int? attr1;

  /// wire `bits` 文本原样保留（上游不解释位义）。
  final String? bits;
}

/// discovery.rs `EncodedMap`（ipmap.attr0/bits）。
class MusicEncodedMap {
  const MusicEncodedMap({this.attr0, this.bits});

  final int? attr0;
  final String? bits;
}

/// discovery.rs `VoiceAd`（试听前贴片音频事实）。
class MusicVoiceAd {
  const MusicVoiceAd({this.startMs, this.sizeBytes, required this.hash});

  final int? startMs;
  final int? sizeBytes;
  final String? hash;
}

/// discovery.rs `CatalogRights`——版权/展示事实包，全部是展示用途的码值，
/// 不构成任何播放授权。
class MusicCatalogRights {
  const MusicCatalogRights({
    this.qualityMap,
    this.classification,
    this.ipMap,
    this.copyrightAttributes,
    this.copyrightScope,
    this.copyrightGrade,
    this.copyrightLevel,
    this.displayCode,
    this.displayRate,
    this.paymentTemplate,
    this.blockedApplications,
    this.originalityCode,
    this.advanceCode,
    this.preview,
    this.multitrackHash,
    this.coverUrl,
    this.audioPrivilege,
    this.freeForAd,
    this.freeLimited,
    this.voiceAd,
  });

  final MusicQualityMap? qualityMap;

  /// wire `classmap`（classification）：未知条目宽容为 null（optional_map）。
  final Map<String, int?>? classification;
  final MusicEncodedMap? ipMap;
  final int? copyrightAttributes;
  final String? copyrightScope;
  final int? copyrightGrade;
  final int? copyrightLevel;
  final int? displayCode;
  final int? displayRate;
  final int? paymentTemplate;
  final String? blockedApplications;
  final int? originalityCode;
  final int? advanceCode;

  /// catalog_rights.rs：`hash_offset.filter(|v| !v.is_empty())`——全空
  /// PreviewRange 不透出（privilege_lite 的顶层 preview 不过滤，见该端点）。
  final MusicPreviewRange? preview;
  final String? multitrackHash;
  final String? coverUrl;
  final int? audioPrivilege;
  final int? freeForAd;
  final int? freeLimited;
  final MusicVoiceAd? voiceAd;
}

/// discovery.rs `CatalogSongFacts`——最小目录事实（资源行复用共享层
/// `MusicAudioResource`，wire 不含 download_status）。
class MusicCatalogSongFacts {
  const MusicCatalogSongFacts({
    this.paymentType,
    this.failureCode,
    this.oldCopyrightCode,
    this.originalityCode,
    this.rights,
    required this.resources,
  });

  final int? paymentType;
  final int? failureCode;
  final int? oldCopyrightCode;
  final int? originalityCode;
  final MusicCatalogRights? rights;
  final List<MusicAudioResource> resources;
}

/// privilege_lite.rs `EncodedFile`（ogg 编码文件事实；hash/size 至少一个存在）。
class MusicEncodedFile {
  const MusicEncodedFile({required this.hash, required this.sizeBytes});

  final String? hash;
  final int? sizeBytes;
}

/// privilege_lite.rs `QualityVariant`——一个音质档位的权益事实（status=0 只
/// 表示该档服务未放行，不构成最终可播判定，上游注释）。
class MusicQualityVariant {
  const MusicQualityVariant({
    required this.message,
    required this.errorCode,
    required this.hash,
    required this.quality,
    required this.level,
    required this.privilege,
    required this.serviceStatus,
    required this.failureCode,
    required this.paymentType,
    required this.priceUnits,
    required this.durationMs,
    required this.sizeBytes,
    required this.bitRateBps,
    required this.extension,
    required this.coverUrl,
  });

  final String message;
  final int? errorCode;
  final String hash;
  final String quality;
  final int? level;
  final int? privilege;

  /// wire `status`（音质服务状态）。
  final int? serviceStatus;

  /// wire `fail_process`。
  final int? failureCode;

  /// wire `pay_type`。
  final int? paymentType;

  /// wire `price`。
  final int? priceUnits;
  final int? durationMs;
  final int? sizeBytes;

  /// wire `bitrate` × 1000（上游 checked_mul）。
  final int? bitRateBps;
  final String extension;

  /// `{size}` 占位符已替换为 240。
  final String coverUrl;
}

/// privilege_lite.rs `ResourcePrivileges`——一个资源（hash）的完整权益。
class MusicResourcePrivileges {
  const MusicResourcePrivileges({
    required this.id,
    required this.albumId,
    required this.songId,
    required this.hash,
    required this.displayName,
    required this.artistText,
    required this.albumTitle,
    required this.primary,
    required this.variants,
    required this.oggStandard,
    required this.oggHigh,
    required this.preview,
    required this.qualityMap,
    required this.resourceError,
    required this.resourceMessage,
    required this.language,
    required this.presentationExtension,
  });

  final int? id;
  final String albumId;

  /// wire `album_audio_id`。
  final int? songId;
  final String hash;
  final String displayName;
  final String artistText;
  final String? albumTitle;

  /// 主档位（资源自身字段折叠出的 Variant）。serde flatten 语义下资源级
  /// `_msg`/`_errno` 由 Resource 的显式字段接住，因此 primary.message 恒空串、
  /// primary.errorCode 恒 null（上游同构，见端点文件注释）。
  final MusicQualityVariant primary;
  final List<MusicQualityVariant> variants;
  final MusicEncodedFile? oggStandard;
  final MusicEncodedFile? oggHigh;

  /// 资源级预览区间（不过滤空值；与 CatalogRights.preview 的过滤语义不同）。
  final MusicPreviewRange? preview;
  final MusicQualityMap? qualityMap;
  final int? resourceError;
  final String resourceMessage;
  final String language;

  /// trans_param 未映射键的原样保留（serde flatten 的 extension）。
  final Map<String, Object?> presentationExtension;
}

/// images_audio.rs `Portrait`——歌手写真（url 可能升级为 https）。
class MusicPortrait {
  const MusicPortrait({
    required this.id,
    required this.fileHash,
    required this.url,
    required this.filename,
    required this.publishTime,
    required this.source,
  });

  final String? id;
  final String? fileHash;
  final String? url;
  final String? filename;
  final String? publishTime;
  final int? source;
}

/// images_audio.rs `ArtistImages`——一首歌关联的歌手图片组。
class MusicAuthorImages {
  const MusicAuthorImages({
    required this.artistId,
    required this.name,
    required this.publishStatus,
    required this.resourceHash,
    required this.avatar,
    required this.avatarUrl,
    required this.audioPublishDate,
    required this.images,
  });

  /// wire `author_id`（`optional<String>`：数字 → 文本）。
  final String? artistId;
  final String? name;

  /// wire `is_publish`。
  final int? publishStatus;
  final String? resourceHash;

  /// wire `avatar` 原样文本（可能是 `{size}` 模板）。
  final String? avatar;

  /// wire `sizable_avatar` 经 https 升级；非法 → null。
  final String? avatarUrl;
  final String? audioPublishDate;

  /// 图片类别 → 写真列表（保持服务端键序；null 列表 → 空表）。
  final Map<String, List<MusicPortrait>> images;
}

/// krm_audio.rs `SongInformation`——词曲/发行/BPM 等展示性资料（与播放授权
/// 无关的公开目录事实）。
class MusicSongInformation {
  const MusicSongInformation({
    required this.publishedAt,
    required this.albumPublishedAt,
    required this.language,
    required this.lyricist,
    required this.composer,
    required this.bpm,
    required this.tempoCode,
    required this.tempoDescription,
  });

  final String? publishedAt;
  final String? albumPublishedAt;
  final String? language;

  /// wire `extra.lyrics`（作词）。
  final String? lyricist;

  /// wire `extra.composer`（作曲）。
  final String? composer;
  final double? bpm;

  /// wire `bpm_type`（节拍码，原样保留不猜标签）。
  final String? tempoCode;

  /// wire `bpm_desc`（服务端给定的展示文案）。
  final String? tempoDescription;
}

/// krm_audio.rs `SongPresentation`——一首歌的展示性资料包。
class MusicSongPresentation {
  const MusicSongPresentation({
    required this.id,
    required this.title,
    required this.albumId,
    required this.albumTitle,
    required this.coverUrl,
    required this.artists,
    required this.information,
  });

  /// wire `base.album_audio_id`（text：数字 → 文本）。
  final String id;
  final String title;
  final String albumId;
  final String albumTitle;
  final String coverUrl;
  final List<MusicPresentationArtist> artists;
  final MusicSongInformation information;
}

/// discovery.rs `ArtistDetail`（krm_audio 的作者行投影；组内独立命名避免与
/// 其它组的歌手详情模型重名）。
class MusicPresentationArtist {
  const MusicPresentationArtist({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.publicationCode,
  });

  final int? id;
  final String name;

  /// 上游恒 Some(cover_url(avatar))——空头像也保留 Some（空串）。
  final String? avatarUrl;
  final int? publicationCode;
}
