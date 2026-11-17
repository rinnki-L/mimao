# 对抗复盘（plan-retrospective.md）

> 状态：规划期设计文档。写给没有参与对抗过程的你：三个架构师提了案、三个批评家
> 攻击了案、裁决者（我）复核了攻击并裁决，最终设计落在
> [architecture.md](architecture.md) 与 [directory-layout.md](directory-layout.md)。
> 本文讲清全过程：谁提了什么、挨了什么打、为什么这么判。
> 撰写日期：2026-11-17。

---

## 1. 背景与规则

任务：把四个 GPL-3.0 开源媒体应用聚合成一个本地 App（番剧←Kazumi、漫画←Venera-Next、
小说←legado/阅读、音乐←EchoMusic），Flutter + Material 3，桌面（Windows）优先，
当前纯规划期——只产出设计文档，不写代码、不装环境。

裁决遵循五条规则：
1. 不折衷出四不像：选一个底子，其余只做点状嫁接；
2. 攻击逐条复核：成立的必须体现在最终设计里，不成立的写明驳回理由；
3. **"目录不过于繁乱"是一票否决项**；
4. 两个口味问题（drift vs raw sqlite3、MobX 是否接受）只标"临时决定，等你拍板"；
5. 与已锁定决策冲突的设计一律不许出现。

---

## 2. 三个方案各一段摘要

### 方案1「主干即上游」
仓库起点就是 Kazumi 的 fork（保留 git 历史），目录即上游目录：番剧不设独立目录、
它就是主干本身；漫画把 Venera-Next 的 lib/ 整树搬进 `lib/comic/`；音乐/小说自写。
核心产物是 `docs/upstream-map.md`（每个目录←上游哪路径 + cherry-pick 配方）。
卖点是番剧"白得"、上游修复字面 `git cherry-pick` 可用。

**挨的最重的攻击**（实测证实成立）：里程碑 1 的"统一书架"必然落成双库、双页、双写——
Kazumi 的收藏/历史不是两个动作点，是一条带 Bangumi 同步管线的 hive_ce 链路
（`pages/collect` 8 文件、`modules/collect` 9 文件含 collect_sync_merger/collect_sync_plan、
history_repository 顶部 import hive_ce + storage coordinator + sync service）。
要么往这条链路里插桩（对新手是高风险动刀、漏一处时间线就分叉），要么 M1 书架空页
没有可验收物——与锁定决策 7"M1=壳+统一书架"正面冲突。此外"一次 sed 搬树"漏掉
`packages/rhttp` 与 assets（漫画第一天就卡环境）、fork 主干意味着继承 409 文件陌生代码
+ 双基础设施（网络×2 存储×2 webview×2）+ 上游快节奏带来的持续冲突面——对
"第一次做项目、极度在意自己能看懂"的你，这是开局即背半年的别人代码。

### 方案2「少一层是一层」
目录是长出来的器官：开工当天只建 `shell/` + `core/` + main.dart，每里程碑长出一个
模块目录；lib/ 根终态 6 目录+1 文件；依赖方向靠三条铁律约定；统一书架是投影
（模块三动作写入）；flutter_modular/MobX/drift 全部标"临时决定等你拍板"。
卖点是目录最少、每个文件都出自我手、生长规则与你的"好整理"诉求同构。

**挨的最重的攻击**（实测证实成立）：①蓝图与上游体量差一个数量级——实测 Kazumi lib/
409 个 Dart 文件（lib/modules 是 13 个域而非"各一 store"）、Venera-Next 561 文件，
"每模块终态 15-25 文件"的平铺规划第一次生长就会连环爆墙；②统一表与模块内部库
双记账没有任何裁决规则（关窗杀进程，模块库记 ep5、统一表停 ep4，没有"哪边是权威"
可查）；③audio_service 官方不支持 Windows（pub.dev 平台徽章实测），声称"媒体键在这层
接线"接不上——Kazumi 为此自养 audio_service_win/mpris 两个 fork。另有依赖篮子、
cherry-pick 字面跑不通、Android 无法"跳过编译某文件"等中低severity攻击，全部属实。

### 方案3「目录表契约」
三层固定（lib/app + lib/core + lib/modules/{anime,comic,music,novel}），边界由
`test/architecture/boundary_test.dart` 机器把守；模块经 entry.dart 实现 AppModule 契约
（5 成员 UI 出口），registry 是全库唯一 import 模块的地方；"删模块=删目录+删一行"。
卖点是边界机械可验证、模块可摘除。

**挨的最重的攻击**（实测证实成立）：①"cherry-pick diff 最小"与目录重排自相矛盾——
实测 Kazumi 的 store 住在 pages/*/controller/ 与 lib/modules/ 域目录，anime 六分法
（engine/network/repository/store/pages/player）对不上 Kazumi 的 13 个顶层目录，
services/network、webview、plugins、utils、bean、bbcode 在树里没有家，上游一个修复
要跨目录人工重放；②契约只有 UI 出口没有数据侧约定，统一书架缺收藏列与进度文案列，
M1 是零消费者假完成；③媒体会话有两个注册点、无唯一所有者；④目录数自报 21 实数 27，
core/downloads 与两个上游的下载子系统正面冲突（Venera 下载一体化进 comic_storage，
实测 lib/features 下没有 download 目录）——自己申报"可推迟"却画在 M1 树里。

---

## 3. 裁决

### 选谁：方案2「少一层是一层」

理由（按权重排序）：
1. **一票否决项下它最优**。"目录少而清晰"的终态（lib/ 根 6+1、典型 3 层）是三案中
   最低的，且它把"子目录出生条件""删除优先于保留"写成了纪律——这正是你要的
   "好整理"的制度化保障。
2. **用户画像的匹配度最高**。第一次做软件项目、极度在意"自己能看懂"：方案2 的壳与
   核心从你自己的 demo 01/02/04 长出来，每一行的来龙去脉你都知道；方案1 开局即接手
   409 文件陌生主干，方案3 要先接受 21~27 目录+契约/哨兵/六分法概念税。
3. **方案2 的三个最重攻击全部可修且不伤底子**（修法见下节嫁接），而方案1 的死穴
   （M1 与锁定决策 7 冲突、继承双基础设施）是结构性的，修了就不是方案1。

### 嫁接什么（点状，共 5 条）

| 嫁接 | 来自 | 为什么 |
|------|------|--------|
| ① `docs/upstream-map.md` 上游对照表（逐目录←上游路径 + fork remote + 前缀映射配方 + 剥离清单 + 基础设施归属表 + 每次 patch 后的 sed/grep 检查清单） | 方案1 | 方案2 的盲区是"模块移植后怎么跟上游修复"；这是方案1 最有价值的产物，A4/A5 两攻击的补救条目一并并入。M2 建立，活文档 |
| ② 模块内部镜像上游原始路径（anime/←Kazumi lib/、comic/←Venera lib/、music/←echo-api crate 形状） | 方案1（哲学）+ 方案3 攻击 C1（修法建议） | 同时解决方案2 的 B1（15-25 文件蓝图与 409 文件现实差一个数量级）和方案3 的 C1（六分法对不上上游）——且让锁定决策 6 的"上游修复可机械对照"从口号变成固定前缀映射。模块内部多不是我们的对称设计，是上游基因 |
| ③ 轻量契约 + registry 白名单（core/contract.dart 的 AppModule + app_registry.dart 唯一 import 模块处，升为第四条铁律） | 方案3 | "删模块=删目录+删一行"的机械性值得保留；C3 指出注册点分散的洞，白名单补上。砍掉方案3 的重目录与五成员 UI 契约膨胀，只留一个文件 |
| ④ 边界哨兵测试（test/architecture/boundary_test.dart，扫 import 断言四铁律） | 方案3 | 方案2 自认"边界靠约定不靠编译器"是最大代价；一个测试文件把约定变成机器断言，正中"自己能看懂、能整理" |
| ⑤ 统一表公共列补 progressText/starred + 双记账四条裁决规则（权威=模块库、写入点=持久化点、校正点=打开动作、壳只读公共列） | 方案3（C2 攻击的修法）+ 方案1（A1 攻击的洞察） | B2 的崩溃场景（ep4/ep5 分叉）必须有明文规则；demo 04 `main.dart:80-81` 本来就预告了"收藏升列"方向，提前到 M1 表设计 |

### 驳回什么（复核后不成立的攻击，共 3 条）

| 攻击 | 驳回理由 |
|------|---------|
| 「Kazumi 的 Flutter/Dart 基线与锁定决策 5 对不上（3.41.9 / >=3.3.4）」（方案3 攻击 6②） | **本次实测推翻**：2026-11-17 raw 拉取 Kazumi main `pubspec.yaml`，environment 为 `sdk: ">=3.10.0 <4.0.0"`、`flutter: 3.50.0`——与锁定决策 5 的"Flutter 3.50 / Dart >=3.10（跟 Kazumi）"完全一致。该批评家引用的数字有误（或取自旧 commit）。真正低的一方是 Venera-Next（实测 flutter 3.41.4 / sdk >=3.8.0），其代码搬入后以本项目环境约束为准，版本冲突按锁定决策 5 用 dependency_overrides 糊平——这正是锁定决策预判的场景 |
| 「Kazumi 把 media_kit 以 `path: ./media_kit` 仓库内 vendor，仓库会多出含源码的目录」（方案2 攻击 4 中针对 Kazumi 的部分） | **本次实测推翻**：Kazumi main pubspec 的 media_kit/media_kit_video 是 `git: url Predidit/media-kit + ref cd75bcf... + path ./media_kit` 的 git 依赖（path 仅用于定位 fork monorepo 内的子目录），不产生仓库内目录；"git url+ref 钉死 fork"由此确认为正统做法并写进依赖落位表。该攻击对 Venera 的 `rhttp: path: packages/rhttp` 部分成立，已体现在 M3 拍板项 |
| 「AudioService.init 必须写进 main.dart 启动清单，否则 M4 回头改 main 属于半重构」（方案2 攻击 3 的后半） | **本次实测推翻**：raw 拉取 Kazumi main `lib/main.dart`，其启动时序含 MediaKit.ensureInitialized、Hive init、windowManager 等，但**没有** AudioService.init——上游的媒体会话接线在 `services/player/audio_controller.dart`。M1 不引入无人使用的空初始化，M2 随番剧照搬上游接线即可，启动时序清单不需要预留 audio_service 位。该攻击的前半（官方 audio_service 不支持 Windows、须用 Predidit audio_service_win fork）成立，已采纳为依赖组合+唯一 handler 规则 |

### 攻击逐条处置总表（18 条全数复核）

| 攻击 | 复核 | 落点 |
|------|------|------|
| A1 M1 双库双页双写 | 成立（弃选方案1 的主因；其"插桩挂持久化单点"洞察被吸收） | 复盘 §2；architecture §3.1 规则② |
| A2 rhttp 不在整树+Rust 工具链 | 成立（rhttp path 声明与 README Rust 1.80+ 要求均本次实测） | architecture §8 依赖表、§9 拍板项 5 |
| A3 TS 直跑被依赖链证死 | 成立 | architecture §4.4（Dart 重写为主，novel/js/ 语义冻结） |
| A4 cherry-pick 配方毛糙 | 成立（相对导入实测试样属实） | architecture §7 固定工序；upstream-map.md 配方 |
| A5 双基础设施缺归属表 | 成立 | architecture §3.4 排障地图 + upstream-map.md |
| B1 体量差一个数量级 | 成立 | directory-layout §1（模块镜像上游） |
| B2 双记账无裁决规则 | 成立 | architecture §3.1 四条规则、§3.2 公共列 |
| B3 audio_service 无 Windows | 核心成立；"init 进 main 清单"部分被实测推翻 | architecture §6.2、§1.1；复盘驳回③ |
| B4 依赖篮子 | 成立（Kazumi media_kit part 被实测推翻） | architecture §8 依赖落位表；复盘驳回② |
| B5 cherry-pick 字面不可执行 | 成立 | architecture §7 明示现实+拍板项 4 |
| B6 Plan B 零依赖是假象 | 成立 | architecture §4.4（TS 直跑降级为拍板项） |
| B7 Android 无法跳过编译文件 | 成立 | directory-layout §1 window/ 单文件运行时判断；architecture §1 第 3 条、§6.1（修法经独立复审更正为运行时判断，见文末修订记录 A13） |
| C1 Kazumi 形状对不上 | 成立（修法建议被采纳为嫁接②） | directory-layout §1；architecture §4.1 |
| C2 契约缺数据侧 | 成立（公共列修法被采纳为嫁接⑤） | architecture §3.2 |
| C3 媒体会话无唯一所有者 | 成立（"聚合器抽象"的修法被更轻的"唯一 handler + core 注册槽"替代，落位经独立复审定死，见文末修订记录 A5/A14） | architecture §6.2；core/media_session.dart；app_registry 注册 |
| C4 core/downloads 空架子+数错 | 成立（砍掉 M1 的 downloads；download.dart 推迟 M2 由第一个消费者定形状） | directory-layout §2/§4；architecture §3.3 |
| C5 flutter_qjs 单版本/两宿主/TS 构建链 | 成立（TS 部分随备选降级消解；两 QuickJS 实例为 M5 已知成本） | architecture §4.4、§9 |
| C6 命名陷阱/版本基线/EchoMusic 非 Flutter | ①③成立（命名陷阱进 upstream-map；EchoMusic 非 Flutter 与"网络层重写"决策一致）；②**驳回**（见上） | architecture §4.1 命名陷阱提醒；复盘驳回① |

---

## 4. 本次会话实际执行的核实（可复跑）

裁决不基于印象，以下核实全部在 2026-11-17 执行：

| # | 命令 / URL | 结果 |
|---|-----------|------|
| 1 | `ls -la /c/da && ls -R /c/da/demos`（工作区现状） | demos/ 4 个 demo（01/02/04 各一个 main.dart，03 另附 verify_regex.js 对照脚本）+ README + preview.html；tools/ 3 个 CI 校验脚本；.github/workflows/ci.yml——directory-layout 已按此保留 |
| 2 | Read demos 01/02/03/04 全文 | 批评家引用的行号全部属实（01:37-38 壳职责、01:85 switch、01:293 LibrarySection、04:14 不迁移、04:27-49 表、04:80-81 收藏先用 payload） |
| 3 | WebFetch `raw.githubusercontent.com/Predidit/Kazumi/main/pubspec.yaml` | sdk >=3.10.0 / flutter 3.50.0；media_kit git ref cd75bcf…；audio_service ^0.18.15 + audio_service_win ref 8ad650c… + audio_service_mpris ref d30b53f…；hive_ce ^2.16.0 |
| 4 | WebFetch `raw.githubusercontent.com/CyrilPeng/Venera-Next/main/pubspec.yaml` | flutter 3.41.4 / sdk >=3.8.0；`rhttp: path: packages/rhttp`；flutter_qjs git CyrilPeng ref f5a1f20…；dio ^5.11.1 |
| 5 | WebFetch GitHub contents API `repos/Predidit/Kazumi/contents/lib/modules` | 13 个域目录：bangumi/character/characters/collect/comments/danmaku/download/history/my/plugin/roads/search/staff |
| 6 | WebFetch `raw.githubusercontent.com/gedoor/legado/main/README.md` | 官方仓库已清空，README 仅剩侵权风险公告与阅文知识产权保护链接 |
| 7 | WebFetch `pub.dev/packages/rhttp` | v0.18.0；平台徽章五平台全绿但 README 明确要求本机 Rust 1.80+（rustup）与 Android NDK，未提供预编译二进制；基于 flutter_rust_bridge + reqwest |
| 8 | WebFetch `raw.githubusercontent.com/Predidit/Kazumi/main/lib/main.dart` | 启动时序含 MediaKit.ensureInitialized / Hive.initFlutter(失败进 StorageErrorPage) / windowManager；**无** AudioService.init；ModularApp 为路由主干 |
| 9 | WebFetch contents API Venera-Next `lib/` 顶层 | 8 条目：app_runtime / app_shell / components / features / foundation / network / routing / main.dart |
| 10 | WebFetch contents API EchoMusicNext `crates/echo-api/src/` | domain.rs / domain/ / error.rs / lib.rs / module/ / util/ |

未做（机器无 Flutter/Dart，属规划期约束）：任何编译/运行验证；Kazumi/Venera 全库
逐文件统计（沿用批评家实测数字 409/561，标注"以开工当天实数为准"）。

---

## 5. 遗留的开放问题（等你拍板）

完整清单见 architecture.md §9，速览：

1. **drift vs raw sqlite3**（统一库）——临时决定：drift；
2. **MobX 是否接受**——临时决定：接受（demo 02 方向）；
3. **flutter_modular 是否引入**——**M1 不引入**（M1 壳没有嵌套路由消费者，违背
   「无消费者不建」），M2 搬 Kazumi 路由前再拍（Kazumi 路由主干实测 ModularApp；
   注意"页面满篇 Modular.get"的论据已被实测推翻，理由是路由不是 DI）；
4. **cherry-pick 执行形式**：接受"fork 上游 + 固定前缀映射 patch 重放"吗（锁定决策 6
   的意图不变，字面 git cherry-pick 仅方案1 布局可成立）；
5. **rhttp 与 Rust 工具链**：M3 需要本机 rustup（实测 README 要求 Rust 1.80+，无预编译
   二进制）——装工具链≠学 Rust，但需你明示接受；备选 dio 重写代价大不推荐；
6. **legado 参照 fork 选定**（官方仓库已清空，实测仅剩侵权公告）；
7. **Bangumi 同步体系 M2 默认不搬**，后续按需补；
8. **番剧/音乐唯一 AudioHandler**：落位已定死（core/media_session.dart 接口+注册槽，
   handler 实现=Kazumi audio_controller 经 app_registry 注册），M4 前只拍板切换细节；
9. **仓库名/pubspec name**（决定 import 前缀映射 sed 目标串，占位 aggregator）。

两项已记录的已知成本（非问题）：双状态体系（MobX vs comic 无库）、双基础设施
（网络/存储/webview 各两套）——归属表 architecture §3.4 + upstream-map.md 承接。

---

## 6. 下一步（你醒来后）

1. 先拍板 architecture.md §9 的 9 项——开工当天前至少拍板**第 1（drift）、2（MobX）、
   9（仓库名）三项**，M1 开工即用（drift 不拍，开工当天 core/db.dart 就没有合法写法）；
   第 3（flutter_modular）已改为 M2 开工前拍板，M1 不引入；
2. 开工当天照 [directory-layout.md](directory-layout.md) §2 的"M1 行"建目录，
   素材从 demos/ 里取（对应关系见其 §5）；
3. M2 开工前建立 docs/upstream-map.md（配方模板在 architecture.md §7）；
4. 上游数字（文件数、commit ref）开工当天全部重核一遍——本文所有实测
   均标注了日期，上游在动。

---

## 7. 独立复审与修订记录（2026-11-17 第二轮）

三份文档定稿前经一轮独立复审（25 条意见，其中 2 条重复提交、5 条同族合并），
逐条复核后修订。**所有事实性声称均由本次会话重新实测**，方式与结论随条记录。
除 A13（条件导入药方错误）与 A5/A14（共享件落位与铁律冲突）属于"复审揭示硬伤、
修正结构落位"外，其余均为事实纠错与清单补齐，不动裁决者的结构级决策。

### 吸收并落实（A1–A22）

| # | 意见 | 处置 | 本次实测依据 |
|---|------|------|-------------|
| A1 | architecture §3.2 表定义是编译不过的单调用伪代码 | 代码块全列改双调用（`text()()` / `textEnum<MediaType>()()`），并加语法注记 | drift 官方 getting-started 实测示例即双调用；**另发现 demo 04 自身 `main.dart:31` 同为单调用**（复审只说对了一半），已在 §3.2 注记"落地以本节为准" |
| A2 | directory-layout 树缺 `app_registry.dart`，shell 8≠7 | 树补该文件（注明铁律④载体）；因 A13 window/ 由双文件并成单文件，shell 文件数改为 **7**，architecture §1 补可点数清单对账 | 文档自证 |
| A3 | §4.2「7 个子树」自相矛盾 + Venera 剥离清单缺失 | 改为"5 个业务子树"；补 app_runtime/app_shell 剥离清单 | codeload 全库解包 grep：**app_runtime（31 文件）与 app_shell（5 文件）的 import 引用面均只有 main.dart 一处**，整域剥离不伤业务子树；bootstrap 装配由 comic_entry.dart 重接 |
| A4 | §2 增长表子树计数与 §1 树对不上 | anime 改 **10**（补 repositories/）、music 改 **5**、comic/novel 不变，全部标注"清单=§1 树 ××段"，数字只在一处维护 | Kazumi lib/ 顶层 contents API 实测 10 目录 |
| A5 | AudioHandler 落位与铁律②③冲突，矛盾被推迟到 M4 | 落位在 §6.2 定死：core/media_session.dart 最小接口+注册槽（M2 建立，M1 不建空架子），唯一 handler 实现=Kazumi audio_controller 原样住 anime/、经 app_registry 注册；拍板项 8 只剩切换细节 | 文档自证（铁律冲突推演） |
| A6 | 弹窗 webview「壳层借用 anime/webview/」无合法路径 | §3.4 改为"模块自供（webview 场景在模块自身页面内闭环），壳不借用"；若壳确需借用的唯一通道=app_registry 白名单特批+哨兵行内注释登记，一例一登记，当前零例外 | 文档自证（铁律④推演） |
| A7 | 拍板项 3 与 §4.1 剥离清单对 app_module.dart 给出相反答案 | 拍板项 3 措辞改为"在 shell 侧**重组** Kazumi 路由表时结构对得上"（app_module.dart 维持不搬） | 文档自证 |
| A8 | §8 依赖表缺 M1 当天就要用的三个包 | 补 window_manager ^0.5.1 / tray_manager ^0.5.0 / path_provider ^2.1.5（M1 行）；drift 行补拍板期限对齐拍板项 1 | Kazumi pubspec 实测三包版本 |
| A9 | 目录树缺 packages/ | 树根补 packages/ 行，标注【M3·拍板项 5 通过才建】 | 文档自证 |
| A10 | services/platform/ 两处口径不一且"剥离给壳"方向错误 | 统一为"不搬：窗口/托盘由 shell/window/ 全新实现取代，非移植"；architecture 与 directory-layout 同步 | 文档自证 |
| A11 | 复盘 §6「前 2、3、9 三项」指代不明且漏了拍板项 1 | 改为直写"第 1（drift）、2（MobX）、9（仓库名）三项"，并注明第 3（flutter_modular）已按 §8 R5 改为 M2 拍板 | 文档自证 |
| A12 | 核实表 #1「4 个单文件 demo」与实况不符 | 改为"03 另附 verify_regex.js 对照脚本" | `ls -R /c/da/demos` 实测 |
| A13 | **条件导入双文件机制错误**（Dart 条件导入只有 dart.library.* 条件，分不开 Windows 与 Android） | window/ 改单文件 window.dart + 运行时平台判断（Kazumi 同款）；architecture §1/§1.1/§6.1、directory-layout 树与 §2、本文 B7 行同步改写 | Kazumi main.dart 实测 `if (isDesktop())` 运行时分支，无条件导入；drift 之外另核 window_manager 无 Android 实现（pub.dev） |
| A14 | 共享件落位三处违反四铁律（webview 弹窗、AudioHandler），M2 落地当天哨兵必炸 | 与 A5/A6 合并落实；顺带修正 §1.1「（§6.3）」→ §6.2；**不采纳**其"扩铁律④白名单、树补 shell/audio/ 与 shell/webview_dialog.dart"备选——见 D3 | 文档自证 |
| A15 | Kazumi 搬运清单漏 repositories/、剥离清单漏 hive_registrar.g.dart | 搬运清单补 repositories/（10 子树）；hive_registrar.g.dart 定性"不属壳、随搬"——实测调用链在 `services/storage/storage.dart:150`（GStorage.init 内），随搬闭环，M2 验收专测一次 | Kazumi contents API 实测 lib 顶层与 repositories/ 6 文件、storage.dart 内容 |
| A16 | §8 依赖表缺 M2/M3 的 fork/版本事实 | 补 webview_windows（ref `2b3306d2...`）、desktop_webview_window（ref `2b25bd7d...`）、hive_ce_flutter ^2.3.3、flutter_modular ^7.1.0（M2·拍板项 3，按 §8 R5 调整）、flutter_inappwebview 家族（Venera 钉 ref `0aaf7a0...`）、sqlite3/sqlite3_flutter_libs、url_launcher；表加"引入"列；fork 台账进 upstream-map.md | Kazumi 与 Venera pubspec/dependency_overrides 实测 |
| A17 | Venera 四件套漏本地包 | 四件套③扩为 **8 个 path 包**（比复审说的 3 个还多 5 个：photo_view/share_plus/venera_native/venera_saf/webdav_client），lib/ 内被引用 20 处缺一编译不过 | Venera codeload 解包实测 packages/ 8 目录与 pubspec |
| A18 | 三处子树计数漂移 + app_runtime 零交代 | 与 A3/A4 合并落实；app_runtime/app_shell 处置写死（A3），同步/无头体系并入拍板项 7 泛化，不新增拍板项 | 同 A3 |
| A19 | app_registry.dart 不在树（与 A2 重复提交） | 同 A2 | 文档自证 |
| A20 | Venera assets「reader 资源」描述错误 | 四件套②改逐文件清单+必需级（init.js/translation.json/opencc.txt 必需），合并规则=相对路径原样保持（rootBundle 硬编码路径） | 解包实测 assets 8 文件；init.js 被 `foundation/js_engine.dart:450`、`image_processing.dart:329` 加载 |
| A21 | Kazumi 侧 assets 零交代（静默缺失风险） | §4.1 补 assets 映射：images/、images/logo/、shaders/、statements/、licenses/ech_http/ 五处，原路径并入 | Kazumi pubspec assets 段实测 |
| A22 | window_manager 无单实例功能；尺寸位置记忆需自行持久化 | §6.1 与树注释改为"单实例=runner 互斥体或第三方包，M1 拍板做不做"；记忆=自行持久化 | window_manager README 实测：唯一提及是自实现教程链接 |

（同族低项一并吸收：audio_service_mpris 为 Linux 死依赖 → §6.2 加 grep 去留规则；
lib/src/ 惯用法零交代 → §4 负面清单补行并注明"entry 唯一对外是约定+哨兵非语言机制"；
any-reader legado 包半成品 → §4.4 标注 AnalyzerHtml.ts 0 字节、降为规则语义旁证、
M5 开工当天重核。）

### 驳回或部分驳回（D1–D4）

| # | 意见（或其子建议） | 驳回理由 |
|---|------------------|---------|
| D1 | A5 复审建议的主选项"handler 完整实现住 core/" | core 完整实现必然 import 模块（handler 要触达播放器），违反铁律①；采纳其备选"接口在 core、实现经 app_registry 注入"——既守住铁律，又不改动 Kazumi 文件（上游 patch 仍可机械重放） |
| D2 | A6 复审建议的"AppModule 契约加 webviewFactory 成员" | 该成员当前无消费者（违背本项目"无消费者不建"纪律，C4 同款教训）；实际场景里模块 webview 在模块自身页面内闭环，壳借用场景为零——写明"备而不用"的特批通道比预设契约成员更轻 |
| D3 | A14 复审建议"铁律④白名单扩为 app_registry + 指定共享出口文件；树补 shell/audio/、shell/webview_dialog.dart" | 扩白名单稀释"删模块=删目录+删一行"的机械性（铁律④的存在理由）；shell/audio/ 是空架子（handler 住 anime 原位、壳只做一行注册，无需新目录） |
| D4 | any-reader 项复审的旁证描述"jsoup 手写 DOM 层在当前上游找不到实体"（主旨已吸收进上文同族段） | **实测推翻**：DOM 层实体就在 `packages/legado/src/javascript/jsoup/`（Element/Elements/Jsoup.ts，2026-11-17 解包验证）；采纳其主旨（AnalyzerHtml.ts 确为 0 字节、any-reader 降为旁证、M5 开工重核），§4.4 按实测事实改写 |

### 修订后新增的核实（本节，2026-11-17 执行）

| 手段 | 对象 | 结论 |
|------|------|------|
| GitHub contents API | Kazumi lib/ 顶层、lib/repositories/、lib/services/storage/storage.dart、lib/main.dart | 10 目录+6 根文件；repositories/ 6 文件；registerAdapters 在 GStorage.init；桌面窗口=运行时分支 |
| GitHub contents API | Kazumi/Venera pubspec.yaml 全文 | A8/A16/A21 全部版本与 ref |
| codeload 解包 + grep | Venera-Next 全库 | app_runtime/app_shell 引用面仅 main.dart；packages/ 8 本地包；assets 8 文件与 init.js 加载点 |
| codeload 解包 | aooiuu/any-reader master | AnalyzerHtml.ts 0 字节；jsoup DOM 层实体在 src/javascript/jsoup/ |
| WebFetch | drift 官方 getting-started | 列构造器双调用语法 |
| jsdelivr CDN | window_manager README | 无内置单实例 |
| 本地 `ls -R /c/da/demos` | 工作区 | 03 含 verify_regex.js |

未做（机器无 Flutter/Dart，规划期约束不变）：任何编译/运行验证；本节的 grep
结论均为静态源码检查。

---

## 8. 2026-11-17 晨间修订（接缝补齐，不改裁决结论）

定稿后把三份文档与凌晨交付的 CI（`.github/workflows/ci.yml`）、以及全部 demo 行号
逐项对照，发现的问题全部属于"交付物之间的接缝"与"示例偏差"，不触及方案选择。
逐条修订如下：

| # | 问题 | 修订 |
|---|------|------|
| R1 | **CI 与"上游镜像"互相拆台**：`dart format .` / `analyze --fatal-infos` / `dart fix` 覆盖全库，M2/M3 搬入 409/561 个上游文件后必红；修它们又等于改写上游文件、毁掉 §7 的机械 patch 重放 | architecture 新增 **§11**：自写代码严格门、镜像目录只守 error；ci.yml 同步改成分域执行 |
| R2 | **GPL-3.0 法律件缺位**：四个上游均为 GPL-3.0，整树搬运并分发必须 GPL-3.0 + 署名，仓库却无 LICENSE/NOTICE | architecture 新增 **§12**；directory-layout 树与 M1 行加入 LICENSE/NOTICE/README |
| R3 | **铁律用 `modules/*` 指代不存在的 `lib/modules/`**（文档自己又警告过这个词不存在） | 铁律表与全文改为四条具体目录，并加"写法约定"段，哨兵按具体路径写 |
| R4 | **AudioHandler 落位与"entry 唯一对外"冲突**：app_registry 直连 `audio_controller.dart`，而 §3.4 声称"零例外" | 改为 `anime_entry.dart` 以 getter 暴露 handler；不给白名单开例外 |
| R5 | **flutter_modular 建议 M1 引入**，违背本项目"无消费者不建/先能跑后抽象" | 改为 M1 不引入（纯 Navigator），M2 开工前再拍；§5、§6、§9、§8 依赖表同步 |
| R6 | **示例偏差**：demo 01 时间线实为 `124-131`；demo 04 `:72` 枚举列与 `.name` 比较类型错配、`:85` 落位与 `core/db.dart` 不一致 | architecture §3.2 加注记并修正行号；demo 保持原样（选型材料），文档注明"以此为准" |
| R7 | **台账数字对不上**：正文说 25 条意见，处置表为 A1–A22 + D1–D4 共 26 行 | 口径说明：处置表按**处置单元**计行，重复提交（A19=A2）与同族合并（A18 等）已并入对应行，不与原始意见条数一一对应 |

**验证**：ci.yml 改动后跑 `node tools/validate-ci-yaml.mjs .github/workflows/ci.yml`
与 `node tools/test-validate-ci-yaml.mjs`（结构校验，不替代真实运行）；文档改动做
交叉引用检查（§ 编号、行号、目录树条目数）。仍未做：任何编译/运行验证（机器无
Flutter/Dart），CI 首次推送的实际结果需上线当天确认。
