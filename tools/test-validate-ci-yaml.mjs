// test-validate-ci-yaml.mjs — validate-ci-yaml.mjs 的回归测试。
// 用法：node test-validate-ci-yaml.mjs；全部通过退出码 0。
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const validator = path.join(here, "validate-ci-yaml.mjs");
const tmp = mkdtempSync(path.join(tmpdir(), "ci-yaml-test-"));

// 最小合规样例
const MINIMAL = [
  "name: 最小样例",
  "",
  "on:",
  "  push:",
  "    branches:",
  "      - main",
  "",
  "concurrency:",
  "  group: ci-${{ github.ref }}",
  "  cancel-in-progress: true",
  "",
  "permissions:",
  "  contents: read",
  "",
  "jobs:",
  "  gate:",
  "    runs-on: ubuntu-latest",
  "    timeout-minutes: 10",
  "    steps:",
  "      - name: 检出",
  "        uses: actions/checkout@v5",
  "      - name: 脚本",
  "        run: |",
  "          set -euo pipefail",
  "          echo ok",
].join("\n");

// 完整合规样例（矩阵、块标量、表达式、空触发器全用到）
const GOOD = [
  "name: CI",
  "",
  "on:",
  "  push:",
  "    branches:",
  "      - main",
  "  pull_request:",
  "    branches:",
  "      - main",
  "  merge_group:",
  "",
  "concurrency:",
  "  group: ci-${{ github.workflow }}-${{ github.ref }}",
  "  cancel-in-progress: true",
  "",
  "permissions:",
  "  contents: read",
  "",
  "env:",
  '  FLUTTER_VERSION: "3.50.0"',
  "",
  "jobs:",
  "  quality:",
  "    name: 质量（格式 + 分析 + 测试）",
  "    runs-on: ubuntu-latest",
  "    timeout-minutes: 30",
  "    steps:",
  "      - name: 检出",
  "        uses: actions/checkout@v5",
  "        with:",
  "          fetch-depth: 0",
  "      - name: 装 Flutter",
  "        uses: subosito/flutter-action@v2",
  "        with:",
  "          flutter-version: ${{ env.FLUTTER_VERSION }}",
  "          cache: true",
  "      - name: 锁文件安装",
  "        run: |",
  "          set -euo pipefail",
  "          flutter pub get --enforce-lockfile",
  "      - name: 测试门",
  "        run: |",
  "          set -euo pipefail",
  "          flutter test --coverage",
  "",
  "  build:",
  "    name: 构建",
  "    needs: quality",
  "    strategy:",
  "      fail-fast: false",
  "      matrix:",
  "        include:",
  "          - os: windows-latest",
  "            target: windows",
  "          - os: ubuntu-latest",
  "            target: android",
  "    runs-on: ${{ matrix.os }}",
  "    timeout-minutes: 45",
  "    steps:",
  "      - name: 检出",
  "        uses: actions/checkout@v5",
  "      - name: 构建",
  '        run: |',
  "          set -euo pipefail",
  '          echo "building ${{ matrix.target }}"',
  "",
  "  mergeability:",
  "    name: 合并预演",
  "    runs-on: ubuntu-latest",
  "    timeout-minutes: 10",
  "    steps:",
  "      - name: 检出",
  "        uses: actions/checkout@v5",
  "        with:",
  "          fetch-depth: 0",
  "      - name: 预演合并",
  "        run: |",
  "          set -euo pipefail",
  "          git fetch origin main",
  "          git merge-tree --write-tree --name-only HEAD origin/main",
].join("\n");

const cases = [
  { name: "good-full", yaml: GOOD, expect: 0 },
  { name: "minimal-good", yaml: MINIMAL, expect: 0 },
  { name: "empty-trigger-ok", yaml: MINIMAL.replace("on:\n  push:\n    branches:\n      - main", "on:\n  merge_group:"), expect: 0 },
  { name: "tab", yaml: MINIMAL.replace("jobs:", "\tjobs:"), expect: 1, contains: "Tab" },
  { name: "flow-style", yaml: MINIMAL.replace("on:\n  push:", "on: [push]"), expect: 1, contains: "flow" },
  { name: "dup-key", yaml: MINIMAL.replace("permissions:\n  contents: read", "permissions:\n  contents: read\n  contents: write"), expect: 1, contains: "重复键" },
  { name: "floating-ref", yaml: MINIMAL.replace("@v5", "@main"), expect: 1, contains: "浮动" },
  { name: "bad-ref", yaml: MINIMAL.replace("@v5", "@abc"), expect: 1, contains: "不像" },
  { name: "coe", yaml: MINIMAL.replace("      - name: 脚本", "      - name: 脚本\n        continue-on-error: true"), expect: 1, contains: "continue-on-error" },
  { name: "no-runs-on", yaml: MINIMAL.replace("    runs-on: ubuntu-latest\n", ""), expect: 1, contains: "runs-on" },
  { name: "pipe-true", yaml: MINIMAL.replace("echo ok", "echo ok || true"), expect: 1, contains: "|| true" },
  { name: "unknown-top", yaml: "bogus: 1\n" + MINIMAL, expect: 1, contains: "顶层键" },
  { name: "odd-indent", yaml: MINIMAL.replace("    runs-on: ubuntu-latest", "     runs-on: ubuntu-latest"), expect: 1, contains: "2 的倍数" },
  { name: "upper-job-id", yaml: MINIMAL.replace("  gate:", "  Gate:"), expect: 1, contains: "job id" },
];

let failed = 0;
for (const c of cases) {
  const p = path.join(tmp, `${c.name}.yml`);
  writeFileSync(p, c.yaml, "utf8");
  const r = spawnSync("node", [validator, p], { encoding: "utf8" });
  const out = `${r.stdout || ""}${r.stderr || ""}`;
  const exitOk = r.status === c.expect;
  const containsOk = !c.contains || out.includes(c.contains);
  if (exitOk && containsOk) {
    console.log(`PASS ${c.name}`);
  } else {
    failed += 1;
    console.log(`FAIL ${c.name}（退出码 ${r.status}，期望 ${c.expect}${c.contains && !containsOk ? `；输出未含「${c.contains}」` : ""}）`);
    console.log(out.split("\n").map((l) => `    ${l}`).join("\n"));
  }
}

rmSync(tmp, { recursive: true, force: true });
console.log(failed === 0 ? `\n全部 ${cases.length} 个用例通过。` : `\n${failed}/${cases.length} 个用例失败。`);
process.exit(failed === 0 ? 0 : 1);
