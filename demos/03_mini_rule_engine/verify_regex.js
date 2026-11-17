// 验证脚本：与 main.dart 一字不差的规则和 HTML，用 Node 预演整条解析流水线。
// 为什么存在：本机没装 Dart 也能确认 Demo 03 的逻辑正确
// （Dart 的 RegExp 与 JS 的 RegExp 同源，规则可原样对照）。
// 用法：node verify_regex.js
// 预期：输出与 dart run main.dart 相同的结果，并打印 ✅ 断言通过。

const assert = require('assert');

// ── 与 main.dart 相同的两个页面 ──────────────────────────────
const listPageHtml = `
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
</body></html>`;

const detailPageHtml = `
<!doctype html><html><head><title>葬送的芙莉莲 · 播放列表</title></head><body>
<h1 class="anime-name">葬送的芙莉莲</h1>
<div class="playlist">
  <a class="episode" href="/play/1001-01">第01话 启程</a>
  <a class="episode" href="/play/1001-02">第02话 相遇</a>
  <a class="episode" href="/play/1001-03">第03话 诀别</a>
  <a class="episode" href="/play/1001-04">第04话 决意</a>
</div>
</body></html>`;

// ── 与 main.dart 相同的规则（Dart 里是 r-string，JS 里写 \\s）──
const listRules = {
  '容器': '<div class="anime-item">([\\s\\S]*?)</div>',
  '标题': '<h3 class="title">(.*?)</h3>',
  '封面': '<img src="(.*?)"',
  '链接': '<a class="cover" href="(.*?)"',
};
const detailRules = {
  '剧集标题': '<a class="episode" href="[^"]*">(.*?)</a>',
  '播放地址': '<a class="episode" href="(.*?)"',
};

// ── 与 main.dart 相同的引擎 ──────────────────────────────────
const firstGroup = (text, p) => (new RegExp(p).exec(text) || [])[1] ?? null;
const captureAll = (text, p) =>
  [...text.matchAll(new RegExp(p, 'g'))].map((m) => m[1] ?? '');

function extractList(html, rules) {
  const items = [];
  for (const m of html.matchAll(new RegExp(rules['容器'], 'g'))) {
    const block = m[1];
    const item = {};
    for (const [name, p] of Object.entries(rules)) {
      if (name !== '容器') item[name] = firstGroup(block, p) ?? '';
    }
    items.push(item);
  }
  return items;
}

// ── 流水线（与 main.dart 的 main() 相同）────────────────────
const results = extractList(listPageHtml, listRules);
console.log('══ ① 用「列表规则」解析搜索结果页 ══');
results.forEach((r, i) =>
  console.log(`  [${i}] ${r['标题']}｜${r['封面']}  →  ${r['链接']}`));

const hit = results.filter((r) => r['标题'].includes('芙莉莲'));
assert.strictEqual(hit.length, 1, '搜索应命中 1 条');
console.log(`\n══ ② 搜索「芙莉莲」→ 命中《${hit[0]['标题']}》，进入详情页 ══`);

const titles = captureAll(detailPageHtml, detailRules['剧集标题']);
const urls = captureAll(detailPageHtml, detailRules['播放地址']);
titles.forEach((t, i) => console.log(`  ${t}  →  ${urls[i]}`));

// ── 断言：列表 4 条、字段正确、详情 4 集、地址正确 ───────────
assert.strictEqual(results.length, 4);
assert.strictEqual(results[0]['标题'], '葬送的芙莉莲');
assert.strictEqual(results[0]['链接'], '/anime/1001');
assert.strictEqual(results[2]['标题'], '败犬女主太多了！');
assert.strictEqual(results[3]['封面'], '/img/1004.jpg');
assert.strictEqual(titles.length, 4);
assert.strictEqual(urls[0], '/play/1001-01');
assert.strictEqual(titles[3], '第04话 决意');
console.log('\n✅ 全部断言通过：列表 4 条 / 详情 4 集 / 字段与地址正确');
