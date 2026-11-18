/// 音乐 API 的统一异常——镜像 EchoMusicNext `crates/echo-api/src/error.rs`
/// 的 ApiError kind 词表（docs/architecture.md §4.3）。
///
/// kind 是稳定契约（页面按 kind 决定文案与重试语义），message 只给人看。
class KugouApiException implements Exception {
  const KugouApiException(this.kind, this.message, {this.code});

  /// 'input' | 'business' | 'decode' | 'authentication' | 'http' | 'encoding'
  /// | 'device_registration_unassigned' | 'device_registration_decrypt'
  /// （'clock'/'limit' 等其余 Rust 词表项随后续切片补齐）
  final String kind;

  final String message;

  /// 服务端业务错误码（wire `error_code`），仅 business 类可能携带。
  final int? code;

  @override
  String toString() =>
      'KugouApiException($kind${code == null ? '' : '/$code'}): $message';
}
