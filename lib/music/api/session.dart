/// 音乐各端点组的共享会话底座。
///
/// 现有骨架把「客户端 + 身份仓库」封装在 `KugouMusicApi` 里；端点扩容后
/// 每组成员都需要同一条装配缝，但不应各自持有/复制身份状态。这里把
/// 「传输层 + 身份读写」抽成无状态会话对象，端点组只依赖本文件：
///
/// - [ensureDevice]：与 `MusicApi.ensureDevice` 同一语义（生成匿名身份 /
///   注册真 dfid / 落盘），带缓存；
/// - [loadIdentity]：只读当前身份，不联网；
/// - [saveIdentity]：登录/登出后的唯一写入口。
///
/// 生产装配由 `KugouMusicApi` 提供；测试用假身份 +
/// `CaptureAdapter` 即可离线跑完整端点，不触碰 path_provider。
library;

import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';

/// 读取（必要时生成/注册）可用身份。
typedef MusicIdentityLoader = Future<KugouIdentity> Function();

/// 写回身份（登录/登出/设备注册）。
typedef MusicIdentitySaver = Future<void> Function(KugouIdentity);

/// 端点组共享的传输与身份会话。不可变；身份缓存语义由注入的函数负责。
class MusicSession {
  const MusicSession({
    required this.client,
    required this.ensureDevice,
    required this.loadIdentity,
    required this.saveIdentity,
  });

  final KugouClient client;

  /// 保证 mid/dfid 就绪；首次调用可能联网（设备注册）。
  final MusicIdentityLoader ensureDevice;

  /// 只读身份，不生成、不注册、不联网。
  final MusicIdentityLoader loadIdentity;

  /// 统一写回身份（与搜索/播放共用同一份缓存，避免登录后仍用旧 token）。
  final MusicIdentitySaver saveIdentity;
}
