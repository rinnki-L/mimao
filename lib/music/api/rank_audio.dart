/// 榜单歌曲端点——EchoMusicNext `crates/echo-api/src/module/rank_audio.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 榜单歌曲保留每音质时长、版权、发布、版本、歌手头像与榜内位置等独立事实
/// （上游模块头注释）；资源表不走搜索侧的全空跳过/去重——上游无条件压入
/// 128/320/flac/high/super 五档，ogg 档来自 trans_param。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/rank_models.dart';

/// 榜单歌曲输入（rank_audio.rs `Query { rank_id }`）。
class MusicRankAudioQuery {
  const MusicRankAudioQuery({required this.rankId});

  final int rankId;

  void validate() {
    // 上游显式校验：rank_id == 0 → input「排行榜无效」（负数在 u64 反序列化
    // 层就会被拒，同一入口报 input）。
    if (rankId <= 0) {
      throw const KugouApiException('input', '排行榜无效');
    }
  }
}

/// POST /openapi/kmr/v2/rank/audio（网关；固定 body + kg-tid=369）。
Future<MusicRankSongs> fetchRankAudio(
  MusicSession session,
  MusicRankAudioQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/openapi/kmr/v2/rank/audio',
      method: 'POST',
      body: encodeJsonBody(<String, Object?>{
        'show_portrait_mv': 1,
        'show_type_total': 1,
        'filter_original_remarks': 1,
        'area_code': 1,
        'pagesize': 100,
        'rank_cid': 0,
        'type': 1,
        'page': 1,
        'rank_id': query.rankId,
      }),
      headers: const <(String, String)>[('kg-tid', '369')],
    ),
  );
  return convertRankAudio(response.bytes);
}

/// wire 解析（rank_audio.rs `convert`）：`status` + `error_code` 信封。
MusicRankSongs convertRankAudio(Uint8List bytes) {
  final envelope = decodeEnvelopeWithFields(bytes);
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '榜单歌曲');
  final data = requiredWireMap(envelope.data, 'data');
  return MusicRankSongs(
    total: optionalInt(data['total']),
    songs: wireList(data['songlist'], 'songlist').map(_convertSong).toList(),
  );
}

MusicRankSong _convertSong(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '榜单歌曲条目不是 object');
  }
  // `object` 反序列化语义：audio_info 等嵌套结构 null/非 object → 默认空。
  final audio = wireMap(wire['audio_info']) ?? const <String, Object?>{};
  final album = wireMap(wire['album_info']) ?? const <String, Object?>{};
  final deprecated = wireMap(wire['deprecated']) ?? const <String, Object?>{};
  final business = wireMap(wire['business']) ?? const <String, Object?>{};
  final video = wireMap(wire['video_info']) ?? const <String, Object?>{};
  final privilegeDownload = rankNumberMapFromWire(wire['privilege_download']);
  final userDownload = rankNumberMapFromWire(wire['user_download']);
  final (rights, resources) = rankCatalogRightsFromTransParam(
    wire['trans_param'],
  );

  final authors = wireList(
    wire['authors'],
    'authors',
  ).map(_authorDetail).toList();
  final duration128 = optionalInt(audio['duration_128']);
  final summary = MusicSong(
    id: wireText(wire['album_audio_id']),
    audioId: optionalInt(wire['audio_id']),
    hash: wireText(audio['hash_128']),
    title: wireText(wire['songname']),
    artists: [
      for (final author in authors)
        MusicArtistRef(id: author.id, name: author.name),
    ],
    albumId: wireText(wire['album_id']),
    albumTitle: wireText(album['album_name']),
    // 上游 duration_ms 直接取 audio_info.duration_128（wire 本就是毫秒）。
    durationMs: duration128,
    coverUrl: coverUrl(wireText(album['sizable_cover'])),
    privilege: privilegeDownload['privilege'],
    resources: const <MusicAudioResource>[],
  );

  // 五档无条件压入（rank_audio.rs 的 for 循环；无搜索侧的全空跳过）。
  // 128/super 的 extension 上游恒 Some(text)——缺省是空串不是 null；
  // 320/flac/high 上游显式 None。
  void push(
    String quality,
    String hash,
    int? size,
    int? duration,
    int? bitrate,
    String? ext,
    int? pay,
  ) {
    resources.add(
      MusicRankResource(
        quality: quality,
        hash: hash,
        sizeBytes: size,
        durationMs: duration,
        bitRateBps: bitrate == null ? null : bitrate * 1000,
        extension: ext,
        privilege: privilegeDownload['privilege_$quality'],
        paymentType: pay,
        failureCode: privilegeDownload['fail_process_$quality'],
        downloadStatus: userDownload['status_$quality'],
      ),
    );
  }

  push(
    '128',
    wireText(audio['hash_128']),
    optionalInt(audio['filesize_128']),
    duration128,
    optionalInt(audio['bitrate']),
    wireText(audio['extname']),
    optionalInt(deprecated['pay_type_128']),
  );
  push(
    '320',
    wireText(audio['hash_320']),
    optionalInt(audio['filesize_320']),
    optionalInt(audio['duration_320']),
    null,
    null,
    optionalInt(deprecated['pay_type_320']),
  );
  push(
    'flac',
    wireText(audio['hash_flac']),
    optionalInt(audio['filesize_flac']),
    optionalInt(audio['duration_flac']),
    optionalInt(audio['bitrate_flac']),
    null,
    optionalInt(deprecated['pay_type_flac']),
  );
  push(
    'high',
    wireText(audio['hash_high']),
    optionalInt(audio['filesize_high']),
    optionalInt(audio['duration_high']),
    optionalInt(audio['bitrate_high']),
    null,
    optionalInt(deprecated['pay_type_high']),
  );
  push(
    'super',
    wireText(audio['hash_super']),
    optionalInt(audio['filesize_super']),
    optionalInt(audio['duration_super']),
    optionalInt(audio['bitrate_super']),
    wireText(audio['extname_super']),
    optionalInt(deprecated['pay_type_super']),
  );

  final videos = wireList(wire['mvdata'], 'mvdata').map((raw) {
    final mv = wireMap(raw);
    if (mv == null) {
      throw const KugouApiException('decode', '榜单 MV 条目不是 object');
    }
    return MusicRankVideoReference(
      id: wireText(mv['id']),
      hash: wireText(mv['hash']),
      kind: optionalInt(mv['typ']),
      track: wireText(mv['trk']),
    );
  }).toList();
  // video_info 分支：hash 非空或 id/时长/大小非 0 才补一条。
  final videoId = optionalInt(video['video_id']);
  final videoTimelength = optionalInt(video['video_timelength']);
  final videoFilesize = optionalInt(video['video_filesize']);
  if (wireText(video['video_hash']).isNotEmpty ||
      (videoId != null && videoId != 0) ||
      (videoTimelength != null && videoTimelength != 0) ||
      (videoFilesize != null && videoFilesize != 0)) {
    videos.add(
      MusicRankVideoReference(
        id: videoId?.toString(),
        hash: wireText(video['video_hash']),
        track: optionalInt(video['video_track'])?.toString(),
        durationMs: videoTimelength,
        sizeBytes: videoFilesize,
      ),
    );
  }

  final relatedVersions = wireList(wire['remarks'], 'remarks').map((raw) {
    final remark = wireMap(raw);
    if (remark == null) {
      throw const KugouApiException('decode', '榜单备注条目不是 object');
    }
    return MusicRankRelatedVersion(
      albumAudioId: optionalInt(remark['rel_album_audio_id'])?.toString() ?? '',
      remark: wireText(remark['remark']),
      kind: optionalInt(remark['type']),
    );
  }).toList();

  return MusicRankSong(
    song: summary,
    metadata: MusicRankSongMetadata(
      audioId: optionalInt(wire['audio_id']),
      albumAudioRemark: wireText(business['album_audio_remark']),
      sourceFileName: wireText(business['filename']),
      publicationCode: optionalInt(wire['is_publish']),
      originalityCode: rights.originalityCode,
      hasAccompaniment: optionalBool(wire['has_obbligato']),
      accompanimentCode: optionalInt(wire['has_obbligato']),
      paymentType: optionalInt(deprecated['pay_type']),
      failureCode: privilegeDownload['fail_process'],
      oldCopyrightCode: optionalInt(deprecated['old_cpy']),
      rights: rights,
      resources: resources,
      videos: videos,
      recommendation: MusicRankRecommendationText(
        headline: wireText(business['recommend_reason']),
      ),
      ranking: MusicRankPosition(
        rankId: wireText(business['rank_id']),
        issue: wireText(business['issue']),
        rankCid: optionalInt(wire['rank_cid']),
        position: optionalInt(business['sort']),
        previousPosition: optionalInt(business['last_sort']),
        originalPosition: optionalInt(business['original_index']),
        previousOriginalPosition: optionalInt(business['last_original_index']),
        change: optionalInt(business['offset']),
        publishedAt: wireText(business['rank_id_publish_date']),
      ),
      artists: authors,
      relatedVersions: relatedVersions,
    ),
  );
}

/// 作者条目（rank_audio.rs `Author`；头像走 cover_url）。
MusicRankArtistDetail _authorDetail(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '榜单作者条目不是 object');
  }
  return MusicRankArtistDetail(
    id: optionalInt(wire['author_id']),
    name: wireText(wire['author_name']),
    avatarUrl: coverUrl(wireText(wire['sizable_avatar'])),
  );
}
