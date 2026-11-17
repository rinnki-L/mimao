#!/usr/bin/env node
/**
 * validate-ci-yaml.mjs — GitHub Actions CI 文件结构校验器（受约束的块式 YAML 子集）。
 *
 * 为什么手写：本机没有可用的 YAML 解析器，而且「极其严苛」的 CI 文件值得比通用 YAML
 * 更强的合约。本校验器查两层：
 *   语法层——仅块式风格：2 空格缩进、无 Tab、无锚点/别名、无 flow 集合 {} []；
 *           支持 | 与 > 块标量（脚本体只受全局禁项约束，不做逐行结构检查）。
 *   语义层——GitHub Actions 结构不变式：顶层键白名单、job 必有 runs-on 与 steps、
 *           step 必有 uses 或 run、uses 必须钉住版本 tag 或 40 位 SHA、
 *           禁止 continue-on-error: true、禁止 "|| true"、同层禁止重复键。
 *
 * 用法：node validate-ci-yaml.mjs <file.yml>
 * 退出码：0 = 通过；1 = 有错误；2 = 用法错误。
 * 注意：本结果只保证结构合约；每个 step 的语义正确性仍需评审与真实运行验证。
 */
import { readFileSync } from "node:fs";

const fileArg = process.argv[2];
if (!fileArg) {
  console.error("用法: node validate-ci-yaml.mjs <file.yml>");
  process.exit(2);
}

let text;
try {
  text = readFileSync(fileArg, "utf8");
} catch (e) {
  console.error(`无法读取 ${fileArg}: ${e.message}`);
  process.exit(1);
}

const errors = [];
const err = (line, msg) =>
  errors.push(line > 0 ? `✗ 第 ${line} 行: ${msg}` : `✗ ${msg}`);
const isComment = (l) => l.trimStart().startsWith("#");
const indentOf = (l) => {
  const m = /^ */.exec(l);
  return m ? m[0].length : 0;
};

const lines = text.split(/\r?\n/);

// ---------- 全局预检（含块标量内部） ----------
if (text.startsWith("\uFEFF")) err(1, "文件以 BOM 开头（请以 UTF-8 无 BOM 保存）");
lines.forEach((raw, idx) => {
  const n = idx + 1;
  const line = raw.replace(/\s+$/, "");
  if (line.length === 0) return;
  if (/\t/.test(line)) err(n, "含 Tab 字符——缩进必须用空格");
  const ind = indentOf(line);
  if (ind % 2 !== 0) err(n, `缩进 ${ind} 格不是 2 的倍数（统一 2 空格缩进）`);
  if (!isComment(line) && line.includes("|| true")) err(n, "禁止 '|| true'——吞错误等于假绿");
});

// ---------- 白名单 ----------
const TOP_KEYS = new Set(["name", "run-name", "on", "concurrency", "env", "permissions", "jobs", "defaults", "vars"]);
const REQUIRED_TOP = ["on", "concurrency", "permissions", "jobs"];
const ON_KEYS = new Set(["push", "pull_request", "pull_request_target", "merge_group", "workflow_dispatch", "workflow_call", "schedule", "release", "create"]);
const EMPTY_OK_UNDER_ON = new Set(["push", "pull_request", "pull_request_target", "merge_group", "workflow_dispatch", "workflow_call", "release", "create"]);
const CONCURRENCY_KEYS = new Set(["group", "cancel-in-progress"]);
const PERM_KEYS = new Set(["contents", "pull-requests", "issues", "actions", "checks", "deployments", "packages", "statuses", "security-events", "id-token"]);
const PERM_VALUES = new Set(["read", "write", "none"]);
const JOB_KEYS = new Set(["needs", "if", "name", "runs-on", "timeout-minutes", "concurrency", "env", "permissions", "defaults", "strategy", "container", "services", "environment", "outputs", "steps"]);
const STEP_KEYS = new Set(["name", "uses", "run", "shell", "working-directory", "with", "env", "if", "id", "timeout-minutes"]);
const STRATEGY_KEYS = new Set(["matrix", "fail-fast", "max-parallel"]);
const KNOWN_RUNNERS = new Set([
  "ubuntu-latest", "ubuntu-24.04", "ubuntu-22.04", "ubuntu-20.04",
  "windows-latest", "windows-2025", "windows-2022", "windows-2019",
  "macos-latest", "macos-26", "macos-15", "macos-14", "macos-13",
  "self-hosted",
]);

// ---------- 收集器 ----------
const topSeen = new Set();
const onChildren = new Set();
const jobs = new Map(); // id -> { hasRunsOn, hasSteps, steps, line }
let currentJob = null;
let stepsTotal = 0;

// ---------- 行内值分析 ----------
// ${{ ... }} 视为不透明 EXPR；返回 clean（注释已剥离、引号保留）与
// bracketView（引号与表达式替换为不透明符，专查 flow 集合）。
function analyzeValue(raw, line) {
  let s = "";
  {
    let i = 0;
    while (i < raw.length) {
      if (raw.startsWith("${{", i)) {
        const end = raw.indexOf("}}", i + 3);
        if (end === -1) {
          err(line, "表达式 ${{ 没有对应的 }}");
          i = raw.length;
          s += " EXPR ";
          break;
        }
        s += " EXPR ";
        i = end + 2;
        continue;
      }
      s += raw[i];
      i += 1;
    }
  }
  let q = null;
  let clean = "";
  let bracketView = "";
  for (let k = 0; k < s.length; k += 1) {
    const ch = s[k];
    if (q !== null) {
      if (ch === q) q = null;
      clean += ch;
      bracketView += "Q";
      continue;
    }
    if (ch === '"' || ch === "'") {
      q = ch;
      clean += ch;
      bracketView += "Q";
      continue;
    }
    if (ch === "#" && (k === 0 || s[k - 1] === " " || s[k - 1] === "\t")) break; // 注释起点
    clean += ch;
    bracketView += ch;
  }
  if (q !== null) err(line, "引号未闭合");
  return { clean: clean.trim(), bracketView };
}

function checkUses(clean, line) {
  const v = clean;
  if (v.startsWith("docker://")) return;
  if (v.startsWith("./")) return; // 仓库内本地 action
  const m = /^([\w.-]+\/[\w.-]+)@([\w./-]+)$/.exec(v);
  if (!m) {
    err(line, `uses 写法应为 owner/repo@版本 tag（现在是「${v}」）`);
    return;
  }
  const ref = m[2];
  if (/^(main|master|latest|head)$/i.test(ref)) {
    err(line, `uses 禁止浮动引用 @${ref}——必须钉版本 tag 或 40 位 commit SHA`);
    return;
  }
  if (/^[0-9a-f]{40}$/.test(ref)) return;
  if (/^v?\d+(\.\d+)*(-[\w.]+)?$/.test(ref)) return;
  err(line, `uses 的引用「${ref}」不像版本 tag（v5 / 1.2.3）也不像 40 位 SHA`);
}

function checkScalarValue(key, clean, bracketView, line, path) {
  if (/[{}[\]]/.test(bracketView)) err(line, `键「${key}」的值出现了 flow 集合 { } [ ]——本合约只用块式写法`);
  if (key === "uses") checkUses(clean, line);
  else if (key === "runs-on") {
    if (bracketView.includes("EXPR") || KNOWN_RUNNERS.has(clean)) return;
    err(line, `runs-on 的标签「${clean}」不在已知托管 runner 列表（${[...KNOWN_RUNNERS].join("、")}）`);
  } else if (key === "timeout-minutes" && !/^\d+$/.test(clean)) err(line, "timeout-minutes 必须是纯数字");
  else if (key === "continue-on-error" && clean === "true") err(line, "禁止 continue-on-error: true——假绿之源");
  else if (key === "cancel-in-progress" && !/^(true|false)$/.test(clean)) err(line, "cancel-in-progress 只能是 true/false");
  else if (path[path.length - 1] === "permissions" && !PERM_VALUES.has(clean)) err(line, `permissions.${key} 的值只能是 read / write / none`);
}

// ---------- 结构解析 ----------
let pos = 0;

function skipBlank() {
  while (pos < lines.length) {
    const l = lines[pos];
    if (l.trim() === "" || isComment(l)) {
      pos += 1;
      continue;
    }
    break;
  }
}

function consumeBlockScalar(keyIndent) {
  while (pos < lines.length) {
    const l = lines[pos].replace(/\s+$/, "");
    if (l.trim() === "") {
      pos += 1;
      continue;
    }
    if (indentOf(l) > keyIndent) {
      pos += 1;
      continue;
    }
    break;
  }
}

const KEY_RE = /^([\w][\w.-]*)\s*:(.*)$/;

function checkKeyAllowed(key, path, num) {
  if (path.length === 0) {
    topSeen.add(key);
    if (!TOP_KEYS.has(key)) err(num, `顶层键「${key}」不在白名单（${[...TOP_KEYS].join("、")}）`);
    return;
  }
  const parent = path[path.length - 1];
  if (path.length === 1 && parent === "on") {
    onChildren.add(key);
    if (!ON_KEYS.has(key)) err(num, `on: 下的「${key}」不是允许的触发器（${[...ON_KEYS].join("、")}）`);
    return;
  }
  if (path.length === 1 && parent === "jobs") {
    if (!/^[a-z][a-z0-9_-]*$/.test(key)) err(num, `job id「${key}」需小写字母开头、只含小写字母/数字/-/_（job id 会成为 required check 的名字，起名要一辈子不改）`);
    if (jobs.has(key)) err(num, `重复的 job id「${key}」`);
    currentJob = { hasRunsOn: false, hasSteps: false, steps: 0, line: num };
    jobs.set(key, currentJob);
    return;
  }
  if (path.length === 2 && path[0] === "jobs") {
    if (!JOB_KEYS.has(key)) err(num, `job 内的键「${key}」不在白名单（${[...JOB_KEYS].join("、")}）`);
    if (currentJob) {
      if (key === "runs-on") currentJob.hasRunsOn = true;
      if (key === "steps") currentJob.hasSteps = true;
    }
    return;
  }
  if (path.length === 3 && path[0] === "jobs" && path[2] === "steps") {
    if (!STEP_KEYS.has(key)) err(num, `step 内的键「${key}」不在白名单（${[...STEP_KEYS].join("、")}）`);
    return;
  }
  if (path.length === 3 && path[0] === "jobs" && path[2] === "strategy") {
    if (!STRATEGY_KEYS.has(key)) err(num, "strategy 内的键只允许 matrix / fail-fast / max-parallel");
    return;
  }
  if (path.length === 1 && parent === "concurrency") {
    if (!CONCURRENCY_KEYS.has(key)) err(num, "concurrency 内只允许 group 与 cancel-in-progress");
    return;
  }
  if (path.length === 1 && parent === "permissions") {
    if (!PERM_KEYS.has(key)) err(num, `permissions 内的键「${key}」不是 GitHub 认可的权限域`);
    return;
  }
  // 其余层级（with、matrix、env、defaults、outputs、push 配置等）放开
}

function parseSeq(ind, path) {
  while (true) {
    skipBlank();
    if (pos >= lines.length) return;
    const raw = lines[pos].replace(/\s+$/, "");
    const cur = indentOf(raw);
    if (cur < ind) return;
    if (cur > ind) {
      err(pos + 1, "意外的缩进（比列表项还深）");
      pos += 1;
      continue;
    }
    if (!/^-\s/.test(raw.trimStart())) return; // 交还给上层
    const num = pos + 1;
    const itemText = raw.slice(ind + 2); // 去掉 "- "
    pos += 1;
    const inSteps = path.length >= 3 && path[0] === "jobs" && path[2] === "steps";
    if (KEY_RE.test(itemText)) {
      if (inSteps && currentJob) {
        currentJob.steps += 1;
        stepsTotal += 1;
      }
      parseMap(itemText, num, ind + 2, path);
    } else {
      if (inSteps) {
        err(num, "steps 的每一项都必须是映射（- name: … / - uses: … / - run: …），不能是纯标量");
      } else {
        const { clean, bracketView } = analyzeValue(itemText, num);
        if (clean === "") err(num, "空的列表项");
        else checkScalarValue("(列表项)", clean, bracketView, num, path);
      }
    }
  }
}

function parseMap(entryText, entryNum, entryIndent, path) {
  const seen = new Set();
  let cur = entryText;
  let curNum = entryNum;
  let pending = entryText !== null;
  while (true) {
    if (!pending) {
      skipBlank();
      if (pos >= lines.length) return;
      const raw = lines[pos].replace(/\s+$/, "");
      const ind = indentOf(raw);
      if (ind < entryIndent) return;
      if (ind > entryIndent) {
        err(pos + 1, "意外的缩进层级");
        pos += 1;
        continue;
      }
      cur = raw.trimStart(); // 剥掉行首缩进，KEY_RE 才能匹配（缩进已记在 ind 里）
      curNum = pos + 1;
      pos += 1;
    }
    pending = false;
    const m = KEY_RE.exec(cur);
    if (!m) {
      err(curNum, `不是「键: 值」形式：${cur.trim().slice(0, 60)}`);
      continue;
    }
    const key = m[1];
    checkKeyAllowed(key, path, curNum);
    if (seen.has(key)) err(curNum, `同层重复键「${key}」——YAML 会静默覆盖前者`);
    seen.add(key);
    const { clean, bracketView } = analyzeValue(m[2], curNum);
    const childPath = [...path, key];
    if (clean === "") {
      skipBlank();
      const deeper = pos < lines.length && indentOf(lines[pos]) > entryIndent;
      if (deeper) {
        parseNode(indentOf(lines[pos]), childPath);
      } else if (path.length === 1 && path[0] === "on" && EMPTY_OK_UNDER_ON.has(key)) {
        // on 下的空触发器（如 merge_group:）合法
      } else {
        const hint = pos < lines.length && /^-\s/.test(lines[pos].trim()) ? "（列表项需要再缩进 2 格）" : "";
        err(curNum, `键「${key}」没有值也没有子块${hint}`);
      }
    } else if (/^[|>][+-]?$/.test(clean)) {
      consumeBlockScalar(entryIndent);
    } else {
      checkScalarValue(key, clean, bracketView, curNum, childPath);
    }
  }
}

function parseNode(ind, path) {
  skipBlank();
  if (pos >= lines.length) return;
  const raw = lines[pos].replace(/\s+$/, "");
  const cur = indentOf(raw);
  if (cur < ind) return;
  if (/^-\s/.test(raw.trimStart())) parseSeq(cur, path);
  else parseMap(null, pos + 1, cur, path);
}

// ---------- 顶层解析 ----------
skipBlank();
if (pos < lines.length) parseNode(indentOf(lines[pos]), []);

// ---------- 汇总校验 ----------
for (const req of REQUIRED_TOP) {
  if (!topSeen.has(req)) err(0, `缺少顶层「${req}:」块`);
}
if (onChildren.size > 0 && !["push", "pull_request", "merge_group"].some((t) => onChildren.has(t))) {
  err(0, "on: 必须包含 push、pull_request 或 merge_group 之一");
}
if (jobs.size === 0) err(0, "jobs: 下没有任何 job");
for (const [id, j] of jobs) {
  if (!j.hasRunsOn) err(j.line, `job「${id}」缺少 runs-on`);
  if (!j.hasSteps) err(j.line, `job「${id}」缺少 steps`);
  else if (j.steps === 0) err(j.line, `job「${id}」的 steps 为空`);
}

// ---------- 输出 ----------
if (errors.length > 0) {
  console.error(`结构校验未通过，共 ${errors.length} 个问题：`);
  for (const e of errors) console.error(e);
  process.exit(1);
}
console.log(`✓ 结构校验通过：${jobs.size} 个 job、共 ${stepsTotal} 个 step（块式子集合约 + Actions 结构不变式）。`);
console.log("  注意：本结果只保证结构合约；step 语义正确性仍需评审与真实运行验证。");
