/// 听歌上报模型——EchoMusicNext `crates/echo-api/src/module/user_listen_report.rs`
/// 的 DTO 翻译（docs/architecture.md §4.3：`music/models/` ← module DTO）。
///
/// 只承载本组的数据形态：查询参数（`Query`）、内存 CSCC 会话（`Session`）、
/// 上报受理（`Acceptance`）。字段语义逐条对应上游结构体。
library;

/// 上报事件阶段（user_listen_report.rs `Event`：snake_case 的 start/end）。
enum MusicListenReportEvent {
  /// 开始播放（type_id=20431）。
  start,

  /// 结束播放（type_id=4；`durationMs` 必填）。
  end,
}

/// 一次听歌上报的查询参数（user_listen_report.rs `Query`）。
///
/// `mixsongid` 是协议里的 u64 歌曲主键（>0）；`durationMs` 仅 [MusicListenReportEvent.end]
/// 事件需要（毫秒，可空但 end 必填——由端点层校验）；`completed` 对应 end
/// 事件的「完整播放/中断播放」状态，默认 false。
class MusicListenReportQuery {
  const MusicListenReportQuery({
    required this.event,
    required this.mixsongid,
    this.durationMs,
    this.completed = false,
  });

  /// 事件阶段（start/end）。
  final MusicListenReportEvent event;

  /// u64 歌曲主键（Rust 域内恒 >0；==0 会被端点层 input 拒绝）。
  final int mixsongid;

  /// 播放时长（毫秒）；end 事件必填（Rust `duration_ms: Option<u64>`）。
  final int? durationMs;

  /// end 事件是否完整播放（Rust `#[serde(default)] completed: bool`）。
  final bool completed;
}

/// CSCC 握手产出的内存会话（user_listen_report.rs `Session`）。
///
/// 只存在于实现类的内存缓存里：`cookie/clienttime/serverstr` 来自 /v2/gen
/// 的 AES 解密结果，`seed` 是本端生成的 16 字节 hex；`expiresAt` 对应上游
/// `Instant::now() + 1800s`。绝不持久化、不打日志。
class MusicListenReportSession {
  const MusicListenReportSession({
    required this.cookie,
    required this.clienttime,
    required this.serverstr,
    required this.seed,
    required this.expiresAt,
  });

  /// 上报 POST 的 `cookie` 参数（/v2/gen 会话数据）。
  final String cookie;

  /// 会话服务器时间（秒；参与事件密钥派生）。
  final int clienttime;

  /// 服务器字符串（参与事件密钥派生）。
  final String serverstr;

  /// 本端随机 16 字节 hex（32 字符；参与事件密钥派生）。
  final String seed;

  /// 过期时刻（创建 +1800 秒；到期即重新握手）。
  final DateTime expiresAt;
}

/// 上报受理结果（user_listen_report.rs `Acceptance`：`{"accepted":true}`）。
class MusicListenReportAcceptance {
  const MusicListenReportAcceptance({required this.accepted});

  /// 服务端是否受理（本端点成功路径恒为 true）。
  final bool accepted;
}
