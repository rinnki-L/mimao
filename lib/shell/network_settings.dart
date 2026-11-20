/// 全局网络设置：漫画抓取是否走代理。
///
/// 只做「口子」：直连 / 跟随环境变量 / 自定义 HTTP 代理三种模式，落
/// `app_settings` kv 表，设置抽屉可切换。dio 的 `HttpClient.findProxy` 每次
/// 请求都会回调，所以切换后无需重建客户端即可生效。
///
/// 说明：dart:io 只支持 HTTP 代理（CONNECT 隧道），不支持 SOCKS；内嵌的
/// Cloudflare 验证页跟随系统代理，不受这里的自定义代理影响。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/settings.dart';

/// 代理模式。
enum NetworkProxyMode {
  /// 直连（默认，与加代理前的行为一致）。
  direct,

  /// 读取 `HTTP_PROXY` / `HTTPS_PROXY` / `ALL_PROXY` / `NO_PROXY` 环境变量。
  environment,

  /// 用户填写的 HTTP 代理（host:port）。
  custom,
}

/// 代理设置的可观察状态 + 持久化。
class NetworkSettings extends ChangeNotifier {
  static const String modeKey = 'network.proxy.mode';
  static const String hostKey = 'network.proxy.host';
  static const String portKey = 'network.proxy.port';
  static const int defaultPort = 7890;

  NetworkProxyMode _proxyMode = NetworkProxyMode.direct;
  String _proxyHost = '';
  int _proxyPort = defaultPort;
  SettingsRepository? _repository;
  Timer? _saveTimer;

  NetworkProxyMode get proxyMode => _proxyMode;
  String get proxyHost => _proxyHost;
  int get proxyPort => _proxyPort;

  /// 从 kv 表加载；后续写入同一仓库。启动期调用一次。
  Future<void> load(SettingsRepository repository) async {
    _repository = repository;
    final modeName = await repository.getOr(modeKey, _proxyMode.name);
    _proxyMode = NetworkProxyMode.values.firstWhere(
      (mode) => mode.name == modeName,
      orElse: () => NetworkProxyMode.direct,
    );
    _proxyHost = await repository.getOr(hostKey, '') ?? '';
    _proxyPort =
        int.tryParse(await repository.getOr(portKey, '') ?? '') ?? defaultPort;
    notifyListeners();
  }

  Future<void> setProxyMode(NetworkProxyMode mode) async {
    if (_proxyMode == mode) return;
    _proxyMode = mode;
    notifyListeners();
    await _repository?.set(modeKey, mode.name);
  }

  /// 更新自定义代理；输入过程中防抖落库，避免每敲一个字都写 DB。
  void setCustomProxy({String? host, int? port}) {
    if (host != null && host != _proxyHost) _proxyHost = host;
    if (port != null && port != _proxyPort) _proxyPort = port;
    notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      final repository = _repository;
      if (repository == null) return;
      unawaited(repository.set(hostKey, _proxyHost));
      unawaited(repository.set(portKey, '$_proxyPort'));
    });
  }

  /// `HttpClient.findProxy` 规则；每次请求实时读取当前设置。
  String findProxy(Uri uri) {
    switch (_proxyMode) {
      case NetworkProxyMode.direct:
        return 'DIRECT';
      case NetworkProxyMode.environment:
        return HttpClient.findProxyFromEnvironment(uri);
      case NetworkProxyMode.custom:
        final host = _proxyHost.trim();
        if (host.isEmpty || _proxyPort <= 0 || _proxyPort > 65535) {
          return 'DIRECT';
        }
        return 'PROXY $host:$_proxyPort';
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}

/// 单例：设置页读写、app_registry 注入抓取客户端用同一份状态。
final NetworkSettings networkSettings = NetworkSettings();
