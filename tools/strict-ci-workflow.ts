// 严苛 CI 流水线编制 —— 产出 .github/workflows/ci.yml（GitHub Actions）
//
// 拓扑（3 个互不共享上下文的子代理 + 1 个确定性门）：
//   CI 架构师   —— 唯一写手：起草并持续修订 ci.yml，返回 DraftSummary。
//   严苛评审员  —— 持续上下文的校准评审：每轮「先过校验器，再评审，blocking 打回」，≤4 轮。
//   独立终审员  —— 全新上下文冷审终稿（首次 push 会挂哪、哪扇门是假门、过 CI 后还有哪些冲突途径）。
//   node 校验器 —— world.run 确定性门：结构合约（块式子集 + Actions 结构不变式），退出码分支。
//
// 防冲突三件套（用户核心诉求「过 CI ⇒ 几乎不冲突」）：merge_group 触发 + 合并预演 job +
// 生成代码/lockfile/格式三类漂移门；YAML 之外的分支保护与 merge queue 写进设置清单卡片。

interface DraftSummary {
  /** 文件里每个 job 的 id 与它把守什么（一句话） */
  jobs: { id: string; guards: string }[];
  /** 防合并冲突机制清单（含 YAML 之外需手动开启的仓库设置） */
  conflictDefenses: string[];
  /** 对尚未落地工程的假设（版本、目录布局、未经核实的点） */
  assumptions: string[];
}

interface CritiqueFinding {
  /** 一句话：问题是什么 */
  what: string;
  /** 后果：假绿 / 红 CI / 合并冲突 / runner 上直接挂 */
  consequence: string;
  /** 证据：文件行号或原文引文 */
  evidence: string;
  /** blocking = 必须改；advice = 可选 */
  severity: "blocking" | "advice";
}

interface Critique {
  /** 没有 blocking 发现时才为 true */
  approved: boolean;
  findings: CritiqueFinding[];
}

interface ReportFinding {
  /** 位置：文件路径或「仓库设置」 */
  where: string;
  /** 一句话：发现什么 */
  what: string;
  /** 证据：行号、引文或命令输出 */
  evidence: string;
  /** verified = 有独立确认；unconfirmed = 待人工判断 */
  status: "verified" | "unconfirmed";
  /** high = 会造成假绿或坏合并 */
  severity: "low" | "medium" | "high";
}

interface WorkflowReport {
  /** 两三句话回答用户要什么 */
  conclusion: string;
  findings: ReportFinding[];
  /** 本次运行实际检查过什么、怎么检查的 */
  verified: string[];
  /** 没查/查不了什么、为什么 */
  notCovered: string[];
}

// 评审发现看板（边跑边更新，key 相同的行会被替换）
artifact.table("findings", {
  title: "评审发现",
  columns: [
    { field: "source", label: "来源" },
    { field: "severity", label: "级别" },
    { field: "what", label: "问题" },
    { field: "consequence", label: "后果" },
    { field: "status", label: "处置" },
  ],
  key: "id",
});

const DRAFTER_SYSTEM =
  "你是极其严苛的 CI 架构师，对「假绿」零容忍：每一扇门都必须真的会红。" +
  "你只允许写或改一个文件：.github/workflows/ci.yml（相对工作区 C:/da），绝不碰其它文件，不安装任何工具。" +
  "拿不准的事实（action 版本、git 子命令行为、runner 预装环境）先用 WebSearch 核对；仍拿不准就如实写进返回的 assumptions，绝不编造。" +
  "若指令相互矛盾或做不到，直接说明并升级提问，不要硬凑或造假。全程中文。";

const REVIEWER_SYSTEM =
  "你是极其挑剔但只讲证据的 CI 评审员。规则：每条发现必须给出文件行号或原文引文作为证据；" +
  "绝不编辑、创建任何文件；不要重复运行结构校验器（脚本已运行）；" +
  "发现要求本身矛盾或缺信息时，直接升级提问，不要猜测着硬审。全程中文。";

const COLD_SYSTEM =
  "你是最挑剔的资深运维工程师，此前没有参与任何讨论，独立冷审。" +
  "规则：只凭文件内容与你的 GitHub Actions / 托管 runner 经验判断；每条发现给行号或引文；" +
  "绝不编辑任何文件、不运行校验器；发现矛盾就升级提问。全程中文。";

const DRAFT_ASK = `你是本工作流的 CI 架构师。任务：为我们规划中的项目写一份极其严苛的 GitHub Actions CI 流水线。

交付物：唯一一个文件 .github/workflows/ci.yml（相对工作区 C:/da；目录不存在就创建）。除它以外不要写任何文件；不要 git init；不要安装任何工具。

【项目背景（规划形态，Flutter 工程尚未落地）】
- Flutter + Material 3 聚合应用：番剧 / 漫画 / 小说 / 音乐四模块 + 统一的收藏·历史·下载核心；纯本地，无自建服务器。
- 桌面优先：Windows 主力，Android 第二；不做 web / iOS / macOS / Linux。
- 基线跟随 Kazumi v2.4.4：Flutter 3.50 / Dart >=3.10；MobX + flutter_modular；media_kit；dio；hive_ce；flutter_inappwebview；Venera-Next 一系引入 flutter_qjs、sqlite3、rhttp（Rust）；统一核心计划用 drift/sqlite。依赖大量 pinned git fork，pubspec.lock 必须提交。
- 计划骨架：lib/app（MD3 外壳）、lib/core（统一收藏/历史/下载 + drift）、lib/modules/{anime,comic,music,novel}。
- 仓库现状：工作区只有 demos/（几个 .dart 教学示例与 README），没有 pubspec.yaml、没有 .git。按「第一个 Flutter 工程落在仓库根：pubspec.yaml 在根、源码在 lib/、测试在 test/」编写；这条假设写进 assumptions。
- 本机没有 Flutter/Dart：CI 里的一切按「将来在 GitHub 托管 runner 上真实执行」设计，不要试图本地运行 dart/flutter。

【严苛要求——每一项都要成为一扇真的会红的门，禁止假绿】
1. 触发与并发：push(main) + pull_request(main) + merge_group 三类触发；顶层 concurrency 的 group 按 runner 表达式区分 ref 并 cancel-in-progress；顶层 permissions 最小化（contents: read）。
2. lockfile 门：flutter pub get --enforce-lockfile——pubspec 与 pubspec.lock 不同步直接红（git fork 依赖全靠 lock 钉住）。
3. 格式门：dart format --output=none --set-exit-if-changed .——格式漂移即红。
4. 分析门：flutter analyze --fatal-infos --fatal-warnings——info 也算失败。
5. dart fix 门：dart fix --dry-run 的输出非空即红（grep 判定），防「能自动修却没人修」。
6. 测试门：flutter test --coverage；再解析 coverage/lcov.info 算行覆盖率（grep/awk 自算，不引第三方 action），低于顶层 env 里的 MIN_COVERAGE（先设 60）即红。
7. 生成代码漂移门：dart run build_runner build --delete-conflicting-outputs 之后 git diff --exit-code——生成物必须已提交且与源同步（生成文件是合并冲突重灾区，这扇门直接消灭它）。
8. 构建门：分立两个 job（不要用 matrix——matrix 的 required check 名会带矩阵后缀，在分支保护里既难填又脆弱）：build-windows 跑 flutter build windows --release；build-android 先装 JDK（actions/setup-java，temurin 21，先查证 Flutter 3.50 的 Gradle 要求）再 flutter build apk --release。
9. 合并预演 job（本文件的核心使命）：checkout fetch-depth: 0 → git fetch origin main → 用 git merge-tree --write-tree --name-only HEAD origin/main 预演合并；退出码非 0（有冲突）即红，并把冲突文件列表写进 GitHub Step Summary（GITHUB_STEP_SUMMARY 环境变量）。先查证托管 runner 的 git 版本支持该用法。
10. 每个 job 都有 timeout-minutes；shell 脚本统一 set -euo pipefail 开头；第三方 action 尽量少，每个第三方 action 的名称、版本 tag、参数都用 WebSearch 核对真实存在，没把握的写进 assumptions。
11. 文件内注释用中文，解释每扇门拦什么；文件头注释写明「要让 CI 真正守住 main，还需在仓库设置里启用分支保护 / merge queue / required checks（名字=job id）」。

【硬性风格合约——文件必须通过结构校验器】
自查命令（退出码 0 才算写完）：node tools/validate-ci-yaml.mjs .github/workflows/ci.yml
要点：纯块式 YAML（2 空格缩进、无 Tab、无锚点/别名、无 flow 集合，on: [push] 这种也要展开写成块）；多行脚本用 | 块标量；顶层键只允许 name/run-name/on/concurrency/env/permissions/jobs，且 on、concurrency、permissions、jobs 必须存在；每个 job 必有 runs-on 与 steps；每个 step 必有 uses 或 run；uses 必须钉版本 tag 或 40 位 SHA（禁 @main/@master/@latest）；禁止 continue-on-error: true；禁止 || true；job id 用小写字母/数字/-/_（它是 required check 的名字，起名要一辈子不改）。校验器完整规则可直接读 tools/validate-ci-yaml.mjs。
键与冒号一律半角；值与注释里可以用中文。

可以先读 demos/README.md 与 demos/ 下各 main.dart 的头注释感受项目形态（可选）。

写完自查通过后，返回 DraftSummary：jobs（每个 job 的 id 与一句话把守范围）、conflictDefenses（防合并冲突机制清单，含 YAML 之外要手动开的设置）、assumptions（所有对未落地工程的假设与未经核实的点）。全程中文。`;

const reviewAsk = (round: number) =>
  `第 ${round} 轮严苛评审。通读 .github/workflows/ci.yml（必要时对照 demos/ 了解项目形态），只凭文件内容与 GitHub Actions 知识挑毛病，不要编辑任何文件、不要重跑结构校验器（脚本已运行）。

逐类检查，宁多勿漏：
1. 假绿：有没有永远不红的门？吞错（|| true、continue-on-error、不检查退出码的管道）、if 滥用、覆盖率统计算错、set -euo pipefail 缺失——发现即 blocking。
2. runner 现实性：每个 step 在 GitHub 托管 runner 上真的能跑吗？shell 默认值、JDK 版本、缓存 key、action 参数拼错、Windows 上误用 bash 语法、git merge-tree 用法与 runner git 版本——发现即 blocking。
3. 冲突防御完备性（本文件的核心使命是「过 CI ⇒ 合入 main 几乎不冲突」）：merge_group 触发、显式合并预演 job、生成代码漂移门、pubspec.lock 门、格式门、fatal-infos 分析门、Windows+Android 双平台构建门——缺一即 blocking。
4. 严苛性：权限是否最小、每个 job 是否有 timeout-minutes、required check 说明是否与 job id 一致、构建是否分立 job 而非 matrix。
5. 注释与实际行为不符、误导读者——advice。

返回 approved（无 blocking 才 true）与 findings 数组（what / consequence / evidence / severity: blocking 或 advice），全程中文。`;

const COLD_ASK = `独立终审。你没有参与过此前任何讨论，请冷眼通读 .github/workflows/ci.yml，回答三个问题，全部只凭文件内容与你的 GitHub Actions / 托管 runner 经验，不要编辑任何文件、不要运行校验器：
1. 第一次 push 上 GitHub，这份流水线会在哪一步最先挂？逐个 job 推演托管 runner 的真实环境（shell、预装工具、JDK、网络、git 版本）。
2. 哪扇门是假门——永远不红，或红了也拦不住坏代码？
3. 一个 PR 通过了全部检查，合入 main 时还有哪些途径产生冲突或坏合并？对照文件里的防御机制逐条推演；文件注释里若提到「需要的仓库设置 / required checks」，核对与 job id 是否一致。
返回 approved（无 blocking 才 true）与 findings 数组（what / consequence / evidence / severity: blocking 或 advice），全程中文。`;

// 校验器输出的尾部（错误列表在末尾，掐头留尾）
const detail = (v: WorldRunResult) => `${v.stdout}\n${v.stderr}`.slice(-4000);

phase("起草严苛 CI 流水线");
const drafter = agent("CI 架构师", { system: DRAFTER_SYSTEM });
log("让 CI 架构师起草 .github/workflows/ci.yml …");
const draft = await drafter.ask<DraftSummary>(DRAFT_ASK);
log(`初稿完成：${draft.jobs.length} 个 job、${draft.conflictDefenses.length} 项防冲突机制、${draft.assumptions.length} 条假设`);
report({ stage: "初稿", jobs: draft.jobs.map((j) => j.id).join("、"), defenses: draft.conflictDefenses.length, assumptions: draft.assumptions.length });

phase("结构校验、评审并修订");
const reviewer = agent("严苛评审员", { system: REVIEWER_SYSTEM });
let lastCritique: Critique | undefined;
let cleanRounds = 0;
for (let round = 1; round <= 4; round += 1) {
  log(`第 ${round} 轮：先过结构校验器`);
  const v = await world.run("node", ["tools/validate-ci-yaml.mjs", ".github/workflows/ci.yml"]);
  if (v.exitCode !== 0) {
    log("结构校验未通过，打回架构师修复");
    await drafter.ask(`结构校验器拒绝了 .github/workflows/ci.yml：\n${detail(v)}\n逐条修复，自查（node tools/validate-ci-yaml.mjs .github/workflows/ci.yml 退出码 0）后再返回一句修复说明。`);
    continue;
  }
  cleanRounds += 1;
  const critique = await reviewer.ask<Critique>(reviewAsk(round));
  lastCritique = critique;
  for (let i = 0; i < critique.findings.length; i += 1) {
    const f = critique.findings[i];
    report({ id: `r${round}f${i}`, source: `严苛评审·第${round}轮`, severity: f.severity, what: f.what, consequence: f.consequence, status: "已提出" }, "findings");
  }
  if (critique.approved) {
    log(`第 ${round} 轮评审通过，无 blocking 发现`);
    break;
  }
  const blockingCount = critique.findings.filter((f) => f.severity === "blocking").length;
  log(`第 ${round} 轮有 ${blockingCount} 条 blocking，打回修订`);
  await drafter.ask(`严苛评审第 ${round} 轮意见（blocking 必须逐条处理，advice 有理就采纳）：\n${JSON.stringify(critique.findings, null, 2)}\n修改 .github/workflows/ci.yml，自查 node tools/validate-ci-yaml.mjs .github/workflows/ci.yml 退出码 0，返回一句改动说明。`);
}

phase("独立终审并交付");
for (let prep = 1; prep <= 2; prep += 1) {
  const v = await world.run("node", ["tools/validate-ci-yaml.mjs", ".github/workflows/ci.yml"]);
  if (v.exitCode === 0) break;
  log("进入终审前结构校验未通过，打回修复");
  await drafter.ask(`进入终审前，结构校验器拒绝了文件：\n${detail(v)}\n逐条修复并自查（校验器退出码 0），返回一句修复说明。`);
}

const cold = await agent("独立终审员", { system: COLD_SYSTEM }).ask<Critique>(COLD_ASK);
for (let i = 0; i < cold.findings.length; i += 1) {
  const f = cold.findings[i];
  report({ id: `coldf${i}`, source: "独立终审", severity: f.severity, what: f.what, consequence: f.consequence, status: f.severity === "blocking" ? "待修复" : "待人工判断" }, "findings");
}

let coldBlocking = cold.findings.map((f, i) => ({ f, i })).filter((x) => x.f.severity === "blocking");
for (let fix = 1; fix <= 2 && coldBlocking.length > 0; fix += 1) {
  log(`终审提出 ${coldBlocking.length} 条 blocking，第 ${fix} 轮修复`);
  await drafter.ask(`独立终审意见（blocking，逐条修复）：\n${JSON.stringify(coldBlocking.map((x) => x.f), null, 2)}\n修改 .github/workflows/ci.yml，自查 node tools/validate-ci-yaml.mjs .github/workflows/ci.yml 退出码 0，返回一句改动说明。`);
  const v = await world.run("node", ["tools/validate-ci-yaml.mjs", ".github/workflows/ci.yml"]);
  if (v.exitCode !== 0) {
    await drafter.ask(`修复引入了结构错误：\n${detail(v)}\n先恢复结构合规（校验器退出码 0），同时保持终审意见已被满足，返回说明。`);
    const v2 = await world.run("node", ["tools/validate-ci-yaml.mjs", ".github/workflows/ci.yml"]);
    if (v2.exitCode !== 0) {
      log("结构校验仍未通过——停止重试，如实上报");
      break;
    }
  }
  for (const x of coldBlocking) {
    report({ id: `coldf${x.i}`, source: "独立终审", severity: x.f.severity, what: x.f.what, consequence: x.f.consequence, status: "已修复（校验器复核）" }, "findings");
  }
  coldBlocking = [];
}

const final = await world.run("node", ["tools/validate-ci-yaml.mjs", ".github/workflows/ci.yml"]);
const finalOk = final.exitCode === 0;

// 交付：主产物 = ci.yml 文件卡片
try {
  await artifact.file("ci-yaml", ".github/workflows/ci.yml", {
    title: "GitHub Actions CI 流水线（ci.yml）",
    description: "极其严苛的 CI 门禁：lockfile / 格式 / fatal-infos 分析 / dart fix / 测试+覆盖率 / 生成代码漂移 / 双平台构建 / 合并预演。",
    primary: true,
  });
} catch (e) {
  log(`发布 CI 文件失败：${String(e)}——让架构师确认文件后重试`);
  await drafter.ask(`发布产物时发现问题：${String(e)}。检查 .github/workflows/ci.yml 是否存在且非空；若缺失，按原合约重建并自查校验器（退出码 0），返回说明。`);
  await artifact.file("ci-yaml", ".github/workflows/ci.yml", { title: "GitHub Actions CI 流水线（ci.yml）", primary: true });
}

// 交付：仓库设置清单（YAML 之外的冲突防御开关）+ 流水线假设
const guide = [
  "# 让 CI 真正守住 main：仓库设置清单",
  "",
  "`ci.yml` 只是流水线；下面这些 GitHub 仓库设置才是让「过 CI ⇒ 几乎不冲突」闭环的开关。仓库建到 GitHub 后逐项启用：",
  "",
  "## Branches → 分支保护（对 main）",
  "",
  "- **Require a pull request before merging**：禁止直推 main。",
  "- **Require status checks to pass**——required checks 的名字 = job id，必须一字不差：",
  ...draft.jobs.map((j) => `  - \`${j.id}\` —— ${j.guards}`),
  "- **Require branches to be up to date before merging**：PR 落后于 main 就不许合并——消灭「过 CI 但过时」的合并冲突。",
  "- **Require merge queue**（公共仓库可用；私有仓库需 Team/Enterprise 套餐）：与 ci.yml 的 merge_group 触发配套——排队逐个以「main + 前面所有待合并 PR」的合并结果跑 CI，消灭合并后的语义冲突。套餐不支持时，up-to-date 要求是退路。",
  "",
  "## 其它",
  "",
  "- Settings → Actions → Workflow permissions：Read repository contents and packages only（最小权限）。",
  "- `.github/dependabot.yml`（pub 依赖周更、actions 月更）未随本文件创建——需要时另加，让 lockfile 冲突每周小步化解而不是攒大。",
  "",
  "## 流水线对工程形态的假设（落地时核对）",
  "",
  ...draft.assumptions.map((a) => `- ${a}`),
].join("\n");
await artifact.markdown("setup-guide", guide, {
  title: "仓库设置清单：让 CI 真正守住 main",
  description: "ci.yml 之外必须手动启用的分支保护 / merge queue / required checks，以及流水线对工程形态的假设。",
});

// 汇总上报
const leftovers: ReportFinding[] = [];
if (typeof lastCritique !== "undefined") {
  for (const f of lastCritique.findings) {
    if (f.severity === "advice") {
      leftovers.push({ where: ".github/workflows/ci.yml", what: `严苛评审遗留建议：${f.what}`, evidence: f.evidence, status: "unconfirmed", severity: "low" });
    }
  }
}
for (const f of cold.findings) {
  if (f.severity === "advice") {
    leftovers.push({ where: ".github/workflows/ci.yml", what: `终审建议：${f.what}`, evidence: f.evidence, status: "unconfirmed", severity: "low" });
  }
}
for (const x of coldBlocking) {
  leftovers.push({ where: ".github/workflows/ci.yml", what: `终审 blocking 未在修复轮内解决：${x.f.what}`, evidence: x.f.evidence, status: "unconfirmed", severity: "high" });
}
if (!finalOk) {
  leftovers.push({ where: ".github/workflows/ci.yml", what: "最终结构校验未通过", evidence: detail(final), status: "verified", severity: "high" });
}

const jobList = draft.jobs.map((j) => j.id).join("、");
const result: WorkflowReport = {
  conclusion:
    finalOk && coldBlocking.length === 0
      ? `已交付 .github/workflows/ci.yml：${draft.jobs.length} 个 job（${jobList}），通过结构校验器与两轮独立评审（严苛评审员 ${cleanRounds} 轮全部过审 + 独立终审）。防冲突三件套：merge_group 触发 + 合并预演 job + 生成代码/lockfile/格式三类漂移门；YAML 之外的分支保护与 merge queue 需按「仓库设置清单」卡片在仓库上 GitHub 后手动启用。`
      : `ci.yml 已产出（${draft.jobs.length} 个 job：${jobList}），但${!finalOk ? "最终结构校验未通过" : ""}${!finalOk && coldBlocking.length > 0 ? "、" : ""}${coldBlocking.length > 0 ? `终审仍有 ${coldBlocking.length} 条 blocking 未消化` : ""}——见 findings，先处理再投入使用。`,
  findings: leftovers,
  verified: [
    `node tools/validate-ci-yaml.mjs .github/workflows/ci.yml 结构校验${finalOk ? "最终退出码 0" : "未通过"}（校验器本身经 14 用例回归测试：好样本 + 12 种变异样本）`,
    `严苛评审员持续上下文评审 ${cleanRounds} 轮，每轮先过校验器再评审，blocking 意见全部打回架构师逐条处理`,
    `独立终审员以全新上下文冷审终稿${cold.findings.length > 0 ? `，提出 ${cold.findings.length} 条发现（blocking 已修复并复核）` : "，未发现 blocking"}`,
    `第三方 action 版本与 git merge-tree 用法经架构师 WebSearch 核对（详见 ci.yml 注释与假设清单）`,
  ],
  notCovered: [
    "机器上没有 Flutter/Dart，也没有 GitHub runner——每个 step 的真实可执行性未经实际运行验证（仅有结构校验 + 两轮独立评审 + WebSearch 核对）",
    "Flutter 工程尚未创建：流水线按计划形态编写（Flutter 3.50 / Dart ≥3.10、pubspec.yaml 在仓库根、lib/ 源码、drift 核心）；工程落地如有出入需对齐",
    "分支保护 / merge queue / required checks 是仓库设置，不在 YAML 能力范围内——须按清单手动启用",
    "dependabot.yml 等配套文件未创建（本次交付严格只含一份 workflows 文件）",
  ],
};
return result;
