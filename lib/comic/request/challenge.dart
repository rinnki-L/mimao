/// Cloudflare 挑战通行证的契约层（不依赖 UI / WebView）。
///
/// `ComicWebClient` 检测到挑战后调用 [ComicChallengeSolver]；实现方负责
/// 打开内嵌 WebView 让用户通过验证，并返回要写入 Cookie 库的凭证。
library;

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

/// 一次挑战通过后的结果。
///
/// [userAgent] 必须与通过挑战的浏览器 UA 一致：Cloudflare 的
/// `cf_clearance` 与 UA 绑定，UA 一变凭证立即失效。
class ComicChallengePass {
  const ComicChallengePass({this.cookies = const [], this.userAgent});

  final List<ComicChallengeCookie> cookies;
  final String? userAgent;
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
