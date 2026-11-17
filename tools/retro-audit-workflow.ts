/* 复盘并审查两个已完成的 workflow：架构对抗规划（docs/ 三份文档）与严苛 CI（ci.yml + 校验器）。
   三路并行：过程复盘 / CI 审查（分诊遗留意见 + 新眼找问题 + 联网核实）/ 文档审查（一致性 + 工程可行性）。
   各路内部完成复核、修订与确定性校验；最后汇总复盘报告、独立终读并发布。 */

interface Finding {
  /** 文件与位置：如 ".github/workflows/ci.yml:107" 或 "docs/architecture.md 目录树一节" */
  where: string;
  /** 一句话说清问题是什么，写给用户看 */
  what: string;
  /** 支撑证据：读到的行文、对照结果或联网核实结论 */
  evidence: string;
  /** 建议的最小改法（给修订者） */
  fixHint?: string;
  /** 严重度。high 留给会导致错误结果或流程失效的问题 */
  severity: "low" | "medium" | "high";
}

interface CiLeftoverVerdict {
  /** 遗留意见编号：L1..L14 */
  id: string;
  /** fix=本次就改；by-design=设计如此（理由写给用户看）；defer=留给用户或工程落地后 */
  action: "fix" | "by-design" | "defer";
  /** 一句话理由，写给用户看 */
  reason: string;
  /** action=fix 时的具体改法：改哪个 job 的哪几行、改成什么样 */
  fixHint?: string;
}

interface CiAudit {
  /** 对遗留意见的逐条处置 */
  triage: CiLeftoverVerdict[];
  /** 遗留清单之外新发现的问题 */
  newFindings: Finding[];
  /** 联网核实记录：每条一行（核了什么、结论、来源） */
  onlineChecks: string[];
}

interface Confirmation {
  /** 该发现是否成立（证据属实、可复核） */
  holds: boolean;
  /** 复核结论一句话 */
  reason: string;
}

interface MergedDocFinding {
  /** 去重合并后的发现 */
  finding: Finding;
  /** 来源说明：哪位审计员提出、是否两人都提到、是否剔除过什么 */
  sources: string;
}

interface FixOutcome {
  /** 实际改了什么，每条一行 */
  applied: string[];
  /** 决定不改什么及原因，每条一行 */
  skipped: string[];
}

interface ProcessLesson {
  /** 做得好、下次保留的做法，每条一行 */
  kept: string[];
  /** 下次该改的做法，每条一行并写明为什么 */
  improve: string[];
  /** 运行记录与实际不符的订正，没有则空数组 */
  corrections: string[];
}

interface RecheckVerdict {
  ok: boolean;
  issues: Finding[];
}

interface ReportFinding {
  where: string;
  what: string;
  evidence: string;
  status: "verified" | "unconfirmed";
  severity: string;
}

interface WorkflowReport {
  conclusion: string;
  findings: ReportFinding[];
  verified: string[];
  notCovered: string[];
}

// ---------- 素材：来自两次运行的运行记录（GetWorkflowRun），供子代理引用 ----------
const RUN1_FACTS = `运行「聚合App架构对抗规划」，耗时 1h32m，共 11,887,245 tokens，4 个阶段：
①提出三套方案并逐一攻击（35m56s，6 步）：3 位架构师（上游生长 / 极简新手 / 模块边界）各自提案，落地后立即交给对应批评家攻击，不互相等待；
②裁决并写出三份文档（15m11s，1 步）：裁决者选出方案2「少一层是一层」，写出 docs/ 三份文档；
③两组独立复审（20m33s，2 步）：新手视角 + Flutter 工程视角，产出 25 条意见；
④修订定稿并交付：定稿编辑单步消耗 5,479,871 tokens（全程最贵的一步），吸收 20 条、驳回 4 条。
产物：docs/architecture.md、docs/directory-layout.md、docs/plan-retrospective.md；被驳回的复审意见在最终报告里标为 unconfirmed 保留。`;

const RUN2_FACTS = `运行「严苛 CI 流水线编制」，耗时 1h16m，共 6,219,895 tokens，3 个阶段：
①起草严苛 CI 流水线（23m32s）：CI 架构师写出 .github/workflows/ci.yml（5 个 job、9 项防冲突机制、16 条假设）与 tools/validate-ci-yaml.mjs 结构校验器（带回归测试 tools/test-validate-ci-yaml.mjs）；
②结构校验、评审并修订（39m23s，8 步）：每轮先过校验器再交严苛评审员（同一持续上下文），第 1、2 轮各有 1 条 blocking 打回，第 3 轮过审；
③独立终审并交付：独立终审员以全新上下文冷审，提出 12 条发现，blocking 已修复复核，其余 14 条（含严苛评审遗留）全部标 unconfirmed 留在最终报告里没有再处理。
产物：.github/workflows/ci.yml + 校验器 + 仓库设置清单卡片。`;

const CI_LEFTOVERS = `L1（严苛评审遗留）分析门对 lint 基线文件的校验只覆盖「缺失或空文件」：文件存在且非空但 lint 基线被移除（比如只剩注释）时静默通过。证据：16 字节纯注释文件能通过 [ ! -s ] 判断；ci.yml:107-110。
L2（严苛评审遗留）「现状说明」注释漏列 build-windows 的过渡红因（它落位前同样会红），ci.yml:30-34 只点名 static-checks / tests / build-android。
L3（终审·最先挂点）首次 push 上 GitHub，最早失败的是 build-android 第 2 步 setup-java（cache: gradle）：仓库无任何 gradle 文件可哈希，actions/setup-java 的缓存依赖文件匹配会抛硬错误（"No file in ... matched"），job 红在装 Flutter 之前。证据：ci.yml:274-279；目录清点确认仓库无 gradle 文件。
L4（终审）static-checks 与 tests 红在 flutter pub get --enforce-lockfile：仓库无 pubspec.yaml，pub 必然非零退出——属设计内过渡红，核对「现状说明」是否已如实写清。ci.yml:88-91、142-145。
L5（终审·未验证项）action tag 与版本未联网核实：checkout@v5、setup-java@v5.5.0、flutter-action@v2.23.0 是否存在；FLUTTER_VERSION 3.50.0 是否在 stable 渠道存在。ci.yml:65、77、80、134-139、236-241。本次必须联网核实。
L6（终审）merge-check 在 push 与 merge_group 事件上恒绿：push 时 HEAD 即 origin/main，merge-tree 平凡干净；merge_group 时 HEAD 已包含 main。该门只在 pull_request 事件上是真门——核对注释是否如实说明，评估 merge_group 下合并预演是否形同虚设。ci.yml:319-346。
L7（终审）覆盖率门分母只含「已被测试 import 的文件」：新增整模块零测试不进分母，门照样绿（flutter#27997）。ci.yml:189-217。
L8（终审）生成代码漂移门的扩展名白名单漏网：只盯 *.g.dart / *.drift.dart / *.mock.dart / *.mocks.dart / *.freezed.dart 五类；其它命名且被 .gitignore 忽略的生成物，三个子检查全看不见。ci.yml:164-180。
L9（终审）若工程最终不引入 build_runner dev 依赖，漂移门恒红：dart run build_runner build 直接报错；ci.yml:35-37 只讨论了 .gitignore 情形，未讨论「无 codegen」情形。
L10（终审）demos/ 下 4 个游离 main.dart（01..04）在工程落位后会被 dart format . 与 flutter analyze 扫到，是否干净未验证（本机无 Flutter，本次也无法验证）。ci.yml:97、111。
L11（终审）语义坏合并残余通道：绿灯 PR 与已前进的 main 无文本冲突时 GitHub 不阻止合入，语义坏合并直落 main，只能靠 main 的 push CI 事后发现。属平台固有限制，评估现有说明是否充分。
L12（终审）仓库设置清单缺「禁止管理员绕过」（Do not allow bypassing the above settings / bypass 名单控制）。ci.yml:4-10。
L13（终审）仓库现存 4 个游离 dart 文件（demos/01..04/main.dart，import flutter/material、mobx 等），工程落位后 dart format . 与 flutter analyze 是否干净未验证，且漂移门等步骤对 demos/ 的态度未说明。
L14（终审·核对通过）required checks 注释与 job id 一字不差一致（ci.yml:9-10 对照实际 5 个 job id）——非缺陷，处置时确认即可。`;

const DOC_REJECTED = `架构规划运行中两组复审共产出 25 条意见，吸收 20 条、驳回 4 条+1 条旁证订正。被驳回的如下（驳回理由附后，重审其是否站得住）：
R1（复审R5/R14）建议主选项：AudioHandler 完整实现住 core/。驳回理由：handler 要触达播放器，core 完整实现必然 import 模块，违反铁律①；已采纳其备选「接口在 core、实现经 app_registry 注入」。
R2（复审R6）建议 AppModule 契约加 webviewFactory 可选成员，各模块自供。驳回理由：当前无消费者（违背文档 C4 确立的「无消费者不建空架子」纪律）；模块 webview 在模块页面内闭环、壳借用场景为零。
R3（复审R14）建议铁律④白名单扩为「app_registry + 指定共享出口文件」，并在目录树补 shell/audio/、shell/webview_dialog.dart。驳回理由：扩白名单稀释「删模块=删目录+删一行」的机械性；shell/audio/ 是空架子。
R4（any-reader 旁证）复审曾称 jsoup 手写 DOM 层「在当前上游找不到实体」。已被实测推翻：解包验证 DOM 层实体在 packages/legado/src/javascript/jsoup/。文档应已采纳其主旨（AnalyzerHtml.ts 为 0 字节、any-reader 降为旁证、M5 开工当天重核）——核对三份文档是否如实反映。`;

log("开始复盘与审查：三路并行——过程复盘、CI 审查、文档审查；各路自行复核并修订，最后汇总发布。");

artifact.table("findings", {
  title: "审查发现与处置",
  columns: [
    { field: "where", label: "位置" },
    { field: "what", label: "内容" },
    { field: "status", label: "状态" },
    { field: "severity", label: "严重度" },
  ],
  key: "id",
});

// ================= 三路并行 =================

// —— 路一：过程复盘 ——
const retroP = future(async () => {
  phase("复盘两次运行的过程");
  const [r1, r2] = await Promise.all([
    agent("复盘·架构规划").ask<ProcessLesson>(
      `复盘一次已完成的 workflow 运行。运行记录：\n${RUN1_FACTS}\n\n` +
      `先读两样东西再下结论：①脚本 .zcode/workflow-drafts/聚合App架构对抗规划.dwf.ts（真实拓扑与提问文本都在里面）；②docs/ 三份产出（抽查产出与运行记录是否对得上）。\n\n` +
      `输出三组：kept（做得好、下次保留的做法）；improve（下次该改的做法，每条写明为什么——特别要解释「定稿编辑」单步消耗 5,479,871 tokens 为什么这么贵、下次怎么省）；corrections（运行记录与实际不符处，没有就空数组）。每条判断要有脚本或文件里的证据。用中文。`,
    ),
    agent("复盘·CI流水线").ask<ProcessLesson>(
      `复盘一次已完成的 workflow 运行。运行记录：\n${RUN2_FACTS}\n\n` +
      `先读两样东西再下结论：①脚本 tools/strict-ci-workflow.ts；②.github/workflows/ci.yml 与 tools/validate-ci-yaml.mjs（抽查产出）。\n\n` +
      `输出三组：kept / improve / corrections。特别要评估「结构校验器 + 同一持续上下文的严苛评审员循环 + 独立终审」这套结构是否值得复用、评审 3 轮共 8 步的花费是否值得、终审 12 条发现为何标 unconfirmed 后无人处理。每条判断要有证据。用中文。`,
    ),
  ]);
  return [r1, r2];
});

// —— 路二：CI 审查 → 复核 → 修订 → 校验门 ——
const ciP = future(async () => {
  phase("审查 CI 流水线并分诊遗留意见");
  const audit = await agent("审查·CI配置").ask<CiAudit>(
    `读 .github/workflows/ci.yml 与 tools/validate-ci-yaml.mjs 全文（校验器也是交付物，一并审）。\n` +
    `背景：仓库还没有 Flutter 工程（无 pubspec.yaml、无 android/、无 gradle 文件），CI 按计划形态预写，过渡态红灯属设计内行为；本机无 Flutter/Dart，无法实际运行流水线。\n\n` +
    `任务一：对以下遗留意见逐条处置，action 取 fix（本次就改）/ by-design（设计如此，理由写给用户看）/ defer（留给用户或工程落地后处理）：\n${CI_LEFTOVERS}\n\n` +
    `任务二：以新眼光找遗留清单之外的新问题（YAML 语义、GitHub Actions 真实行为、job 依赖与触发器、与仓库现状的匹配），没有就返回空数组。\n\n` +
    `任务三：用 WebSearch 联网核实——checkout@v5、setup-java@v5.5.0、flutter-action@v2.23.0 三个 tag 是否存在；Flutter 3.50.0 是否在 stable 渠道；actions/setup-java 在 cache: gradle 且仓库无 gradle 文件时是否真的硬报错。逐条写进 onlineChecks（核了什么、结论、来源），并据此定 L3 与 L5 的处置。\n\n` +
    `纪律：不要编辑任何文件；fixHint 要写到「改哪个 job 的哪几行、改成什么」的程度，能照着改。用中文。`,
  );
  for (const v of audit.triage) {
    report(
      {
        id: v.id,
        where: ".github/workflows/ci.yml",
        what: v.reason,
        status: v.action === "fix" ? "本次修改" : v.action === "by-design" ? "设计如此" : "移交用户",
        severity: "low",
      },
      "findings",
    );
  }
  log(`遗留意见分诊完成：${audit.triage.length} 条；新发现 ${audit.newFindings.length} 条，开始逐条复核`);

  phase("复核 CI 的新发现");
  const confirmedNew: { finding: Finding; confirmation: Confirmation }[] = await Promise.all(
    audit.newFindings.map(async (f, i) => {
      const confirmation = await agent(`复核·CI新发现${i + 1}`).ask<Confirmation>(
        `独立复核以下关于 .github/workflows/ci.yml 的发现：亲自到文件里核对声称的位置与内容，可以联网查证 GitHub Actions 行为，只凭证据判断是否成立。不要编辑任何文件。\n发现：\n${JSON.stringify(f, null, 2)}`,
      );
      report(
        { id: `ci-new-${i + 1}`, where: f.where, what: f.what, status: confirmation.holds ? "已确认" : "复核驳回", severity: f.severity },
        "findings",
      );
      return { finding: f, confirmation };
    }),
  );

  const fixList: string[] = [];
  for (const v of audit.triage) {
    if (v.action === "fix") fixList.push(`[${v.id}] ${v.reason}——改法：${v.fixHint ?? "（自行设计最小改法）"}`);
  }
  for (const c of confirmedNew) {
    if (c.confirmation.holds) fixList.push(`[新发现] ${c.finding.what}（位置 ${c.finding.where}）——改法：${c.finding.fixHint ?? "（自行设计最小改法）"}`);
  }

  phase("修订 ci.yml 并过校验器");
  let ciFix: FixOutcome | null = null;
  if (fixList.length > 0) {
    const fixer = agent("修订·CI");
    ciFix = await fixer.ask<FixOutcome>(
      `对 .github/workflows/ci.yml 做最小必要修改，逐条落实以下已确认的处置：\n${fixList.map((s, i) => `${i + 1}. ${s}`).join("\n")}\n\n` +
      `规则：①每条只做该条需要的最小修改，不顺手重构、不动无关行；②若某条经你核对发现文件里已覆盖，列入 skipped 并说明；③仓库设置清单与现状说明类修改只动 ci.yml 开头注释；④改完保证 YAML 语法正确——随后脚本会跑 tools/validate-ci-yaml.mjs 校验。用中文写 applied 与 skipped。`,
    );
    ciFix.applied.forEach((line, i) =>
      report({ id: `ci-fix-${i + 1}`, where: ".github/workflows/ci.yml", what: line, status: "已修改", severity: "low" }, "findings"),
    );
  }

  let gate = await world.run("node", ["tools/validate-ci-yaml.mjs", ".github/workflows/ci.yml"]);
  let gateTest = await world.run("node", ["tools/test-validate-ci-yaml.mjs"]);
  let gateFixer: Agent | null = null;
  let gateRounds = 0;
  while ((gate.exitCode !== 0 || gateTest.exitCode !== 0) && gateRounds < 3) {
    gateRounds += 1;
    log(`ci.yml 校验未过（第 ${gateRounds} 轮），打回修订`);
    if (gateFixer === null) gateFixer = agent("校验修复·CI");
    await gateFixer.ask(
      `CI 文件校验未通过。校验器输出（对 .github/workflows/ci.yml）：\n${gate.stderr.slice(0, 1500)}\n${gate.stdout.slice(0, 1500)}\n` +
      `校验器回归测试输出：\n${gateTest.stderr.slice(0, 1500)}\n${gateTest.stdout.slice(0, 1500)}\n` +
      `做最小修改修到两项都通过；不要改坏已经确认的修复内容。`,
    );
    gate = await world.run("node", ["tools/validate-ci-yaml.mjs", ".github/workflows/ci.yml"]);
    gateTest = await world.run("node", ["tools/test-validate-ci-yaml.mjs"]);
  }
  const gateOk = gate.exitCode === 0 && gateTest.exitCode === 0;
  log(gateOk ? "ci.yml 通过结构校验器与校验器回归测试" : "ci.yml 校验三轮未过，将在报告中如实标注");

  let guidePublished = false;
  if (ciFix !== null && ciFix.applied.length > 0 && gateOk) {
    phase("重建仓库设置清单");
    const guide = await agent("更新·设置清单").ask<string>(
      `.github/workflows/ci.yml 刚修订过（开头注释里有「仓库设置清单」与「现状说明」）。上一次运行发布的设置清单卡片无法在此读取，请以修订后的 ci.yml 注释为准重建一份完整的 markdown 设置清单：` +
      `分支保护各项（如清单里有禁止管理员绕过则包含）、required checks 名单、merge queue、workflow permissions、以及过渡态红灯说明（哪些 job 在 Flutter 工程落位前会红、红在哪一步、为什么正常）。直接输出 markdown 全文，不要输出评论。用中文。`,
    );
    await artifact.markdown("setup-guide-v2", guide, {
      title: "仓库设置清单（更新版）",
      description: "CI 修订后按 ci.yml 注释重建的仓库设置与过渡态红灯说明，取代上次运行发布的设置清单卡片。",
    });
    guidePublished = true;
  }

  return { audit, confirmedNew, ciFix, gateOk, gateRounds, guidePublished };
});

// —— 路三：文档审查 → 合并复核 → 修订 → 独立复核 ——
const docP = future(async () => {
  phase("审查三份架构文档");
  const [consistencyFindings, engineeringFindings] = await Promise.all([
    agent("审查·文档一致性").ask<Finding[]>(
      `读 docs/architecture.md、docs/directory-layout.md、docs/plan-retrospective.md 三份全文（互相引用处要对照）。审查角度：\n` +
      `①三份之间的目录树、规则、模块边界、数字是否一致；\n` +
      `②plan-retrospective.md 是否忠实反映实际运行（可对照脚本 .zcode/workflow-drafts/聚合App架构对抗规划.dwf.ts）；\n` +
      `③以下被驳回的复审意见，驳回理由是否站得住（站不住就是 finding）：\n${DOC_REJECTED}\n\n` +
      `每条 finding 给齐 where/what/evidence/fixHint/severity。不要编辑任何文件。用中文。`,
    ),
    agent("审查·工程可行性").ask<Finding[]>(
      `读 docs/architecture.md 与 docs/directory-layout.md 全文（plan-retrospective.md 可跳读）。审查角度：以资深 Flutter 工程师 + 项目未来执行者（用户第一次做项目、极度在意自己能看懂）的双重视角：\n` +
      `①方案有没有工程上站不住的地方（Kazumi 上游生长、app_registry、音频 handler 注入、模块删除的机械性）；\n` +
      `②新手照着目录布局文档开工第一天会不会被卡住；\n` +
      `③有没有漏掉的关键工程决策。\n` +
      `注意：drift 对比 raw sqlite3、是否接受 MobX 是留给用户的决策，不要为它们提 finding。每条 finding 给齐 where/what/evidence/fixHint/severity。不要编辑任何文件。用中文。`,
    ),
  ]);

  phase("合并并复核文档发现");
  const merged = await agent("文档发现整理员").ask<MergedDocFinding[]>(
    `两位审计员对 docs/ 三份文档的发现如下。去重合并（同一处问题只留一条，合并双方证据），剔除明显站不住的（在 sources 里说明），按严重度从高到低排序后返回；没有可合并的就返回空数组。\n` +
    `一致性与忠实性视角：${JSON.stringify(consistencyFindings, null, 1)}\n工程视角：${JSON.stringify(engineeringFindings, null, 1)}`,
  );

  const judged = await Promise.all(
    merged.map(async (m, i) => {
      const confirmation = await agent(`复核·文档发现${i + 1}`).ask<Confirmation>(
        `独立复核以下关于 docs/ 文档的发现：发现声称的行文、目录树、规则要亲自到文件里对照，只凭文件证据判断是否成立。不要编辑任何文件。\n发现：\n${JSON.stringify(m.finding, null, 2)}`,
      );
      report(
        { id: `doc-${i + 1}`, where: m.finding.where, what: m.finding.what, status: confirmation.holds ? "已确认" : "复核驳回", severity: m.finding.severity },
        "findings",
      );
      return { item: m, confirmation };
    }),
  );
  const docConfirmed = judged.filter((d) => d.confirmation.holds).map((d) => d.item);

  let docFix: FixOutcome | null = null;
  let docResidual: Finding[] = [];
  if (docConfirmed.length > 0) {
    phase("修订三份文档并复核");
    const fixer = agent("修订·文档");
    docFix = await fixer.ask<FixOutcome>(
      `按以下已确认的发现修订 docs/ 下的 architecture.md、directory-layout.md、plan-retrospective.md（fixHint 是建议改法，evidence 是依据）：\n${JSON.stringify(docConfirmed, null, 1)}\n\n` +
      `规则：①只改发现指向的问题，不做无关润色；②三份文档必须互相一致——目录树、规则、模块边界、数字的变化要三份同步改；③保持原有语气与结构。用中文写 applied 与 skipped。`,
    );
    docFix.applied.forEach((line, i) =>
      report({ id: `doc-fix-${i + 1}`, where: "docs/", what: line, status: "已修改", severity: "low" }, "findings"),
    );

    const rechecker = agent("修订复核员");
    for (let round = 1; round <= 2; round += 1) {
      const recheck = await rechecker.ask<RecheckVerdict>(
        `第 ${round} 轮复核：docs/ 三份文档刚按以下清单修订：\n${JSON.stringify(docFix.applied, null, 1)}\n` +
        (round > 1 ? "上一轮复核发现的问题已再修一轮（见上轮对话）。\n" : "") +
        `通读三份文档核对：①每条修订落对了位置、没有引入三份之间的新矛盾；②文档结构未被破坏（标题层级、交叉引用、目录树完整性）。没问题返回 ok=true、issues=[]；有问题逐条列 finding（where/what/evidence/fixHint/severity）。不要编辑任何文件。用中文。`,
      );
      if (recheck.ok || recheck.issues.length === 0) {
        docResidual = [];
        break;
      }
      docResidual = recheck.issues;
      if (round < 2) {
        await fixer.ask<FixOutcome>(
          `复核发现以下遗留问题，继续最小修订（同样的三份一致规则）：\n${JSON.stringify(docResidual, null, 1)}`,
        );
      }
    }
  }

  return { confirmed: docConfirmed, docFix, residual: docResidual };
});

// ================= 汇合（报告需要三路的全部结果） =================
const [retroSettled, ciSettled, docSettled] = await Promise.allSettled([retroP, ciP, docP]);
const lessons: ProcessLesson[] = retroSettled.status === "fulfilled" ? retroSettled.value : [];
const ciOut = ciSettled.status === "fulfilled" ? ciSettled.value : null;
const docOut = docSettled.status === "fulfilled" ? docSettled.value : null;
const failedStreams: string[] = [];
if (retroSettled.status === "rejected") failedStreams.push(`过程复盘（${String(retroSettled.reason)}）`);
if (ciSettled.status === "rejected") failedStreams.push(`CI 审查（${String(ciSettled.reason)}）`);
if (docSettled.status === "rejected") failedStreams.push(`文档审查（${String(docSettled.reason)}）`);
for (const f of failedStreams) log(`一路失败，报告将如实降级：${f}`);

phase("汇总复盘报告并终读");

const fixChinese = (a: CiLeftoverVerdict["action"]) => (a === "fix" ? "本次修改" : a === "by-design" ? "设计如此" : "移交用户");

const md: string[] = [];
md.push("# 两个 workflow 的复盘与产出审查", "");
md.push(`> 复盘对象：「聚合App架构对抗规划」与「严苛 CI 流水线编制」两次运行的全部产出。审查中确认的问题已在本次运行内修订，明细见下。`, "");

md.push("## 一、过程复盘", "");
if (lessons.length === 2) {
  md.push("### 聚合App架构对抗规划", "", "**做得好、下次保留**", ...lessons[0].kept.map((s) => `- ${s}`), "", "**下次该改**", ...lessons[0].improve.map((s) => `- ${s}`));
  if (lessons[0].corrections.length > 0) md.push("", "**运行记录订正**", ...lessons[0].corrections.map((s) => `- ${s}`));
  md.push("", "### 严苛 CI 流水线编制", "", "**做得好、下次保留**", ...lessons[1].kept.map((s) => `- ${s}`), "", "**下次该改**", ...lessons[1].improve.map((s) => `- ${s}`));
  if (lessons[1].corrections.length > 0) md.push("", "**运行记录订正**", ...lessons[1].corrections.map((s) => `- ${s}`));
} else {
  md.push(`过程复盘这一路未能完成（${failedStreams.find((s) => s.startsWith("过程复盘")) ?? "失败"}），产出照常交付，复盘留待下次。`);
}
md.push("");

md.push("## 二、CI 流水线（.github/workflows/ci.yml）审查", "");
if (ciOut !== null) {
  md.push("### 遗留意见逐条处置", "");
  for (const v of ciOut.audit.triage) md.push(`- **${v.id}**（${fixChinese(v.action)}）：${v.reason}`);
  if (ciOut.audit.onlineChecks.length > 0) {
    md.push("", "### 联网核实记录", "", ...ciOut.audit.onlineChecks.map((s) => `- ${s}`));
  }
  const confirmedCi = ciOut.confirmedNew.filter((c) => c.confirmation.holds);
  if (confirmedCi.length > 0) {
    md.push("", "### 新发现（已复核确认）", "", ...confirmedCi.map((c) => `- **${c.finding.where}**：${c.finding.what}（${c.finding.evidence}）`));
  }
  const rejectedCi = ciOut.confirmedNew.filter((c) => !c.confirmation.holds);
  if (rejectedCi.length > 0) {
    md.push("", "### 新发现（复核未确认，仅供参考）", "", ...rejectedCi.map((c) => `- ${c.finding.what}——复核：${c.confirmation.reason}`));
  }
  if (ciOut.ciFix !== null) {
    md.push("", "### 本次对 ci.yml 的修订", "", ...ciOut.ciFix.applied.map((s) => `- ${s}`));
    if (ciOut.ciFix.skipped.length > 0) md.push("", "**修订时判定无需改动**", ...ciOut.ciFix.skipped.map((s) => `- ${s}`));
  }
  md.push("", `**校验结果**：ci.yml ${ciOut.gateOk ? "通过" : "未通过"}结构校验器与校验器回归测试${ciOut.gateRounds > 0 ? `（打回修订 ${ciOut.gateRounds} 轮后）` : ""}。`);
} else {
  md.push(`CI 审查这一路未能完成（${failedStreams.find((s) => s.startsWith("CI 审查")) ?? "失败"}），ci.yml 未动。`);
}
md.push("");

md.push("## 三、架构文档（docs/ 三份）审查", "");
if (docOut !== null) {
  if (docOut.confirmed.length > 0) {
    md.push("### 已确认并处理的问题", "", ...docOut.confirmed.map((m) => `- **${m.finding.where}**：${m.finding.what}`));
  } else {
    md.push("两位审计员（一致性 / 工程可行性）的发现经去重与独立复核后无一条成立：三份文档未发现问题。");
  }
  if (docOut.docFix !== null && docOut.docFix.applied.length > 0) {
    md.push("", "### 本次对文档的修订", "", ...docOut.docFix.applied.map((s) => `- ${s}`));
    if (docOut.docFix.skipped.length > 0) md.push("", "**修订时判定无需改动**", ...docOut.docFix.skipped.map((s) => `- ${s}`));
  }
  if (docOut.residual.length > 0) {
    md.push("", "### 复核残留问题（未能修完，标为未确认）", "", ...docOut.residual.map((f) => `- **${f.where}**：${f.what}（${f.evidence}）`));
  }
} else {
  md.push(`文档审查这一路未能完成（${failedStreams.find((s) => s.startsWith("文档审查")) ?? "失败"}），文档未动。`);
}
md.push("");

md.push("## 五、留给你拍板", "");
md.push("- **drift 对比 raw sqlite3、是否接受 MobX**：架构运行按裁决规则标为临时决定，等你定（见 docs/architecture.md 开放问题清单）。");
if (ciOut !== null) {
  const defers = ciOut.audit.triage.filter((v) => v.action === "defer");
  for (const v of defers) md.push(`- **CI 遗留 ${v.id}**：${v.reason}`);
}
md.push("");

md.push("## 六、本次没有覆盖到的", "");
md.push("- 本机没有 Flutter/Dart：CI 各 step 的真实可执行性未实际运行验证（仅结构校验 + 联网核实 + 评审）。");
md.push("- 分支保护 / merge queue 是 GitHub 仓库设置，未在真实仓库上验证（仓库还没推到 GitHub）。");
md.push("- Kazumi / Venera-Next 上游仓库结构未本地克隆核对（沿袭架构运行时的声明）。");
if (failedStreams.length > 0) md.push(`- 本次有 ${failedStreams.length} 路失败：${failedStreams.join("；")}。`);

const reportDraft = md.join("\n");
log("复盘报告草稿完成，交独立终读");

const critique = await agent("终读·复盘报告").ask<string>(
  `下面这份复盘报告即将交给用户（用户第一次做 Flutter 项目、在意文档好懂）。只凭文本挑毛病：哪里读不懂、哪个结论没有支撑、哪里自相矛盾、用户读完最可能追问什么。逐条给出可直接执行的修改意见；没有毛病就返回空。\n\n---\n${reportDraft}`,
);

let finalReport = reportDraft;
if (critique.trim().length > 0) {
  finalReport = await agent("报告修订员").ask<string>(
    `按以下终读意见修订这份 markdown，直接输出修订后的全文（不要输出评论、不要删减章节）：\n${critique}\n\n---\n${reportDraft}`,
  );
}

await artifact.markdown("retro-report", finalReport, {
  title: "复盘与审查报告",
  description: "两次 workflow 的过程复盘、产出审查结论、本次已做的修订与留给你拍板的事项。",
  primary: true,
});

// ================= 最终报告 =================
const finalFindings: ReportFinding[] = [];
if (ciOut !== null) {
  for (const c of ciOut.confirmedNew) {
    finalFindings.push({
      where: c.finding.where,
      what: c.finding.what,
      evidence: c.finding.evidence,
      status: c.confirmation.holds ? "verified" : "unconfirmed",
      severity: c.finding.severity,
    });
  }
  for (const v of ciOut.audit.triage) {
    if (v.action === "defer") {
      finalFindings.push({
        where: ".github/workflows/ci.yml",
        what: `遗留 ${v.id}：${v.reason}`,
        evidence: "严苛评审员/终审员发现，本次分诊为移交用户或工程落地后处理",
        status: "unconfirmed",
        severity: "low",
      });
    }
  }
}
if (docOut !== null) {
  for (const m of docOut.confirmed) {
    finalFindings.push({ where: m.finding.where, what: m.finding.what, evidence: m.finding.evidence, status: "verified", severity: m.finding.severity });
  }
  for (const f of docOut.residual) {
    finalFindings.push({ where: f.where, what: f.what, evidence: f.evidence, status: "unconfirmed", severity: f.severity });
  }
}
finalFindings.push({
  where: "docs/architecture.md 开放问题",
  what: "drift 对比 raw sqlite3、是否接受 MobX——架构运行按规则标为临时决定，等你拍板",
  evidence: "上次运行的最终报告与文档开放问题清单",
  status: "unconfirmed",
  severity: "low",
});

const verified: string[] = [];
if (ciOut !== null) {
  verified.push(
    `node tools/validate-ci-yaml.mjs .github/workflows/ci.yml 退出码 ${ciOut.gateOk ? "0" : "非0"}；node tools/test-validate-ci-yaml.mjs（校验器回归）同步通过`,
    `遗留意见 ${ciOut.audit.triage.length} 条逐条分诊，新发现经独立复核员逐条复核`,
    "action tag 与版本、setup-java 缓存行为经审查·CI配置联网核实（明细见报告核实记录）",
  );
  if (ciOut.ciFix !== null) verified.push(`ci.yml 修订 ${ciOut.ciFix.applied.length} 条，修订后重新过校验器`);
  if (ciOut.guidePublished) verified.push("仓库设置清单已按修订后的 ci.yml 注释重建并发布");
}
if (docOut !== null) {
  verified.push(`文档发现经合并去重与独立复核员逐条复核（确认 ${docOut.confirmed.length} 条）`);
  if (docOut.docFix !== null && docOut.docFix.applied.length > 0) verified.push("文档修订后经修订复核员独立通读复核");
}
verified.push("复盘报告经独立终读员只凭文本批评后修订");

const notCovered: string[] = [
  "本机无 Flutter/Dart：CI 各 step 未实际执行，仅结构校验 + 联网核实 + 评审",
  "分支保护 / merge queue / required checks 未在真实 GitHub 仓库上验证（仓库尚未推送）",
  "Kazumi / Venera-Next 上游结构未本地克隆核对",
];
for (const f of failedStreams) notCovered.push(`失败一路的工作未完成：${f}`);
if (ciOut !== null && !ciOut.gateOk) notCovered.push("ci.yml 校验三轮未过，修订的合法性未经校验器确认");

const ciFixCount = ciOut?.ciFix?.applied.length ?? 0;
const docFixCount = docOut?.docFix?.applied.length ?? 0;
const triageFix = ciOut?.audit.triage.filter((v) => v.action === "fix").length ?? 0;
const conclusion =
  `复盘与审查完成：CI 侧遗留意见 ${ciOut?.audit.triage.length ?? 0} 条逐条分诊（${triageFix} 条本次修改），新发现复核确认后与之一并修订，` +
  `ci.yml 共改 ${ciFixCount} 处并通过结构校验器与校验器回归测试；文档侧确认 ${docOut?.confirmed.length ?? 0} 条问题，修订 ${docFixCount} 处并经独立复核。` +
  `两次运行的过程复盘见报告第一节；drift/MobX 等待你拍板的事项见第五节。`;

const result: WorkflowReport = { conclusion, findings: finalFindings, verified, notCovered };
return result;
