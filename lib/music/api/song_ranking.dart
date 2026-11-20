/// 播放页歌曲排名端点——EchoMusicNext
/// `crates/echo-api/src/module/song_ranking.rs` 的翻译
/// （docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/rank_models.dart';

/// 歌曲排名输入（song_ranking.rs `Query`）。
///
/// 上游 Query 声明 page/page_size（默认 1/30）但 execute 只发送
/// album_audio_id；字段保留形状对齐，wire 上确实不带。
class MusicSongRankingQuery {
  const MusicSongRankingQuery({
    required this.albumAudioId,
    this.page = 1,
    this.pageSize = 30,
  });

  final int albumAudioId;
  final int page;
  final int pageSize;
}

/// GET /grow/v1/song_ranking/play_page/ranking_info（网关）。
Future<MusicSongRanking> fetchSongRanking(
  MusicSession session,
  MusicSongRankingQuery query,
) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/grow/v1/song_ranking/play_page/ranking_info',
      method: 'GET',
      params: <String, String>{'album_audio_id': query.albumAudioId.toString()},
    ),
  );
  return convertSongRanking(response.bytes);
}

/// wire 解析（song_ranking.rs `convert`）：`status` 必填标量 + `errcode`
/// 可缺省（缺省按成功 0 判定）+ data 经 `object` 反序列化。
MusicSongRanking convertSongRanking(Uint8List bytes) {
  final root = decodeRankRoot(bytes);
  final status = requiredScalarInt(root['status'], 'status');
  final errcode = optionalInt(root['errcode']);
  ensureBusinessSuccess(status, errcode ?? 0, context: '歌曲排名');
  return _ranking(root['data']);
}

/// song_ranking.rs `Ranking`：data 或其内部字段不可解析时整个归默认空值
/// （`object` 的 unwrap_or_default 语义），不抛 decode。
MusicSongRanking _ranking(Object? data) {
  final wire = wireMap(data);
  if (wire == null) {
    return const MusicSongRanking();
  }
  try {
    return MusicSongRanking(
      albumAudioId: optionalInt(wire['album_audio_id']),
      platformNum: optionalInt(wire['platform_num']),
      platformTotal: optionalInt(wire['platform_total']),
      title1: wireText(wire['title1']),
      title2: wireText(wire['title2']),
      achievements: wireList(wire['info'], 'info').map(_achievement).toList(),
    );
  } on KugouApiException {
    return const MusicSongRanking();
  }
}

MusicSongRankingAchievement _achievement(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '歌曲排名条目不是 object');
  }
  return MusicSongRankingAchievement(
    platform: optionalInt(wire['platform']),
    rankingNum: optionalInt(wire['ranking_num']),
    rankingTimes: optionalInt(wire['ranking_times']),
    platformName: wireText(wire['platform_name']),
    platformLogo: wireText(wire['platform_logo']),
    lastTime: wireText(wire['last_time']),
  );
}
