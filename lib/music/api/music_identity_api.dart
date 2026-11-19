/// 身份读写缝（L 线扩展，播放/收藏只读）。
///
/// 为什么不扩 `MusicApi`：三个既有测试文件都 `implements MusicApi`，加抽象
/// 方法会同时编译失败。新能力一律走独立接口——`KugouMusicApi` 同时
/// `implements MusicApi, MusicIdentityApi`。
library;

import 'package:mimao/music/client/kugou_identity.dart';

abstract interface class MusicIdentityApi {
  /// 确保设备身份可用（首次生成匿名身份并注册 dfid）。
  Future<KugouIdentity> ensureDevice();

  /// 只读当前身份；未引导返回 null（不联网、不生成）。
  Future<KugouIdentity?> currentIdentity();

  /// 落盘新身份（登录/登出后调用）。
  Future<void> saveIdentity(KugouIdentity identity);
}
