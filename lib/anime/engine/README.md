# 番剧规则引擎（lib/anime/engine + lib/anime/request）

规则是**数据**，引擎是**解释器**。KazumiRules 的 JSON 不归我们维护，我们只负责
导入、存储、按 XPath 把网页解析成结构化条目。网站改版导致规则失效，换一份规则
即可，引擎不用改。

## 1. 数据流

```
规则 JSON ──导入/存储──> AnimeRule ──┐
                                      ├─ AnimeRuleEngine.search()  → 搜索页 HTML → RuleSearchResult[]
网页 URL ──AnimeWebClient(dio+UA/Cookie)┘   AnimeRuleEngine.detail() → 详情页 HTML → RuleEpisode[]
```

输出类型（`result.dart`）是纯 Dart 数据，不依赖 UI/drift/网络，页面可直接消费：

- `RuleSearchResult`：`title`、`url`（页面原始 href）、`coverUrl`、`absoluteUrl`、
  `absoluteCoverUrl`（按规则 `baseURL` 归一化）；
- `RuleEpisode`：`title`、`url`、`absoluteUrl`（播放地址）、`roadIndex`/`roadName`
  （第几条播放线路）；
- `RuleParseResult<T>`：`items` + `diagnostics`。规则坏/页面变/单条缺字段都不抛
  异常，只返回空列表并在 `diagnostics` 说明原因。

## 2. 如何导入规则

```dart
import 'package:mimao/anime/engine/engine.dart';

final importer = RuleImporter();                 // 默认用 AnimeWebClient(dio)
final result = await importer.importFromUrl(
  'https://raw.githubusercontent.com/Predidit/KazumiRules/main/MXdm.json',
  options: const AnimeFetchOptions(
    userAgent: '',                               // 空 = 用内置桌面 Chrome UA
    cookies: {'sid': '...'},                     // 需要登录/过验证时
  ),
);

if (result.isNotEmpty) {
  final store = await RuleStore.openDefault();   // <应用支持目录>/anime_rules/
  await store.saveAll(result.rules);             // 一条规则一个 JSON 文件
}
// result.failures 逐条说明坏规则；网络失败/非 2xx 也返回空结果而不是抛异常。
```

本地 JSON 文本（单个 object 或数组）可直接 `importer.parseJson(text)`；
`RuleStore.loadAll()` 读回全部规则，`delete(name)` 按名删除。

## 3. 如何解析网页

```dart
final rules = await store.loadAll();
final rule = rules.first;
final engine = AnimeRuleEngine();               // 或注入假 client 做测试

// 搜索：@keyword 会被 URL 编码替换；usePost 规则自动改为表单 POST。
final hits = await engine.search(rule, '芙莉莲');
for (final hit in hits.items) {
  print('${hit.title} → ${hit.absoluteUrl}');
}

// 本地命中过滤（真实搜索由站点完成，这一步只用于试跑/聚合过滤）：
final onlyFrieren = filterSearchResults(hits.items, '芙莉莲');

// 详情：相对地址会基于规则 baseURL 补全，再抽剧集。
final episodes = await engine.detail(rule, hits.items.first.absoluteUrl);
for (final episode in episodes.items) {
  print('${episode.roadName} ${episode.title} → ${episode.absoluteUrl}');
}

// 播放：把地址与 UA/Referer 一起交给播放器。
final target = engine.playTarget(rule, episodes.items.first);
```

XPath 语义对齐 Kazumi：

- 只支持 `//` 开头的选择器（KazumiRules 的事实约定）；不支持的规则解析前即
  返回空并给诊断；
- 搜索：`searchList` 选容器 → 容器内 `searchName`/`searchResult` 取标题/链接；
- 详情：`chapterRoads` 选线路 → 线路内 `chapterResult` 取剧集；标题取节点文本，
  地址取节点属性（默认 `href`）；
- 地址归一化与 Kazumi `normalizeEpisodeUrl` 同规则：相对路径补全、同站统一协议、
  去尾斜杠、去空 query；
- 字段名与 Kazumi `Plugin` 序列化一致（`baseURL`/`searchURL`/`muliSources`），
  未识别字段原样保存在 `extras` 并在导出时写回。

引擎扩展（Kazumi 没有、缺省时行为不变）：

- `searchCover`：搜索结果的封面 XPath（demo 03 的列表含封面）；
- `playUrlAttribute`：播放地址所在属性，缺省 `href`。

## 4. 手动验证（需网络）

自动化测试用 `test/anime/fixtures.dart` 里逐字复制的 demo 03 HTML 与 MXdm 真实
规则做离线断言；真实站点会改版，联网验证只作为人工冒烟：

```dart
final importer = RuleImporter();
final rule = (await importer.importFromUrl(
  'https://raw.githubusercontent.com/Predidit/KazumiRules/main/MXdm.json',
)).rules.single;
final hits = await AnimeRuleEngine().search(rule, '芙莉莲');
print(hits.items.map((e) => '${e.title} ${e.absoluteUrl}'));
```

若站点改版，先确认规则 JSON 是否更新；规则失效不是引擎 bug。

页面侧不直接消费这些结构——`lib/anime/data/rule_anime_data_source.dart` 的
`RuleAnimeDataSource` 把它们适配成 `AnimeSummary` / `AnimeDetail`，并说明
`schedule()` 为空等能力边界，详见 [data/README.md](../data/README.md)。

## 5. 测试

```bash
flutter test test/anime
dart analyze --fatal-infos
dart format --output=none --set-exit-if-changed lib/anime/engine lib/anime/request test/anime
```

覆盖：demo 03 列表 4 条字段精确匹配、详情 4 集标题/地址一一对应、搜索命中过滤、
真实 KazumiRules（MXdm）解析、JSON 往返、选择器 `//` 校验、非法规则/畸形 HTML
返回空、导入容错、文件存储往返、UA/Cookie 请求头、导入/搜索/详情编排。