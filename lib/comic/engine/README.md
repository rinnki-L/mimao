# 漫画源引擎（lib/comic/engine + lib/comic/request）

社区维护的 Venera JS 源是**数据**，引擎是**解释器**。60+ 条 `.js` 源脚本不归我们
维护，我们只做导入、存储、执行；网站改版换一份源即可，引擎不用改。

策略：引擎贴近上游语义（API 对齐 Venera `init.js`）、功能借鉴自写、规则数据不维护。

## 1. 数据流

```
源 .js 脚本 ──导入/存储──> ComicSourceScript ──> SourceExecutionPool（每个源一个 QuickJS runtime）
                                                        │
                                                        ▼
                          init.js（内嵌兼容层）── sendMessage ──> ComicJsBridge
                                                                    ├─ Network.*  → ComicWebClient(dio+cookie_jar)
                                                                    ├─ HtmlDocument → HtmlDomBridge(package:html)
                                                                    ├─ Convert/Cookie/log/uuid/random → 自写实现
                                                                    └─ source.search/comic.loadEp → ComicSourceEngine
                                                                                      │
                                                                                      ▼
                                                              models.dart 的纯数据（ComicSummary/Detail/Chapter/ImageRef）
```

输出类型（`models.dart`）不依赖 UI / drift / 网络；上层只 consume 这些类型。

## 2. js_bridge 暴露的 API 清单（对齐 Venera `assets/init.js`）

社区源脚本调用的全局 API 全部走 `sendMessage({method, ...})`，由 `ComicJsBridge.dispatch`
分派：

| JS 全局 API | sendMessage `method` | 我们的实现 |
| --- | --- | --- |
| `Network.get/post/put/patch/delete`、`Network.sendRequest/fetchBytes`、`fetch()` | `http` | `ComicHttpClient.fetch`（dio，带 UA/Referer/byte 响应） |
| `Network.setCookies/getCookies/deleteCookies` | `cookie` | cookie_jar（set/get/delete） |
| `HtmlDocument` / `HtmlElement` / `HtmlNode`（`querySelector(All)` / `text` / `attributes` / `children` / `innerHTML` / `parent` / `classNames` / `id` / `localName` / `previous/nextElementSibling` / `getElementById` / `dispose`） | `html` | `HtmlDomBridge`（`package:html` DOM + 整数句柄） |
| `Convert.encode/decodeUtf8/Gbk/Base64`、`md5/sha1/sha256/sha512`、`hmac/hmacString`、`hexEncode` | `convert` | `dart:convert` + `crypto` |
| `createUuid` | `uuid` | `Random.secure()` 生成 v4 |
| `randomInt` / `randomDouble` | `random` | `Random.secure()` |
| `setTimeout` / `setInterval` | `delay` | `Future.delayed` |
| `console.log/warn/error` | `log` | 落到 `ComicJsBridge.logs` |
| `ComicSource.loadData/loadSetting/saveData/deleteData/isLogged` | `load_data` / `load_setting` / `save_data` / `delete_data` / `isLogged` | 可注入回调（C′ 存储线对接；默认 null/false） |
| `APP.locale` / `getPlatform` / `getLocale` | `getLocale` / `getPlatform` | 固定 `zh_CN` / `windows` |
| `Comic` / `ComicDetails` / `Comment` / `ImageLoadingConfig` 构造器 | —（纯 JS 对象） | `comicInitJs` 内定义 |

**源方法调用**（`source` 是脚本里 `class X extends ComicSource` 的实例）：

| 引擎能力 | JS 表达式 | 返回 |
| --- | --- | --- |
| 搜索 | `source.search.load(keyword, options, page)` | `{comics, maxPage}` |
| 探索 | `source.explore[i].load(page)` | 漫画数组 / `{comics}` |
| 详情 | `source.comic.loadInfo(id)` | `ComicDetails` |
| 章节图片 | `source.comic.loadEp(comicId, epId)` | `{images: string[]}` |

## 3. 用法

```dart
import 'package:mimao/comic/engine/engine.dart';

// 导入：脚本是数据，原样保存，不改一个字符
final importer = ComicSourceImporter();
final result = importer.parseJson(jsonSourceText);   // 或 parseSingle(scriptText)
final store = await ComicSourceStore.openDefault();  // <支持目录>/comic_sources/
await store.saveAll(result.sources);

// 执行：每个源一个隔离的 QuickJS runtime
final pool = SourceExecutionPool();
await pool.register(result.sources.first.key, result.sources.first.script);
final engine = ComicSourceEngine(pool: pool);

final hits = await engine.search(key, '海贼王');
final detail = await engine.detail(key, hits.items.first.id);
final images = await engine.images(key, hits.items.first.id,
    episodeId: detail.items.first.chapters.first.id);

pool.disposeAll();
```

注入自定义网络客户端（离线测试）：`ComicJsBridge(client: fakeClient)` →
`QuickJsHost(bridge: bridge)` → `SourceExecutionPool(hostFactory: () => host)`。

## 4. 测试与原生编译

```bash
flutter test test/comic
dart analyze --fatal-infos lib/comic
dart format --output=none --set-exit-if-changed lib/comic test/comic
flutter build windows --release   # 验证 flutter_qjs native 编译（首次约 80s）
```

源脚本执行单测通过真实 QuickJS 跑：在 `flutter test` 里需把
`flutter_qjs_plugin.dll` 放到工作目录（Windows 本地 `flutter build windows`
后会产生于 `build/windows/x64/runner/Release/`）。无 native 库的环境（如 Linux CI）
用内存 `JsHost` fake + `ComicJsBridge` 纯 Dart 分派测试覆盖 API 对齐性。

## 5. 依赖登记（集成方注意）

本线为可运行/可验证，已在 `pubspec.yaml` 登记：`flutter_qjs`（CyrilPeng fork，
固定 commit）、`cookie_jar`、`html`、`crypto`、`path`。`flutter_qjs` 的 native
编译由本线验证通过；集成方如需统一收口依赖，请把这几项并入共享配置后删除此处。
