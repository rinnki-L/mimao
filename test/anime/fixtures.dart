/// 规则引擎测试的固定输入。
///
/// [demoListPageHtml] / [demoDetailPageHtml] 逐字取自
/// `demos/03_mini_rule_engine/main.dart` 的内嵌 HTML——demo 是"规则=数据、
/// 引擎=解释器"的教学材料，这里把它变成回归测试的 fixture。
///
/// [kazumiMxdmRuleJson] 是 KazumiRules 仓库里的一条真实规则
/// （MXdm.json，2026-11 拉取，api 5），用于验证"现成社区规则能直接吃"。
library;

const demoListPageHtml = '''
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

const demoDetailPageHtml = '''
<!doctype html><html><head><title>葬送的芙莉莲 · 播放列表</title></head><body>
<h1 class="anime-name">葬送的芙莉莲</h1>
<div class="playlist">
  <a class="episode" href="/play/1001-01">第01话 启程</a>
  <a class="episode" href="/play/1001-02">第02话 相遇</a>
  <a class="episode" href="/play/1001-03">第03话 诀别</a>
  <a class="episode" href="/play/1001-04">第04话 决意</a>
</div>
</body></html>''';

/// 与 demo 03 同一套站点的 XPath 版规则（demo 用正则，这里用 XPath）。
const demoRuleJson = r'''{
  "api": "1",
  "type": "anime",
  "name": "demo03",
  "version": "1.0",
  "baseURL": "https://example.com/",
  "searchURL": "https://example.com/search?q=@keyword",
  "searchList": "//div[@class='result-list']/div[@class='anime-item']",
  "searchName": "//h3[@class='title']/text()",
  "searchResult": "//a[@class='cover']/@href",
  "searchCover": "//img/@src",
  "chapterRoads": "//div[@class='playlist']",
  "chapterResult": "//a[@class='episode']"
}''';

/// KazumiRules 真实规则：MXdm（https://github.com/Predidit/KazumiRules）。
const kazumiMxdmRuleJson = r'''{
  "api": "5",
  "type": "anime",
  "name": "MXdm",
  "version": "2.4",
  "muliSources": true,
  "useWebview": true,
  "useNativePlayer": true,
  "usePost": false,
  "useLegacyParser": false,
  "adBlocker": true,
  "userAgent": "",
  "baseURL": "https://www.dcc3.com",
  "searchURL": "https://www.dcc3.com/search/?wd=@keyword",
  "searchList": "//div[contains(@class, 'search')]/ul/li",
  "searchName": "//h3/a",
  "searchResult": "//h3/a",
  "chapterRoads": "//div[@class='playlist']/div[@class='row']/ul",
  "chapterResult": "//li/a"
}''';

/// 与 MXdm 规则选择器匹配的最小搜索页。
const mxdmSearchHtml = '''
<!doctype html><html><body>
<div class="search-page">
  <div class="search-list">
    <ul>
      <li><h3><a href="/detail/201">葬送的芙莉莲</a></h3></li>
      <li><h3><a href="/detail/202">药屋少女的呢喃</a></h3></li>
      <li><h3><a href="/detail/203">孤独摇滚！</a></h3></li>
    </ul>
  </div>
</div>
</body></html>''';

/// 与 MXdm 规则选择器匹配的最小详情页（两条线路，各 2 集）。
const mxdmDetailHtml = '''
<!doctype html><html><body>
<div class="playlist">
  <div class="row">
    <ul>
      <li><a href="/play/201-01">第01话</a></li>
      <li><a href="/play/201-02">第02话</a></li>
    </ul>
  </div>
  <div class="row">
    <ul>
      <li><a href="/play/backup/201-01">第01话（备用）</a></li>
      <li><a href="/play/backup/201-02">第02话（备用）</a></li>
    </ul>
  </div>
</div>
</body></html>''';
