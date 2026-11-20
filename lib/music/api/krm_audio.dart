/// 歌曲资料补全端点——EchoMusicNext `crates/echo-api/src/module/krm_audio.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 纯展示性 enrichment（词曲/发行/BPM/语言），独立于播放授权。上游注释：
/// 缺失实体可能带 `__status=1`；合法歌曲的 album_info 也可能为 null——各
/// 可选事实独立保留。公开 100-ID 契约不变，但单次 HTTP 最多 50 个实体，
/// 顺序分块合并（保持在调用方既有的传输/取消作用域内）。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/playback_ext_models.dart';

/// 歌曲资料批量查询输入（krm_audio.rs `Query`）。
class KrmAudioQuery {
  const KrmAudioQuery({required this.albumAudioIds});

  final List<int> albumAudioIds;

  /// krm_audio.rs `execute` 的入参校验：1..=100 个、非 0、去重
  /// （u64 域：负数同样无效）。
  void validate() {
    if (albumAudioIds.isEmpty ||
        albumAudioIds.length > 100 ||
        albumAudioIds.any((id) => id <= 0) ||
        albumAudioIds.toSet().length != albumAudioIds.length) {
      throw const KugouApiException('input', '歌曲资料批量ID无效');
    }
  }
}

/// 单次请求实体上限（上游经验值：>50 会被网关以 20010 拒绝）。
const int kKrmAudioChunkSize = 50;

/// POST /kmr/v2/audio（网关 + x-router=openapi.kugou.com，KG-TID: 238）。
Future<List<MusicSongPresentation>> fetchKrmAudio(
  MusicSession session,
  KrmAudioQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  final presentations = <MusicSongPresentation>[];
  // 顺序分块：保持上游顺序，合并各块结果。
  for (
    var start = 0;
    start < query.albumAudioIds.length;
    start += kKrmAudioChunkSize
  ) {
    final end = start + kKrmAudioChunkSize > query.albumAudioIds.length
        ? query.albumAudioIds.length
        : start + kKrmAudioChunkSize;
    final ids = query.albumAudioIds.sublist(start, end);
    final response = await session.client.sendEndpoint(
      identity,
      KugouEndpoint(
        origin: KugouOrigin.gateway,
        path: '/kmr/v2/audio',
        router: 'openapi.kugou.com',
        method: 'POST',
        body: encodeJsonBody(<String, Object?>{
          'data': [
            for (final id in ids) <String, Object?>{'entity_id': id},
          ],
          'fields': 'album_info,base,authors.base,extra',
        }),
        headers: const <(String, String)>[('KG-TID', '238')],
      ),
    );
    presentations.addAll(convertSongPresentations(response.bytes));
  }
  return presentations;
}

/// krm_audio.rs `convert`。
///
/// 上游 `request::decode_value` 语义：无 decode_envelope 恢复分支，结构失败
/// 直接 decode；登录过期探测来自传输层 receive()（request.rs 对所有响应
/// 统一先判），本端点在解码入口补齐。
List<MusicSongPresentation> convertSongPresentations(Uint8List bytes) {
  final root = decodePlaybackRoot(bytes);
  // Wire{status 必填 scalar, error_code 必填 scalar, data 缺省 null}。
  final status = playbackOptionalUnsigned(root['status']);
  if (status == null) {
    throw const KugouApiException('decode', '无法解码接口响应字段 status');
  }
  final errorCode = requiredScalarInt(root['error_code'], 'error_code');
  ensureBusinessSuccess(status, errorCode, context: '歌曲资料');
  final data = root['data'];
  if (data == null) return const <MusicSongPresentation>[];
  // decode_value(Vec<Value>)：data 必须是数组（无 list 的空对象宽容）。
  if (data is! List) {
    throw const KugouApiException('decode', '无法解码接口响应字段 data');
  }
  final result = <MusicSongPresentation>[];
  for (final row in data) {
    final wire = wireMap(row);
    if (wire == null) {
      throw const KugouApiException('decode', '无法解码接口响应字段 data');
    }
    // 缺失实体确认（__status==1 且无 base）→ 跳过；其余行照常解码。
    final entityStatus = playbackOptionalUnsigned(wire['__status']);
    if (entityStatus == 1 && !wire.containsKey('base')) {
      continue;
    }
    result.add(_convertRecord(wire));
  }
  return result;
}

/// krm_audio.rs `Record` → `SongPresentation`。
MusicSongPresentation _convertRecord(Map<String, Object?> wire) {
  // base：response::object——缺失/非对象 → 空默认。
  final base = wireMap(wire['base']) ?? const <String, Object?>{};
  // album_info：optional——null/非对象 → None。
  final albumInfo = wireMap(wire['album_info']);
  final authors = wireList(
    wire['authors'],
    'authors',
  ).map(_convertAuthor).toList();
  // extra：optional——null/非对象 → 默认（全部未知）。
  final extra = wireMap(wire['extra']) ?? const <String, Object?>{};
  final albumPublishedAt = albumInfo == null
      ? null
      : optionalText(albumInfo['publish_date']);
  // album_info 缺失时回退 base 的专辑名；封面只在 album_info 里。
  final albumTitle = albumInfo == null
      ? wireText(base['album_name'])
      : wireText(albumInfo['album_name']);
  final cover = albumInfo == null ? '' : coverUrl(wireText(albumInfo['cover']));
  return MusicSongPresentation(
    id: wireText(base['album_audio_id']),
    title: wireText(base['songname']),
    albumId: wireText(base['album_id']),
    albumTitle: albumTitle,
    coverUrl: cover,
    artists: authors,
    information: MusicSongInformation(
      publishedAt: optionalText(base['publish_date']),
      albumPublishedAt: albumPublishedAt,
      language: optionalText(base['language']),
      lyricist: optionalText(extra['lyrics']),
      composer: optionalText(extra['composer']),
      bpm: playbackOptionalFiniteDouble(extra['bpm']),
      tempoCode: optionalText(extra['bpm_type']),
      tempoDescription: optionalText(extra['bpm_desc']),
    ),
  );
}

/// krm_audio.rs `Author`：base 走 response::object 宽容；avatar 恒过
/// cover_url（空头像保留 Some('')，上游 avatar_url 是 Some(cover_url(..))）。
MusicPresentationArtist _convertAuthor(Object? value) {
  final wire = wireMap(value);
  if (wire == null) {
    throw const KugouApiException('decode', '无法解码接口响应字段 authors');
  }
  final base = wireMap(wire['base']) ?? const <String, Object?>{};
  return MusicPresentationArtist(
    id: playbackOptionalUnsigned(base['author_id']),
    name: wireText(base['author_name']),
    avatarUrl: coverUrl(wireText(base['avatar'])),
    publicationCode: playbackOptionalUnsigned(base['is_publish']),
  );
}
