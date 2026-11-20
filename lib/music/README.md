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

### 进度写入口（已在集成收口接线）

`app_registry.dart` 在未显式注入 `musicProgressSink` 时，把 `ProgressSink`
接到 C 线 `history.saveProgress`（内部事务写权威表 + 投影 core）；登录/播放/
收藏历史三条线合并时已生效。播放线在暂停/拖动/切歌/播完/每 10 秒调用；
解析新地址期间（`isResolving`）不写，避免把旧曲快照记到新歌头上。

### 本线未做（下一片）

后台播放 / SMTC / 歌词 / 下载 / 歌单榜单 / 倍速 UI。


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

已落（三线合并后）：搜索/设备引导之外，播放链路（user_verify → song_auth
→ tracker，匿名不可播映射登录提示）、扫码登录（二维码会话 + 身份注入）、
收藏/历史/搜索历史（MusicDb 双记账 + 统一书架投影 + 「我的」页）。

待落（按依赖序）：
1. **登录续期**：`login_token`（`/v5/login_by_token` 需要 `t1`，扫码不回传
   `t1`，故不做自动续期）；`AuthenticationMode` 与切换逻辑届时一并翻译；
2. **后台播放 / 媒体会话**：audio_service + `core/media_session.dart` 唯一
   handler（architecture §6.2），SMTC/媒体键；
3. **歌单/榜单/每日推荐**：playlist_* / rank_* / everyday_* 端点 + 页面；
4. **歌词 / 下载**：TTML 夹具 + 离线缓存。

已知骨架期裁剪（对照 Rust 的差异，均有意为之）：
- search 的 `trans_param`（版权映射 WireTrans）不解析——播放/下载切片再补；
- crypto.rs 其余信封函数未翻译（登录/云盘切片按同一上游文件补齐）；
- receive 层的 retry-after/ssa-code/challenge 拦截、16MB 响应上限、
  host 显式超时未翻译（骨架端点不触发；播放/登录切片按需补齐）；
- 端点声明的 clienttime/x-router 头与默认派生值的覆盖优先级未翻译
  （骨架端点不声明这两类头）；
- search wire 的 `<em>` 高亮标签在展示层剥除，模型保持上游原样。


## M4-X 全量端点扩容（2026-11-21）

在骨架/播放/登录/收藏三条线之外，把 EchoMusicNext `crates/echo-api` 里
**除评论/云盘/MV/社交之外**的端点全部移植，并接入可浏览的 UI。排除清单：

- 评论 `comment_*`（12）
- 云盘 `user_cloud*`（5）
- MV/视频 `video_*`、`mv_collect*`、`kmr_audio_mv`、`user_video_collect`、
  `song_barrage*`
- 社交 `listen_together_*`、`blacklist*`、`user_follow*`、`user_fans`、
  `user_friends`、`user_visitors`、`artist_follow`/`artist_unfollow`

### 端点组（12 个域 / 70+ 端点）

| 域 | Dart 门面 | 端点 |
|---|---|---|
| 搜索扩展 | `api/search_ext_api.dart` | search Album/Author/Special/Lyric 分支、search_default、search_hot、search_suggest、search_lyric、sidedt |
| 发现/推荐 | `api/discovery_api.dart` | home_discover、everyday_recommend、everyday_style_recommend、ai_recommend_song、personal_fm、song_climax |
| 榜单 | `api/rank_api.dart` | rank_list、rank_top、rank_audio、song_ranking、song_ranking_filter、top_album、top_ip、top_playlist、top_song |
| 专辑 | `api/album_api.dart` | album_detail、album_dycover、album_songs、favorite_count |
| 歌手 | `api/artist_api.dart` | artist_detail、artist_albums、artist_audios_new、artist_lists |
| 音效 | `api/effects_api.dart` | effects_artist、effects_brand、effects_brand_detail、effects_match |
| 歌单读 | `api/playlist_read_api.dart` | playlist_detail、playlist_track_all、playlist_track_all_new、playlist_tags、import_playlist |
| 歌单写 | `api/playlist_write_api.dart` | playlist_add/del/update/sort、tracks_add/del/sort、pic_upload |
| 用户资料 | `api/user_profile_api.dart` | user_info、user_detail、user_update、update_avatar、avatar_upload、vip_detail、grade_info、batch_union_vipinfo |
| 用户库 | `api/user_library_api.dart` | user_history、user_playlist、user_preference(+update)、purchased_albums/songs、verify_user_info |
| 登录 | `api/auth_login_api.dart` | login、cellphone、token、qq/openplat、qq/wx qr create/check、device、device_kick |
| 验证/歌词 | `api/verify_api.dart`、`api/lyric_api.dart` | captcha_sent、get_verify_info、lyric |
| 播放扩展 | `api/playback_ext_api.dart` | audio_match、privilege_lite、get_model、images_audio、krm_audio |
| 听歌上报 | `api/listen_report_api.dart` | user_listen_report（CSCC 握手 + 事件 + 内存会话缓存） |

共享底座：

- `api/session.dart`：`MusicSession`（客户端 + 身份读写）与
  `requireMusicAccount`；`KugouMusicApi` 把全部端点组惰性装配进
  `MusicBrowseApis`（`api/music_browse_apis.dart`）。
- `client/kugou_client.dart`：新增 `sendRaw`（固定主机裸传输：CSCC、头像/歌单
  封面、动态封面；保留全部响应头值）。
- `client/kugou_crypto.dart`：补齐裸 RSA 画像、AES-256、登录/验证/偏好/云歌单
  信封；关键路径用上游黄金向量对拍。
- `api/wire.dart`：`optionalBool`/`requiredWireMap`/`coverUrl`/`encodeJsonBody`/
  `decodeEnvelopeWithFields`；登录过期严格对齐上游（只认 `error_code` + msg
  文本，`errcode=20018` 是 business）。

### UI 接线

- 音乐主页首 tab：`pages/music_discovery_page.dart`（发现/歌曲/专辑/歌手/歌单/
  歌词六 tab；默认词/热词/建议、首页发现、每日推荐、AI 畅听、私人 FM）。
- `pages/music_rank_page.dart` + `music_rank_detail_page.dart`：榜单/新歌/专辑/
  歌单/IP。
- `pages/music_album_detail_page.dart`、`music_artist_detail_page.dart`。
- `pages/music_playlist_list_page.dart`、`music_playlist_detail_page.dart`：
  云/公开歌单、新建/删除（write 注入时）。
- `pages/music_account_center_page.dart`：资料/会员/听歌等级/历史/已购/我的歌单。
- 主页底部 tab：发现（无扩展时回退旧搜索）/ 我的（顶部「我的歌单」入口）/
  账号 / 设置；迷你播放条与播放页保持原状。

### 验证

- 14 个 API 工作流 + 5 个 UI 工作流均在独立 worktree 中完成，逐组通过
  `dart format` / `flutter analyze`（0 issue）/ 组内测试后合并。
- 全仓 `flutter test --coverage`：1280 条用例全绿，行覆盖率 76.4%
  （CI 口径：lcov 已 import 文件集，阈值 60%）。
- `dart fix --dry-run`（lib/music、lib/shell、test/music）：无待修项。

### 已知边界（有意保留）

- 歌词端点只下载 base64 文档（krc/lrc/text），不在 Dart 侧解析 KRC 文档；
  UI 按纯文本展示。
- 云盘/评论/视频/社交/关注端点按需求排除，不建文件。
- u64 上限（>2^63-1）在 Dart `int` 下不可表示；真实 id 不会触达。
- `MusicCatalogRights` 等少数 catalog 共享结构在 album/user_library/
  playback_ext 三组各有一份（上游同名 util 的独立翻译），字段语义一致；
  后续可抽取到 `models/catalog_rights_models.dart` 统一。
- 私人 FM「换一批」未透传 curMark/batchMark（上游翻页语义未验证）。
- sideDt（安全上报）、everydayStyleRecommend、songClimax 已提供 API，UI 未
  单独入口；播放页歌词/高潮区间留待播放线后续切片。
