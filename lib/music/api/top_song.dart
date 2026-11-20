/// 新歌首发端点——EchoMusicNext `crates/echo-api/src/module/top_song.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 数字 id 与每音质毫秒时长；字段模型独立于每日推荐（上游模块头注释）。
/// wire 的 `data` 是**根级数组**（不是信封 data 字段下的嵌套），状态对在
/// 根上：status/error_code 必填标量 + total 可缺省。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/rank_models.dart';

/// POST /musicadservice/container/v1/newsong_publish（网关；固定新歌榜
/// rank_id=21608，tags 空数组）。
Future<MusicRankNewSongs> fetchTopSongs(MusicSession session) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/musicadservice/container/v1/newsong_publish',
      method: 'POST',
      body: encodeJsonBody(<String, Object?>{
        'rank_id': 21608,
        'userid': identity.userId,
        'page': 1,
        'pagesize': 30,
        'tags': <Object?>[],
      }),
    ),
  );
  return convertTopSongs(response.bytes);
}

/// wire 解析（top_song.rs `convert`）：先按 AckEnvelope 判
/// status/error_code，再解根级 data 数组（上游 decode_value 的白名单键只
/// 服务诊断路径，语义等价于整包反序列化）。
MusicRankNewSongs convertTopSongs(Uint8List bytes) {
  final root = decodeRankRoot(bytes);
  final status = requiredScalarInt(root['status'], 'status');
  final errorCode = requiredScalarInt(root['error_code'], 'error_code');
  ensureBusinessSuccess(status, errorCode, context: '新歌首发');
  return MusicRankNewSongs(
    total: optionalInt(root['total']),
    songs: wireList(root['data'], 'data').map(_convertSong).toList(),
  );
}

MusicRankNewSong _convertSong(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '新歌条目不是 object');
  }
  final trans = wireMap(wire['trans_param']) ?? const <String, Object?>{};
  final (rights, resources) = rankCatalogRightsFromTransParam(trans);

  final artistDetails = wireList(
    wire['authors'],
    'authors',
  ).map(_author).toList();
  final relatedVersions = <MusicRankRelatedVersion>[];
  final defaultAliasCodes = <int?>[];
  for (final rawRemark in wireList(wire['remarks'], 'remarks')) {
    final remark = wireMap(rawRemark);
    if (remark == null) {
      throw const KugouApiException('decode', '新歌备注条目不是 object');
    }
    relatedVersions.add(
      MusicRankRelatedVersion(
        albumAudioId:
            optionalInt(remark['rel_album_audio_id'])?.toString() ?? '',
        remark: wireText(remark['remark']),
        kind: optionalInt(remark['remark_type']),
      ),
    );
    defaultAliasCodes.add(optionalInt(remark['is_defaut_alias']));
  }

  // 五档无条件压入（top_song.rs 的 for 循环）；128/super 的 extension 上游
  // 恒 Some(text)——缺省是空串不是 null；320/flac/high 上游显式 None。
  void push(
    String quality,
    String hash,
    int? size,
    int? duration,
    int? privilege,
    int? pay,
    int? failure,
    int? downloadStatus,
    int? bitrate,
    String? ext,
  ) {
    resources.add(
      MusicRankResource(
        quality: quality,
        hash: hash,
        sizeBytes: size,
        durationMs: duration,
        bitRateBps: bitrate == null ? null : bitrate * 1000,
        extension: ext,
        privilege: privilege,
        paymentType: pay,
        failureCode: failure,
        downloadStatus: downloadStatus,
      ),
    );
  }

  push(
    '128',
    wireText(wire['hash_128']),
    optionalInt(wire['filesize_128']),
    optionalInt(wire['timelength_128']),
    optionalInt(wire['privilege_128']),
    optionalInt(wire['pay_type_128']),
    optionalInt(wire['fail_process_128']),
    optionalInt(wire['status_128']),
    optionalInt(wire['bitrate']),
    wireText(wire['extname']),
  );
  push(
    '320',
    wireText(wire['hash_320']),
    optionalInt(wire['filesize_320']),
    optionalInt(wire['timelength_320']),
    optionalInt(wire['privilege_320']),
    optionalInt(wire['pay_type_320']),
    optionalInt(wire['fail_process_320']),
    optionalInt(wire['status_320']),
    null,
    null,
  );
  push(
    'flac',
    wireText(wire['hash_flac']),
    optionalInt(wire['filesize_flac']),
    optionalInt(wire['timelength_flac']),
    optionalInt(wire['privilege_flac']),
    optionalInt(wire['pay_type_flac']),
    optionalInt(wire['fail_process_flac']),
    optionalInt(wire['status_flac']),
    optionalInt(wire['bitrate_flac']),
    null,
  );
  push(
    'high',
    wireText(wire['hash_high']),
    optionalInt(wire['filesize_high']),
    optionalInt(wire['timelength_high']),
    optionalInt(wire['privilege_high']),
    optionalInt(wire['pay_type_high']),
    optionalInt(wire['fail_process_high']),
    optionalInt(wire['status_high']),
    optionalInt(wire['bitrate_high']),
    null,
  );
  push(
    'super',
    wireText(wire['hash_super']),
    optionalInt(wire['filesize_super']),
    optionalInt(wire['timelength_super']),
    optionalInt(wire['privilege_super']),
    optionalInt(wire['pay_type_super']),
    optionalInt(wire['fail_process_super']),
    optionalInt(wire['status_super']),
    optionalInt(wire['bitrate_super']),
    wireText(wire['extname_super']),
  );

  // video_hash 为空 → 无视频条目（上游 Vec::new()）。
  final videos = wireText(wire['video_hash']).isEmpty
      ? const <MusicRankVideoReference>[]
      : <MusicRankVideoReference>[
          MusicRankVideoReference(
            id: optionalInt(wire['video_id'])?.toString(),
            hash: wireText(wire['video_hash']),
            track: optionalInt(wire['video_track'])?.toString(),
            durationMs: optionalInt(wire['video_timelength']),
            sizeBytes: optionalInt(wire['video_filesize']),
          ),
        ];

  return MusicRankNewSong(
    song: MusicSong(
      id: wireText(wire['album_audio_id']),
      audioId: optionalInt(wire['audio_id']),
      hash: wireText(wire['hash']),
      title: wireText(wire['songname']),
      artists: [
        for (final artist in artistDetails)
          MusicArtistRef(id: artist.id, name: artist.name),
      ],
      albumId: wireText(wire['album_id']),
      albumTitle: wireText(wire['album_name']),
      durationMs: optionalInt(wire['timelength']),
      coverUrl: coverUrl(wireText(wire['album_sizable_cover'])),
      privilege: optionalInt(wire['privilege']),
      resources: const <MusicAudioResource>[],
    ),
    metadata: MusicRankNewSongMetadata(
      catalog: MusicRankSongMetadata(
        audioId: optionalInt(wire['audio_id']),
        titleSuffix: optionalText(trans['songname_suffix']),
        albumAudioRemark: wireText(wire['album_audio_remark']),
        sourceFileName: wireText(wire['filename']),
        publishedAt: wireText(wire['publish_date']),
        originalityCode: rights.originalityCode,
        hasAccompaniment: optionalBool(wire['has_obbligato']),
        accompanimentCode: optionalInt(wire['has_obbligato']),
        paymentType: optionalInt(wire['pay_type']),
        failureCode: optionalInt(wire['fail_process']),
        oldCopyrightCode: optionalInt(wire['old_cpy']),
        rights: rights,
        resources: resources,
        videos: videos,
        recommendation: MusicRankRecommendationText(
          headline: wireText(wire['recommend_reason']),
        ),
        artists: artistDetails,
        relatedVersions: relatedVersions,
      ),
      chart: MusicRankSongChart(
        rankId: wireText(wire['rank_id']),
        issue: wireText(wire['issue']),
        rankCid: optionalInt(wire['rank_cid']),
        position: optionalInt(wire['sort']),
        previousPosition: optionalInt(wire['last_sort']),
        change: optionalInt(wire['offset']),
      ),
      defaultAliasCodes: defaultAliasCodes,
    ),
  );
}

/// 作者条目（top_song.rs `Author`；is_publish 落 publicationCode）。
MusicRankArtistDetail _author(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '新歌作者条目不是 object');
  }
  return MusicRankArtistDetail(
    id: optionalInt(wire['author_id']),
    name: wireText(wire['author_name']),
    avatarUrl: coverUrl(wireText(wire['sizable_avatar'])),
    publicationCode: optionalInt(wire['is_publish']),
  );
}
