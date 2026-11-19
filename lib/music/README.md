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
| `player/` | — | M4-P 落地：media_kit 纯音频内核 + MobX store + 播放页/迷你条 |

## M4-P 播放线（点歌链路）

### 端点（一端点一文件，逐函数对照 Rust）

| 本仓库 | 上游 | 说明 |
|---|---|---|
| `api/user_verify.dart` | `module/user_verify.rs` | `/v1/user_verify`（网关 + `trackercdngz` 路由，`module_id=51`）→ 播放授权串 |
| `api/song_auth.dart` | `module/song_auth.rs` | `/v1/authorization`（五参数，hash 小写）→ 歌曲授权 + `open_time` |
| `api/song_url_auth.dart` | `module/song_url_auth.rs` | `/tracker/v5/url` **走网关**；24 个协议参数 + `tracker_key` |
| `api/kugou_playback_api.dart` | `module/song_url_auth_merge.rs` | 三段链路门面；默认 higher(320)，business 回退 standard(128) 一次 |

- `album_audio_id` 只取 `MusicSong.id`（MixSongID），**不回退 `audioId`**。
- 质量映射：`standard→128 / higher→320 / flac→flac / hiRes→high /
  viperTape→viper_tape / viperClear→viper_clear / viperAtmos→viper_atmos /
  automatic→128`。
- `timeLength` 秒→毫秒；`std_hash_time` 已是毫秒，原样透传。
- tracker `status!=1` → business 带 `error_code`；`status==1` 但 `url` 空 →
  business（产品约束，提前失败，不把空地址交给播放器）。

### 播放器内核 / UI

- `player/media_kit_music_engine.dart`：media_kit `Player`（纯音频，不建
  `VideoController`）；`open(play:false)` 后由 store 显式 `play()`。
- `player/player_store.dart`：队列/索引/快照/解析中/错误；引擎工厂惰性求值；
  进度写入按注入时钟 10 秒节流（换歌/暂停/拖动/播完强制写）。
- `player/player_ui_impl.dart`：实现契约 `MusicPlayerUi`，registry 注入
  `createMusicPlayerUi`。
- `player/pages/`：播放页（封面/进度/上下首/错误重试/队列抽屉）+ 迷你条。

### 匿名播放结论（2026-11-19 实测）

匿名设备可以搜索，但 `/v1/user_verify` 返回 `business/35002`，拿不到播放
授权 —— 即**未登录不可播**。`KugouPlaybackApi` 对匿名身份的这一业务失败
映射为 `authentication`（UI 文案「请先登录酷狗账号后播放」，保留原始
code）；已登录账号的 business 原样透出错误码。详见
`docs/music-playback-probe.md`（本地）。

### 本线未做（下一片）

后台播放 / SMTC / 歌词 / 下载 / 歌单榜单 / 倍速 UI；`music_entry.dart` 的
进度写入口（`ProgressSink` 适配 `history.saveProgress`）由集成方在 C 线
合入后接线。


## 设备引导（ensureDevice）

1. 本地无身份 → 生成匿名身份：guid=UUID v4、mid=calculateMid(guid)
   （MD5 hex → 十进制大整数，Node `calculateMid` 同构）、dfid=`'-'`；
2. dfid 为 `'-'`/空 → `registerDevice`（userservice.kugou.com
   `/risk/v3/r_register_dev`，请求体 = AES 信封 + RSA 画像，响应为二进制密文，
   用同一 seed 解密取 dfid）；
3. 每一步落盘 `<appSupport>/music_device/music_identity.json`。
   启动期不发网络请求——注册在首次搜索时惰性触发，失败下次重试。

## 扫码登录（M4-L）

- **端点**（`api/login_qr.dart` ← `login_qr_key.rs` / `login_qr_check.rs`）：
  - `GET /v2/qrcode`（login-user.kugou.com，**web 签名**）：`appid=1001`、
    `type=1`、`plat=4`、`srcappid=2919`、`qrcode_txt` 末尾带 `&`；响应
    `data.qrcode`（会话 key）与 `data.qrcode_img`（PNG data URL，`scalar`
    宽容：数字/字符串都收）。
  - `GET /v2/get_userinfo_qrcode`：`appid=3116`、`srcappid=2919`、`plat=4`、
    `qrcode=<key>`、`dev=<deviceName>`；`data.status` → `0 expired / 1 waiting /
    2 scanned / 4 authorized`（4 缺 userid/空 token → `authentication`，
    其它值 → `business(code=status)`）。
  - 两端点都用 `identity.withoutAccount()` 请求（token/userid/t1 不带）；
    key 为空或超 4096 → `input`，不发请求。
- **身份**（`client/kugou_identity.dart`）：新增可选 `nickname` / `avatarUrl`
  与 `withAccount(...)` / `accountLabel`；`withoutAccount()` 一并清空账号
  展示字段。旧身份 JSON 缺这两个键仍可读；`KugouMusicApi` 同时实现
  `MusicIdentityApi`（`saveIdentity` 复用同一份缓存/写盘路径）。
- **门面**（`api/music_account_api.dart` 的 `KugouAccountApi`）：`start/poll`
  先 `ensureDevice()`；`loginWith` 合并账号字段并落盘（userId=0/空 token
  直接 `input`，不写盘）；`logout` 清账号保留设备、幂等。
- **控制器/UI**：`pages/qr_login_controller.dart` 状态机
  `idle → loading → waiting ⇄ scanned → authorized | expired | failed`；只在
  用户打开对话框后 `start()`，`cancel/dispose` 后无定时器。设置页用
  `Image.memory` 渲染 data URL（兼容 `data:image/png;base64,` 前缀与纯
  base64），登录态显示头像/昵称/ID 与退出入口。
- **已知约束**：扫码只返回 `userid + token`，**不含 `t1`**；
  `/v5/login_by_token` 自动续期本片不做——登录态过期时提示重新扫码。

## 黄金向量

- `test/music/client/signature_test.dart`：独立 Python 实现交叉生成的向量；
- `test/music/api/register_dev_test.dart`：上游
  `tests/fixtures/protocol/register-dev-request-20261017.json`（明文 JSON、
  seed、AES 密文 base64 逐字节对拍）。

## M4-C 数据层（收藏 / 历史 / 搜索历史）

> 双记账对齐 anime/comic：模块私有 drift 库是权威，`core/media_entries` 只收
> 投影。设计清单见 `docs/music-dual-ledger.md`（本地文档，不入公开仓库）。

- **表**（`music_db.dart`，生成物 `music_db.g.dart` 入库）：
  `music_collect`（`id` 主键，保存 `MusicSong` 完整 JSON）、
  `music_history`（`positionMs/durationMs/openedAt/playCount/payload`）、
  `music_search_term`（`keyword` 主键 + `hits`）。音乐没有源维度，投影
  `sourceName` 恒为 `kugou`。
  `MusicDb()` 用 `LazyDatabase`（构造零 I/O，首查才开库）；测试用
  `MusicDb.forTesting(NativeDatabase.memory())`。
- **服务**（实现契约 `library_api.dart` 的三接口；额外提供列表方法）：
  `MusicCollectService.list()`、`MusicHistoryService.recent()`、
  `MusicSearchHistoryService.record/recent/clear`。构造 `(MusicDb, LibraryRepository)`。
- **投影**（`music_projection.dart`）：唯一写入口 `syncMusicProjection`
  - payload 恒为 `{"positionMs": int, "durationMs": int}`（毫秒），歌曲 JSON 不泄漏；
  - `progressText`：无历史 → `尚未播放`；有历史 → `已听 N%`（夹 0–100）或 `听过`；
  - `createdAt` 优先收藏时间、`lastOpenedAt` 优先历史打开时间（与 anime 投影同序）。
- **页面**：`pages/music_library_page.dart`（收藏 / 历史两段）+ `music_library_store.dart`
  （MobX，仅本页状态）。历史条目点击经 `onPlaySong(song, startAt)` 续播，
  未接线时提示「播放功能未接线」。
- **装配变化**：`initAppModules` 新增 `musicDb`；C 段在未注入服务时用
  `MusicDb` 构造三个服务与默认 `libraryBuilder`（registry 自建库记入
  `_ownedMusicDb`，reset 时关闭）。`MusicApi` 零改动。

## 骨架范围 / 后续切片

已落：设备身份引导 + 签名/加密地基 + 搜索端到端 + 模块注册/主页/设置。
传输层语义与 Rust 对齐：非 2xx 抛 `http`、重定向不跟随（防签名凭证外流）、
error_code=20018 在 decode 层统一映射 `authentication`、信封 status/error_code
必填标量、bool 不当文本（不产生 `"true"` 假 dfid 这类持久化污染）、非数组
不吞成空表、AlbumPrivilege → Privilege 回退链。

待落（按依赖序）：
1. **登录续期**：`login_token`（`/v5/login_by_token` 需要 `t1`，扫码不回传
   `t1`，故本片不做自动续期）；`AuthenticationMode` 与切换逻辑届时一并翻译；
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
