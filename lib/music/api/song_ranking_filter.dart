/// 播放页榜单筛选端点——EchoMusicNext
/// `crates/echo-api/src/module/song_ranking_filter.rs` 的翻译
/// （docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/rank_models.dart';

/// 榜单筛选输入（song_ranking_filter.rs `Query`）。
class MusicSongRankingFilterQuery {
  const MusicSongRankingFilterQuery({
    required this.albumAudioId,
    this.page = 1,
    this.pageSize = 30,
  });

  final int albumAudioId;

  /// 上游 Query 默认 1，execute 以 `page` 键发送。
  final int page;

  /// 上游 Query 默认 30，execute 以 `pagesize` 键发送。
  final int pageSize;
}

/// GET /grow/v1/song_ranking/unlock/v2/ranking_filter（网关）。
Future<MusicSongRankingFilter> fetchSongRankingFilter(
  MusicSession session,
  MusicSongRankingFilterQuery query,
) async {
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/grow/v1/song_ranking/unlock/v2/ranking_filter',
      method: 'GET',
      params: <String, String>{
        'album_audio_id': query.albumAudioId.toString(),
        'page': query.page.toString(),
        'pagesize': query.pageSize.toString(),
      },
    ),
  );
  return convertSongRankingFilter(response.bytes);
}

/// wire 解析（song_ranking_filter.rs `convert`）：`status` 必填标量 +
/// `errcode` 可缺省（缺省按成功 0 判定）+ data 经 `object` 反序列化。
MusicSongRankingFilter convertSongRankingFilter(Uint8List bytes) {
  final root = decodeRankRoot(bytes);
  final status = requiredScalarInt(root['status'], 'status');
  final errcode = optionalInt(root['errcode']);
  ensureBusinessSuccess(status, errcode ?? 0, context: '榜单筛选');
  return _filter(root['data']);
}

/// song_ranking_filter.rs `Ranking`：data 或其内部字段不可解析时整个归默认
/// 空值（`object` 的 unwrap_or_default 语义），不抛 decode。
MusicSongRankingFilter _filter(Object? data) {
  final wire = wireMap(data);
  if (wire == null) {
    return const MusicSongRankingFilter();
  }
  try {
    return MusicSongRankingFilter(
      options: wireList(wire['list'], 'list').map(_option).toList(),
    );
  } on KugouApiException {
    return const MusicSongRankingFilter();
  }
}

MusicSongRankingFilterOption _option(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '榜单筛选条目不是 object');
  }
  return MusicSongRankingFilterOption(
    area: optionalInt(wire['area']),
    count: optionalInt(wire['count']),
    platform: optionalInt(wire['platform']),
    topRanking: optionalInt(wire['top_ranking']),
    logoPic: wireText(wire['logo_pic']),
    name: wireText(wire['name']),
    platformName: wireText(wire['platform_name']),
    sharePic: wireText(wire['share_pic']),
  );
}
