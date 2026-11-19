/// 扫码登录轮询控制器（不依赖 UI）——把 [MusicAccountApi] 的状态映射成
/// 设置页可观察的 [QrLoginPhase]，并负责定时器生命周期。
///
/// 状态机：`idle → loading → waiting ⇄ scanned → authorized | expired | failed`。
/// 两条硬约束（既有设置页测试与真机体验的前提）：
/// 1. **构造时绝不自动 start()**——只有用户点「扫码登录」打开对话框后才启动，
///    否则 2 秒周期定时器会把 `pumpAndSettle()` 永久挂住；
/// 2. `cancel()`/`dispose()` 之后不再有任何定时器与请求回调。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/music_account_api.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

/// 对话框可见的登录阶段。
enum QrLoginPhase {
  idle,
  loading,
  waiting,
  scanned,
  authorized,
  expired,
  failed,
}

/// 把服务端 `data:image/png;base64,` 前缀（或纯 base64）转成图片字节。
///
/// 解析失败返回 null——UI 显示「二维码获取失败，请刷新」，绝不抛到 build。
Uint8List? decodeQrImageData(String dataUrl) {
  final trimmed = dataUrl.trim();
  if (trimmed.isEmpty) return null;
  var payload = trimmed;
  if (trimmed.startsWith('data:')) {
    final comma = trimmed.indexOf(',');
    if (comma < 0) return null;
    payload = trimmed.substring(comma + 1);
  }
  try {
    return base64Decode(base64.normalize(payload));
  } on FormatException {
    return null;
  }
}

class QrLoginController {
  QrLoginController({
    required this.account,
    this.pollInterval = const Duration(seconds: 2),
    this.onChanged,
  });

  final MusicAccountApi account;

  /// 每轮轮询间隔；测试注入短间隔。
  final Duration pollInterval;

  /// 状态变化通知（UI 用它 setState；控制器自身不 import Flutter）。
  final void Function()? onChanged;

  QrLoginPhase _phase = QrLoginPhase.idle;
  QrLoginSession? _session;
  String? _error;
  KugouIdentity? _identity;

  Timer? _timer;

  /// 只有 `_active` 时才继续轮询；authorized/expired/failed/cancel 都会置 false。
  bool _active = false;
  bool _polling = false;
  bool _disposed = false;

  /// 代际计数：refresh/cancel 后忽略旧会话的迟到结果。
  int _epoch = 0;

  QrLoginPhase get phase => _phase;

  QrLoginSession? get session => _session;

  /// 失败原因（failed 阶段可展示）；不包含 token/t1。
  String? get error => _error;

  /// 授权成功后的新身份（落盘完成）。
  KugouIdentity? get identity => _identity;

  bool get isActive => _active;

  /// 取新二维码并开始轮询。可在 failed/expired 后重试。
  Future<void> start() => _loadSession();

  /// 刷新二维码（等价于重新 start）。
  Future<void> refresh() => _loadSession();

  Future<void> _loadSession() async {
    if (_disposed) return;
    _stopped();
    final epoch = ++_epoch;
    _session = null;
    _error = null;
    _identity = null;
    _phase = QrLoginPhase.loading;
    _notify();
    try {
      final session = await account.startQrLogin();
      if (!_isEpoch(epoch)) return;
      // 上游允许空串（合法字段值）；产品策略在此拒绝并提示刷新。
      if (session.key.trim().isEmpty || session.imageDataUrl.trim().isEmpty) {
        _fail('二维码获取失败，请刷新');
        return;
      }
      _session = session;
      _active = true;
      _phase = QrLoginPhase.waiting;
      _notify();
      _timer = Timer.periodic(pollInterval, (_) => unawaited(_poll()));
    } on Object catch (error) {
      if (_isEpoch(epoch)) _fail(_messageOf(error));
    }
  }

  Future<void> _poll() async {
    final session = _session;
    if (_disposed || !_active || _polling || session == null) return;
    final epoch = _epoch;
    _polling = true;
    try {
      final status = await account.pollQrLogin(session.key);
      if (!_isCurrent(epoch) || !_active) return;
      switch (status.state) {
        case QrLoginState.waiting:
          _phase = QrLoginPhase.waiting;
          _notify();
        case QrLoginState.scanned:
          _phase = QrLoginPhase.scanned;
          _notify();
        case QrLoginState.expired:
          _stopped();
          _phase = QrLoginPhase.expired;
          _notify();
        case QrLoginState.authorized:
          // 先停表再落盘：授权只消费一次，避免重复 loginWith。
          _stopped();
          final authorization = status.authorization;
          if (authorization == null) {
            _fail('登录凭证缺失，请刷新二维码重试');
            return;
          }
          try {
            final identity = await account.loginWith(authorization);
            if (!_isEpoch(epoch)) return;
            _identity = identity;
            _phase = QrLoginPhase.authorized;
            _notify();
          } on Object catch (error) {
            if (_isEpoch(epoch)) _fail(_messageOf(error));
          }
      }
    } on Object catch (error) {
      if (_isEpoch(epoch) && _active) _fail(_messageOf(error));
    } finally {
      _polling = false;
    }
  }

  /// 停止轮询但保留当前状态（对话框关闭/已结束）。幂等；之后不再发请求。
  void cancel() {
    _stopped();
    _epoch++;
  }

  void dispose() {
    _disposed = true;
    cancel();
  }

  void _stopped() {
    _active = false;
    _timer?.cancel();
    _timer = null;
  }

  void _fail(String message) {
    _stopped();
    _phase = QrLoginPhase.failed;
    _error = message;
    _notify();
  }

  bool _isEpoch(int epoch) => !_disposed && epoch == _epoch;

  bool _isCurrent(int epoch) => _isEpoch(epoch) && _active;

  void _notify() {
    if (_disposed) return;
    onChanged?.call();
  }

  /// 对外文案：KugouApiException 用 message，其它异常用原始文本（网络层
  /// 信息对用户有用）；统一去掉 `token/t1/signature=` 这类凭证片段。
  String _messageOf(Object error) {
    final raw = error is KugouApiException ? error.message : '$error';
    final message = raw.trim();
    return _redact(message.isEmpty ? '登录失败，请重试' : message);
  }

  String _redact(String text) => text.replaceAllMapped(
    RegExp(r'(token|t1|signature)=[^&\s]+', caseSensitive: false),
    (match) => '${match[1]}=***',
  );
}
