# AGENTS.md — mimao 工作说明书

> 随仓库走（入库）。`LESSON.md` 是踩坑账本，两者互补：通用工程纪律读 dev skill；跑、点、看、验本应用读 mimao-dev skill。

## 这个仓库是什么

Flutter + Material 3 的个人媒体聚合应用，桌面优先（Windows 首发、Android 次要），纯本地运行、无自建服务器。
当前模块：漫画 `lib/comic`、音乐 `lib/music`、小说 `lib/novel`；壳 `lib/shell`、跨模块共享 `lib/core`。
**番剧模块已下线**，`lib/anime` 不存在——文档里出现 anime 一律当历史。

## 谁的判断优先

1. 源码、`pubspec.yaml`、`.github/workflows/ci.yml` —— 当前行为的唯一判据。
2. `LESSON.md` —— 具体踩过的坑，以及跨模块复用的状态机/规划纪律。
3. 本文件下面的架构、目录、模块、环境各节 —— 由 `doc/` 里的设计文档提炼而来（原文只留本机，不入库）。与源码冲突时按源码做，并顺手改本文件；不要为迎合过期文档改代码。

## 硬约束

### CI 三门扫 `lib/*`，别再改回逐目录点名
`ci.yml` 的 format / analyze / dart fix 三门扫 `lib/*`（含 `lib/main.dart`）、`test`、`tool`，**新增 `lib/<模块>` 自动纳入，不用改 ci.yml**。
别再改回枚举目录：那样新目录不进任何门却 CI 全绿，是本仓最隐蔽的假绿。
（2026-11-24 落地：原写 `for d in lib/shell lib/core lib/comic lib/music lib/novel test tool`，format 111 行 / analyze 142 行 / dart fix 155 行；按「铁律怎么产生」§3 的终局改成 `lib/*`，改后目标集合与改前逐文件比对一致。）

### 生成物必须入库
`*.g.dart` / `*.drift.dart` / `*.mock.dart` 一律提交，**不得加进 `.gitignore`**。
CI 会 `build_runner build` 后查三件事：有被忽略的生成物、已跟踪文件 diff 非空、冒出未跟踪新文件——任一即红。
改 schema / 注解后本地 `dart run build_runner build`，产物和源码一起提交。

### 依赖与 lockfile
`pubspec.lock` 与 `pubspec.yaml` 必须同步；CI 用 `flutter pub get --enforce-lockfile`，不同步直接红。
改依赖要用 `PUB_HOSTED_URL=https://pub.flutter-io.cn` 重新生成 lock——lock 里 139 个 hosted 条目记的就是这个镜像，换源会触发全量重解析而必红。
`.dart_tool/`、`build/`、`coverage/` 不入库。

### 提交
Conventional Commits + scope：`fix(comic): …`、`feat(music): …`、`test(novel): …`。一个 commit 一个目标。
body 写清验证了什么、没验证什么。

### 公开仓卫生
`doc/`（常驻资料库，含设计文档、选型 demo、环境笔记、上游参考）、`.zcode/`、`tmp/` 由 `.gitignore` 挡在仓库外。`AGENTS.md` 与 `LESSON.md` **入库**——它们是迁移与接手的主要载体，新机器 clone 即得。
**私人规划、选型草稿、密钥，一律不进受版本控制的文件。**

### 本地目录只有两种：doc/ 常驻资料库、tmp/ 临时区
- `doc/`（gitignored）是唯一常驻资料库：设计文档、选型 demo（`doc/demos/`）、环境笔记（`doc/ENV-SETUP-LOCAL.md`）、上游参考（`doc/references/`）。挪进去的东西留一句来历说明（哪来的、干什么用）。
- `tmp/`（gitignored）是唯一临时区：一次性下载、解压、抠出来的文件放这里，用完即删。发现有价值的先挪进 `doc/` 并留来历，再清 `tmp/`。
- 不许把临时文件散落在仓库根或 `doc/` 里，也不许在根上另开 `.tmp-*`、`temp` 之类的临时目录——临时区就叫 `tmp/`，资料库就叫 `doc/`。
（2026-11-22 定：原 `docs/`、`demos/`、根上 `ENV-SETUP-LOCAL.md` 归并为 `doc/` 资料库，临时区定为 `tmp/`；NOTICE、ci.yml 注释、anima-icon-gen.mjs 的路径引用已同步。）

### 工作树是多线共用的
`C:\da` 可能同时有几条并行线在改。只碰自己那条线的文件；改动尽早 `git add && git commit`——暂存区会被别线的提交一起扫走。
看到别人线留下的大改动，不要顺手整理或回退。

### 验证分工
- **全量测试交给 GitHub CI**（本机性能不行，别在本地跑整套 `flutter test`）。
- 本地最少自查（改到哪查哪）：`dart format --output=none --set-exit-if-changed <文件>`、`dart analyze --fatal-infos <目录>`、`dart fix --dry-run <目录>`（必须出现 `Nothing to fix!`）。
- 本地跑漫画引擎测试要有 native QuickJS：把 `build/windows/x64/.../flutter_qjs_plugin.dll` 拷到仓库根（已 gitignore），否则缺库。
- 验收一个跑起来的 app：走 mimao-dev skill（`flutter run -d windows` 起 debug 构建，内嵌 dev 服务），**别用 `| tail` 吞掉 flutter 的退出码**。
- Android 真机由用户自己下 APK 低频测；我负责 Windows 与 CI。
- **Windows 构建类问题以 CI 为准**：本机 VS 2022 / MSVC 14.44，runner 的 `windows-latest` 已是 VS 18 / MSVC 14.52——本地 `flutter build windows` 绿不代表 CI 绿（2026-11-24：STL1011 协程弃用断言本机根本没有）。改 `windows/CMakeLists.txt` 或插件编译设置后，跑 `flutter build windows --release --config-only`，再 grep 生成的 `build/windows/x64/plugins/*/*.vcxproj` 的 `PreprocessorDefinitions`，确认定义真到了插件工程。

### UI：一套 token，不留第二套
**样式的唯一事实源是 `lib/core/theme.dart`**（`buildMimaoTheme` 集中了颜色、圆角、字体、输入框、卡片、对话框、菜单、chip 的 shape）。页面不覆写组件 theme，不另起一套。

- **圆角**只用 `MimaoRadii`（sm 10 / md 14 / lg 20 / xl 28 / pill 999）和 `MimaoShapes`，不写 `BorderRadius.circular(<数字>)`。
  现状还有二十来处页面级手搓圆角，改到哪顺手收口，别专门开清理任务。
- **颜色**只从 `ColorScheme` 角色取，不写 `Color(0x…)`、不用 `Colors.*`。
  唯一例外：覆盖在封面 / 图片 / 视频上的遮罩与文字（播放页、歌词、渐变 scrim）用固定黑白——那里没有语义色可依。
- **字体**锁死 `Microsoft YaHei`，只用 w400 / w700。**不要用 500 / 600**：雅黑没有这两档，系统会把它们就近乱配到不同文件，同一句里个别字莫名变粗变细。字号 / 行高沿用 M3 基线，不手写 `fontSize`。
- **主题三态**：跟随系统 / 浅色 / 深色（`shellStore.themeMode`，默认 system）。种子色来自设置（基础色板 / 系统强调色 / 动态取色），深浅两套一律由 `ColorScheme.fromSeed` 派生，不为深色另写一套颜色。

**布局与导航现状**：壳是三态切换（入口拼贴页 / 模块层 / 统一时间线，`AnimatedSwitcher` 260ms）+ 设置 `endDrawer`；小说模块内部是五入口（首页/书架/发现/订阅/我的），宽 ≥900 用左侧自绘侧栏（240px 图标+文字；2026-11-22 三模块统一为同款自绘侧栏改的，原 `NavigationRail`（≥1180 展开文字、否则图标+文字）移除），窄窗口仍用底部 `NavigationBar`；漫画模块内部是**自绘左侧边栏**四分区（主页/收藏/发现/分类，底部设置项；2026-11-22 用户拍板改的，宽 ≥720 走 240px 图标+文字、窄窗口 84px 仅图标——不是 `NavigationRail` 组件，别拿它顶替）。三模块侧栏导航行统一（2026-11-22）：悬停/选中的高亮药丸区锚定原位（外距 12），内容在药丸内缩进 8、图标垫落到 x=20；音乐模块与漫画同款**自绘左侧边栏**（2026-11-22 依 `lib/music/pages/music_module_page.dart` 改，原为底部 NavigationBar 四 tab）：顶部账号小卡片（点按进账号分区）+ 发现/我喜欢/播放历史三个导航行（「我的」tab 拆成后两个入口，`MusicLibraryPage` 以 initialTab/showTabSwitch 锁定分段）+ 歌单区（云歌单列表，`MusicSidebarPlaylists`，窄窗不渲染；行是**可选中分区**——点行内容区内嵌切到 `MusicPlaylistInlineView`（IndexedStack 保活不 push 路由），导航行高亮让位给歌单行）+ 底部设置项弹面板；发现/账号分区页 embedded 时不再自带 AppBar。新页面先抄同类页骨架，不引入第二套布局习惯。

**小说页的共用件**：页头、卡片、封面、统计卡、空/错/加载态、阅读目标表盘统一在 `lib/novel/pages/novel_widgets.dart`；新页面从这里取，别在页面里另造一套。

**书架（2026-11-25 五种布局）**：布局/展示项的唯一事实源是 `lib/novel/shelf/shelf_view_config.dart`（`NovelShelfViewConfig` + 分组/顺序纯函数），存 kv `shelf_view`；单书卡片在 `lib/novel/pages/shelf/shelf_cards.dart`，布局设置与书籍信息面板各在同目录 `shelf_layout_dialog.dart` / `book_meta_sheet.dart`，`novel_shelf_page.dart` 只留数据、筛选、布局骨架与交互。
- 五种布局：网格 / 列表 / 瀑布 / 文件夹分组 / 平板双列。**双列的列数必须按「半窗宽 / 封面宽度」重算**（`autoShelfColumns`），套整窗列数会退化成普通网格（截图验收时踩到）。
- 文件夹模式的分区列数用分区自己的 `LayoutBuilder` 宽度，**不读 `MediaQuery`**（有侧栏/内边距时 MediaQuery 宽度偏大，卡片被挤窄）。
- 拖拽排序只在「手动排序」模式且非选择模式可用，顺序存 kv `shelf_order`；被筛选掉的书按原相对顺序留在后面，不丢书。
- 备注 / 自定义封面 / 系列都落在收藏行（`note` / `customCoverPath` / `seriesId`）；自定义封面由 `lib/novel/shelf/novel_cover_picker.dart` 复制进支持目录 `novel_covers/`，**不要直接存用户原路径**。系列在 `novel_series` 表，删除系列只解绑不删书。

**首页模块化（2026-11-25）**：`lib/novel/home/home_module_config.dart` 是唯一事实源（模块清单/开关/顺序/自定义分组卡片），存 kv `home_modules`；管理面板在 `lib/novel/pages/home/home_module_manager.dart`。`NovelHomeModuleKind.slot` 决定宽窗落位（主栏/侧栏/整行），默认值刻意还原改造前的两栏骨架——**改默认清单前先想清楚会不会改变用户现有观感**。某栏被关空时另一栏占满，不留空洞。

**发现页（2026-11-25 三修）**：`layout_flexBasisPercent`/`layout_flexGrow` 在 `engine/explore_kinds.dart` 的 `layoutExploreKindRows` 里转成行内宽度，弹层按它排（`novel_explore_sheet.dart`）；`ruleExplore.pageParam` 由 `applyExplorePageParam` 决定翻页 query 名（地址自带 `{{page}}`/`<1,2>`/`@js:` 时不重复追加）；发现结果按 `type == 0` 过滤成文字书并留警告。**这三个字段都是"解析了但曾经不生效"的典型——新增规则字段时先确认它真的被消费**。分类入口条的百分比宽度要先扣掉间距再乘（`available = maxWidth - gap*(n-1)`），否则刚好溢出。

**小说书源引擎**：`lib/novel/{analyzer,engine,js,cache}` 已实现（2026-11-23），Kotlin 语义对照见本文「上游对照」节（`doc/references/legado-with-MD3/` 只是本机只读副本，不入库）；改规则解析/选择器前先看 `LESSON.md` §八（xpath_selector 静默空、`##` 与 private name、GBK 容错、目录顺序、JS 同步网络重放）。

**本地书（第二条通路，2026-11-25 落地）**：TXT / EPUB / Markdown 导入与阅读，独立于书源。
- 纯逻辑在 `lib/novel/local/`：`local_models.dart`（格式/编码/目录项）、`local_source.dart`（字节来源抽象，测试用内存文件）、`local_encoding.dart`（编码嗅探与分段解码）、`local_txt.dart`（TXT 规则与流式分章 + Markdown）、`local_epub.dart`（container→opf→spine）、`local_book_service.dart`（探测/导入/重新分章/重新定位 + TXT 规则表）。
- 引擎分流与虚拟源在 `lib/novel/engine/local_engine.dart`（与 `legado_engine.dart` 同目录：两者都是 `NovelOnlineEngine` 的实现，放一起才看得出「同一接口两条通路」）。
- **本地书必须走同一个 `NovelOnlineEngine`**：虚拟源 `novelLocalSourceKey` 由 `NovelLocalSourceStore` 追加进「详情/阅读器」用的书源列表，引擎按 sourceKey 分流。**不要在页面里加 `if (isLocal)`**——进度、书签、划线、替换规则、TTS 全靠这条一致性。
- 本地书的目录是**导入时落库的缓存**（`novel_local_book.toc_json`），所以「文件是否还在」必须显式探测（详情页 `NovelLocalFile(path).length()`、阅读控制器 catch `NovelLocalFileMissing` → `localFileMissingPath`），否则文件被移走后页面会先显示目录、点进去才报错。改这块前先看 `LESSON.md` §八末尾两条。
- 编码嗅探顺序：BOM → UTF-8 严格 → 无 BOM 的 UTF-16 → 中文候选按字符合理性打分（GBK 优先于 GB18030，因为 GBK ⊂ GB18030）。全部失败才回退 UTF-8 宽松解码并标 `lossy` 给警告。
- 测试全部用 `NovelMemoryFile` + `NovelDb.forTesting(NativeDatabase.memory())`；`NovelLocalBookService` 的 `opener` 参数就是给这个用的，别在测试里碰真实路径。

**搜索 / 书源编辑 / 书源调试**（2026-11-25 落地，社区工具三件套）：
- 搜索的纯逻辑在 `lib/novel/search/`：`novel_search_scope.dart`（全部 / 分组 / 手选多选的选源范围）、`novel_search_merge.dart`（归一化书名+作者跨源合并、相关度/源权重/字数三档排序）、`novel_search_session.dart`（限流并发、分页追加、单源重试、取消）。**页面不自己实现过滤/合并/排序**，改行为改这三个文件并补 `novel_search_test` / `novel_search_session_test`。
- 书源编辑的纯逻辑在 `lib/novel/source/novel_source_edit.dart`：字段表（六段）、表单↔raw 双向读写、离线校验、导出、分组增删改、批量移动、权重。**书源的权威形态始终是 Legado 原始 JSON（`NovelBookSource.raw`），编辑不引入第二套模型**；保存走 `NovelSourceUpsert`（地址变则迁移主键），拿不到该能力时退回「先 saveAll 再 delete」。
- 书源调试在 `lib/novel/debug/`：`novel_engine_trace.dart`（追踪事件 + 内存 sink + 取消令牌）、`novel_source_debugger.dart`（四步校验链 + 单动作调试）。引擎实现 `NovelEngineTraceable`，调试时把 sink 挂到**同一个** `LegadoNovelEngine` 实例上——**不要给调试另写解析路径**，否则调的和跑的不是一回事。调试页 `novel_source_debug_page.dart` 只在 `kDebugMode` 注册路由，**并且管理页不 import 它**——入口是装配处注入的 `openDebug` 回调（release 传 null），否则 AOT 会把这个类和整套追踪设施一起打进包。
  **验收方法**：`flutter build windows --release` 后，用 UTF-16LE 在 `build/windows/x64/runner/Release/data/app.so` 里搜调试页独有文案（「JS 控制台」「完整校验」「目录 0 章」）应为 ABSENT，同时搜「搜索历史」「分组管理」应 FOUND——2026-11-25 实测如此。
- 长任务加超时**一律走 `lib/novel/engine/safe_timeout.dart` 的 `withSafeTimeout`**，别直接 `.timeout()`：后者超时后原 future 仍在跑，迟到错误没有 await 方会变成 unhandled async error 打崩 app（见 `LESSON.md` §八）。
- dev HTTP 通道：`/eval` 的 `novel.verify` / `novel.debug` / `novel.pushRoute`（debug-only，桌面端用应用内页面 + 本地 HTTP，不移植 Android 的 WebSocket 服务形态；接口形态与 Android 复用同一 `NovelSourceDebugger`）。
- **真源验收记录（2026-11-25）**：本机可访问部分公网书源。用「飞速小说网」跑完整校验链通过（搜索 50 本 → 详情 → 目录 94 章 → 正文 37 段，总 1.4s）；故意把它的 `ruleToc.chapterList` 写成漏括号的 `//div[@class=box_con`，编辑器和调试面板都能给出可读错误（「目录规则括号不配对」/「目录 0 章」）。**已知限制**：书旗小说等源的目录地址依赖 `java.put('bid')` 跨请求传变量，而本引擎的 `java.put/get` 是每 analyzer 实例内的变量表、不跨 search→detail 持久化，故这类源目录取不到；这不是工具链问题，是引擎对 legado「源级变量持久化」的保真缺口，单列待办、不在本目标范围。本机网络对不少源仍会 DNS 失败/超时，验收时以「能连通的真实源」为准，不可连通者如实记为网络限制。

**阅读器菜单与每书设置**（2026-11-25 落地）：顶栏/底栏/浮动行的按钮一律从 `lib/novel/reader/novel_menu_actions.dart` 的注册表取（`id` + 文案 + 图标 + 可用性谓词），三处各存一份「顺序 + 启用」；**别在页面里另写一套按钮清单**。顶栏截断到 `novelTitleBarMaxActions`（6），紧凑标题栏只留「更多」，一个都不剩时也保留「更多」。点击副作用集中在 `novel_reader_page.dart` 的 `_menuActionTap`：先按 id 特判（`settings` 打开设置面板、`more` 打开更多面板），其余才落 `dispatchClickAction`——注册表的 `settings` 条目与点击区的 `NovelClickAction.menu`（显隐浮层）语义不同，别混。每书覆盖走 `NovelReaderSettings` 里的纯函数（`diffNovelReaderSettings` / `mergeNovelBookOverride`），只存与全局不同的白名单字段（背景/字体/翻页/动画/点击区），优先级「每书 > 全局 > 默认」；**不可覆盖字段（菜单外观等）一律落全局，不许静默丢弃**（见 `LESSON.md` §七）。kv 键统一在 `lib/novel/library_api.dart`。

**WebDAV 备份与同步（2026-11-25 升级为「可同步 / 可合并 / 可预览」）**：实现全在
`lib/novel/backup/`，`lib/novel/webdav_backup.dart` 只是门面（re-export + 旧名别名）。
- **文档 v2**（`backup_document.dart`）：带 `deviceId` / `deviceName` / `schemaVersion` /
  `kind`（`full` | `progress`）；兼容读 v1（进度由收藏与历史合成、按本机设备落库）。
  稿里 `chapterIndex` 是 **1 起章号**（0 = 未读，与 `novel_history` 同口径），
  `locator.chapterIndex` 才是 **0 起**（与 `NovelLocator` 同口径）——别混。
- **合并是纯函数**（`backup_plan.dart` 的 `planNovelRestore`）：进度按
  `(bookId, sourceKey)` 章号大者胜、同章取时间新者；收藏/系列/搜索词取并集；书签划线
  按锚点自然键去重；阅读时长按 `(deviceId,bookId,chapterIndex,day)` 取 max（重复导入
  幂等）；设置分「跨设备共享」与「设备本地」两档；墓碑压过较旧的行。**预览计数与执行
  吃同一份 plan**，不许另算一遍。
- **上传也是合并写**（`mergeNovelBackupDocuments`）：先 GET 远端再 PUT 超集，否则第二次
  备份就把另一台设备的进度抹了。远端是加密包但没密码时只能跳过合并并说明原因。
- **恢复先预览再执行**：`preview()` → 用户确认（含逐条冲突选择）→ `apply()`。执行前写
  一份整库兜底快照（`novel_backup/pre-restore-*.json`），并按行记 journal；
  `undo()` 只回滚"当前值仍等于本次写入值"的行，恢复后用户又改过的数据不会被连坐。
- **密码**：WebDAV 账号密码进**系统安全存储**——Windows 用 `dart:ffi` 直连
  `crypt32.dll` 的 DPAPI（`CryptProtectData`，密文落 `novel_credentials/`），
  **不要再引 `flutter_secure_storage`**：它的 Windows 端是 C++ 插件，要 ATL 头
  （`atlstr.h`）与 `/WX`，没装 ATL 的 VS 直接 `C1083` 把主平台编挂（见 `LESSON.md` §四）。
  其它平台暂为 `NovelUnavailableCredentialStore`（读当没有、写明确抛错），Android
  需要 Keystore 时再补实现。旧版明文 kv 键会自动迁走并清空。备份文件密码是另一回事
  （AES-256-GCM + PBKDF2），选了"记住"才进安全存储，否则自动备份与进度同步会没有
  密码而明确报错——**不静默跳过**。
- **进度专用包**：主地址插 `-progress` 得到，只带 `progress` 段；阅读页「同步进度」与
  备份中心的「立即同步」共用 `NovelProgressSync`，**本地更新的记录绝不被覆盖**。
- **自动备份**：`off` / `exit` / `daily`，判定是纯函数 `shouldAutoBackup`（daily 用 24
  小时，避开时区/DST）。退出钩子只能由壳提供——`lib/shell/lifecycle.dart` 的
  `registerAppExitHook` / `AppLifecycleGuard`（10 秒硬超时，备份慢不能卡住关窗），
  由 `app_registry` 注册（壳不知道备份是什么）。
- 删除墓碑在 `novel_tombstone`（schema v9）：**只覆盖书签 / 划线**，超 90 天 prune；
  取消收藏的传播不在范围内。

**滚动**：横向滚动区（源 chip 行、海报行）必须鼠标能拖——全局 `MimaoScrollBehavior` 已把 mouse 加进 `dragDevices`，**别在局部自建 `ScrollBehavior` 覆盖它**。

**词典 / 标签 / 主题包 / 键盘辅助（2026-11-25 落地）**：
- **词典** `novel_dict_rule` + `lib/novel/dict/`：查询复用 `AnalyzeUrl` + `LegadoRuleAnalyzer`（只有 `showRule` 含 `@js:`/`<js>` 才建 `LegadoJsHost`）；`{{key}}` 在 `expandNovelDictUrl` 里先做 UTF-8 百分号编码——`AnalyzeUrl` 只编码 query，词典地址常把词放在路径里。内置只留 `dict.cn` 与一条 `data:` 离线样例（单测与截图不联网）；**汉典已从内置移除**——它对 Dart HttpClient/dio 一律 404（浏览器/.NET 正常，疑似 TLS 指纹拦截），留着只会让第一条永远报错。入口：我的 → 字典规则；阅读页选区菜单「词典」共用 `NovelDictResults`。
- **标签** `novel_tag_group_rule` + `lib/novel/tags/`：正则匹配分类标签（kind）或书名 → 写收藏行 `groupName`，**只加不减**（已有分组不覆盖，对齐上游 `book.group or newGroupMask`）；颜色存规则里，书架 chip 用它。页面只预览与手动「应用到书架」，规则不自动执行。
- **主题包** `novel_theme_package` + `lib/novel/theme/`：JSON = `format` + `version` + `settings`（`NovelReaderSettings.toJson`）+ `keyBindings` + `preview`（PNG base64）；版本高于 `novelThemePackageVersion` 一律拒绝并说明。应用只写全局 `reader_settings`，不碰每书覆盖，不含背景图原图。
- **键盘辅助**：独立 kv `reader_keyboard_assist`（**不塞进** `reader_settings`），动作复用 `NovelClickAction`，默认表 == 改造前写死的方向键/翻页键/空格；Home/End/Esc 是阅读页保留键，不进可配置表。阅读页用 `_shortcutBindings()` 合成；按键提示浮层默认关、仅桌面端。
- 数据层：schema **v9** 三表纯增量（迁移 `if (from < 9)`），`novel_db.g.dart` 一起提交。

**界面什么时候算"做完"**：测试绿 ≠ 界面没坏。UI 改动必须用 mimao-dev 的 `/shot` 截图亲眼看过，并走过**加载 / 空 / 错误**三态。
空态写"为什么空 + 下一步做什么"，不写"暂无数据"；错误态给可操作的下一步，堆栈进日志不进界面。破坏性操作二次确认或可撤销；桌面端可点区域要有 hover / focus 反馈。

## 架构与启动时序

**四条边界铁律**（`test/architecture/boundary_test.dart` 逐条把守，改 import 前先看它）：

1. `core/` 永不 import `shell/` 与三个模块；
2. 三个模块互不 import；
3. 模块不 import `shell/`，只准 import `core/`；
4. `shell/` 里**只有 `app_registry.dart`** 允许 import 三个模块。

**启动时序**（`lib/main.dart`，改顺序要连带改这里）：

1. `WidgetsFlutterBinding.ensureInitialized()`
2. `initWindow()` + `initTray()`（运行时判断平台，Android 空操作）
3. `AppDb()` + 一次 `select(appSettings)` 探活；失败 `runApp(StorageErrorPage)` 后 return
4. `networkSettings.load`（失败按直连继续）
5. `kDebugMode` 下 `startDevHarness` + 挂 `devRouteTracker`
6. `SystemTheme.accentColor.load()` 注入 `systemAccentProvider`（失败不阻塞启动）
7. `initAppModules(library:)` → `runApp(LibraryScope(MimaoApp))`（debug 外包 `DevReassembleProbe`）

**壳**按 `(activeModule, showLibrary)` 三态切换：入口拼贴页 / 模块层 / 统一时间线（`AnimatedSwitcher` 260ms），设置挂 `endDrawer`；没有 `NavigationRail`。

**双记账**：模块内部库是唯一权威，`core.media_entries` 只是投影。

- 投影只挂在模块的**持久化点**（写完内部库，同函数内 upsert）；绝不挂内存状态或定时器。
- 打开动作回写校正（comic：`ComicHistoryService.open`；无历史记录时不写，避免点开就凭空上架）。
- 壳只读公共列（含 `progressText`），**永不解析 `payload`**。
- `media_entries` 主键 `{id, mediaType, sourceName}`，core schema 现为 **v2**。

**模块失败隔离**：`initAppModules` 各自 try/catch，失败只不注册该模块；`appModulesError` 用 `\n` 拼接（后写不能覆盖前写）；异常不冒到 `main`。

**总原则**：目录是长出来的器官，不为对称造空架子；「无消费者不建」；里程碑结束时系统必须完整可用，绝不「重构到一半不可用」。

## 目录职责

| 目录 | 职责 |
| --- | --- |
| `lib/shell/` | 导航 + 承载 + 桌面窗口（`window/window.dart`）+ 统一书架页 + 设置；`app_registry.dart` 是全库唯一 import 模块处；`shell/dev/` 是 debug-only 调试设施 |
| `lib/core/` | `contract.dart`（`AppModule` 契约＝模块唯一对外面）、`db.dart`（`AppDb`）、`library.dart`（书架唯一 facade）、`settings.dart`（kv）、`theme.dart`（样式唯一事实源）、`navigation.dart`、`volume_keys.dart` |
| `lib/comic/` | `engine/`（Venera JS 源引擎）、`data/`、`request/`（dio + cookie + challenge）、`pages/`、`reader/`，根级服务 `collect_service` / `history_service` / `download_store` / `local_comic_service` / `comic_projection` / `comic_db` |
| `lib/music/` | `api/`（一端点一文件）、`models/`、`client/`（签名/加密/身份）、`player/`（media_kit + store + 播放页/迷你条）、`pages/`、`lyric/`、`hotkey/`、`widgets/` |
| `lib/novel/` | `analyzer/`、`engine/`（含 `local_engine`）、`js/`、`cache/`、`local/`、`search/`、`source/`、`debug/`、`shelf/`、`home/`、`reader/`、`dict/`、`tags/`、`theme/`、`backup/` |
| `doc/` `tmp/` | 本机资料库与临时区，均 gitignore（见上文） |

**新目录规则**：`lib/` 根下新增目录必须对应一个模块；同层文件 > 8 且能自然分组才开子目录；不建 `lib/app`、`lib/common`、`lib/shared`、`lib/utils`、`lib/modules/`、`lib/src/`；删除优先于留空壳；目录变动单独成提交。

## 新机器环境搭建

- **Flutter 3.50.0** stable（Dart 3.14），装在 `C:\flutter`；`pubspec.yaml` 约束 `sdk >=3.10.0 <4.0.0`；CI 里 `FLUTTER_VERSION` 必须是同一个版本。
- **Android**：cmdline-tools latest、platform `android-36`、build-tools `36.1.0`、platform-tools（`C:\Android\Sdk`）。
- **Java**：Temurin JDK 25，设 `JAVA_HOME`。
- **Windows 构建**：VS Build Tools 2022 17.14+，workload **必须是 `Microsoft.VisualStudio.Workload.VCTools`**——装成 `NativeDesktop` 会静默得到没有 `cl.exe` 的空壳；UAC 必须真人点，自动化装不成。
- **环境变量**：`PATH` += `C:\flutter\bin` 与 platform-tools；`ANDROID_HOME` / `ANDROID_SDK_ROOT`；`PUB_HOSTED_URL=https://pub.flutter-io.cn`；`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`；改完重开终端。
- **lockfile 与镜像强耦合**：`PUB_HOSTED_URL` 被写进 `pubspec.lock` 的每个 hosted 条目（当前 180 个），换源必须同时改 `ci.yml` 顶层 env 并重新 `pub get`，否则 `--enforce-lockfile` 必红。
- **`nuget.exe` 必须在 PATH**（`flutter_tts` 的 Windows 端在 CMake 里 `find_program(nuget)`）——本机在 `%USERPROFILE%\tools\nuget.exe`，Git Bash 先 `export PATH="$HOME/tools:$PATH"`，否则 `FATAL_ERROR: nuget.exe not found`。
- **下载走镜像**：Flutter SDK 用 `storage.flutter-io.cn`；GitHub 资源用 `https://ghfast.top/<原url>`（`gh-proxy.com` 可用，`ghproxy.net` 慢易断）。
- **本机网络对 `github.com:443` 不通**（TLS 被拦，`api.github.com`、`github.com:22`、`ssh.github.com:443` 都通）：`git push` 用 SSH；仓库当前挂的是写权限 deploy key（`~/.ssh/github_ed25519`），`gh` 命令行照常可用。
- **Git Bash 两个坑**：调 `.bat` 时参数里的 `;` 会被 cmd 吃掉（改成写 `.bat` 文件执行）；`curl` 不能直接写 `C:\` 根（先下到工作目录再移）。
- **刻意不装**：Android Studio（用 sdkmanager）、模拟器（用真机）、Web/Chrome（doctor 里红可忽略）、iOS/macOS/Linux 工具链。

## Windows 真机验收

- 首次构建前把 media_kit 的两个预编译包放进 `build/windows/x64/`（CMake 的 `CMAKE_BINARY_DIR`），CMake 自校验 MD5：`mpv-dev-x86_64-20230924-git-652a1dd.7z` = `a832ef24b3a6ff97cd2560b5b9d04cd8`（8785710 字节）、`ANGLE.7z` = `e866f13e8d552348058afaafe869b1ed`（5035414 字节）；缺则 `Integrity check failed`。
- `flutter run -d windows` 首次约 **6 分钟**出窗；**禁止 `| tail`**（吞输出、吞退出码，看起来像卡死）；`Policy CMP0175 is not set` 之类 dev warning 正常。
- 产物核对：`build/windows/x64/runner/Debug/mimao.exe` + `libmpv-2.dll`（约 29.7MB）。
- 漫画引擎测试需 native QuickJS：把 `flutter_qjs_plugin.dll` 拷到仓库根（已 gitignore）。
- 壳层：首页标题 + 副标题；宽窗 3×2 拼贴、<720px 单列；每个模块页与书架页都要有返回入口；顶栏齿轮开设置抽屉（模块分组 + 外观 + 存储）；主题种子色 8 色 + 「跟随系统」第 9 枚（主题色不持久化）。
- 存储页要显示 `%APPDATA%` 下的应用支持路径 + 「统一书架 mimao.db（与模块内部存储分离，模块存储为权威）」。
- 跨模块一致性：各模块收藏/进度 → 书架出现条目且文案正确；写进度后 `starred`/`coverUrl`/`createdAt` 不丢；人为造「内部 ep5、投影 ep4」分叉 → 打开条目 → 校正回 ep5；杀进程重开无分叉；单模块初始化失败不影响其它。
- 音乐：**匿名设备可搜索但不可播放**（`/v1/user_verify` 返 `business/35002`），文案「请先登录酷狗账号后播放」；出声必须在扫码登录后复测。
- 无真源时用替身：漫画源管理可导入 `test/comic/fixtures.dart` 的 `fixtureSourceScript`（真 QuickJS + fake HTTP）。
- 外部脚本截图/驱动三坑：PowerShell `CopyFromScreen` 默认 DPI-unaware（须 `SetProcessDPIAware()`，否则只截到 1280×720 虚拟屏）；`FindWindow($null,"mimao")` 恒 0（须 `[NullString]::Value`）；Flutter Windows 不暴露 UI Automation 节点。结论：外部注入只看观感，正解是 app 内 dev 端点。
- 勾选约定：`[x]` 通过 / `[-]` 产品预期不通过（注明原因）/ `[ ]` 未验；无网、无真源标「待验」，不冒充通过。

## 上游对照

- **搬运配方**：前缀 `package:<上游>/` → `package:mimao/<模块>/` 一把 sed；Venera 有相对导入，sed 后逐文件复核。每个 patch 后必须：`grep -rn "package:<上游>" lib/<模块>/` 为 0、`build_runner build` 后 `git diff --exit-code` 干净、per-file 测试数不降。
- **来源阶梯**：官方稳定版 → 已验证完整 commit → 必要补丁本地源码；每个 fork 登记「固定 commit + 引入理由 + 退出条件」。
- **漫画** ← `CyrilPeng/Venera-Next`（GPL-3.0，基线 main `86739d92`，2026-11-16）；`flutter_qjs` 钉 `f5a1f20d…`；`flutter_inappwebview` 钉 `0aaf7a0…`；`rhttp` 是 vendor 本地包（需 Rust 1.80+，Android 需 NDK + `cargo-ndk`）。
- **音乐** ← `hoowhoami/EchoMusicNext` 的 `crates/echo-api/`（Rust）**自写 Dart 重写，不是镜像**，无 patch 重放；只读对照 `domain.rs` / `util/crypto.rs`，歧义查 `MakcRe/KuGouMusicApi`（Node）。
- **小说** ← legado 规则语义；官方 `gedoor/legado` **已清空**（仅剩侵权公告），主对照 `HapeLee/legado-with-MD3` @ `db3d401d…`（2026-11-19，开工当天重取）；语义入口在 `app/src/main/java/io/legado/app/`：`AnalyzeRule.kt`(35KB)、`AnalyzeUrl.kt`(36KB)、`AnalyzeByJSoup.kt`(18KB)、`JsExtensions.kt`(39KB) 等。
- **番剧** ← Kazumi 一节**作废**（模块已下线，`lib/anime` 不存在）。
- **许可**：上游均 GPL-3.0，搬码即衍生作品 → 必须 GPL-3.0 发布 + `LICENSE` 全文 + `NOTICE` 逐上游列仓库/版权/许可/搬入目录/改动 + README「来源与许可」段 + 上游自带 LICENSE 随搬不删。

## 音乐模块

- **范围**：搜索扩展、发现/推荐、榜单、专辑、歌手、音效、歌单读写、用户资料/库、登录、验证/歌词、听歌上报、播放补全已落地；**明确不做**评论、云盘、MV/视频、社交；插件系统、后台播放/SMTC、下载也没做。
- **端点约定**：一端点一文件 + `<group>_api.dart` 组接口（`Music<Group>Api` / `Kugou<Group>Api`）；顶层函数 `fetchXxx`；参数/默认值/校验/回退链逐条对齐 Rust，不「顺手优化」；网络错误统一 `KugouApiException`；`ensureDevice()` 入口必调；20018 → authentication，不自行预判 `hasAccount`。
- **共享底座禁止改**：`api/session.dart`、`api/wire.dart`、`models/catalog_models.dart`、`models/music_models.dart`、`client/kugou_client.dart`、`client/kugou_crypto.dart`、`test/music/api/capture_adapter.dart`。测试用 `CaptureAdapter` + 匿名身份 + 假 `MusicSession`，覆盖请求装配/解码成功与边界/失败码/校验/回退顺序，不写网络、不 sleep。
- **播放链**：`user_verify → song_auth → tracker`（注入授权串则跳过第一步）；`user_verify` 走网关（`x-router=trackercdngz.kugou.com`、`module_id=51`），`status=0 && error_code=35005` → authentication；`song_auth` 五参数、`clientver=11561`、hash 小写；tracker **走网关**、24 参数、`key=kugouTrackerKey(hash,mid,userid)`、`timeLength` 秒→毫秒，`status!=1` 或 url 空 → business。
- **取址**：8 档质量映射（`standard→128 / higher→320 / flac / hiRes→high / viperTape / viperClear / viperAtmos / automatic→128`），默认 `higher(320)`，仅 business 回退 `standard(128)` 一次；hash 须 32 位 hex，`song.id` 不可解析直接 input，**不回退 `audioId`**。
- **播放器内核**：`player/media_kit_music_engine.dart` 用 media_kit `Player`（不建 `VideoController`），`open(play:false)` 由 store `play()` 驱动；**引擎工厂惰性求值**（启动不加载 libmpv）；换歌/暂停/拖动/播完强制写进度，播放中按注入 clock **10 秒节流**；next 到尾不回绕、previous 到头不回退；错误文案按 kind。
- **长尾 UI 约定**：页面只依赖 `Music*Api`，不 import `Kugou*Api` / `dio`；新增能力一律**可选构造参数**，null 时入口隐藏。已接音效商城/耳机匹配/听歌识曲（16000Hz 单声道 PCM16、≤160000 字节）、歌单导入编辑、账号资料、听歌上报 + 高潮 chip、手机/QQ/微信/设备登录、歌曲资料/权益/歌手写真、发现页风格推荐。
- **听歌上报**：`mixsongid` 非正整数跳过；`settings.listenReportEnabled`（默认 true）关则不上报；fire-and-forget 吞异常、不阻塞播放，不改 `progressSink` 语义。

## 漫画模块

- **源形态**：Venera 社区 JS 源，`lib/comic/engine/` 跑 QuickJS；manifest 含 `key/name/version/minAppVersion/url/enabled`，`enabled` 缺失按 true 读。**`sourceName` 承载注册 key**（如 `bilimanga`）而非展示名——同作品不同源就是不同 `{id, sourceName}` 两行。
- **章节 URL 自描述**：`mimao-ep://<key>/<comicId>/<epId>`（三段各 `encodeURIComponent`），不用 `detailUrl#ep=`；解码**只做一次**（二次解码遇字面 `%` 会错值或抛错）。
- **唯一进度写入口**：`ReaderController`（每页/切章都写，**不节流**）→ `ProgressRecorder.persist` → `ComicLibraryProgressRecorder` → `ComicHistoryService.saveProgress`（先写 `comic_history` 权威行）→ 同函数内 `syncComicProjection`；payload 统一 `{chapterId, page, pageCount}`（chapterId = 源稳定 epId）。`progressText` 只有一个生成器 `comicProgressText`。
- **双记账**：写入点 W1 收藏 / W2 取消收藏 / W3 写进度 / W4 导入本地漫画；校正点 C1 `ComicHistoryService.open(ref)`；`syncComicProjection` 每次从内部表重读权威行，幂等。列优先级：`title` 收藏→历史→本地→fallback；`coverUrl` 收藏→历史→fallback（**本地 `coverPath` 不进公共列**）；`lastOpenedAt` 历史→收藏→本地→now；`createdAt` 收藏→本地→历史→now。不投影的例外只有搜索历史、下载任务、图片缓存。
- **内部库** `mimao_comic`（drift schema **v3**，8 表）；`LibraryRepository` **没有 delete API**，取消收藏保留 `starred=false` 索引行。下载只有模型 + 状态机 + 仓储，**不含真实下载器**。
- **阅读器**（`lib/comic/reader/`）：每屏 1~5 图、连续滚动锚点、有界预载 + 尺寸缓存、自动阅读、键盘/右键菜单/全屏/存图、`comic.onImageLoad` 懒解析、自动版式、白边裁剪、宽图拆分、墨水屏整页刷新、音量键翻页。**未移植**：图片收藏、评论点赞、TV 焦点、自定义 JS 图片处理。
- **已知边界（产品预期）**：全章预载（几百章线性变慢、不可取消）；空关键词搜索返回 `[]`；搜索历史只落库无 UI；AES/RSA decrypt、GBK 解码维持原状。
- **源导入**：key 派生＝URL basename 去扩展名 → 非法字符换 `-` → 空则 `source`，脚本自带 key 优先；导入 URL 始终覆盖脚本 `url`；失败以异常抛给页面；顺序 fetch → parse → `pool.register` → `store.save`（不留「列表可见但永远搜索失败」的半成品）；源管理回调只做幂等对账 `syncPool()`（零网络），**不重复调 `importSource`**。
- **图片缓存与注入**：registry 生产注入 `defaultComicImageCache()`（`comic_images/` 的 `DiskByteStore`），null 回退内存缓存，保证 widget 测试不碰 path_provider；测试一律 `MemoryByteStore` + 假 loader。注入缝：`comicDb` / `comicSourceStore` / `comicHttpClient` / `comicHostFactory` / `comicImageCacheFactory` / 整模块。
- **打开点校正接线**：详情页 `onOpenDetail` → `history.open(ref)`（失败不挡导航）；阅读器 `_openReader` 先 `open(ref)` 再 `latest(ref)`，按 **epId 匹配**反查章节（空章跳过会致下标偏移），`initialPage = latest.page - 1` 钳制 `[0, pageCount-1]`，显式点章节从第 1 页起。

## dev HTTP 通道（`lib/shell/dev/`）

- 由 `main.dart` 在 **`kDebugMode`** 下启动，`startDevHarness` 是门面。文档里曾有的 `--dart-define=MIMAO_DRIVER`、`tool/mimao_mcp`、`mimao_*` MCP 工具**都不存在**了，别照着找。
- 绑定 `127.0.0.1` + 端口 0；每次启动重生成 32 字节随机 hex token；`driver.json` 原子写到应用支持目录，字段 `{port, token, pid, vmServiceUri, startedAt}`；`MIMAO_DRIVER_FILE` 可覆盖路径；`/shot` 落盘到同级 `dev-shots/`。
- 鉴权 `Authorization: Bearer <token>` 或 `?token=`；无效 401；请求体 > 1MB → 413。
- **GET**：`/health`、`/logs?level=&limit=`、`/route`、`/state`、`/shot`、`/db`（列库名）、`/eval`（列能力名）。
- **POST**：`/tap`（`{key?, text?, index?, dryRun?}`，合成真实指针事件走 hit-test）、`/navigate`（`{action, name?}`，action ∈ `home / library / settings / closeSettings / module / back`；**不做任意路由跳转**）、`/db`（`{db, sql, params?}`，**禁 ATTACH/DETACH/LOAD**，剥前导注释后再判前缀）、`/eval`（`{capability, args?}`，未注册 → 404）。
- **已注册库名**：`app`、`comic`、`music`、`novel`。**已注册能力**：`comic.eval`、`novel.sources / search / searchPage / detail / content / open / openReader / pushRoute / verify / debug`。
- **铁律遵守方式**：dev 层不 import 模块；模块能力/库在 `app_registry.dart` 用**闭包捕获 + 类型收窄**注册。
- **门面不拖垮本体**：`startDevHarness` 全程 try/catch 吞异常、只记 `DevLog`；幂等（热重启只重装钩子 + 重写 driver.json）；`DevLog` 挂 `FlutterError.onError` + `PlatformDispatcher.onError`，环形缓冲 500 条。
- **发布零携带验证**：`flutter build windows --release` 后用 UTF-16LE 在 `build/windows/x64/runner/Release/data/app.so` 搜 dev 独有串（`driver.json`、`127.0.0.1`、「JS 控制台」）应为 0 命中，同时搜「搜索历史」「分组管理」应命中。
- **覆盖边界**：导航/点击/树/状态/DB 可结构化验收；画质、音画同步、布局美观仍须人眼。

## 路由表（只读当前需要的那一份）

| 情形 | 读 |
| --- | --- |
| 要不要立规、两难取舍、判断值不值得为某件事加门禁 | dev skill（《决策规则》§六：观察 → 记录 → 三次晋升 → 机器固化） |
| 本次踩到或怀疑踩到的具体坑（测试假死、引擎、drift、Windows 原生、工具怪癖） | `LESSON.md` 对应分节 |
| 要跑、点、截图、查库、看真机效果 | mimao-dev skill |
| 改颜色 / 圆角 / 字体 / 组件样式 / 页面布局 | `lib/core/theme.dart`（唯一事实源）+ 本文「UI」节 |
| 目录职责、模块边界、启动时序 | 本文「架构与启动时序」「目录职责」两节（源码优先） |
| 新机器搭环境、装 Flutter/Android/VS | 本文「新机器环境搭建」 |
| 验收一轮真机 / 首次出窗 | 本文「Windows 真机验收」 |
| 这段代码是从哪个上游搬来的 | 本文「上游对照」 |

## 这两份文档自己会改

`AGENTS.md` 和 `LESSON.md` 是活的，不是一次写死的。干活途中发现它们说错了、过时了，**当场改，不用等用户点头**：

- 某条约束与源码 / `ci.yml` 不符 → 改文档（**不是改代码去迎合文档**）。
- `LESSON.md` 某条已被修复、或机制描述错了 → 标 `~~已失效~~（日期：原因）` 或直接删。
- 发现新的、会再犯的坑 → 补进 `LESSON.md` 对应分节，按「现象 / 为什么 / 怎么断」三行，末尾 ✕。
- 某条 ✕ 够三次 → 搬进本文件「硬约束」，并在 LESSON 那条标「已晋升」。

`doc/` 下的原文（本机资料库、gitignored）是这两份文档的来源：**结论已经搬进本文件，原文只作决策留档**。原文里被后来拍板推翻的段落不删，标「已被 X 取代」——丢了「为什么当时这么定」，以后会重开已决的辩论；但**要改的是本文件**，原文只做旁证。

改的时候守三条，防止越改越乱：

1. **先核对再改**：依据只能是源码、`ci.yml`、`pubspec`、或实际跑出来的结果。凭印象、或两份旧文档互相印证，都不算依据。
2. **只碰相关条目**：这次任务没涉及的部分，哪怕看着不顺眼也不动；不顺手重排、不把 LESSON 改写成散文。
3. **留依据**：改动处附一行 `（2026-11-22 依 ci.yml:111 修正，原写"…"）`，让后来的我能判断这次改得对不对。

两种例外：文档和源码**都解释得通**、自己判不了谁对 → 别猜，列出来问用户；改动会**放宽一条硬约束**（比如删掉某道门、允许忽略生成物）→ 先问，不自行放水。

## 铁律怎么产生

1. 出错先记进 `LESSON.md`：现象 → 为什么会这样 → 以后怎么断，条目末尾加一个 ✕。
2. **同一处错满 ✕✕✕**（不同日期或不同场景）就搬进本文件「硬约束」，并在 LESSON 里标「已晋升」。
3. 能机检的做成 CI 门或测试（例：新增目录逃逸这件事，正确的终局是把门改成扫 `lib/*` 而不是继续点名——2026-11-24 已落地）；不能机检的写进本文件，靠评审执行。
4. 不为一次事故立规，立规必须有真实事故依据。