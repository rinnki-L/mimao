# 架构设计（architecture.md）

> 状态：规划期设计文档，先于一切代码存在。本文是三方案对抗裁决后的落地版，
> 裁决过程与理由见 [plan-retrospective.md](plan-retrospective.md)，目录形状见
> [directory-layout.md](directory-layout.md)。
> 底子方案：**方案2「少一层是一层」**，嫁接方案1 的上游对照/依赖钉死、方案3 的契约出口/边界哨兵。
> 撰写日期：2026-11-17。文中所有上游数据均标注核实方式与日期，开工当天须重核（上游在动）。

---

## 0. 一图看懂（总体分层）

```
┌────────────────────────────────────────────────────────────────────┐
│                            lib/shell/  壳                          │
│   导航 + 承载 + 桌面窗口。只认识 core/contract.dart 里的一张目录表，   │
│   以及唯一允许 import 四个模块的 app_registry.dart。不含任何业务。     │
└───────┬────────────────────────────────────────────▲───────────────┘
        │ 依赖方向（四条铁律，test/architecture/boundary_test.dart 机器把守）
        ▼                                            │ 唯一白名单
┌────────────────────────────────────────────────────────────────────┐
│                            lib/core/  核                            │
│  统一书架投影表+contract+settings+媒体会话槽。永不 import 壳与模块。 │
└───────▲───────────────────▲───────────────────▲───────────────┬────┘
        │ 各模块只准 import core（写投影、读契约）              │
        │                   │                   │               │
┌───────┴──────┐  ┌─────────┴───────┐  ┌────────┴──────┐  ┌─────┴────────┐
│ lib/anime/   │  │ lib/comic/      │  │ lib/music/    │  │ lib/novel/   │
│ 番剧         │  │ 漫画            │  │ 音乐          │  │ 小说         │
│ M2 移植      │  │ M3 移植         │  │ M4 自写重写   │  │ M5 自写重写  │
│ Kazumi       │  │ Venera-Next     │  │ EchoMusicNext │  │ legado 书源  │
│ lib/ 镜像    │  │ lib/ 镜像       │  │ 网络层 Dart 化│  │ 引擎 Dart 化 │
│ (MobX 原样)  │  │ (无状态库原样)  │  │ (MobX)        │  │ (MobX)       │
└──────────────┘  └─────────────────┘  └───────────────┘  └──────────────┘
     模块之间互不 import；模块内部形状＝各自上游 lib/ 的镜像（见 directory-layout.md）
```

一句话哲学（继承底子方案）：**目录是长出来的器官，不是画出来的对称图。**
壳和核心由我们自己从 demo 01/02/04 长出来；四个模块的内部形状由各自的基因（上游）决定，
我们只负责把它们接进壳、并守住边界。

---

## 1. 壳层（lib/shell/）职责与边界

壳只做四件事（对应 demo 01 `main.dart:37-38` 的既有原则：「壳只负责导航 + 承载，
不含任何业务逻辑」）：

1. **导航**：`home.dart` 用 NavigationRail 提供五项目的地（番剧/漫画/小说/音乐/我的），
   骨架照搬 demo 01 `main.dart:59-92`；内容区从 demo 01 `main.dart:85` 的 switch 表达式
   升级为查表（遍历 `core/contract.dart` 的目录表）。
2. **承载**：`app.dart` = MaterialApp + MD3 主题（种子色沿用 demo 01 `main.dart:29` 的做法）。
3. **桌面窗口**：`window/window.dart` 单文件 + **运行时平台判断**——桌面平台
   （Windows/Linux/macOS）才触碰 window_manager（窗口尺寸/位置，持久化自行实现）与
   tray_manager（托盘），Android 及其他平台为空操作，启动路径不炸。
   为什么不用条件 import：**Dart 条件导入只有 `dart.library.*` 条件，Windows 与 Android
   同样满足 io/ffi，编译期分不开**——独立复审实测推翻了初版"条件导入双文件"的药方
   （窗口行为是运行时属性，不是编译期属性）。Kazumi 同款做法已核实：其 main.dart 用
   `if (isDesktop())` 运行时分支包裹 windowManager 调用，无条件导入。
   window_manager 无 Android 实现（pub.dev 平台徽章实测），运行时误调用会抛
   MissingPluginException——运行时判断正是防这个。
4. **统一书架页**：`library_page.dart`（demo 01 `main.dart:293` LibrarySection 的真身），
   只读 `core/` 投影表（§3 的四条裁决规则），永不 import 任何模块。

壳级状态用 MobX（`shell_store.dart`，demo 02 的 ShellStore 升级版；**MobX 是否接受仍是
开放口味问题，见 §9**）。`app_registry.dart` 是全库**唯一** import 四个模块目录
（`anime/`、`comic/`、`music/`、`novel/`）的地方（第四条铁律，§2）。壳的 M1 文件清单（**7 个，可点数**）：`app.dart`、`home.dart`、
`shell_store.dart`、`library_page.dart`、`settings_page.dart`、`app_registry.dart`、
`window/window.dart`——与 directory-layout.md §1 树逐一对得上。

### 1.1 启动时序（main.dart，M1 一次定型，此后不再动）

实测参照：Kazumi `lib/main.dart`（2026-11-17 raw main）的顺序是
`WidgetsFlutterBinding → 深链 → MediaKit.ensureInitialized → Hive.initFlutter(失败进
StorageErrorPage) → windowManager.ensureInitialized/waitUntilReadyToShow → runApp(ModularApp)`，
且**没有** `AudioService.init`。我们的壳更简单：

```
1. WidgetsFlutterBinding.ensureInitialized()
2. 桌面平台（运行时判断）：windowManager.ensureInitialized() + waitUntilReadyToShow
3. 打开 AppDb（drift；失败进错误页并 return——学 Kazumi 的 StorageErrorPage 兜底）
4. MediaKit.ensureInitialized()
5. 装配目录表（app_registry）→ runApp()
```

注意：**audio_service 的初始化不进这份清单**。Kazumi 实测不在 main.dart 里 init，
其媒体会话接线在 `services/player/audio_controller.dart`（M2 随番剧搬入 `anime/`，
作为全进程唯一 AudioHandler 实现，由 `anime_entry.dart` 暴露给壳、经
`app_registry.dart` 注册——落位方案见 §6.2），
M4 音乐经 `core/media_session.dart` 触达同一通道（§6.2）。M1 就把 audio_service 塞进
启动清单反而违背"先能跑后抽象"，且造成无人使用的空初始化。

---

## 2. 边界铁律与哨兵

四条铁律（写在 `main.dart` 文件头注释与本文档，双处冗余）：

| # | 规则 | 理由 |
|---|------|------|
| 1 | `core/` 永不 import `shell/` 与四个模块目录 | 核心是最低层，向上依赖即成环 |
| 2 | 四个模块目录（`anime/`、`comic/`、`music/`、`novel/`）互不 import | 四个模块互相是"四个 app"，共享只通过 core 投影 |
| 3 | 四个模块目录不 import `shell/`（只准 import `core/`） | 模块写投影/读契约走 core 单门 |
| 4 | `shell/` 中仅 `app_registry.dart` 允许 import 四个模块目录 | 删模块=删目录+删注册表一行，机械可验证 |

**写法约定**：本文与 `boundary_test.dart` 里的「模块目录」一律指 `lib/anime/`、
`lib/comic/`、`lib/music/`、`lib/novel/` 四条路径；**不存在 `lib/modules/` 这一层**。
Kazumi 上游的 `lib/modules/` 是 13 个按域划分的目录（§4.1 命名陷阱），与本项目的
「模块」不是同一个词——哨兵测试必须按四条具体路径写，不能写 `lib/modules/`。

**机器把守**：`test/architecture/boundary_test.dart`（M1 的第一个测试）——扫描
`lib/**/*.dart` 的 import 行，逐一断言上表。实现为普通 Dart 字符串处理即可，
**不依赖 lint**：方案3 曾提议开 `always_use_package_imports` lint 来辅助扫描，
但我们的模块内部是上游镜像（Venera-Next 实测存在相对导入，如
`lib/features/comic_source/comic_source_page.dart` 内的
`import 'source_failure_presentation.dart';`），开这个 lint 会让上游搬来的文件
报警一片——所以哨兵自扫，lint 从宽。

**为什么值这个代价**：方案2 自认"边界全靠约定不靠编译器"是最大弱点；方案3 的
哨兵测试用一个文件把约定变成机器断言，正中"自己能看懂、能整理"——嫁接进来，
成本一次 `dart test`。

---

## 3. 统一书架与数据存储落位

### 3.1 两层存储，权威分明（双记账裁决规则）

锁定决策 5 已定：「模块内部存储保持上游原样」。于是全系统存在两套存储，
**权威归属与一致性规则必须白纸黑字**（这是三份攻击记录共同指向的最大坑，
B2/A1 的崩溃场景：看番到 ep5 关窗杀进程，模块库记 ep5、统一表停 ep4，新手无从排查）：

| 规则 | 内容 |
|------|------|
| **① 权威** | 模块内部存储是唯一权威（Kazumi 的 hive_ce、Venera 的模块内 sqlite、M4/M5 自写库）。统一表 `media_entries` 是**投影**：跨类型索引 + 时间线 |
| **② 写入点** | 投影写入只挂在模块的**持久化点**——即模块把进度/收藏写进自己内部库的同一个函数里，写完内部库紧接着调 `core/library.dart` upsert 一行。**绝不**挂"内存状态变化"回调。这样关窗杀进程时两库最多同时丢"最后一次持久化"，永不分叉 |
| **③ 校正点** | 从统一时间线点进某条目 = 模块"打开动作" = 回写校正：模块打开详情时用内部库权威值覆盖投影。即使投影偶发漏写一次，下次打开自动修正 |
| **④ 展示** | 壳只读公共列（含 `progressText`，模块写好的文案），**永不解析 payload**。payload 是各模块私有 JSON，只有模块自己读 |

### 3.2 统一表 schema（M1 冻结的最小面）

在 demo 04（`demos/04_unified_library/main.dart:27-49`）的基础上落成真表，
并落实其 `main.dart:80-81` 自己预告的"收藏升格成真列"方向 + 攻击 C2 的修法：

```dart
class MediaEntries extends Table {
  TextColumn get id => text()();            // 源内唯一键 "kazumi:1001" / "venera:srcA:12345" / "legado:书源id:书id"
  TextColumn get mediaType => textEnum<MediaType>()();
  TextColumn get sourceName => text()();    // 来自哪个源/规则包
  TextColumn get title => text()();
  TextColumn get coverUrl => text().nullable()();
  TextColumn get payload => text()();       // 各模块私有结构，壳不读（demo 04:52 的约定）
  TextColumn get progressText => text()();  // 【新增】模块写好的展示文案，如"看到第 12 话"/"第1432章 · 32%"
  BoolColumn get starred => withDefault(const Constant(false))();  // 【新增】收藏布尔，可索引可筛选
  DateTimeColumn get lastOpenedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id, mediaType, sourceName};  // demo 04:48 复合主键
}
```

**语法注记**：drift 的列构造器必须**双调用**（`text()` 返回 ColumnBuilder，再补一个
`()` 才是 TextColumn），drift 官方 getting-started 示例即
`integer().autoIncrement()()` / `text().withLength(...)()`（2026-11-17 实测核实）。
上面的块是可直接过 build_runner 的写法。**注意 demo 04 的 `main.dart:31`
（`textEnum<MediaType>();`）同为单调用旧写法**——demo 是"读"的材料，M1 落地时以
本节为准，demo 04 对应行一并修正。同文件还有两处同类偏差，一并记在此处免得照抄：
`main.dart:72` 的查询示例写 `.equals(MediaType.anime.name)`，`textEnum` 列应按
枚举值比较（`.equals(MediaType.anime)`），与 `.name` 字符串比较是值类型错配；
`main.dart:85` 预告表会落到 `lib/core/database/`，本项目的落位已定为 `core/db.dart`
（§1 的 shell/core 平铺纪律），以本文为准。

- **为什么这两列现在就加**：demo 01 `main.dart:124-131` 的时间线文案
  （"看到第12话""第1432章 · 32%"）就是模块解释好的字符串；没有 progressText，
  壳就得按 mediaType switch 去解析每家 payload——每接一个新模块壳改一次，
  违背"壳只认目录表"。starred 同理（否则收藏筛选退化为 payload 字符串匹配）。
- **M1 只建这一张表 + settings kv 表**。`download_tasks` 不在 M1 建（见 3.3）。
- M2 番剧是**第一个真实消费者**：先让番剧按规则①-④接上、验证投影不丢数据，
  再把同样的三行胶水复制给 comic/music/novel（"先能跑后抽象"的落地顺序）。
- M1 的统一书架页显示空态（"番剧模块接入后这里开始有内容"），M1 的可验收物是
  壳可导航 + 库读写单测绿 + 哨兵测试绿——不假装有数据。

### 3.3 下载、设置、文件落盘

- **统一下载**：锁定决策 5 要求统一收藏/历史/下载核心。但实测两个上游都自带下载
  子系统（Kazumi 有 `services/download` + `repositories/download_repository.dart`；
  Venera-Next 的下载一体化进 `features/comic_storage`/`local_comics`，lib/features 下
  实测没有独立 download 目录）。因此 M1 **不建**统一下载表：M2 番剧下载移植时
  再定 `core/download.dart` 的形状——参照双记账规则，它要么成为下载状态的投影表
  （同规则①-④），要么若发现纯多余则带着理由砍掉。推迟≠放弃，形状由第一个消费者定。
- **应用设置**：`core/settings.dart`，同一 AppDb 里一张 kv 表，不加新依赖。
  各模块自己的设置仍走各自上游惯例（Kazumi 走 hive、Venera 走 foundation 的偏好存储）。
- **磁盘路径**：统一库与壳数据放 `%APPDATA%` 应用支持目录（path_provider）；
  模块内部存储各按上游惯例落位。Windows 中文/长路径的注意事项集中记在
  `docs/upstream-map.md` 的"Windows 备忘"节（M2 建立）。

### 3.4 存储/网络栈归属（排障地图，防"改错层"）

双栈并存是镜像上游的必然代价（攻击 A5 成立），排障归属表进 `docs/upstream-map.md`，
此处立骨架：

| 问题类别 | 番剧/壳侧 | 漫画侧 | 音乐/小说侧 |
|---------|-----------|--------|-------------|
| 网络 | `anime/request/`（dio） | `comic/network/`（dio + rhttp + cookie_jar，M3） | `music/client/`（自写） |
| 本地存储 | `anime/` 内 hive_ce | `comic/` 内模块 sqlite（上游原样） | core 投影 + 自写库 |
| Cookie/登录态 | `anime/webview/` | `comic/network/` 自管（跨模块共享登录态需显式搬运，不自动互通） | `music/client/` |
| 弹窗 webview | 模块自供：webview 登录场景在模块自身页面/设置页内完成，用模块自己的 webview 栈；**壳不借用模块 webview**（机制见下） | 同左（`comic/network/` 侧 webview 栈，M3） | 音乐登录走 `music/client/` 签名 API，目前无 webview 场景 |

**"壳不借用模块 webview"的例外通道（唯一，备而不用）**：模块互不 import（铁律②）、
`shell/` 仅 `app_registry.dart` 允许 import 模块（铁律④），所以壳若某天确需借用模块
webview，唯一合法走法 = 在 `app_registry.dart` 白名单内特批一行（import 模块的
webview 出口），并在 `boundary_test.dart` 的白名单处加行内注释登记"哪一行、为什么、
删哪个模块时要一起删"——一例一登记，upstream-map.md 同步记账。当前没有任何已登记
的例外（M2 落地时若发现真场景再走此通道）。**注意：AudioHandler 不属于本通道**——
它由 `anime_entry.dart` 暴露给壳，走的是"模块唯一对外面"，不是白名单特批（§6.2）。

典型迷路场景（攻击原文）：漫画源请求超时，去改 `anime/request/` 的 dio 工厂——没用，
漫画走 `comic/network/`。归属表就是防这个的。

---

## 4. 四个引擎的接入方式

模块内部**不自创布局**，一律镜像上游原始相对路径（攻击 B1/C1 的共同修法）：
上游的修复 patch 才能按固定前缀映射机械重放（§7），上游的 issue/文档/commit
里的路径与我们树里的路径直接对得上。完整目录树见 directory-layout.md，
逐目录"←上游哪仓库哪路径"的对照表在 `docs/upstream-map.md`（M2 建立，活文档）。

### 4.1 番剧（M2）← Kazumi 移植

- 搬 `Kazumi/lib/` 的**番剧本体**进 `lib/anime/`：**10 个子树**（2026-11-17 GitHub
  contents API 实测 lib/ 顶层 10 目录）——pages（160+ 文件）、services、modules、
  **repositories**（collect/download/history/danmaku_shield/search_history/collect_crud
  六个 repository，本文 §3.3 引用的 download_repository.dart 就住这里）、bean、request、
  utils、webview、plugins、bbcode 各成子树，包内 import 改写为我们的包前缀。
- **根文件 6 个的处置**（upstream-map.md 首节剥离清单）：`main.dart / app_module.dart /
  app_widget.dart / core_module.dart / navigation.dart` 属于 Kazumi 的壳——壳职责归
  我们的 `lib/shell/`，不搬；`hive_registrar.g.dart` 是 hive_ce 生成文件**不属壳、随搬**：
  实测其注册调用链在 `services/storage/storage.dart` 的 `GStorage.init()`
  （第 150 行 `Hive.registerAdapters()`），随搬后闭环，不调用它则番剧 hive 读写
  运行时崩且报错离原因很远——M2 验收时专测一次。
- **assets 映射**（开工当天逐项核对 lib/ 引用）：Kazumi pubspec 声明
  `assets/images/`、`assets/images/logo/`、`assets/shaders/`（播放器着色器）、
  `assets/statements/`、`licenses/ech_http/` 五处，全部按**原相对路径**并入我们
  `assets/`（代码里是硬编码路径，改路径即 AssetNotFound 且编译不报错）。
- `services/platform/` 不搬：窗口/托盘职责由 `shell/window/`（window_manager +
  tray_manager）**全新实现取代，非移植**；个别工具函数若确有复用价值，由
  upstream-map.md 记单点引用，不整目录搬。
- `lib/modules/` 里 `collect` 域的 Bangumi 账号同步管线（collect_sync_merger/
  collect_sync_plan，实测存在）默认**不搬**（拍板项 7）。
- 命名陷阱（实测提醒）：Kazumi 的 `lib/modules/` 是 13 个**按域划分的 store+模型**目录
  （bangumi/character/characters/collect/comments/danmaku/download/history/my/plugin/
  roads/search/staff，2026-11-17 GitHub contents API 实测），不是"四个子应用"——
  我们树里的 `lib/modules/` 这个词不存在（模块目录直接叫 `lib/anime/` 等），避免同词歧义。
- 状态管理：MobX 原样（锁定决策 4）。
- 规则引擎：xpath_selector / json_path / antlr4 纯 Dart 包，随移植原样进
  `anime/` 对应子树；上游修复走 §7 工序。

### 4.2 漫画（M3）← Venera-Next 移植

- 搬 `Venera-Next/lib/` 的 **5 个业务子树**进 `lib/comic/`：features、foundation、
  components、network、routing（实测 lib/ 顶层共 8 条目，main.dart 不搬）。
- **剥离清单**（与 Kazumi 对齐，进 upstream-map.md）：`app_runtime/`（31 文件的启动
  装配域：bootstrap/init/headless 无头模式/data_sync 同步接线/窗口摆放）与
  `app_shell/`（app_shell/home_page/main_page/auth_page/startup_failure）均**不搬**——
  2026-11-17 全库实测两者的 import 引用面都只有 `main.dart` 一处，整域剥离不伤
  features/foundation/network/routing 任何一个文件。其中 bootstrap 装配序列由
  `comic_entry.dart` 重接（upstream-map.md 记映射偏移）；data_sync/webdav/无头更新等
  同步体系按拍板项 7（上游同步体系默认不接）处置，业务体（features/sync、
  features/webdav_library、network/webdav.dart）随搬但默认无人启动。
- **搬运四件套**（攻击 A2 的实证修正，缺一跑不通）：①`lib/` 业务整树（上面 5 子树）；
  ②Venera 的 `assets/` **逐文件**并入我们 `assets/`，**路径原样保持**（代码硬编码，
  2026-11-17 实测：`init.js`（JS 引擎宿主引导脚本，`foundation/js_engine.dart:450` 与
  `image_processing.dart:329` rootBundle 加载）、`translation.json`（文案 API 全靠它）、
  `opencc.txt`（简繁词典）三者必需；`tags.json`/`tags_tw.json`（源标签翻译）、
  `app_icon.png`（窗口/托盘图标）随功能；Venera pubspec assets 段里的
  pubspec.yaml/CHANGELOG.md 是其打包特例，不并入）；③Venera `packages/` 的 **8 个本地
  path 包全部随搬**（实测 pubspec path 依赖 7 个 + dependency_overrides 1 个，lib/ 内
  被引用 20 处，缺一编译不过）：`rhttp`（Rust+Dart，工具链=拍板项 5）、
  `desktop_webview_window`、`flutter_inappwebview_windows`、`photo_view`（阅读器图片
  查看）、`share_plus`、`venera_native`、`venera_saf`（Android 平台通道）、
  `webdav_client`（同步体系用，默认不接）；④平台插件注册（windows/ runner 的插件
  注册行为）。
- import 改写：`package:venera_next/` → 我们包前缀，一把 sed；**Venera 存在相对导入**，
  相对导入搬树不用改，但此后每次应用上游 patch 都要重跑 sed + grep 兜底（§7 固定工序）。
- flutter_qjs 用 CyrilPeng fork 并锁 ref（实测 `ref: f5a1f20d08c33b0a6b3e38eda2a7b27705420620`）。
- 模块内无状态管理库，原样不强加 MobX；模块内 sqlite（comic_storage/local_comics）原样。

### 4.3 音乐（M4）← EchoMusicNext 网络层 Dart 重写

- 实测 `EchoMusicNext/crates/echo-api/src/` 顶层为 `domain.rs / domain/ / error.rs /
  lib.rs / module/ / util/`（GitHub contents API，2026-11-17）。Dart 侧一一对应：
  `music/models/` ← domain，`music/api/` ← module（一端点一文件），`music/client/` ←
  util（request + 签名/加密，**对照 Rust 逐函数翻译，Rust 只读**）。
- 这不是规则引擎，没有源管理页；酷狗概念版登录态 API 客户端 + 播放器 +
  歌单/搜索/播放页。
- 播放接 media_kit（与番剧同一内核包）+ audio_service；媒体会话规则见 §6.2。
- 状态管理 MobX（自写部分跟壳一致）。

### 4.4 小说（M5）← legado 书源引擎 Dart 重写

- **默认路线：Dart 重写**。锁定决策 4 原文给了"或让 TS 引擎跑在 flutter_qjs 里"的备选，
  但三方攻击一致实证该备选被依赖链证死：any-reader 的 TS 引擎依赖 isolated-vm（Node
  原生 addon）、cheerio、@xmldom/xmldom、axios、iconv-lite 等 Node 侧设施，跑进
  QuickJS 等于重造五件套 + 一条 npm/esbuild 构建链——工作量不小于 Dart 重写本身，
  且引入需要维护的 JS 构建产物，违背"只学 Dart"。**TS 直跑从"备选"降级为
  "需你明示拍板才考虑的额外工作量"（拍板项 6 附带）**。
- `lib/novel/` M1 只有一个占位出口（甚至目录都不建，见 directory-layout.md 的
  开工当天清单）；M5 才生长：engine（搜索→发现→目录→正文流水线）、analyzer
  （**主对照=拍板项 6 选定的 Kotlin fork**；any-reader `packages/legado/` 为规则语义
  **旁证**——2026-11-17 实测该包是半成品：`src/analyzer/` 21 个文件里 `AnalyzerHtml.ts`
  为 0 字节空文件，拿它逐文件对照会踩空；连带面已定位：手写 DOM 层实体在
  `src/javascript/jsoup/`（Element/Elements/Jsoup.ts），与 RuleManager 一起对应。
  M5 开工当天重核其完成度）、cache、js。
- **lib/novel/js/ 的语义在此冻结**：flutter_qjs 宿主只用于**执行书源 JSON 里内嵌的
  JS 片段**（legado 书源规则中的 js 规则），与 Kazumi 的 plugins 同理；**不是**
  "跑整个 TS 引擎"。
- legado 官方仓库（gedoor/legado）**实测已清空**（2026-11-17 raw main README 仅剩
  侵权风险公告）。规则语义的第一手 Kotlin 原版缺失，M5 开工前需选定一个社区 fork
  存档作 Kotlin 对照（拍板项 6）。

---

## 5. 状态管理总表

| 层 | 方式 | 来源 |
|----|------|------|
| 壳（shell/） | MobX store（demo 02 手感） | 自写 |
| core/ | 不设状态管理（纯数据 API）；需要响应处由壳 store 桥接 | 自写 |
| anime/ | MobX 原样（Kazumi 同款） | 上游 |
| comic/ | 无状态管理库，上游原样 | 上游 |
| music/、novel/ | MobX | 自写 |

三条口味/概念相关项全部挂"临时决定，等你拍板"（§9）：MobX 是否最终接受、
drift vs raw sqlite3、flutter_modular 是否引入。**已知代价明码标价**：
MobX 与 comic 的"无状态管理库"并存是真实的双体系理解成本（两家上游本来就是如此，
镜像策略不掩盖它）。

---

## 6. Windows 桌面特有事项（第一优先平台）

### 6.1 窗口 / 托盘 / 单实例

- window_manager（无边框窗口；尺寸/位置提供读写 API，**记忆=自行持久化**）+
  tray_manager（托盘），代码住 `shell/window/window.dart`。Kazumi 的实参可对照：
  `main.dart` 里 `isLowResolution()` 决定 840×600 或 1280×860、`WindowOptions` 配
  TitleBarStyle——M1 直接抄这套参数。
- **单实例不是 window_manager 的功能**（2026-11-17 pub.dev README 实测：唯一提及是
  一篇教你自实现的博客链接）：要做的话走 runner 层互斥体或第三方包，**M1 拍板做不做**，
  不默认承诺。
- Android（第二优先）：`window.dart` 运行时判断落到空操作分支，启动路径不炸（§1 第 3 条）。

### 6.2 媒体键 / 系统媒体会话（SMTC）

- **官方 audio_service（0.18.x）不支持 Windows**（pub.dev 平台徽章实测仅
  Android/iOS/macOS/web）。现成答案不是未知数，是上游已经踩平的路：Kazumi pubspec
  实测组合 `audio_service ^0.18.15` + `audio_service_mpris`（Predidit fork，ref
  `d30b53f...`）+ `audio_service_win`（Predidit fork，ref `8ad650c...`）。
  三个依赖原样进我们 pubspec（git + ref 钉死，见 §8）。**audio_service_mpris 的去留
  规则**：mpris 是 Linux MPRIS 集成，本项目平台面只有 Windows/Android——M2 搬
  audio_controller 接线时 grep 它是否被 import，被引用才保留并在 upstream-map.md 登记
  理由，否则不进 pubspec。
- **唯一所有者规则（落位 M1 哨兵写好前定死，M2 落地）**：audio_service 全进程只有
  一个 AudioHandler。落位方案（满足全部四条铁律）：
  - `core/media_session.dart`【M2 建立，M1 不建——无消费者不建空架子】：最小接口 +
    可空注册槽（core 只认纯数据，不 import 任何模块，铁律①不破）；
  - 唯一 handler 实现 = Kazumi 的 `audio_controller.dart` 原样住进
    `anime/services/player/`（上游 patch 可机械重放）；`anime_entry.dart` 以 getter
    暴露该 handler（entry 是模块唯一对外面，壳只认 entry，不新增白名单例外）；
    M2 时壳经 `app_registry.dart`（铁律④白名单内）从 entry 拿到它并
    `AudioService.init` 注册；
  - M4 音乐模块 import `core/media_session.dart` 经槽触达同一 handler（铁律②③
    均不破——音乐不 import anime，也不 import shell）；
  - 番剧与音乐的切换逻辑住 handler 所在的单点，**不建"聚合器"抽象**——十几行的
    协调代码，先能跑后抽象。M4 开工前把切换细节补进本文档（拍板项 8）。

### 6.3 文件读写

- 直接读写磁盘（番剧缓存/漫画下载/小说正文缓存/音乐下载）：path_provider 定根，
  统一库在 `%APPDATA%` 应用支持目录；各模块下载落盘沿用各自上游的目录约定。
  Windows 长路径/中文路径备忘集中在 `docs/upstream-map.md` "Windows 备忘"节。

---

## 7. 上游跟进工序（cherry-pick 的现实形态）

锁定决策 6："fork 上游并 cherry-pick 引擎修复"。**必须明示一个现实**（攻击 B5/A4，
诚实优先）：

- 字面意义的 `git cherry-pick <sha>` 只在"仓库起点=上游 fork"（方案1 布局）时成立；
  我们选了方案2 布局，模块树与上游路径存在固定前缀差（如 `lib/` → `lib/anime/`），
  `git cherry-pick` 会报"文件不存在"或空提交——**这不是事故，是布局选择的结果**。
- 我们的工序 = **fork 上游到自己 GitHub 账号下（加 remote，不进本仓库、不用
  submodule）→ `git log -p`/`format-patch` 读上游修复 → `git apply`（带
  `-p` 参数或 `--directory=` 前缀映射）或手工重放**。因为模块内部镜像上游原始路径，
  前缀映射是**固定的一条规则**（不是逐文件账本），机械可执行。
- 固定工序每次必做（写进 upstream-map.md 当 checklist）：
  1. 应用 patch 后跑前缀 sed（comic：`package:venera_next/` → 我们前缀）；
  2. `grep -rn "package:venera_next\|package:kazumi" lib/` 兜底清零；
  3. 上游 patch 涉及我们未移植的文件（如剥离清单里的 Kazumi collect sync 管线、
     Venera 的 app_runtime/app_shell）→ 跳过该 patch 并在 upstream-map.md 记录；
  4. 冲突口诀与"接受上游对已剥离路径的 patch 用 --skip"判定进 upstream-map.md。
- 此执行形式是对锁定决策 6 的**执行细节落地**（意图不变：上游修复可跟进），
  是否接受该形式=拍板项 4；若你更看重字面 cherry-pick 而愿意接受"接手 409 文件
  主干"的代价（方案1 布局），那是推翻本设计底子的重大改向，请明示。

---

## 8. 依赖落位（开工当天的 pubspec 蓝图）

**一句话盖不住**（攻击 B4 成立）：上游依赖真身是一篮子 fork/path 包，dependency_overrides
只解决版本冲突，解决不了"包不在 pub.dev 上"。逐项落位（2026-11-17 实测）：

| 依赖 | 供应方式 | 引入 | 核实 |
|------|---------|------|------|
| Flutter / Dart 基线 | `flutter 3.50.0` / `sdk >=3.10.0 <4.0.0`（与锁定决策 5 一致） | M1 | Kazumi main pubspec 实测 |
| window_manager ^0.5.1 | pub | **M1** | Kazumi pubspec 实测（§6.1） |
| tray_manager ^0.5.0 | pub | **M1** | Kazumi pubspec 实测（§6.1） |
| path_provider ^2.1.5 | pub | **M1** | Kazumi pubspec 实测（§3.3 磁盘路径定根） |
| mobx / flutter_mobx / mobx_codegen | pub | M1 | 壳级状态 |
| flutter_modular ^7.1.0 | pub | M2·拍板项 3（M1 不引入） | Kazumi pubspec 实测（路由主干） |
| drift + drift_flutter（dev: drift_dev, build_runner） | pub | M1 | **临时决定**（拍板项 1，M1 开工前） |
| media_kit / media_kit_video | git `Predidit/media-kit` ref `cd75bcf...`（path 指向 fork 内子目录） | M2 | Kazumi pubspec 实测 |
| audio_service ^0.18.15 | pub | M2 | Kazumi 同款 |
| audio_service_win / audio_service_mpris | git Predidit 两 fork，ref 钉死（mpris 去留见 §6.2） | M2 | Kazumi pubspec 实测 |
| hive_ce ^2.16.0 + hive_ce_flutter ^2.3.3 | pub | M2 | Kazumi pubspec 实测（hive_ce_flutter 是 `Hive.initFlutter` 所在包） |
| webview_windows / desktop_webview_window | git Predidit 两 fork，ref `2b3306d2...` / `2b25bd7d...` | M2 | Kazumi pubspec 实测（anime/webview 必带） |
| dio | pub ^5.x（Kazumi ^5.11.0 / Venera ^5.11.1） | M2/M3 | 按上游版本，冲突时 dependency_overrides |
| flutter_qjs | git `CyrilPeng/flutter_qjs` ref `f5a1f20...` | M3 | Venera pubspec 实测 |
| flutter_inappwebview 家族 | git `pichillilorenzo/flutter_inappwebview` ref `0aaf7a0...`（Venera 钉死）+ `flutter_inappwebview_windows`（Venera packages/ 本地包随搬） | M3 | Venera pubspec/overrides 实测 |
| sqlite3 ^2.9.4 + sqlite3_flutter_libs ^0.5.42 | pub | M3 | Venera pubspec 实测（comic 模块内存储原样） |
| url_launcher ^6.3.3 | pub | M3 | Venera pubspec 实测（comic_source_page 实测直接 import） |
| rhttp | `path: packages/rhttp` vendor（需 Rust 工具链）或另议 | M3 | **拍板项 5** |

原则：**依赖必须本地改时才建 `packages/`，否则一律 git url+ref 钉死**；
每个 fork 的"固定 commit + 引入理由 + 退出条件"登记进 `docs/upstream-map.md`
（对照 Venera-Next 的 dependency_audit 模式）。

---

## 9. 开放问题清单（全部"临时决定，等你拍板"，不许默默定死）

| # | 问题 | 当前临时决定 | 拍板期限 |
|---|------|-------------|---------|
| 1 | **drift vs raw sqlite3**（统一库） | drift（demo 04 即 drift 风格；查询编译期检查；代价与 comic 的 raw sqlite3 两栈并存，可接受） | M1 开工前 |
| 2 | **MobX 是否接受**（壳/自写模块） | 接受（demo 02 方向；Kazumi 同款） | M1 开工前 |
| 3 | **flutter_modular 是否引入** | **M1 不引入**：M1 壳只有 5 个静态目的地、没有嵌套路由消费者，引入即违背「无消费者不建」；M1 用纯 Navigator，壳的 7 个文件不依赖它。M2 搬 Kazumi 路由前再拍：实测 Kazumi main.dart 以 ModularApp 为路由主干；若引入，收益=在 shell 侧**重组** Kazumi 路由表（其 app_module.dart 已划入剥离清单不搬，§4.1）时结构对得上、嵌套挂载 diff 最小；全页面改写 Navigator 会让上游 patch 全废。注：实测 Kazumi 页面几乎不用 `Modular.get`（DI 论据不成立），引入理由是**路由**不是 DI。降级方案=纯 Navigator | M2 开工前 |
| 4 | **cherry-pick 执行形式**：接受 §7 的"fork+前缀映射 patch 重放"吗？ | 是（意图不变） | M2 开工前 |
| 5 | **rhttp 与 Rust 工具链**：实测 rhttp（pub 0.18.0）README 要求本机 Rust 1.80+（rustup），无预编译二进制；vendor Venera 的 packages/rhttp 同样要 cargo。装 rustup ≠ 学 Rust（锁定决策 3 是"不学"，不是"不装"），但必须你明示接受；备选=改用 dio 重写漫画网络层（代价：改 19 个文件、切断上游修复通道，不推荐） | 默认装 rustup | M3 开工前 |
| 6 | **legado 参照 fork 选定**（官方仓库已清空，实测仅剩侵权公告） | M5 前选定并登记进 upstream-map.md | M5 开工前 |
| 7 | **上游同步/账号体系默认不接**：Kazumi collect 域 Bangumi sync 管线（M2）、Venera 的 data_sync/WebDAV/无头更新体系（M3，业务体随搬但 app_runtime 剥离后默认无人启动） | 默认不搬不接，后续按需补 | M2 开工前 |
| 8 | **番剧/音乐唯一 AudioHandler**：落位已定死（§6.2：core 接口+注册槽，handler 实现=Kazumi audio_controller 经 app_registry 注册） | M4 开工前只拍板**切换细节**（音乐抢占时番剧如何暂停、元数据归谁写） | M4 开工前 |
| 9 | **仓库名 / pubspec name**（决定 import 前缀映射的 sed 目标串，改一次全库抖动） | 占位 `aggregator`，定名后不再改 | M1 开工前 |

另有两项"已知成本"记录在案（非问题，勿忘）：①双状态体系（MobX vs comic 无库）；
②双基础设施（网络×2、存储×2、webview×2）——归属表 §3.4 + upstream-map.md 承接。

---

## 10. 里程碑与验收

| 里程碑 | 内容 | 目录增量（详见 directory-layout.md） | 验收物 |
|--------|------|--------------------------------------|--------|
| M1 | MD3 壳 + 统一书架 | shell/ + core/ + main.dart；test/architecture + test/core；LICENSE/NOTICE/.gitignore | 五目的地可导航；库读写单测绿；哨兵测试绿；时间线空态页；**CI 五 job 全绿** |
| M2 | 番剧 | lib/anime/（Kazumi 镜像）；upstream-map.md 建立；download 形状拍板；core/media_session.dart | 规则引擎搜索→详情→播放→弹幕全通；投影写入按规则①-④验证；**CI 全绿** |
| M3 | 漫画 | lib/comic/（Venera 镜像）+ assets 逐文件并入 + packages/（8 个 vendor 本地包，rhttp 依赖拍板项 5） | JS 漫画源加载/阅读器/本地下载通；投影接上；**CI 全绿**（构建 job 的 Rust/NDK 前置见 §11.4） |
| M4 | 音乐 | lib/music/ | 酷狗登录态 API 通；后台播放+SMTC 通；投影接上；**CI 全绿** |
| M5 | 小说 | lib/novel/ | 书源引擎（Dart 重写）搜索→目录→正文通；投影接上；**CI 全绿** |

里程碑顺序与锁定决策 7 一致；每一步结束系统都完整可用（工程原则 6：
永不进入"重构到一半不可用"）。

**CI 是完成定义的一部分**：里程碑验收以 `.github/workflows/ci.yml` 五个 job 全绿为准，
不允许用分支保护 bypass 合并。CI 落地早于本架构，两者的接缝规则见 §11——不按 §11
处理，M2 搬入第一个上游子树时 CI 必红。

---

## 11. CI 接缝：严格门禁与"上游镜像"如何共存

CI 在架构定稿前就已交付（`.github/workflows/ci.yml`），它按"整个仓库都是我们写的代码"
设定门禁；本架构的 M2/M3 却要求模块内部**整树镜像上游**。两个目标默认会互相拆台，
所以把边界写死。

### 11.1 分域门禁（自写代码严，上游镜像代码只守编译）

| 范围 | `dart format` | `dart analyze` | `dart fix` |
|------|---------------|----------------|------------|
| 自写：`lib/main.dart`、`lib/shell/`、`lib/core/`、`test/`、模块入口/挂载点 `*_entry.dart`、`*_module.dart`、M4/M5 自写模块 | 必须零漂移 | `--fatal-infos`（warning 默认即失败） | 零可修复项 |
| 镜像：`lib/anime/`、`lib/comic/`（从 Kazumi / Venera 整树搬入的部分） | **不覆盖** | `--no-fatal-warnings`（只有 error 失败） | **不覆盖** |
| `demos/`（选型材料，不是产品代码） | **不覆盖** | **不覆盖** | **不覆盖** |

补充三点：`dart fix` 只接受目录参数，所以 `lib/main.dart` 与 `*_entry.dart`/`*_module.dart`
由 format/analyze 两扇门覆盖，不进 fix 门；`demos/` 必须显式排除——demo 04 是 drift
设计稿（含已知的示例偏差），当产品代码分析会让 CI 无意义地红；生成物
（`*.g.dart`、`*.drift.dart`、`*.freezed.dart` 等）不进 format 门——它们由 build_runner
产出，格式化它们会与 §11.2 的"重建后 diff 必须干净"直接冲突。

理由：对镜像文件跑 format/批量 fix 会改写上游文件内容，让 §7 的"固定前缀映射 patch
重放"从机械操作退化成逐文件人工合并——CI 的严格性不能以毁掉上游跟进通道为代价。
模块代码仍然过编译（构建 job）、过单测、过边界哨兵；只是不再要求它符合我们的格式与
lint 口味。

**代价（明码标价）**：镜像目录里我们手写的胶水文件（如 `anime_entry.dart`）也不进
format/fix 门，靠提交前自查；它们仍被 `dart analyze --no-fatal-warnings` 覆盖 error。
**备选（当前不采纳）**：M2/M3 开工当天对整树 `dart format` + `dart fix --apply`，
接受 patch 重放退化为 `git apply --3way` 模糊应用。若 M2 实测上游树本身已是
format/fix 干净，可改判回此方案并在 upstream-map.md 记账。

### 11.2 生成物必须入库

本仓库策略与 CI 漂移门一致（`ci.yml` 第五扇门）：`build_runner` 产物
（`*.g.dart`、`*.drift.dart` 等）**提交入库**，`.gitignore` 不得忽略。drift（拍板项 1）
从 M1 起产出 `core/db.g.dart`，M1 的提交必须包含它；M3 若上游自带生成物，同样随搬
入库。CI 在重建后查三件事：被忽略的生成物、已跟踪文件 diff、未跟踪新文件。
`pubspec.lock` 同样入库（lockfile 门的前提）。

**与拍板项 1 的联动**：漂移门假设 `dev_dependencies` 里有 `build_runner`。若你改判
raw sqlite3 **并且** MobX 也未引入（项目没有任何 codegen），`dart run build_runner`
会因包不存在而红——拍板时必须同步把漂移门改成"检测到 build_runner 才执行"，这是
选型的一个隐藏成本。当前临时决定（drift + MobX）下不需要改。

### 11.3 每个里程碑的 CI 验收

M1 落地当天必须让 CI 从"无 pubspec 的过渡态红"转为**五 job 全绿**；此后每个里程碑
的 PR 以全绿为完成条件。CI 的覆盖率口径（只统计被测试 import 的文件）不变，
`MIN_COVERAGE=60` 不变。

### 11.4 M3 的 Rust / NDK 前置（已知未接，写死在验收里）

`rhttp` 需要 Rust 1.80+（rustup），Android 构建还需要 NDK 与 `cargo-ndk`；当前
`ci.yml` 的 `build-windows` / `build-android` 没有这些步骤。**M3 开工当天必须补齐**，
不许让构建门红着进 M3：

1. `build-windows`：确认 runner 的 `cargo` 可用（GitHub 托管 runner 预装；实测当天核实）；
2. `build-android`：安装 Android NDK（runner 通常预装）、`cargo install cargo-ndk`、
   `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android`；
3. 把上述步骤连同"为什么需要"写进 `ci.yml` 注释与 `upstream-map.md` 的 rhttp 条目；
4. 若最终拍板项 5 改判为"dio 重写漫画网络层"，则本条整段作废，CI 不动。

### 11.5 CI 文件自身的改动纪律

改 `ci.yml` 后必须跑 `node tools/validate-ci-yaml.mjs .github/workflows/ci.yml` 与
`node tools/test-validate-ci-yaml.mjs`，两者退出码 0 才算改完；结构校验器不替代真实
运行，首次推送仍要盯 GitHub 上的实际结果。

---

## 12. 许可与署名（M1 必做，与功能无关但阻断发布）

四个上游（Kazumi、Venera-Next、legado、EchoMusic）均为 GPL-3.0。把它们的代码整树
搬入并分发，本项目就是衍生作品，**必须以 GPL-3.0 发布并保留署名**。M1 落地清单：

1. 根目录 `LICENSE`：GPL-3.0 全文；
2. 根目录 `NOTICE`：逐上游列出仓库地址、版权行、许可证、搬入了哪些目录、做过哪些
   修改（import 前缀改写、剥离清单）——这也是 §7 的 upstream-map 的法律镜像；
3. `README.md` 增加"来源与许可"段，链接四个上游并声明本项目同为 GPL-3.0；
4. 上游自带的 `LICENSE`/版权头随搬不删（Kazumi 的 `licenses/ech_http/` 等第三方许可
   也按 §4.1 原路径保留）；
5. 发布二进制时附源码获取方式（GPL 义务），本地自用阶段也先把文件备齐。

Aniyomi 因法律压力停止维护是先例；这不是"以后再说"的事项，M1 一起做掉。
