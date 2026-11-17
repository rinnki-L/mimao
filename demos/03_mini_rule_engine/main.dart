// ═══════════════════════════════════════════════════════════════
// Demo 03 — 微缩规则引擎：Kazumi / 阅读 / Venera 的共同本质
//
// 三个上游 app 的架构一模一样，差别只在"规则语言"：
//   Kazumi : XPath 五行        阅读: 书源 JSON+JS     Venera: JS 漫画源
// 但它们遵循同一条流水线：
//
//   规则(纯数据) → 引擎(解释规则的代码) → 网页 → 结构化数据 → 列表页 → 详情页
//
// 本 demo 用"正则迷你选择器"把整条流水线走一遍。纯 Dart、零依赖：
//   dart run main.dart
//
// 看懂它 = 看懂「为什么规则仓库可以直接对接、而引擎必须自己养」：
// 换一个网站 = 换一份规则；引擎一行都不用改。
// ═══════════════════════════════════════════════════════════════

// ─────────────────────────────────────────────
// 假想"番剧站"的两个页面（真实场景里它们来自 dio 的 HTTP 响应）
// ─────────────────────────────────────────────
const listPageHtml = '''
<!doctype html><html><head><title>某番剧站 · 搜索结果</title></head><body>
<div class="result-list">
  <div class="anime-item">
    <a class="cover" href="/anime/1001"><img src="/img/1001.jpg"></a>
    <h3 class="title">葬送的芙莉莲</h3>
    <span class="meta">2024 · 28话</span>
  </div>
  <div class="anime-item">
    <a class="cover" href="/anime/1002"><img src="/img/1002.jpg"></a>
    <h3 class="title">药屋少女的呢喃</h3>
    <span class="meta">2025 · 24话</span>
  </div>
  <div class="anime-item">
    <a class="cover" href="/anime/1003"><img src="/img/1003.jpg"></a>
    <h3 class="title">败犬女主太多了！</h3>
    <span class="meta">2024 · 12话</span>
  </div>
  <div class="anime-item">
    <a class="cover" href="/anime/1004"><img src="/img/1004.jpg"></a>
    <h3 class="title">孤独摇滚！</h3>
    <span class="meta">2022 · 12话</span>
  </div>
</div>
</body></html>''';

const detailPageHtml = '''
<!doctype html><html><head><title>葬送的芙莉莲 · 播放列表</title></head><body>
<h1 class="anime-name">葬送的芙莉莲</h1>
<div class="playlist">
  <a class="episode" href="/play/1001-01">第01话 启程</a>
  <a class="episode" href="/play/1001-02">第02话 相遇</a>
  <a class="episode" href="/play/1001-03">第03话 诀别</a>
  <a class="episode" href="/play/1001-04">第04话 决意</a>
</div>
</body></html>''';

// ─────────────────────────────────────────────
// 规则：和 Kazumi 的番剧规则一样，是「纯数据」——
// 可以直接序列化成 JSON 分发、导入、分享。
// （试着改一改这些正则，看看列表会怎么变。）
// ─────────────────────────────────────────────
const animeSource = <String, Map<String, String>>{
  '列表规则': {
    '容器': r'<div class="anime-item">([\s\S]*?)</div>',
    '标题': r'<h3 class="title">(.*?)</h3>',
    '封面': r'<img src="(.*?)"',
    '链接': r'<a class="cover" href="(.*?)"',
  },
  '详情规则': {
    '剧集标题': r'<a class="episode" href="[^"]*">(.*?)</a>',
    '播放地址': r'<a class="episode" href="(.*?)"',
  },
};

// ─────────────────────────────────────────────
// 引擎：解释规则的代码。
// 真实引擎用 HTML 解析器 + XPath/JSONPath/JS（各有几万行），
// 这里为了 130 行能跑通，用正则做迷你版——行为模式是一样的。
// ─────────────────────────────────────────────
String? firstGroup(String text, String pattern) {
  final m = RegExp(pattern).firstMatch(text);
  return m?.group(1);
}

List<String> captureAll(String text, String pattern) =>
    RegExp(pattern).allMatches(text).map((m) => m.group(1) ?? '').toList();

/// 用「容器 + 字段规则」把一页列表拆成结构化数据
List<Map<String, String>> extractList(String html, Map<String, String> rules) {
  final items = <Map<String, String>>[];
  for (final m in RegExp(rules['容器']!).allMatches(html)) {
    final block = m.group(1)!;
    final item = <String, String>{};
    rules.forEach((name, pattern) {
      if (name != '容器') item[name] = firstGroup(block, pattern) ?? '';
    });
    items.add(item);
  }
  return items;
}

void main() {
  final listRules = animeSource['列表规则']!;
  final detailRules = animeSource['详情规则']!;

  // ① 列表页 → 结构化数据（对应 Kazumi 的"搜索"）
  print('══ ① 用「列表规则」解析搜索结果页 ══');
  final results = extractList(listPageHtml, listRules);
  for (var i = 0; i < results.length; i++) {
    final r = results[i];
    print('  [$i] ${r['标题']}｜${r['封面']}  →  ${r['链接']}');
  }

  // ② 搜索命中 → 详情规则上线（对应 Kazumi 的"详情页规则"）
  const keyword = '芙莉莲';
  final hit = results.where((r) => r['标题']!.contains(keyword)).toList();
  if (hit.isEmpty) {
    print('搜索「$keyword」未命中');
    return;
  }
  print('\n══ ② 搜索「$keyword」→ 命中《${hit.first['标题']}》，进入详情页 ══');

  final titles = captureAll(detailPageHtml, detailRules['剧集标题']!);
  final urls = captureAll(detailPageHtml, detailRules['播放地址']!);
  for (var i = 0; i < titles.length; i++) {
    print('  ${titles[i]}  →  ${urls[i]}');
  }

  print('\n══ 完 ══ 注意：换一个站 = 换一份规则，引擎一行没改。');
  print('这就是「规则仓库可以直接对接，引擎必须自己养」的全部含义。');
}
