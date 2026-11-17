# 规则数据适配器（`lib/anime/data`）

`AnimeDataSource` 是番剧 UI 的唯一数据入口（`anime_data_source.dart`）。本目录
既有面向页面的扁平模型（`anime_models.dart`）、测试用的 `fixture_anime_data_source.dart`，
也有把规则引擎输出适配成这些模型的 `RuleAnimeDataSource`。

## D 页面如何消费规则引擎

### 依赖注入

```dart
import 'package:mimao/anime/data/rule_anime_data_source.dart';
import 'package:mimao/anime/engine/engine.dart';

// 生产：从本地规则仓库读规则；每次 search/detail 都重新读盘，
// 设置页刚导入的规则下一次即生效（刻意不做会过期的缓存）。
final store = await RuleStore.openDefault();
final AnimeDataSource source = RuleAnimeDataSource.fromStore(store);

// 测试 / 自定义：注入引擎与规则加载器，完全离线。
final source = RuleAnimeDataSource(
  engine: AnimeRuleEngine(client: fakeClient),
  loadRules: () async => [rule1, rule2],
);
```

页面只认 `AnimeDataSource`，换成 fixture 实现或规则实现都不用改 widget。

### 行为与能力边界

| 场景 | 行为 |
| --- | --- |
| 空关键词 `search('   ')` | 直接返回空列表，**不发任何请求** |
| 无规则 / 规则目录为空 | 返回空列表 |
| `loadRules()` 抛异常 | 返回空列表，写一条诊断，不向上抛 |
| 单条规则 HTTP 500 / 坏 HTML / 非法 XPath | 只跳过该源，其它源照常返回；诊断记录规则名与原因 |
| 单条结果缺标题或详情地址 | 跳过该条并记诊断；其余条目保留 |
| 规则名找不到（`detail`） | 返回"空详情"：标题/封面/地址仍取条目，剧集为空，写诊断 |
| 详情页解析失败 / 无剧集 | 同上，返回空剧集详情 + 诊断，不抛异常 |
| `schedule()` | **恒返回空列表**，不访问网络。Kazumi 规则没有"周时间表"数据，这是已知能力边界；时间表页会显示空态 |

每次 `search` / `detail` / `schedule` 开始时都会清空诊断，结束时只保留本次的
`lastDiagnostics`（`RuleSourceDiagnostic { ruleName, message }`），调用方据此向用户
解释"为什么没有结果"。多条规则用 `Future.wait` 并发抓取，但结果按规则传入顺序
稳定拼接，不随网络完成先后漂移。

### `id` / `sourceName` 的语义（对齐 core 复合主键）

- `AnimeSummary.id` = 搜索命中的绝对详情地址 `absoluteUrl`（为空回退原始 `url`）；
  同一规则内稳定，并以 id 去重（保留首条）。跨规则**不去重**——不同站点可能返回
  同一个 URL，此时两条都会保留。
- `AnimeSummary.sourceName` = 规则名（trim；空名用「未命名规则」）。即使两条结果
  `id` 相同，只要 `sourceName` 不同，core 的复合主键（source + 外部 id）仍能区分。
- `detail` 依据 `item.sourceName` 找回对应规则：先精确匹配，再大小写不敏感匹配。
  所以规则名既是展示文案，也是跨层定位键，导入规则时不要随意改名。

`detailFromRule` 刻意丢弃 `RuleEpisode.roadIndex/roadName`——D 模型没有线路字段，
不把它们拼进标题；`duration` 恒为 null（Kazumi 规则无时长选择器），`description`
恒为空串（无简介选择器，页面显示「暂无简介」），均不伪造内容。

更多引擎语义（XPath 约定、URL 归一化、导入/存储）见 [engine/README.md](../engine/README.md)。
