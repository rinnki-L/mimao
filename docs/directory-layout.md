# 目录布局（directory-layout.md）

> 状态：规划期设计文档。本文是"好整理"要求（**宁可目录少而清晰，不为对称或美观造空架子**）
> 的核心保障：完整目录树 + 每目录一句话职责 + 增长规则 + 新目录纪律。
> 架构与边界理由见 [architecture.md](architecture.md)，裁决过程见 [plan-retrospective.md](plan-retrospective.md)。
> 撰写日期：2026-11-17。

---

## 0. 三条总原则（本布局的宪法）

1. **目录是长出来的器官，不是画出来的对称图**：开工当天只建 shell/ 和 core/，
   每个里程碑长出一个模块目录；子目录只在文件多到命名分区撑不住时才出生。
2. **模块内部的形状不归我们设计**：番剧模块照 Kazumi 的 lib/ 长，漫画模块照
   Venera-Next 的 lib/ 长——因为它们的基因来自上游，上游的修复 patch 才能按固定
   前缀映射机械对照（architecture.md §7）。模块内部目录多不是我们的对称设计，
   是上游自身的形状，每一步都能在 `docs/upstream-map.md` 查到出处。
3. **lib/ 根永远一眼装得下**：终态 6 个目录 + 1 个文件（shell、core、anime、comic、
   music、novel + main.dart），不用滚动就能记住。"要理解的地图"始终只有一屏。

---

## 1. 完整目录树（终态展望，逐级标注来源里程碑）

```
聚合App/                                # 仓库根（pubspec name 占位 aggregator，拍板项 9）
├── pubspec.yaml                        # 依赖唯一入口；基线 Flutter 3.50 / Dart >=3.10（Kazumi main 实测一致）；
│                                       #   fork 包一律 git url+ref 钉死（architecture.md §8）
├── analysis_options.yaml               # lint 从宽：不开 always_use_package_imports（上游镜像含相对导入，
│                                       #   边界由哨兵测试把守，不靠 lint——architecture.md §2；CI 分域门禁见 §11.1）
├── LICENSE  NOTICE  README.md          # 【M1】GPL-3.0 全文 + 上游署名/改动清单 + 来源与许可段（architecture.md §12）
├── .gitignore                          # 【M1】flutter create 模板起手；生成物必须入库，不得忽略 *.g.dart（§11.2）
├── docs/                               # 【M0·已存在】设计文档（本三份）；M2 起新增 upstream-map.md
├── demos/                              # 【M0·已存在】四个选型 demo 原样保留，勿删（选型依据与教学材料）
├── tools/  .github/                    # 【M0·已存在】CI 校验脚本与 workflow，原样保留
├── assets/                             # 【M1】应用图标/字体；M3 逐文件并入 Venera assets（init.js/translation.json/
│                                       #   opencc.txt 必需，tags*.json/app_icon.png 随功能；相对路径原样保持，
│                                       #   见 architecture.md §4.2 四件套②）
├── packages/                           # 【M3·拍板项 5 通过才建】Venera 的 8 个本地 path 包 vendor（rhttp 需 Rust
│                                       #   工具链；photo_view/share_plus/desktop_webview_window/
│                                       #   flutter_inappwebview_windows/venera_native/venera_saf/webdav_client 纯随搬）
├── windows/                            # 【M1】flutter create 生成；第一打磨平台（runner 常量/最小尺寸/图标）
├── android/                            # 【M1 生成】第二优先打磨（M2 后才动）
├── test/
│   ├── architecture/
│   │   └── boundary_test.dart          # 【M1】边界哨兵：四条铁律的机器断言（architecture.md §2）
│   ├── core/
│   │   └── library_test.dart           # 【M1】统一库 CRUD / payload 往返 / starred 筛选单测
│   └── modules/                        # 【M2 起】随引擎生长；番剧规则引擎单测先行（demo 03 思路）
└── lib/
    ├── main.dart                       # 【M1】唯一入口：启动时序五步（architecture.md §1.1）+ 四条铁律注释
    ├── shell/                          # 【M1】MD3 壳：导航+承载+桌面窗口，不含业务（M1 共 7 个 Dart 文件，
    │                                   #   与 architecture.md §1 清单可点数对账）
    │   ├── app.dart                    # MaterialApp + MD3 主题（M2 若拍板引入才装 ModularApp）
    │   ├── home.dart                   # NavigationRail 五目的地 + 内容区查表（demo 01 main.dart:59-92 骨架）
    │   ├── shell_store.dart            # 壳级 MobX store（demo 02 ShellStore 升级；口味问题①待拍板）
    │   ├── library_page.dart           # 「我的」统一时间线：只读 core 投影（demo 01 main.dart:293 真身）
    │   ├── settings_page.dart          # 应用设置 + 各模块设置入口
    │   ├── app_registry.dart           # 【M1】全库唯一允许 import 四个模块目录的白名单文件（铁律④载体；
    │                                   #   M2 起经它注册唯一 AudioHandler——architecture.md §6.2）
    │   └── window/
    │       └── window.dart             # 【M1】窗口/托盘单文件 + 运行时平台判断（桌面才触碰 window_manager/
    │                                   #   tray_manager，Android 走空操作；Kazumi 同款，非条件导入）
    │                                   #   单实例需 runner 互斥体或第三方包，M1 拍板做不做（§6.1）
    ├── core/                           # 【M1】跨模块共享物；铁律：永不 import shell 与 modules
    │   ├── contract.dart               # AppModule 契约（label/icon/homePage/settingsPage）——模块唯一对外面
    │   │                               #   （"唯一对外"是约定+哨兵断言，非 Dart 语言机制；本仓库是应用
    │   │                               #   不是包，不建 lib/src/ 私有层——§4 负面清单）
    │   ├── db.dart                     # AppDb（drift）：media_entries + settings kv 两张起步表（临时决定①）
    │   ├── library.dart                # 统一书架读写唯一 facade：模块在"持久化点/打开点"调它（规则①-④）
    │   ├── settings.dart               # 应用设置 kv 读写（同 DB 一张表，不加新依赖）
    │   ├── media_session.dart          # 【M2】唯一 AudioHandler 的最小接口+注册槽：番剧注册实现、
    │   │                               #   音乐经此触达（四铁律全合规的落位，architecture.md §6.2）
    │   └── download.dart               # 【M2 或不建】统一下载形状由番剧下载移植时定（可投影可砍，见 architecture §3.3）
    ├── anime/                          # 【M2】番剧＝Kazumi lib/ 的域内镜像（形状照上游，不自创；10 个上游子树）
    │   ├── anime_entry.dart            # 实现 AppModule，本模块唯一对外文件（铁律④出口）；并暴露
    │   │                               #   唯一 AudioHandler 的 getter（壳只经此拿，§6.2）
    │   ├── anime_module.dart           # 路由子模块挂载点（若拍板 flutter_modular）
    │   ├── pages/                      # ← Kazumi lib/pages/（播放器/搜索/详情/时间表/设置…160+ 文件）
    │   ├── services/                   # ← Kazumi lib/services/（player/download/network…；platform/ 不搬：
    │   │                               #   窗口/托盘由 shell/window/ 全新实现取代，非移植）
    │   ├── modules/                    # ← Kazumi lib/modules/（13 个域 store+模型；collect 的 sync 管线默认不搬）
    │   ├── repositories/               # ← Kazumi lib/repositories/（collect/download/history 等 6 个 repository）
    │   ├── bean/  request/  utils/  webview/  plugins/  bbcode/   # ← Kazumi 同名整树
    ├── comic/                          # 【M3】漫画＝Venera-Next lib/ 的域内镜像（5 个业务子树；
    │                                   #   app_runtime/app_shell 两装配域剥离不搬，architecture.md §4.2）
    │   ├── comic_entry.dart  comic_module.dart
    │   ├── features/                   # ← Venera lib/features/（reader ~83 文件、comic_source、local_comics…）
    │   ├── foundation/                 # ← Venera lib/foundation/（appdata/js_engine/js_pool/file_system…）
    │   ├── components/                 # ← Venera lib/components/
    │   ├── network/                    # ← Venera lib/network/（dio+rhttp+cookie_jar；rhttp 供应=拍板项 5）
    │   └── routing/                    # ← Venera lib/routing/（模块内路由参数）
    ├── music/                          # 【M4】音乐＝EchoMusicNext crates/echo-api 的 Dart 重写（自写，非移植）
    │   ├── music_entry.dart  music_store.dart
    │   ├── api/                        # ← echo-api src/module/：一端点一文件
    │   ├── models/                     # ← echo-api src/domain(.rs)/：曲目/歌单/歌词模型
    │   ├── client/                     # ← echo-api src/util/：登录态+签名+加密（对照 Rust 逐函数翻译，Rust 只读）
    │   ├── player/                     # media_kit 音频 + audio_service（唯一 handler 通道，architecture §6.2）
    │   └── pages/                      # 歌单/搜索/播放页
    └── novel/                          # 【M5】小说＝legado 书源引擎 Dart 重写（M1 不建目录，见 §2）
        ├── novel_entry.dart            # 出口占位（M5 初建时即带）
        ├── engine/                     # 搜索→发现→目录→正文流水线
        ├── analyzer/                   # ← 拍板项 6 选定的 Kotlin fork 为主对照；any-reader packages/legado
        │                               #   仅规则语义旁证（实测半成品：AnalyzerHtml.ts 0 字节；其手写
        │                               #   DOM 层实体在 src/javascript/jsoup/，对应时一并看）
        ├── cache/                      # 正文缓存/离线下载（桌面直写磁盘）
        └── js/                         # flutter_qjs 宿主：只跑书源内嵌 JS 片段（语义已冻结，architecture §4.4）
```

> 树中所有 `←` 指向上游原始路径；逐目录的"上游仓库+commit+映射配方+剥离清单"
> 全文在 `docs/upstream-map.md`（M2 建立，活文档，每里程碑补一节）。

---

## 2. 增长规则：开工当天建什么、每个里程碑长什么

| 时点 | lib/ 根状态 | 动作 |
|------|------------|------|
| **开工当天（M1）** | `main.dart` + `shell/` + `core/`，仅此而已 | flutter create（windows/android 两平台）；写 pubspec 基线（M1 当天就要装：window_manager、tray_manager、path_provider，mobx 组，drift 若拍板项 1 通过——见 architecture §8 的 M1 行；**不引 flutter_modular**，拍板项 3 已改为 M2 再定）；**shell 7 文件**（app.dart、home.dart、shell_store.dart、library_page.dart、settings_page.dart、app_registry.dart、window/window.dart，可点数）+ core 4 文件（contract/db/library/settings）；test/architecture 哨兵 + test/core 单测；**LICENSE/NOTICE/README/.gitignore 落地**（architecture §12）、生成物（`*.g.dart`）随提交入库。**novel/anime/comic/music 目录一律不建**——未接入的模块在壳的目录表里显示占位页（home.dart 的 switch 默认分支："该模块尚未接入"），不需要空目录。**完成条件含 CI 五 job 全绿** |
| **M2 番剧** | + `anime/`（10 个子树，清单=§1 树 anime/ 段） | Kazumi 镜像搬运（architecture §4.1：10 子树 + hive_registrar.g.dart 随搬 + assets 五处映射）+ upstream-map.md 建立 + core/media_session.dart 接线 + core/download.dart 形状拍板；CI 全绿 |
| **M3 漫画** | + `comic/`（5 个子树，清单=§1 树 comic/ 段） | Venera 镜像 + assets 逐文件并入（相对路径原样）+ packages/ 8 个 vendor 本地包（rhttp 依赖拍板项 5）+ dependency_overrides 糊冲突；**CI 构建 job 补 Rust/NDK 前置（architecture §11.4）**，CI 全绿 |
| **M4 音乐** | + `music/`（5 个子树，清单=§1 树 music/ 段） | 自写重写，无新大依赖（media_kit 已在；经 core/media_session.dart 触达唯一 handler）；CI 全绿 |
| **M5 小说** | + `novel/`（4 个子树，清单=§1 树 novel/ 段） | Dart 重写为主；engine 内部是否再分域（如 parser/）届时按 §3 纪律现场定，现在不预留；CI 全绿 |

**验收一个里程碑的标准动作**：`ls lib/` 仍然一屏装下（≤7 条目）；哨兵测试绿；
**CI 五个 job 全绿**（architecture §11.3）；旧功能不坏（原则 6：永不进入"重构到一半不可用"）。

---

## 3. 新目录纪律（何时才允许新增目录）

1. **lib/ 根新增目录的唯一许可**：对应一个里程碑（anime/comic/music/novel）或
   上游整树镜像。除此之外任何"为了整齐"的根目录（lib/app、lib/common、lib/shared、
   lib/utils 这类）一律不许建——工具函数去处：壳用 shell/ 内平铺文件，模块用自己的
   上游 utils 子树，core 的辅助跟 core 文件平铺。
2. **模块内新增子目录的出生条件**（继承底子方案的存活条款）：同一层文件数 > 8
   且按名能自然分组时才允许开子目录；不达标的先平铺。
   实证上界参考：Venera-Next 的 foundation/ 平铺 30+ 文件（实测 87 条目的目录）仍可用，
   说明平铺有真实上限，但上限远比直觉高——宁可晚开目录，不要早开。
3. **自写模块（music/novel）内部**照 §1 树上的既有子目录落位；确需新子目录时
   先在这里登记一句理由再建。
4. **删除优先于保留**：任何目录若被搬空/合并（如 core/download.dart 若判定不需要），
   用一个"删除提交"明确删掉，不留空壳——空架子比没有架子更伤"能整理"。
5. **一切目录变动在 git 里单独成提交**（一个提交只做搬移不做修改），让
   "整理"在历史里可追溯、可回滚。

---

## 4. 刻意不建的东西（负面清单，防止未来手痒）

| 不建 | 理由 |
|------|------|
| `lib/app/` + `lib/core/` + `lib/modules/` 三层嵌套（方案3 形状） | 实测数出来 27 个目录、概念税最重；我们用"模块与 shell/core 平列"少一层 |
| `core/downloads/`、`core/settings/`、`database/tables/`（方案3 M1 树） | 前两个无消费者（上游下载/设置各自原样），第三个一张表不值得一个目录——攻击 C4 实证 |
| 统一内容模型层 | 锁定决策：不提前设计统一内容模型；投影表 + payload 已覆盖 |
| 共享播放器抽象层 | media_kit 包本身就是共享内核；番剧（视频+弹幕）与音乐（后台+SMTC）差异太大，先各写各的，出现真实共享需求再上提（"先能跑后抽象"） |
| `lib/modules/` 分组层 | 四个模块目录直接平列，模块名即分组；若未来加第五种媒体导致根目录到 10 个左右，再承认 modules/ 层该回来（届时是显式决定，不是欠账） |
| `lib/src/` 私有层 | 本仓库是应用不是包，没有对外 API 面需要遮蔽；模块可见性由 `*_entry.dart` 出口 + 铁律④哨兵测试承担（约定+机器断言，不是 Dart 语言机制——Dart 没有 per-file 私有） |
| 任何现在用不到的平台目录/空架子 | 不维护的目录不建；flutter create 只留 windows/android 两个我们真正打磨的平台（仓库根 `packages/` 唯一例外：M3 拍板项 5 通过才建，见 §1 树） |

---

## 5. 本布局与 demos 的对应关系（开工当天的源代码素材）

- `shell/home.dart` ← demo 01 `main.dart:59-92`（NavigationRail + switch）骨架照搬；
- `shell/shell_store.dart` ← demo 02 的 ShellStore 写法升级（StatefulWidget 字段搬进 @observable Store）；
- `shell/library_page.dart` ← demo 01 `main.dart:293-313` LibrarySection 真身化；
- `core/db.dart` ← demo 04 `main.dart:27-49` 表定义 + 本项目新增 progressText/starred 两列
  （见 architecture.md §3.2）；
- 番剧规则引擎单测的方法论 ← demo 03（规则=数据、引擎=解释器，130 行微缩流水线）。

demos/ 目录原样保留：它们是选型依据，也是将来给"明天的自己"讲为什么的最短材料。
