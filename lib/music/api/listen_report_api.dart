/// 听歌上报组接口——`MusicListenReportApi` + 酷狗实现 `KugouListenReportApi`。
///
/// 组内只此一个端点（user_listen_report）；CSCC 会话缓存在实现类实例里
/// （按身份派生 key、1800 秒过期、最多 256 条、并发初始化合并、失败清除），
/// 不做全局单例。协议细节见 `user_listen_report.dart`。
library;

import 'dart:math';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/user_listen_report.dart';
import 'package:mimao/music/models/user_listen_report_models.dart';

/// 听歌上报组接口（集成者组合进 `KugouMusicApi`）。
abstract interface class MusicListenReportApi {
  /// 上报一次听歌事件（start/end）。
  ///
  /// `clock`/`random` 为测试注入缝（固定时钟/随机源），生产可不传。
  Future<MusicListenReportAcceptance> listenReport(
    MusicListenReportQuery query, {
    MusicListenReportClock? clock,
    Random? random,
  });
}

/// 酷狗实现：持有 [MusicSession] 与实例私有的 CSCC 会话缓存。
class KugouListenReportApi implements MusicListenReportApi {
  KugouListenReportApi(this.session);

  final MusicSession session;

  /// CSCC 会话缓存（内存表；生命周期与本实例一致）。
  final MusicListenReportSessionCache _sessions =
      MusicListenReportSessionCache();

  @override
  Future<MusicListenReportAcceptance> listenReport(
    MusicListenReportQuery query, {
    MusicListenReportClock? clock,
    Random? random,
  }) => fetchListenReport(
    session,
    query,
    cache: _sessions,
    clock: clock,
    random: random,
  );
}
