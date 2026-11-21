/// 登录态变化信号（音乐模块内部）。
///
/// 登录/登出都只经 `KugouMusicApi.saveIdentity` 这一个写入口（扫码线
/// `KugouAccountApi` 与登录组 `KugouAuthApi` 共用），因此由它递增该值；
/// UI 页面监听后自动重拉依赖账号的数据（资料/会员/历史/私人 FM/账号收藏），
/// 不需要用户手动点重试。
///
/// 做成独立接口而不是塞进 `MusicApi`：既有 fake 不必实现它，页面拿到 null
/// 时保持原行为（不监听），测试注入 `ValueNotifier<int>` 即可驱动。
library;

import 'package:flutter/foundation.dart';

abstract interface class MusicAuthEvents {
  /// 每次账号登录/登出（hasAccount 或 userId 变化）递增。
  ValueListenable<int> get authEpoch;
}
