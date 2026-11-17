<p align="center">
  <img src="assets/mimao.png" alt="mimao 图标" width="220" />
</p>

<h1 align="center">mimao</h1>

<p align="center">
  一个把 <strong>番剧 · 漫画 · 小说 · 音乐</strong> 聚到一起的本地媒体应用。<br/>
  Flutter + Material 3 · 桌面优先（Windows）· 纯本地、无自建服务器
</p>

<p align="center">
  <img alt="license" src="https://img.shields.io/badge/license-GPL--3.0-blue.svg" />
  <img alt="status" src="https://img.shields.io/badge/status-planning-orange.svg" />
  <img alt="platform" src="https://img.shields.io/badge/platform-Windows%20%7C%20Android-lightgrey.svg" />
</p>

---

## 这是什么

`mimao` 的目标是把四个各自好用的开源媒体客户端整合进一个统一的 Material 3 壳里：

| 内容 | 参考上游 | 接入方式 |
| --- | --- | --- |
| 番剧 | [Kazumi](https://github.com/Predidit/Kazumi) | 移植其规则引擎与 UI 模块 |
| 漫画 | [Venera-Next](https://github.com/venera-app/venera-next) | 复用 `flutter_qjs` 漫画源与模块 |
| 小说 | [legado 阅读](https://github.com/gedoor/legado) | 书源引擎在 Dart 中重写（最难、最后做） |
| 音乐 | [EchoMusicNext](https://github.com/hoowhoami/EchoMusic) | 重写酷狗概念版 API 网络层 + 播放器 |

设计哲学是 **「少一层是一层」**：目录是长出来的器官，不是画出来的对称图。
壳和核心从本项目自带的 demo 长出来，四个模块的内部形状各自镜像上游，方便上游修复 patch 机械对照。

现状：**规划期**。架构、目录布局、CI 与多个可交互 demo 已经就位，Flutter 工程本体尚未开工。
详见 [架构设计](docs/architecture.md) 与 [目录布局](docs/directory-layout.md)。

## 仓库里有什么

- `docs/` — 架构设计、目录布局、对抗式规划复盘
- `demos/` — 若干单文件、可直接阅读的选型 demo 与交互 HTML 预览（含图标方案）
- `assets/` — 应用图标
- `tools/` — CI 校验脚本等辅助工具
- `.github/workflows/ci.yml` — 严格的 CI 流水线（Flutter 工程落地前部分任务为红，属预期）

## 技术选型（已定）

- Flutter + Material 3，Dart 为唯一需要新学的语言
- 桌面优先：Windows 首发，Android 随后，同一套代码
- 状态管理采用 MobX（与 Kazumi 一致）；统一核心数据层建议 drift/SQLite（待最终拍板）
- GPL-3.0：与四个上游保持一致，上游署名与改动清单将写入 `NOTICE`

## 许可

本项目以 **GPL-3.0** 发布，详见 [LICENSE](LICENSE)。
上游项目的署名与改动说明会在工程落地时写入 `NOTICE`。

应用图标为原创角色设计（AI 辅助生成），随项目以 GPL-3.0 开源；若未来用于商业用途，建议先行做商标/标识检索。
