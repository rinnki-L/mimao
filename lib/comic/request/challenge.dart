/// Cloudflare 挑战通行证的契约层（不依赖 UI / WebView）。
///
/// `ComicWebClient` 检测到挑战后调用 [ComicChallengeSolver]；实现方负责
/// 打开内嵌 WebView 让用户通过验证，并返回要写入 Cookie 库的凭证。
library;

import 'dart:async';

/// 一条要写入 Cookie 库的凭证（与 WebView 的 Cookie 类型解耦）。
class ComicChallengeCookie {
  const ComicChallengeCookie({
    required this.name,
    required this.value,
    this.domain,
    this.path = '/',
    this.expires,
    this.secure = false,
    this.httpOnly = false,
  });

  final String name;
  final String value;
  final String? domain;
  final String path;
  final DateTime? expires;
  final bool secure;
  final bool httpOnly;
}

/// 验证页 WebView 代抓到的响应（可选随 [ComicChallengePass] 返回）。
///
/// 有的站点按 TLS 指纹把 dart:io 抓取器当机器人拦下（403 挑战页），却
/// 直接放行真实浏览器引擎——这种站 WebView 里根本不会出现挑战、也生成
/// 不了凭证 Cookie，重试请求注定还是 403。此时验证页把自己加载成功的
/// 正文带回来，调用方直接采用，源脚本照常解析。
class ComicChallengeFetchedBody {
  const ComicChallengeFetchedBody({
    required this.statusCode,
    required this.url,
    required this.body,
    this.headers = const <String, String>{},
  });

  final int statusCode;

  /// WebView 最终停留的地址（重定向后）。
  final String url;

  /// 渲染后的页面正文（`document.documentElement.outerHTML`）。
  final String body;

  final Map<String, String> headers;
}

/// 一次挑战通过后的结果。
///
/// [userAgent] 必须与通过挑战的浏览器 UA 一致：Cloudflare 的
/// `cf_clearance` 与 UA 绑定，UA 一变凭证立即失效。
class ComicChallengePass {
  const ComicChallengePass({
    this.cookies = const [],
    this.userAgent,
    this.fetchedBody,
  });

  final List<ComicChallengeCookie> cookies;
  final String? userAgent;

  /// WebView 代抓的响应；null = 只拿到凭证，调用方重试请求。
  final ComicChallengeFetchedBody? fetchedBody;
}

/// 挑战类型：决定验证页等哪个 Cookie 出现算通过。
enum ComicChallengeKind {
  /// Cloudflare 托管挑战，凭证是 `cf_clearance`。
  cloudflare,

  /// 站方自建 gatekeeper（如 baozi），凭证名形如 `__Host-gk_clearance_*`。
  gatekeeper,
}

/// 一次待处理的挑战：打开 [url]，等对应类型的凭证。
class ComicChallenge {
  const ComicChallenge({required this.url, required this.kind});

  final Uri url;
  final ComicChallengeKind kind;
}

/// [kind] 对应的通过凭证 Cookie 名判定——验证页等它出现算通过，客户端
/// 重试前也用它判断凭证是否真的到手。
bool isChallengeCredentialCookie(ComicChallengeKind kind, String name) =>
    switch (kind) {
      ComicChallengeKind.cloudflare => name == 'cf_clearance',
      // baozi 等站方 gatekeeper：`__Host-gk_clearance_<hash>`。
      ComicChallengeKind.gatekeeper => name.contains('gk_clearance'),
    };

/// 挑战求解器：打开验证界面，返回通过后的凭证；用户取消/超时返回 null。
abstract interface class ComicChallengeSolver {
  Future<ComicChallengePass?> solve(ComicChallenge challenge);
}

/// 交互式挑战的活动闸门。
///
/// 等待用户在 WebView 里完成验证的时间不应计入源执行的超时，否则用户在
/// 30 秒后点完验证，搜索早就被判超时了。执行池在闸门打开期间不累计超时；
/// 求解器内部仍有 2 分钟的等待上限，不会无限挂住。
abstract final class ComicChallengeGate {
  static int _active = 0;

  static bool get active => _active > 0;

  static void begin() => _active++;

  static void end() {
    if (_active > 0) _active--;
  }
}

/// 每主机挑战的合并与冷却。
///
/// 一次页面加载会并发打出多个会被拦的请求：不给它们各开一个验证页，而
/// 是同主机的挑战共享一次求解（后来者 join 先行者的 Future）。否则用户
/// 关掉一页立刻弹出一页，看起来就是「退出又重新进入验证」的死循环。
///
/// 用户取消（求解返回 null）后该主机进入短冷却：冷却期内的新挑战直接返
/// null，不再弹页——自动重试风暴止于此；冷却过后用户手动重试仍会正常弹页。
class ComicChallengeCoordinator {
  ComicChallengeCoordinator({this.cooldown = const Duration(seconds: 30)});

  /// 取消后同主机不再自动弹页的时长。
  final Duration cooldown;

  final Map<String, Completer<ComicChallengePass?>> _active =
      <String, Completer<ComicChallengePass?>>{};
  final Map<String, DateTime> _cooldownUntil = <String, DateTime>{};

  Future<ComicChallengePass?> join(
    String host,
    Future<ComicChallengePass?> Function() solve,
  ) {
    final key = host.toLowerCase();
    final until = _cooldownUntil[key];
    if (until != null) {
      if (DateTime.now().isBefore(until))
        return Future<ComicChallengePass?>.value();
      _cooldownUntil.remove(key);
    }
    final pending = _active[key];
    if (pending != null) return pending.future;
    return _lead(key, solve);
  }

  Future<ComicChallengePass?> _lead(
    String key,
    Future<ComicChallengePass?> Function() solve,
  ) {
    final completer = Completer<ComicChallengePass?>();
    _active[key] = completer;
    // leader 也走 completer.future：保证它至少有一个监听者，失败时不会
    // 变成未处理的异步错误。
    unawaited(() async {
      try {
        final pass = await solve();
        if (pass == null) {
          // 用户取消/放弃：短冷却，止住自动重试风暴的连环弹页。
          _cooldownUntil[key] = DateTime.now().add(cooldown);
        } else {
          _cooldownUntil.remove(key);
        }
        completer.complete(pass);
      } on Object catch (error, stack) {
        // 求解失败所有 join 者一起失败；视同一次失败进冷却，别连环弹页。
        _cooldownUntil[key] = DateTime.now().add(cooldown);
        completer.completeError(error, stack);
      } finally {
        if (identical(_active[key], completer)) _active.remove(key);
      }
    }());
    return completer.future;
  }
}
