/// 歌单写端点的结果模型与组内共享协议辅助——EchoMusicNext
/// `crates/echo-api/src/domain.rs`（`LibraryPlaylistChange` /
/// `LibraryOrderChange` / `CloudTrackChange` / `TrackWriteOutcome` /
/// `UploadedCover`）与 `util/cloudlist.rs` 纯函数部分的翻译。
///
/// `util/cloudlist.rs` 是组内共享 util，但本组不能新增共享文件，因此把它的
/// 纯函数（id/text 校验、信封解码、JSON 编码）寄存在这里；传输类辅助
/// （unix_seconds/write_params/encrypted）在 `playlist_add.dart`。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_error.dart';

/// 歌单归属种类（playlist_sort.rs `Kind`：owned=0 / collected=1）。
enum MusicPlaylistKind {
  owned(0),
  collected(1);

  const MusicPlaylistKind(this.wire);

  /// wire 上的数字编码（`Kind::wire`）。
  final int wire;

  /// wire 数字 → 种类；0/1 之外的编码是未知事实，返回 null（playlist_sort.rs
  /// convert 的 match：Some(0)/Some(1) 之外的 type 不臆造种类）。
  static MusicPlaylistKind? fromWire(int? code) => switch (code) {
    0 => MusicPlaylistKind.owned,
    1 => MusicPlaylistKind.collected,
    _ => null,
  };
}

/// 歌单库变更结果（domain.rs `LibraryPlaylistChange`）——创建/删除/编辑共用。
class MusicPlaylistChange {
  const MusicPlaylistChange({
    this.userId,
    this.cloudListId,
    this.previousTotalRevision,
    this.totalRevision,
    this.playlistCount,
    this.providerStatus,
    this.resourceCode,
    this.coverUrl,
  });

  final int? userId;
  final int? cloudListId;
  final int? previousTotalRevision;
  final int? totalRevision;
  final int? playlistCount;

  /// 嵌套的 provider 状态位，独立于信封成功判定（上游注释）。
  final int? providerStatus;
  final int? resourceCode;

  /// 仅 playlist_update 会返回（服务端封面引用，{size} 已替换为 240）。
  final String? coverUrl;
}

/// 歌单库排序里单个歌单的位置事实（domain.rs `LibraryPosition`）。
class MusicPlaylistOrderPosition {
  const MusicPlaylistOrderPosition({
    this.cloudListId,
    this.kind,
    this.kindCode,
    this.position,
    this.resourceCode,
  });

  final int? cloudListId;

  /// kind 与 kind_code 独立保存：未知编码只丢失种类语义，不丢数字。
  final MusicPlaylistKind? kind;
  final int? kindCode;
  final int? position;
  final int? resourceCode;
}

/// 歌单库排序结果（domain.rs `LibraryOrderChange`）。
class MusicPlaylistOrderChange {
  const MusicPlaylistOrderChange({
    this.userId,
    this.previousTotalRevision,
    this.totalRevision,
    this.playlistCount,
    required this.positions,
  });

  final int? userId;
  final int? previousTotalRevision;
  final int? totalRevision;
  final int? playlistCount;
  final List<MusicPlaylistOrderPosition> positions;
}

/// 单曲写入结果（domain.rs `TrackWriteOutcome`）。
class MusicTrackWriteOutcome {
  const MusicTrackWriteOutcome({
    this.position,
    this.fileId,
    this.songId,
    this.resourceCode,
  });

  final int? position;
  final int? fileId;
  final int? songId;
  final int? resourceCode;
}

/// 云歌单曲目写结果（domain.rs `CloudTrackChange`）。
class MusicCloudTrackChange {
  const MusicCloudTrackChange({
    this.userId,
    this.cloudListId,
    this.providerStatus,
    this.previousRevision,
    this.revision,
    this.songCount,
    this.outcomes,
    this.replacedFileIds,
  });

  final int? userId;
  final int? cloudListId;

  /// provider 的嵌套操作位，独立于信封成功与逐项 code（上游注释）。
  final int? providerStatus;
  final int? previousRevision;
  final int? revision;
  final int? songCount;

  /// tracks_add/tracks_sort 恒有（可为空表）；tracks_del 恒为 null。
  final List<MusicTrackWriteOutcome>? outcomes;

  /// 仅 tracks_add 可能返回；顶层不是数组时为 null（未知，绝不当作失败）。
  final List<int?>? replacedFileIds;
}

/// 上传成功的歌单封面（module/playlist_pic_upload.rs `UploadedCover`）。
class MusicUploadedPlaylistCover {
  const MusicUploadedPlaylistCover({
    required this.fileName,
    required this.reference,
  });

  final String fileName;

  /// `custom/<file_name>`——playlist_update 的 cover_reference 入参形态。
  final String reference;
}

// ---------------------------------------------------------------------------
// util/cloudlist.rs 纯函数翻译（组内各写端点共用）。
// ---------------------------------------------------------------------------

/// `cloudlist::id`——0（或超出 i64 上限，Dart int 无法表达该值）无效。
void validateCloudListId(int value) {
  if (value <= 0) {
    throw const KugouApiException('input', '云歌单或文件 ID 无效');
  }
}

/// `cloudlist::text`——按 UTF-8 字节长度限幅（Rust `str::len` 是字节数）。
void validateCloudListText(
  String value,
  int limit, {
  required bool allowEmpty,
}) {
  if ((!allowEmpty && value.trim().isEmpty) ||
      utf8.encode(value).length > limit ||
      value.contains('\x00')) {
    throw const KugouApiException('input', '歌单文本参数无效');
  }
}

/// `cloudlist::decode` 的信封部分：
/// - JSON/结构错误 → decode（status/error_code 必填标量）；
/// - 20018 或「登录已过期」msg → authentication（decodeEnvelope 统一判定）；
/// - status!=1 且 error_code=20017 → authentication(20017)；
/// - 其余非成功 → business（request::success）。
WireEnvelope decodeCloudListEnvelope(Uint8List bytes) {
  final envelope = decodeEnvelope(bytes);
  if (envelope.status != 1 && envelope.errorCode == 20017) {
    throw const KugouApiException(
      'authentication',
      '账号认证无效，请重新登录',
      code: 20017,
    );
  }
  ensureBusinessSuccess(envelope.status, envelope.errorCode);
  return envelope;
}

/// `cloudlist::decode::<Option<Data>>(..).unwrap_or_default()`：data 缺省/null
/// → 空 object（全字段缺省）；其它非 object（数组/标量）→ decode。
Map<String, Object?> decodeCloudListData(Uint8List bytes) {
  final envelope = decodeCloudListEnvelope(bytes);
  final data = envelope.data;
  if (data == null) return const <String, Object?>{};
  final map = wireMap(data);
  if (map == null) {
    throw const KugouApiException('decode', '云歌单响应 data 不是 object');
  }
  return map;
}

/// `request::encode(&json!({...}))`：serde_json 默认 Map 是 BTreeMap，
/// `json!` 的键按字典序输出（嵌套同理）——明文 JSON 请求体按此编码，
/// 与 Android 签名覆盖的字节保持一致。
Uint8List encodeCloudListJson(Map<String, Object?> value) =>
    Uint8List.fromList(utf8.encode(_sortedJsonText(value)));

String _sortedJsonText(Map<String, Object?> value) =>
    jsonEncode(_sortedValue(value));

Object? _sortedValue(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _sortedValue(value[key]),
    };
  }
  if (value is List) {
    return <Object?>[for (final item in value) _sortedValue(item)];
  }
  return value;
}
