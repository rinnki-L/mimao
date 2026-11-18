# lib/music/ — 音乐模块（M4）

酷狗概念版登录态 API 客户端的 Dart 重写。规划：`docs/architecture.md` §4.3；
目录契约：`docs/directory-layout.md` §1 music/ 段。

## 上游与来源

- **上游（Electron）**：[hoowhoami/EchoMusic](https://github.com/hoowhoami/EchoMusic)。
  它的酷狗概念版 API **不是自研**——以 git submodule 把
  [MakcRe/KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi)（Node.js）
  挂为 `server/`（见其 `.gitmodules`）。
- **翻译对照（Rust）**：[hoowhoami/EchoMusicNext](https://github.com/hoowhoami/EchoMusicNext)
  的 `crates/echo-api/`（Qt+Rust 下一代）。**Dart 侧逐函数对照 Rust 翻译，
  Rust 只读**；Node 版（KuGouMusicApi）作为协议语义旁证（签名 helper.js、
  guid/mid/dfid 生成规则均已在 Node/Rust 两边核对一致）。

## 目录对照表

| 本仓库 | EchoMusicNext | 说明 |
|---|---|---|
| `models/music_models.dart` | `src/domain.rs`（子集） | 曲目/歌手/分页/音质资源 |
| `client/signature.dart` | `src/util/signature.rs` | 全函数翻译（android/web/album_cover/tracker_key/cloud_key） |
| `client/kugou_crypto.dart` | `src/util/crypto.rs`（子集） | 仅 register_dev 信封（AES-128-CBC-PKCS7 + RSA PKCS#1 v1.5 + 6 位 seed） |
| `client/kugou_identity.dart` | `src/util/request.rs Identity` + Node util.js | 身份快照 + JSON 文件仓库 + guid/mid 生成 |
| `client/kugou_client.dart` | `src/util/request.rs ApiClient/send_endpoint` | 默认参数/签名/主机表/头/字节响应 |
| `client/kugou_error.dart` | `src/error.rs` | kind 词表异常 |
| `api/register_dev.dart` | `src/module/register_dev.rs` | 设备注册（含加密信封与响应解密） |
| `api/search.dart` | `src/module/search.rs`（Song 分支） | /v2/search/song + 音质事实折叠 |
| `api/wire.dart` | `src/util/response.rs`（子集） | 信封与宽容解码 |
| `api/music_api.dart` | `src/lib.rs execute` 的门面等价物 | MusicApi 接口 + ensureDevice 引导 |
| `pages/` | —（自写 UI） | 搜索主页 + 设置分组 |
| `player/` | — | **暂不建目录**；播放器切片时随 media_kit/audio_service 落位 |

## 设备引导（ensureDevice）

1. 本地无身份 → 生成匿名身份：guid=UUID v4、mid=calculateMid(guid)
   （MD5 hex → 十进制大整数，Node `calculateMid` 同构）、dfid=`'-'`；
2. dfid 为 `'-'`/空 → `registerDevice`（userservice.kugou.com
   `/risk/v3/r_register_dev`，请求体 = AES 信封 + RSA 画像，响应为二进制密文，
   用同一 seed 解密取 dfid）；
3. 每一步落盘 `<appSupport>/music_device/music_identity.json`。
   启动期不发网络请求——注册在首次搜索时惰性触发，失败下次重试。

## 黄金向量

- `test/music/client/signature_test.dart`：独立 Python 实现交叉生成的向量；
- `test/music/api/register_dev_test.dart`：上游
  `tests/fixtures/protocol/register-dev-request-20261017.json`（明文 JSON、
  seed、AES 密文 base64 逐字节对拍）。

## 骨架范围 / 后续切片

已落：设备身份引导 + 签名/加密地基 + 搜索端到端 + 模块注册/主页/设置。
传输层语义与 Rust 对齐：非 2xx 抛 `http`、重定向不跟随（防签名凭证外流）、
error_code=20018 在 decode 层统一映射 `authentication`、信封 status/error_code
必填标量、bool 不当文本（不产生 `"true"` 假 dfid 这类持久化污染）、非数组
不吞成空表、AlbumPrivilege → Privilege 回退链。

待落（按依赖序）：
1. **登录**：login_qr_key/login_qr_check/login_token（crypto.rs 其余信封；
   web 签名路径已就位）→ token/userid 注入 Identity（settings 页占位已挂；
   `AuthenticationMode` 与切换逻辑届时一并翻译）；
2. **播放**：song_auth（/v1/authorization）→ song_url_auth（/tracker/v5/url
   + tracker_key）→ player/ 目录（media_kit 复用番剧内核 + audio_service
   SMTC，经 core/media_session.dart 唯一 handler，architecture §6.2）；
3. **数据层**：MusicDb（收藏/历史双记账 + core 投影，对齐 anime/comic）；
4. **歌单/榜单**：playlist_* / rank_* / user_* 端点 + 页面。

已知骨架期裁剪（对照 Rust 的差异，均有意为之）：
- search 的 `trans_param`（版权映射 WireTrans）不解析——播放/下载切片再补；
- crypto.rs 其余信封函数未翻译（登录/云盘切片按同一上游文件补齐）；
- receive 层的 retry-after/ssa-code/challenge 拦截、16MB 响应上限、
  host 显式超时未翻译（骨架端点不触发；播放/登录切片按需补齐）；
- 端点声明的 clienttime/x-router 头与默认派生值的覆盖优先级未翻译
  （骨架端点不声明这两类头）；
- search wire 的 `<em>` 高亮标签在展示层剥除，模型保持上游原样。
