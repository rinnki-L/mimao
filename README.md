<div align="center">

<h1>mimao</h1>

<img src="https://raw.githubusercontent.com/rinnki-L/mimao/main/assets/mimao.png" alt="mimao" width="200"></img>

<img alt="license" src="https://img.shields.io/badge/license-GPL--3.0-blue.svg?style=for-the-badge"></img>
<img alt="Flutter" src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white"></img>
<img alt="Dart" src="https://img.shields.io/badge/Dart-0175C2?style=for-the-badge&logo=dart&logoColor=white"></img>
<img alt="status" src="https://img.shields.io/badge/status-%E8%A7%84%E5%88%92%E6%9C%9F-orange.svg?style=for-the-badge"></img>

<p>一个把 <strong>漫画 · 小说 · 音乐</strong> 聚到一处的本地媒体应用。使用 Flutter + Material 3 开发, 桌面优先 (Windows), 纯本地运行、无需自建服务器。三大模块分别移植自成熟的开源客户端, 目录按上游形状生长, 便于跟随上游修复。绝赞规划中 (～￣▽￣)～</p>

</div>

## 支持平台

- Windows 10 及以上（首发目标）
- Android（同一套代码, 次要优先级）

> 目前工程本体尚未开工, 以上为目标平台；后续会随实现更新。

## 功能 / 开发计划

- [ ] 统一的 Material 3 壳（拼贴式三入口 + 全局设置）
- [ ] 漫画模块（复用 Venera 的 `flutter_qjs` 漫画源）
- [ ] 音乐模块（重写酷狗概念版 API 网络层 + 播放器）
- [ ] 小说模块（legado 书源引擎 Dart 化, 最难、最后做）
- [ ] 统一书架 / 收藏 / 历史 / 下载
- [ ] 我的（个人中心）

## 设计

三个模块各自的来源与接入方式：

| 内容 | 参考上游 | 接入方式 |
| --- | --- | --- |
| 漫画 | [Venera](https://github.com/venera-app/venera) | 复用 `flutter_qjs` 漫画源与模块（Venera-Next 可借鉴） |
| 小说 | [legado 阅读](https://github.com/gedoor/legado) | 书源引擎在 Dart 中重写 |
| 音乐 | [EchoMusicNext](https://github.com/hoowhoami/EchoMusic) | 重写酷狗概念版 API 网络层 + 播放器 |

## 开发

欢迎提交 PR！动手前请先了解项目的模块划分与边界约定。

本地校验 CI 配置：`node tools/validate-ci-yaml.mjs .github/workflows/ci.yml`

## 美术资源

应用图标 `assets/mimao.png` 由本项目所有, 依据现有角色形象、融入自己的想法设计, 随本项目以 GPL-3.0 开源。

## 免责声明

本项目基于 GNU 通用公共许可证第 3 版（GPL-3.0）授权。我们不对其适用性、可靠性或准确性作出任何明示或暗示的保证。在法律允许的最大范围内, 作者和贡献者不承担任何因使用本软件而产生的直接、间接、偶然、特殊或后果性的损害赔偿责任。

使用本项目需遵守所在地法律法规, 不得进行任何侵犯第三方知识产权的行为。

## 隐私政策

本项目纯本地运行, 引擎直连内容站点；不收集任何用户数据, 不使用任何遥测组件, 无自建服务器。

## 致谢

特别感谢以下上游项目, 本项目站在它们的肩膀上：

- [Venera](https://github.com/venera-app/venera) — 漫画模块与 `flutter_qjs` 漫画源；[Venera-Next](https://github.com/venera-app/venera-next) 作为活跃后续版本供借鉴
- [legado 阅读](https://github.com/gedoor/legado) — 小说书源引擎的参考实现
- [EchoMusicNext](https://github.com/hoowhoami/EchoMusic) — 音乐模块网络层的参考实现

上游署名与改动清单将在工程落地时写入 `NOTICE`。
