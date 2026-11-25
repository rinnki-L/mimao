# LESSON.md — mimao 踩坑账本

> 随仓库走（入库，新机器 clone 即得）。只记**会再犯、犯了会痛**的具体坑；每条 ≤4 行：现象 / 为什么 / 怎么断。
> 条目末尾的 ✕ 是复发计数：**同一处错满 ✕✕✕ 就搬进 `AGENTS.md` 硬约束**，这里标「已晋升」。
> 不收：交付流水、commit 号、"某某已交付"、进度快照、一次性偶发故障——那些 git 记得更准。
>
> **这份账本自己会改**：干活时发现某条已被修复或写错了，直接改——标 `~~已失效~~（日期：原因）` 或删除；踩到新坑就按格式补一条。改前先核对源码，只碰相关条目，改完在条目里留一行依据（见 `AGENTS.md`「这两份文档自己会改」）。

---

## 一、Flutter 测试与热重载

### 真实 I/O 让 pumpAndSettle 永久超时　复发：✕
**现象**：`testWidgets` 里碰真实 `dart:io`（目录、文件、PathProvider），`pumpAndSettle` 永不返回，测试挂到超时。
**为什么**：`testWidgets` 跑在 FakeAsync 里，真实异步的 Future 不归它调度；而且关闭的内存 drift 写入不会抛异常，所以连错都看不到。
**怎么断**：碰文件系统的用例抽成可注入 seam，或用 `test()` 跑真实异步，不要在 `testWidgets` 里等真实 I/O。

### repeat() 无限动画让测试挂死　复发：✕
**现象**：同一个 `pumpAndSettle` 超时，但代码里根本没有 I/O。
**为什么**：`AnimationController.repeat()` 永远有下一帧，settle 等不到静止。
**怎么断**：测试环境关掉循环动画（或注入一个不重复的控制器），真机才让它转。

### setState 箭头简写返回 Future　复发：✕
**现象**：`setState(() => _future = f)` 触发断言，报错又常被上层 catch 成「失败：$e」，跟真因完全不像。
**为什么**：`void Function()` 里箭头体把 Future 当返回值，框架断言 callback 不能返回值。
**怎么断**：一律写块体 `setState(() { _future = f; });`。

### finder 的 offstage 与视口外　复发：✕
**现象**：明明在屏幕上的控件 `find.text` 找不到；或者 `scrollUntilVisible(...).first` 直接抛异常。
**为什么**：`skipOffstage` 默认跳过视口外的 sliver；`.first` 在候选为空时立即抛，不是等滚动后再找。
**怎么断**：长列表先滚到目标再断言；不要用 `.first` 当兜底。

### 热重载给单例加非空字段：真机诡异失效，测试全绿　复发：✕
**现象**：给长生命周期对象加了个非空字段，热重载后按钮没反应，但所有测试通过。
**为什么**：热重载复用旧实例，不重跑构造函数，新字段在旧对象里是 null。
**怎么断**：动了单例先热重启；新字段用可空 + 懒初始化 getter 加固。

### 改 typedef / 回调签名后热重载：旧闭包实例保留旧签名，运行时 subtype 红屏　复发：✕
**现象**（2026-11-22）：给 `MusicLibraryBuilder` 加命名参数后热重载进运行中的 app，进音乐模块整屏红：`type '(BuildContext, MusicPlayerUi, …) => Widget' is not a subtype of type '… {int initialTab, bool showTabSwitch}} => Widget)?' of 'function result'`；本地 analyze/测试全绿，新代码本身无错。
**为什么**：热重载替换代码，但**重启前创建的闭包实例仍指向旧编译产物**；模块字段按新 typedef 读取时运行时 subtype 检查失败。签名类变更，reload 换不了存量对象。
**怎么断**：红屏报 function result subtype 错 → 先想到旧闭包实例，直接 `--restart`；动过 typedef / 回调签名的改动一律按「必须 restart」对待。

### 并行线共用一个 app 实例：对方的 hot reload 会重置你的导航　复发：✕（2026-11-25）
**现象**：验收朗读高亮时，`/tap` 刚推进到详情页，一两秒后又回到首页；`/route` 栈对不上截图，日志反复出现「热重载：导航栈追踪已重置」；`/tap` 的 dryRun 还会枚举已经 deactivate 的旧页文本，候选看起来正常却点不中。
**为什么**：`C:\da` 同时有另一条线在改小说页面，两边读同一个 `%APPDATA%\com.rinnki.mimao\mimao\driver.json`，对方的 `hot_reload.dart` 连到同一个 app 实例；热重载按设计重放初始路由，你的阅读器栈被弹掉。共享工作树里的未提交改动也会被热重载进你的 app，导致页面被对方的半成品路由覆盖。
**怎么断**：验收时给 `flutter run` 加 `MIMAO_DRIVER_FILE=<独立路径>`，driver.json 与 `/shot` 落盘都跟过去；要连代码也隔离（工作树里有对方未提交的改动），`git worktree add <独立目录> HEAD` 从自己的提交起干净代码跑，验收完 `git worktree remove`。热重载后 `/tap` 偶发 0 候选，再发一次或先 hot reload 一次即可。

---

## 二、漫画源引擎

### 真源搜索返回 0 条，先查这四层　复发：✕
**排查顺序**：settings 默认值没初始化 → `init.js` 的执行顺序 → brotli 解压没接上 → `maxPage` 算出 NaN。
**怎么断**：按这个顺序查，别一上来改解析器；每层都能单独用探针证伪。

### 同脚本 Venera 能跑、我们被拦：缺的是客户端能力　复发：✕
**为什么**：站点拦的是"不像浏览器"，不是解析写错。缺持久 Cookie、Cloudflare / gatekeeper 的 WebView 通行、系统代理、DNS 覆盖、证书忽略中的任何一个都会被拦。
**怎么断**：先补齐客户端能力再谈解析；不要因为对方脚本一样就回去怀疑代码。

### Uri.decodeComponent 遇非 ASCII 直接抛　复发：✕
**怎么断**：URL 解码包 try/catch 或按字节解，别假设来源站只给 ASCII。

### JS 桥两套接口、引用要还　复发：✕
**现象**：同步 / 异步两套桥混用会死锁；跑久了内存涨。
**怎么断**：按现有 `js_bridge` 的用法成对调用，JSRef 用完 `freeRecursive`。

### 字段名是 fileName，不是 filename　复发：✕
**为什么**：真数据就是这么写的；按直觉拼 `filename` 会静默拿到 null，表现为"下载没名字"。

### Windows 读站点 Cookie 走 CDP　复发：✕
**怎么断**：不要用系统 cookie 库去猜；走 CDP 读浏览器真实 Cookie。

---

## 三、数据 / drift / 下载

### drift 在测试里必须 mock 平台路径　复发：✕
**现象**：测试一启动就挂，或本地能跑 CI 红。
**为什么**：eager open + PathProvider 在测试环境没有真实路径。
**怎么断**：测试注入内存库或 `NativeDatabase.memory()`，不要碰真实目录。

### drift 的 DateTime 写进去是 UTC、读出来是本地时区　复发：✕（2026-11-25）
**现象**：单测里 `expect(row.deletedAt, DateTime.utc(2026, 11, 20))` 失败，实际值多 8 小时（`2026-11-20 08:00:00.000`）；换成 `isAfter/isBefore` 就过。
**为什么**：drift 默认按 unix 秒存 DateTime、读回时套本地时区，`DateTime.utc` 与本地 `DateTime` 的 `==` 因此不等（`isAtSameMomentAs` 才比时刻）。
**怎么断**：断言时间用 `isAtSameMomentAs` 或区间比较，别直接 `==`；要落库再比较的字段（墓碑 `deletedAt` 之类）也按"先后"设计判据。

### 本地漫画的封面不要写进收藏 / 公共投影　复发：✕
**为什么**：本地文件不是线上资源，投影会被当成"可同步的远程条目"，导致别处拿到失效封面。
**怎么断**：本地数据统一走本地接口，投影只收在线条目。

### 下载与取消赛跑：以"已完成"为准　复发：✕
**现象**：取消晚于完成时，清单指向已删的页，打开就黑。
**怎么断**：状态机里让完成优先；取消只清理未完成的中间态。

### user_playlist 收藏行的 gcid 是订阅架位合成 id　复发：✕
**现象**（2026-11-22）：收藏（别人的）歌单详情显示「歌单里还没有歌曲」，全程无报错；账号中心与侧栏入口都一样。
**为什么**：user_playlist wire 的 `global_collection_id` 对收藏行是**订阅架位合成 id**（`collection_<kind>_<本人 userid>_<架位 listid>_<序号>`）；云端取曲（get_list_all_file_v3）与公开取曲（get_other_list_file_nofilt）对它都回**空页而非报错**（详情端点也只回骨架）。创作者的真 gcid 在 `list_create_gid`——模型早解析成 `creatorGlobalId`，只是取数没人选它。
**怎么断**：收藏歌单打不开先 dump wire 整行、与自建行对比两个 gcid 字段是否分歧；公开读一律用 `MusicUserPlaylist.publicGlobalId`，别直接用 `globalId`。

### 逐页进度别走 transition 动画通道　复发：✕
**为什么**：进度是高频离散事件，动画通道会合并/丢失/乱序。
**怎么断**：进度走状态更新，动画只做视觉修饰。

### DB v2 分表不要重复投影　复发：✕
**为什么**：新旧表都投影会让计数翻倍、列表重复。
**怎么断**：投影只从一个权威表出，分表是内部存储细节。

---

## 四、Windows 与原生依赖

### media_kit 活会话期间热重启：当场死亡或下次播放闪退　复发：✕
**现象**（2026-11-22）：app 正在播放（libmpv 会话活跃）时 `--restart`，一次直接 `Performing hot restart... → Lost connection to device`（进程死，`flutter run` 退出）；另一序列里 restart 存活，但用户随后点播放立即闪退。两种死法 Windows 事件日志都没有 1000 记录，纯原生崩。
**为什么**：热重启重跑 main()，`MediaKit.ensureInitialized` / NativeReferenceHolder 在同一进程里对已初始化的 libmpv 二次装配，原生句柄状态被破坏——要么重启瞬间崩，要么下次下发命令（play）时段错误。debug 专用路径，release 无热重启不受影响。
**怎么断**：无 Dart 异常痕迹的闪退 + 事件日志无记录 + 崩前有过热重启 → 先怀疑热重启污染原生会话，冷启（杀进程重 `flutter run`）复现验证；**media_kit 已初始化/播放中的进程不要热重启**，换原生状态一律冷启。

### media_kit 首次构建会下载 libmpv / ANGLE　复发：✕
**现象**：第一次 `flutter run -d windows` 特别慢，像是卡死。
**为什么**：按 MD5 下载到 `build/windows/x64`，不是网络挂。
**怎么断**：等它下完；别在首次构建时判定"坏了"去改代码。

### 截图脚本先 SetProcessDPIAware　复发：✕
**为什么**：不声明 DPI 感知，截出来的坐标和实际 UI 对不上，点哪都错位。

### file_picker 13 / record 7 的 API 差异　复发：✕
**为什么**：file_picker 13 是静态 API，没有 `withData`；record 7 在 Windows 走 MediaFoundation。
**怎么断**：测试里必须注入 seam，不要直接调包。

### 本地跑引擎测试要有 QuickJS 的 dll　复发：✕
**怎么断**：从 `build/windows/x64/...` 把 `flutter_qjs_plugin.dll` 拷到仓库根（已 gitignore），否则测试缺库。

### 构建失败后的增量构建可能产出「旧代码拼新代码」的 kernel　复发：✕
**现象**（2026-11-22）：第一次 `flutter run` 因 DLL 文件锁失败后，紧接的重跑成功且 `kernel_blob.bin` 时间戳新鲜，但运行中的 app 呈现「早已删除的番剧入口卡片 + 旧版 logo 头 + 新 reader 页面」的混合体；`/state` 模块注册表却只有 3 个模块。对照源码（home.dart 三带斜切入口、无 logo、无番剧）完全对不上，排查渲染 bug 白烧半小时。
**为什么**：构建被文件锁打断后，`.dart_tool`/build 的增量编译指纹损坏，重跑时未变更文件直接复用了**陈旧的目标产物**（回滚到番剧删除之前的状态），新增/变更的文件才真正重编——产出新旧拼接的 kernel。
**怎么断**：app UI 与源码对不上时，先 `flutter clean && flutter pub get` 全新构建再怀疑代码；构建失败（尤其文件锁 MSB3027）之后的那次构建不可信。
**同日另一例**：`flutter run` 构建进行中改了 `novel_source_manage_page.dart`，本次产物仍是旧页面；随后 hot reload 只重载 2 个库、hot restart 也不补，换一条线新起的 `flutter run` 才生效。构建跑完（看到 Built）之前别改源码，改了就重新构建。

### 两条线并行各起 flutter run，后启动的构建被 DLL 锁死　复发：✕
**现象**（2026-11-22）：另一条线的 `mimao.exe` 正在跑，第二条 `flutter run` 的 MSBuild 反复重试后报 MSB3027：“WebView2Loader.dll 正由另一进程使用”，构建失败。
**为什么**：两个 flutter run 写同一个 `build\windows\x64\runner\Debug`，exe 锁住了 runner 目录里的 DLL。
**怎么断**：先看 `tasklist | grep mimao`；已有实例在跑就复用它的 dev harness 验收，不另起 build。确需新构建就先停掉旧实例，或换独立构建目录。

### photo_view.customChild 包无限尺寸 Image 会静默整层不画　复发：✕
**现象**：分页阅读页用 `PhotoView.customChild(child: Image(width: ∞, height: ∞))`，画面只有文字/图标，所有填充（黑底、工具栏底色、图片）全部消失，无异常弹窗；日志里才有 `RenderPositionedBox infinite size` + `Rect NaN` + `Infinity or NaN toInt`。
**为什么**：contained 缩放基于 child 实测尺寸计算，无界约束炸布局后 scale 变 NaN，photo_view 整层静默不画（widget 测试只断言 Key 在不在树里，拦不住 paint 缺失）。
**怎么断**：给 child 有界尺寸（去掉显式 ∞，让 `Image(fit: contain)` 按约束自适应）；UI「文字画了、填充没画」先查 `/logs` 里的 layout 异常，再怀疑渲染管线。

### 桌面安全存储别选要 ATL 的 C++ 插件　复发：✕（2026-11-25）
**现象**：按需求加 `flutter_secure_storage ^11.2.0` 做 WebDAV 密码存储，本机
`flutter build windows` 直接失败：
`flutter_secure_storage_windows_plugin.cpp(6,10): error C1083: Cannot open include file: 'atlstr.h'`。
**为什么**：`flutter_secure_storage_windows` 的 Windows 端是 C++ 插件（`wincred` +
`atlstr.h` + `bcrypt`），ATL 是 VS Installer 的独立组件，本机 VS 2022 BuildTools
没装；跑 `flutter analyze`/`flutter test` 都不会暴露，只有真编 release 才炸。Windows
是本应用首发平台，这类依赖等于把主平台锁死在别人的环境假设上。
**怎么断**：Windows 的系统安全存储用 `dart:ffi` 直连 `crypt32.dll` 的
`CryptProtectData`（`lib/novel/backup/credential_store.dart`），纯 Dart、零原生构建；
引"带 Windows 原生端"的插件前，先 `flutter build windows --release` 验证一次，
别只看 pub 页面标了 windows 支持。

### FFI 调 Win32 API 漏一个参数会让进程直接死，不报 Dart 异常　复发：✕（2026-11-25）
**现象**：`CryptProtectData` 的 Dart 侧签名少写了 `pPromptStruct`，测试进程
"did not complete"（没有异常、没有栈），`flutter test` 只报测试没跑完。
**为什么**：x64 调用约定里少一个参数 = 后面所有参数整体错位：flags 落进 prompt 槽、
输出指针落进 flags 槽，`CryptProtectData` 往一个整数当地址写，进程当场死。
**怎么断**：对着 MSDN 原型的参数个数逐个数（`CryptProtectData` 是 7 个、
`CryptUnprotectData` 也是 7 个）；FFI 调用没有任何类型检查兜底，写完先在单测里
跑一次真实往返（本仓 `backup_credential_test` 就是为此加的），别等到 app 里点按钮。

### CMake 首次 configure 失败后，INSTALL_PREFIX 会永久停在 C:/Program Files　复发：✕（2026-11-25）
**现象**：`flutter build windows` 编译全过，最后 INSTALL 阶段
`MSB3073 ... cmake_install.cmake` 退出码 1；手动跑那个 install 脚本才看到真因：
`file cannot create directory: C:/Program Files/mimao. Maybe need administrative privileges`。
**为什么**：`windows/CMakeLists.txt` 靠 `if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)`
把安装前缀改到 bundle 目录。这个变量**只在 build 目录里第一次 configure 时为真**；
那次 configure 若因为别的原因（本机是 `flutter_tts` 找不到 nuget.exe）中途失败，
缓存里已经写死了默认前缀 `C:/Program Files/mimao`，之后每次重跑都走 else 分支，
编译绿、安装红，而且报错只说 MSB3073。
**怎么断**：见到"编译通过但 INSTALL 失败"先手动跑一次
`cmake -DBUILD_TYPE=Debug -P build/windows/x64/cmake_install.cmake` 拿真因；
若是 INSTALL_PREFIX 问题，`RM -rf build/windows` 重新 configure（别去改 CMakeLists）。

### 给第三方插件改编译设置，改 APPLY_STANDARD_SETTINGS 是空操作　复发：✕
**现象**（2026-11-24）：`build-windows` 连续红在 `flutter_inappwebview_windows_plugin` 的 `experimental/coroutine(37,1): error C2338`（STL1011 弃用硬错误）。按报错提示把 `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` 加进 `windows/CMakeLists.txt` 的 `APPLY_STANDARD_SETTINGS()`，重跑 CI 报错一字不差——宏根本没进插件的 vcxproj。
**为什么**：`APPLY_STANDARD_SETTINGS` 只对调用它的 target 生效；插件在 pub cache 里自带一套 `FLUTTER_INAPPWEBVIEW_WINDOWS_APPLY_STANDARD_SETTINGS`（故意去掉 `/WX`），那份 CMakeLists 里连 `apply_standard_settings` 都是注释掉的。另一层坑：runner 的 `windows-latest` 已升到 VS 18 / MSVC 14.52，本机 VS 2022 只有 14.44（还没有这条断言），**本地构建绿不代表 CI 绿**。
**怎么断**：注入编译定义要在 `include(flutter/generated_plugins.cmake)` **之前**用 `add_compile_definitions(...)`（随后 add_subdirectory 的插件继承目录属性），或插件 target 建好后 `target_compile_definitions(<插件>_plugin PRIVATE ...)`；改完跑 `flutter build windows --release --config-only`，再 grep `build/windows/x64/plugins/<插件>/*.vcxproj` 的 `PreprocessorDefinitions`，确认宏真到了插件工程，别只看源文件改了没有。

### Windows 朗读永远停在第一段：Dart 写 PowerShell stdin 只有第一行能到达　复发：✕（2026-11-25）
**现象**：app 里 Windows SAPI 朗读永远停在第一段；宿主进程活着，缓存索引不再增加，`/logs` 无错误。纯 Dart 复现同一个宿主：第一条 `speak` 回 OK，第二条起 `ReadLine` 收不到；Python 用同一份脚本却能连发多条。曾误判成「SAPI 写完 wav 没放文件句柄 → PlaySync 等锁」，把 synth 改成独立 synthesizer + Dispose、play 改共享读，仍然只读第一段。
**为什么**：Dart `Process.stdin` 写 PowerShell 的 stdin，在 Windows 上只有第一行可靠到达（第二条起 ReadLine 阻塞/收不到）。不是 SAPI、不是音频设备、也不是 wav 文件锁：把命令通道换成 loopback TCP 后，同一宿主连续 speak/synth/play/voices 全部正常。
**怎么断**：宿主启动先 `TcpListener` 绑 127.0.0.1:0，stdout 打一行 `PORT <n>`；Dart 读这行、连 TCP，之后所有 JSON 命令/回执走 socket 行协议（`novel_tts.dart` 的 `_spawn`/`_requestNow`）；停止 = destroy socket + kill 进程。探针：Dart 连发 2 条 speak + voices 全 OK；app 真机 2 分钟定时完整读了「人设→序章→第一章」并弹出「睡眠定时已到，朗读已停止」。synth 的独立 synthesizer + Dispose、play 的 `FileShare.ReadWrite` 仍保留作防御，但**不是**这个卡死的根因。

---

## 五、工具与环境怪癖

### Bash heredoc 会吃掉一层反斜杠　复发：✕
**怎么断**：带转义的脚本用 Write 写文件再执行，不要塞进 heredoc。

### PowerShell 文本改写会静默毁掉 UTF-8 中文　复发：✕（2026-11-25）
**现象**：用 `(Get-Content x.dart -Raw).Replace(a,b) | Set-Content -Encoding utf8 x.dart` 批量改中文源码，改完文件里中文全变成 `å¤‡ä»½è®¾äº†` 这类乱码；`dart analyze` 不报错，只有测试断言里的中文对不上，甚至逻辑判断跟着歪。
**为什么**：Windows PowerShell 5.1 的 `Get-Content -Raw` 对**无 BOM 的 UTF-8**按系统 ANSI 解码，读进来就已经是乱码；再以 UTF-8 写回，等于把乱码固化。`-Encoding utf8` 只影响写，不影响读。
**怎么断**：改源码一律用 Edit/Write 工具（按 UTF-8 读写），不要用 PowerShell 做文本替换；非要脚本化就用 `Get-Content -Encoding utf8 -Raw` 并显式验证一处中文。已经在仓库里的生成/配置类文件，改完 `grep` 一眼中文是否还在。

### Write 工具会把敏感行脱敏截断　复发：✕
**现象**：写含 `authorization: <值>` 一类行的文件，内容被截成语法错误，且不报错。
**怎么断**：换个字段名写，写完 `dart analyze` 验一遍。

### github.com 直连会 RST　复发：✕
**怎么断**：用 `gh` CLI / API；curl 要钉 IP 加重试；往 main 推用 `HEAD:main`（本地分支叫 master 就 `master:main`）。
（2026-11-24 补：`git fetch` / `git push` 首次 RST、隔几秒重试即通，不是鉴权或分支保护问题——别去改 remote。）

### HTML → PNG 用 Playwright + 系统 Edge　复发：✕
**怎么断**：ESM 里用 `createRequire` 取绝对路径，Edge 的 `executablePath` 用正斜杠的 `C:/…`。

---

## 六、CI 口径（容易误判的地方）

### 本地模拟 format 门，整棵树一次调用会撞 Windows 命令行长度上限　复发：✕
**现象**（2026-11-24）：照抄 ci.yml 的格式门在 Git Bash 里跑，输出只有 `The command line is too long.`，退出码 1——看着像格式漂移，实际一个文件都没检查。
**为什么**：门把 600+ 个路径拼成一条命令，Windows 的 32767 字符上限顶不住（runner 是 Linux，ARG_MAX 大得多，CI 上没问题）。
**怎么断**：本地复现按目录或 `split -l 40` 分块跑，别把「命令行太长」当格式失败去改代码。

### 覆盖率分母只含"被测试 import 到的文件"　复发：✕
**为什么**：`flutter test --coverage` 的 lcov 不含没人 import 的文件，所以 60% 阈值衡量的不是全库覆盖率。
**怎么断**：别拿它当"整体质量"，要看新代码是否进了分母。

### 生成代码漂移门会把"忽略生成物"变成持续红　复发：✕
**为什么**：CI 在 build_runner 重建后专门查被 gitignore 的生成物，忽略规则会让这道门永远红。
**怎么断**：删掉 ignore 规则、正常提交产物，不要用 `git add -f` 绕。

---

## 七、UI 与渲染

### 用 500 / 600 字重，个别汉字会莫名变粗　复发：✕
**现象**：同一行里个别字（比如「剧」）比旁边的字粗一点，看着像渲染 bug。
**为什么**：雅黑只有 Regular 400 / Bold 700 / Light 290 三个独立文件；Flutter 遇到 500/600 会就近配到不同文件，同一句里字重不一致。
**怎么断**：只用 w400 / w700（`MimaoFonts`）；要强调就换字号或颜色，别加中间字重。

### 桌面横向列表鼠标拖不动　复发：✕
**现象**：源 chip 行、海报行用鼠标拖不了，排序靠后的项永远够不着。
**为什么**：桌面端默认 `ScrollBehavior` 的 `dragDevices` 不含 `PointerDeviceKind.mouse`。
**怎么断**：全局 `MimaoScrollBehavior` 已经加了 mouse，别在局部自建 `ScrollBehavior` 把它盖掉。

### UI 改完只看测试绿，界面其实坏了　复发：✕
**为什么**：widget test 只验 widget 树、文字和状态，验不了"看起来对不对"——溢出、遮挡、颜色对比、空态缺失它都不会报。
**怎么断**：UI 改动必须 `/shot` 截图亲眼看，并走过加载 / 空 / 错误三态，再谈完成。

### 百分比宽度直接乘再加间距 → Row 溢出条纹　复发：✕（2026-11-25 发现页分类入口条）
**现象**：分类 chip 行右侧出现黄黑斜条纹（Row overflow），日志里是 `A RenderFlex overflowed`。
**为什么**：`layout_flexBasisPercent` 的语义是"占父宽度"，实现里直接 `available * factor` 当宽度，又额外插了 8px 间距；两列各 50% 时总宽 = 父宽 + 8px，必溢出。百分比语义下"间距"必须先从可用宽度里扣掉。
**怎么断**：`available = maxWidth - gap * (n - 1)` 之后再乘百分比；加一条断言"各项宽度 + 间距 ≤ 父宽"的纯函数测试钉住。任何"百分比 + gap/间距"的组合都照这个顺序算。

### 在 showDialog 的 builder 里 new controller、await 后 dispose　复发：✕（2026-11-25 首页模块管理）
**现象**：测试里抛 `A TextEditingController was used after being disposed`，堆栈指向对话框里的 TextField；线上表现为关掉对话框时偶发红屏。
**为什么**：`showDialog` 的 future 在路由**开始退场**时就完成，退场动画期间对话框还在重建，controller 却已经被 `await` 之后的 `dispose()` 收掉了。
**怎么断**：对话框需要 controller 就单独写成 `StatefulWidget`，让 controller 跟着对话框自己的 `State.dispose` 走；不要在调用方 `await showDialog(...)` 之后手动 dispose。

### Scaffold 有 drawer 时，AppBar 的返回键被静默换成汉堡菜单　复发：✕（2026-11-23 小说阅读器退不出来）
**现象**：页面 push 进来后 AppBar 左边只有一个目录/汉堡图标，没有返回箭头；桌面端没有系统返回键，点进阅读器就出不去了。
**为什么**：`AppBar.automaticallyImplyLeading` 在有 drawer 时优先插入 `DrawerButton`，而不是 `BackButton`——两者抢同一个 leading 槽位，不报任何错。
**怎么断**：页面带 drawer 又想保留返回入口时，显式给 `AppBar.leading`（返回键），目录入口放 actions；加一条"push 进去能 pop 出来"的 widget 测试钉住，别只靠肉眼。

### 模块早已接线，页面仍写着「未接入/未接线」　复发：✕（2026-11-24）
**现象**：书源引擎（`LegadoNovelEngine`）与阅读器都已在 `app_registry` / `NovelModule` 注入，首页「书源功能未接线」、书架空态「书源引擎尚未接入」、详情「目录正文还未接入」、我的「书签阅读器接入后可用」仍挂在界面上，把已有能力说成没有。
**为什么**：能力边界文案写于接入之前，接入时只改代码没回头扫文案；这些词散在 doc 注释、toast、空态、disabled 菜单四类位置，单看一处容易漏。防御分支（依赖为 null）又被当成"功能没做"的证据。
**怎么断**：接完一条能力先 `grep -rn "未接入\|未接线\|接入后\|需要.*引擎" lib/<模块> test/<模块>`，逐条拿装配处（`app_registry` / 模块注入点）核对真伪，不看旧文档；依赖为 null 的防御分支改说「X 服务未启用…重启应用后再试」并给下一步；disabled 菜单先确认所依赖的引擎是否早已存在。核对删除"零实现骨架"时同理：看 `implements` / import 引用，别按文件名判断（`rule_analyzer`/`engine.dart` 都有真实实现，删了会断）。

---
## 八、小说书源引擎（legado 规则 Dart 重写）

### xpath_selector 的 `[子元素]` 谓词与属性轴会静默返回空　复发：✕
**现象**：黑岩目录规则 `//li[span]/a` 用 `xpath_selector` 得 0 个节点，`//li/span` 却有 27 个；`//a[text()="开始阅读"]/@href` 也恒空。
**为什么**：该库的谓词求值把裸 tag 当表达式、属性轴又先走了 child 轴，语义与 XPath 不一致；它不抛错，只是空集。
**怎么断**：`analyzer/simple_xpath.dart` 先实现书源常用子集（`//` `/` `@attr` `text()` `contains` `starts-with` `[tag]` `[n]` `and/or` `|`），解析失败才回落 `xpath_selector`；新规则先在真页面验节点数。

### `@js:` 规则尾部的 `##说明` 会被 QuickJS 当 private name　复发：✕✕（已修 2026-11-23）
**现象**：晋江详情报 `SyntaxError: invalid first character of private name`。
**为什么**：legado 的 `@js:` 贪婪吃掉整段，`SourceRule` 再用 `##` 拆出正则替换；若在 JS 模式下提前 return，整段 `##手机地址：` 就进了 eval。
**怎么断**：JS/Regex 模式同样先拆 `##`（rule / replaceRegex / replacement / replaceFirst），再执行 JS。
**复发（2026-11-23）**：修复只落在规则层 `makeUpRule`，漏了两条独立入口——`SourceRule` 构造时 js/regex 模式直接 return（同步路径 `makeUpRuleSync` 又跳过拆分），以及 `AnalyzeUrl._analyzeJs` 里 `@js:` 贪婪捕获直连 runner。两处都补上 `##` 拆分才算断干净（c563b15）。教训：同一语义的拆分要.findAll入口逐个对照，别只修"看过的那条"。

### 严格 GBK 解码失败后回落 UTF-8，整页乱码　复发：✕
**现象**：晋江搜索结果显示 `[����֮��]` 一类替换字符。
**为什么**：站点声明 gbk，但页面夹带广告脚本的非法字节，`GbkCodec` 严格模式抛错，兜底 UTF-8 把正文全解坏。
**怎么断**：gbk/gb2312/gb18030 一律 `GbkCodec(allowMalformed: true)`；UTF-8 只在无声明且严格解码通过时使用。

### 目录顺序：不要无条件 reverse　复发：✕
**现象**：sfacg 第一章变成"第六章"，目录被翻反。
**为什么**：legado 的 `-` 前缀表示"源是倒序（最新在前）"；没有前缀的源通常是自然顺序（最旧在前）。无条件 reverse 会翻错。
**怎么断**：只有 `chapterList` 以 `-` 开头才 reverse 成阅读顺序；其余保持源顺序并重排 index。

### QuickJS 跑 Rhino 同步 JS：网络必须"哨兵 + 重放"　复发：✕
**现象**：书源 JS 里 `java.ajax(url)` 需要同步返回字符串，Dart 的 dio 只有 Future。
**怎么断**：JS 侧网络调用返回 `{__mimaofetch:[spec]}` 并抛 `__MIMAO_FETCH__`；Dart 捕获后预取、写缓存、重跑整段脚本（上限 30 次）。不要尝试在 QuickJS 回调里 await。

### JS 宿主测试在 CI 恒 skip，掩盖所有 JS 回归　复发：✕（2026-11-23）
**现象**：`legado_js_host_test.dart` / `js_host_failure_test.dart` 用 `File('flutter_qjs_plugin.dll').existsSync()` 判就绪，而 tests job 跑在 ubuntu-latest、dll 被 .gitignore 挡掉——CI 永远只跑一个空 skip，全绿但 JS 回归（post body、`##`、失败缓存、对称密钥）一个都测不到。
**为什么**：native 库按平台不同名（Windows .dll / Linux .so），测试却硬编码 Windows 文件名；skip 无导航，构建了但库没放对地方也看不出来。
**怎么断**：统一用 `test/novel/js_native_guard.dart` 跨平台探测；CI 先 `cmake` 编出 `libflutter_qjs_plugin.so` 放进 `LD_LIBRARY_PATH`，并置 `MIMAO_REQUIRE_NATIVE_JS=1`——strict 模式拿不到库直接 fail 而非 skip。任何新 JS 测试都引用这个 guard，别自己写 existsSync。

### 给传输窄接口加方法会静默打断所有 fake　复发：✕（2026-11-23）
**现象**：给 `NovelHttpTransport` 加 `setCookie` 带默认实现后，所有 `implements NovelHttpTransport` 的测试 fake 立刻编译失败——`implements` 必须实现全部方法，默认体不算。
**为什么**：Dart 接口默认方法体不免除 `implements` 的实现义务（只有 `extends`/`with` 才继承）。
**怎么断**：给"少数实现要的可选能力"单开一个 abstract interface（如 `NovelCookieSink`），宿主用 `is` 探测；别往通用接口上加方法。

### JS 全局补丁的顺序：先存原函数再覆盖　复发：✕（2026-11-23）
**现象**：给 `Math.random` 打钉住补丁时写成 `Math.random = fn; Math.__originalRandom = Math.random;`，补丁里再调 `__originalRandom()` 会无限递归——存到的是补丁自己。
**为什么**：先覆盖再保存，保存的是新函数不是原生函数。
**怎么断**：`var __original = Math.random;` 在覆盖**之前**，补丁闭包引用 `__original`。

### 书源 JS 每次重放都会留下副作用，别只钉时间/随机数　复发：✕（2026-11-23）
**现象**：哨兵重放整段脚本时，`java.put` / `java.log` / `book.putVariable` / `source.setVariable` / `cookie.set` / `cache.put` 在网络调用前的写入全部重复执行一遍；日志翻倍、计数器错乱。
**为什么**：重放是从脚本第一行重新 eval，Dart 侧的外部状态不会随 JS 栈回滚。
**怎么断**：宿主维护"已提交副作用高水位" + "本次调用序号"，第 i 个副作用只在 i ≥ 水位时落地，重放时同序号跳过；网络后的新副作用继续推进水位。`setContent` 幂等可每次执行。

### pointycastle RSA 私有运算必须有合法 p/q，只有一个 {n,e,d} 会 NPE　复发：✕（2026-11-23）
**现象**：用 `RSAPrivateKey(n, d, null, null)` 签名/解密抛空指针；自己写 `(n,e,d)` 反推 p/q 的随机算法又脆弱不稳定。
**为什么**：`RSAEngine._processBigInteger` 私有路径硬走 CRT（`privKey.p!` / `q!`），不接受只有 n/d 的密钥。
**怎么断**：书源 RSA 签名/解密直接用 BigInt 模幂实现 PKCS#1 v1.5（`m = EM^d mod n`），只需 n/e/d，绕开 pointycastle CRT；DER INTEGER 长度 ≥128 必须写长形式 `0x81 <len>`，否则长度字节被当长形式标记导致解析全空。

### 列表/元素的 JS 规则漏 `await`：目录恒 0 章，且只在真源上暴露　复发：✕（2026-11-25）
**现象**：部分真实书源（书旗小说等）搜索、详情都正常，唯独「目录 0 章」；
调试面板「执行链路」里该条 chapterList 规则回报 `结果：Instance of 'Future<Object?>'`。
**为什么**：`LegadoRuleAnalyzer.getElements` / `getElement` 的 `case RuleMode.js:`
写成 `result = evalJs(...)` 少了 `await`，`result` 是 `Future` 不是值；后续
`result is List` 判否 → 返回空。`getString`/`getStringList` 走 `_applyModeToString/List`
（函数内 `return evalJs(...)` 被外层 await）所以没中招，唯独取元素这两处漏了。
**怎么断**：取元素的 JS 分支一律 `result = await evalJs(...)`；
`legado_js_rule_await_test` 用可注入假 runner 钉住「返回真实列表而非 Future」。
教训：同一语义（JS 结果要 await）散在三个入口，改一处要 `grep "= evalJs("` 全对照，
别只修报错那条。调试面板的「规则执行链路」正是靠这类「结果类型摘要」帮定位的。

### 网络失败被转空串并永久缓存 / DESede 密钥拼成 72 字节 / post body 丢了　复发：✕（2026-11-23）
**现象**：超时一次后该 URL 终身返回空正文（静默），DES 源报"正文抓空"，POST 搜索恒空结果——三者都无语法错，测试又因上一条恒 skip 没拦住。
**为什么**：`_request` catch 返回 `body:''`，空串非 null 被 `_bodyCache` 钉死；`_fitKey(key,24)` 零填充再三倍拼成 72 字节，pointycastle DESede 只收 16/24 直接抛；`java.post` 把 args[1]（body）塞进了 timeout 位而 body 没传。
**怎么断**：失败返回 `ERROR:` 错误串且不入缓存、空串当 miss 重抓（对齐 Kotlin `stackTraceStr`）；AES 按密钥实际长度 16/24/32、DESede 只给 16/24（8 字节扩 K1K1K1）；`post(url,body,headers,timeout?)` 严格按 Kotlin 参数序映射。

### 给长任务加 `.timeout()` 会留下孤儿 future，它迟到报错直接打崩 debug 构建　复发：✕（2026-11-25）
**现象**：书源校验链跑到「万层中文」时 30s 超时，之后 app 直接退出，控制台只有
`Unhandled Exception: LegadoJsException: TypeError: cannot read property 'map' of undefined`——
出错点与超时那一步完全对不上，看起来像"引擎自己崩了"。
**为什么**：`future.timeout(d)` 只给自己加了计时器，原 future 毫秒不停继续跑；
一旦它随后抛错，已经没有 await 方接收，Dart 把它报成 unhandled async error。
引擎里的 JS 宿主、dio 请求都会在超时之后才失败，所以每个 `.timeout()` 都是潜在崩溃点。
`flutter_test` 的 test zone 会把这类未处理错误直接记成用例失败，**也因此没法用
`runZonedGuarded` 写"断言没有 unhandled"的回归测试**（嵌套 guard 拦不住）。
**怎么断**：统一走 `lib/novel/engine/safe_timeout.dart` 的 `withSafeTimeout(future, d, label:)`
——先给原 future 挂一个吞错的 `then(onError:)`，再单独 `await` 带超时那条分支；
测试侧验证可观测契约（超时抛 `TimeoutException` 且该步记为失败），别试图断言"没崩"。
新增长任务别直接写 `.timeout(`；`grep -rn "\.timeout(" lib/` 只剩阅读器与切源面板两处历史遗留待收口。

### `package:html` 的选择器解析不了 OPF，会把自闭合标签套成嵌套　复发：✕（2026-11-25）
**现象**：EPUB 解析拿 `<spine>` 里所有 `itemref` 的 idref 去 `<manifest>` 找 href，结果只剩第一个
章节（或干脆一章都没有）；`querySelector('dc:title')` 直接抛
`UnimplementedError: ':title' selector of type PseudoClassSelector is not implemented`。
**为什么**：`html` 包是 HTML 解析器，不是 XML 解析器。OPF 里 `<item ... />` 是自闭合的，
它被当成开始标签，于是 `<item id="c0"/><item id="c1"/>` 解析成 `item > item` 嵌套——
`manifest > item` 这种组合选择器只命中第一层，spine 里其余 idref 全查不到。另外它把
选择器里的 `:` 一律当伪类，命名空间前缀（`dc:`）因此必然报错。
**怎么断**：EPUB 内所有查询都用**标签名 + 属性**（`querySelectorAll('item')` 再读
`attributes['id']/['href']`）；取元数据按「去掉前缀的 localName」遍历比较
（`local_epub.dart` 的 `_firstText`）。写单测时专门放一个多章节 EPUB 并断言
spine 顺序——只测一章的样本永远发现不了这个问题。

### 本地书文件被移动后，目录还从库里读得出来，错误态要提前探文件　复发：✕（2026-11-25）
**现象**：把本地 TXT 挪走再打开详情页，目录照常列出 6 章（因为 `tocJson` 是导入时
落库的缓存），用户点「继续阅读」才撞上「文件不存在」；详情页当时显示的是目录卡片，
连「重新定位」入口都看不到。
**为什么**：本地书的目录是导入时解析一次、落库复用的；详情页的渲染分支是
`if (online != null) 显示目录 else if (missing) 显示错误`，而 `online` 只要目录在就非空，
错误分支永远走不到。
**怎么断**：本地书的详情页在拿到目录后额外探一次文件存在（`NovelLocalFile(path).length()`），
并把「文件缺失」的渲染优先级排在目录之前；阅读控制器把 `NovelLocalFileMissing`
单独 catch 成 `localFileMissingPath`，页面据此给「重新定位文件」而不是无意义的「重试」。
新加「文件可能不在」的本地能力时，别只依赖落库缓存判断可用性。

### `data:` URL 里的裸中文会让 `Uri.decodeComponent` 直接抛　复发：✕（2026-11-25）
**现象**：词典内置的离线样例规则用 `data:text/html,<h2>词条：{{key}}</h2>`，查询时报
`Invalid argument(s): Illegal percent encoding in URI`，整条查询变成错误态。
**为什么**：`Uri.decodeComponent` 不是"宽松解码器"——它把裸非 ASCII 当非法百分号编码，
而 `AnalyzeUrl` 的 `_decodeDataUri` 原来直接 `return Uri.decodeComponent(data)`，没有兜底。
**怎么断**：`analyze_url.dart` 的 `_decodeDataBody` 自己逐段解码：`%XX` 还原字节、ASCII 直取、
非 ASCII 按 UTF-8 重编（含代理对），最后 `utf8.decode(allowMalformed: true)`。
解析 `data:` 响应或写 `data:` 规则时别直接调 `Uri.decodeComponent`。

### 词典内置站点要先验「Dart 能不能拿到 200」　复发：✕（2026-11-25）
**现象**：把上游 `dictRules.json` 的汉典规则照搬进内置，查询永远第一条报 HTTP 404；
同一个 URL 用浏览器 / .NET 都是 200。
**为什么**：站点按客户端指纹挡非浏览器请求（Dart `HttpClient` 与 dio 都 404，换 UA 无效）。
上游能跑不代表本机能跑。
**怎么断**：内置规则只放实测 200 的站点（当前是 `dict.cn`）+ 离线 `data:` 样例；
新增默认词典前先用 `DioNovelHttpTransport` 真查一次，别只对照 Kotlin 源码。

## 九、小说阅读器

### 分页在 build 里同步跑 TextPainter，改字号/窗口就卡一帧　复发：✕（2026-11-24）
**现象**：`LayoutBuilder` 每帧调 `_pagesFor`，长章整章 `TextPainter.layout` + `computeLineMetrics` 全在 UI 线程；滚动模式明明不用页，也白跑一遍。`pumpAndSettle` 能过，真机改字号明显掉帧。
**为什么**：把「布局结果」当成 build 的纯函数算，忽略了排版是重 CPU 工作；缓存 key 只在 build 内比较，key 变了就当场重算。
**怎么断**：排版交给 `NovelLayoutService`，帧后调度 + generation token + LRU（最近 4 个 key）；build 只登记尺寸并读缓存，滚动模式完全不排版。改样式先去抖 80ms，只保留最后一次。

### 全屏点按热区盖在正文之上，章末按钮与选文长按被吃掉　复发：✕（2026-11-24）
**现象**：3:4:3 的透明 `GestureDetector` 行是 Stack 里正文之上的兄弟节点，点「下一章」实际触发了热区翻页；滚动模式长按选文也经常没反应。
**为什么**：Stack 命中测试从最上层开始，热区 `HitTestBehavior.translucent` 自己先拿到 tap；正文里的 InkWell/SelectionArea 与它抢手势时按命中顺序吃亏。
**怎么断**：不盖热区。把左/中/右判定做成正文外层 `GestureDetector.onTapUp`（滚动模式包 SelectionArea，翻页模式挂在翻页手势上），按钮等更深的手势自然优先；`reader_chapter_prefetch_test` 用章末按钮点击守住。

### 章内进度只存页码 + 滚动比例，换字号/窗口就漂　复发：✕（2026-11-24）
**现象**：恢复阅读位置时按 `page/pageCount` 或 `scrollRatio` 折算，字号、行高、窗口宽度一变，同一比例落到别的段落；换源后同一本书还共用一个位置。
**为什么**：页码和比例都是「当前布局的函数」，不是正文的函数；位置存储又只按 `bookId` 建键。
**怎么断**：位置锚到 `NovelLocator{chapterIndex, paragraph, charOffset}`（段内偏移不含段首缩进），页码/比例只做旧数据回退；kv 键改 `sourceKey|bookId`，旧键读一次后迁移删除。翻页按切片反查页号，滚动按段落 GlobalKey `ensureVisible` 落点。

### 换章先清空正文再 await 网络，每章边界必白屏　复发：✕（2026-11-24）
**现象**：`_openChapter` 一开始就把 `_content = null`，网络来回期间整屏只剩「正在加载正文…」；也没有相邻章预取，连续阅读每章都停一次。
**为什么**：把「切章」和「正文就绪」绑成一个状态，加载失败还只能整屏报错。
**怎么断**：会话内 `NovelChapterCache` 预取前 2 后 1 章；未命中时保留当前正文 + 底部加载条，正文到了再原子替换；失败保留旧章并给内联重试。`reader_chapter_prefetch_test` 用 Completer 卡住第二章守住这个时序。

### 避头尾改断点后仍用原行高记账，双栏/长段落撑破页高　复发：✕（2026-11-24）
**现象**：开双栏 + 避头尾后阅读页报 `A RenderFlex overflowed by 37 pixels`（`novel_reader_page.dart` 的正文 Column），底部几行被裁掉；单栏时偶发但被页高富余盖住。
**为什么**：分页按 `computeLineMetrics()` 的每行高度累加，但避头尾把字挪到上一行后，那一行实际会多折一行——渲染层每个切片是独立 `Text`，高度已不是原 metrics 高度。另有一处叠加：分页用 `columnGap=32`，渲染层却写死 `SizedBox(width: 28)`，每列实际宽比测量窄 2px，进一步触发多折行。
**怎么断**：切片入页前用 `_measureSliceHeight()` 对「真正要渲染的子串」重新 `TextPainter` 量一次高度再累加；列间距抽成 `_twoColumnGap` 常量，分页与渲染共用同一个值；渲染 `Text` 补上分页用的 `TextHeightBehavior`。`novel_pagination_test` 的双栏用例守住连续性，观感靠 `/shot` 亲眼看。

### path_provider 的支持目录已经带 app 名，再拼一层就成孤儿目录　复发：✕（2026-11-24）
**现象**：导入字体写进 `…/com.rinnki.mimao/mimao/mimao/reader_fonts/`，字体选择弹窗里永远看不到导入项；文件其实写成功了，只是没人读同一个位置。同目录的 `novel_sources/`、`novel_cache/` 都正常。
**为什么**：Windows 上 `getApplicationSupportDirectory()` 返回的路径本身就以 `…/com.rinnki.mimao/mimao` 结尾；我按「support 目录是 AppData 根」的直觉多拼了一个 `mimao`，读写两边各自算路径，谁也没报错。
**怎么断**：新目录一律写成 `p.join(support.path, '<name>')`，跟 `novel_sources`/`novel_cache` 同一层级；`novel_reader_fonts_test` 断言 `fontDirectory()` 的上一级就是给定的根目录，多拼一层立刻红。

### AnimatedSwitcher 的 transitionBuilder 只建一次，按 status 判入场/退场要放进 builder　复发：✕（2026-11-24）
**现象**：翻页动画里想「新页从侧面进、旧页往反方向退」，在 `transitionBuilder` 里读 `animation.status` 决定方向；结果旧页也按入场方向动（cover/scroll/parallax 变成两页同向滑，看不出「盖」和「视差」）。
**为什么**：`transitionBuilder` 只在建 `_ChildEntry` 时调用一次，结果缓存进 `_outgoingWidgets`；之后再 build 走的是 `layoutBuilder`，旧的 transition widget 不会重跑 builder。建条目那一刻 status 还是 `forward`，所以永远读到「入场」。
**怎么断**：把 `animation.status` 的判定放进 `AnimatedBuilder`（或 `AnimatedWidget`）的 builder 里，每次 tick 重新读；`novel_reader_gestures_test` 对六种风格各跑一遍翻页，至少保证不抛异常、页码前进。

### 设置面板切页签共用滚动区，不重置就停在上一页的半空　复发：✕（2026-11-24）
**现象**：从「全局」页签往下滚到一半再点「菜单」，新页签内容比旧的短，滚动位置却保留——顶部内容被顶出视口，自动化点某个开关时命中坐标是负值（`Offset(402.0, -26.0)` 在根渲染树外），点了个空。
**为什么**：`SingleChildScrollView` 没有自己的 controller 时用 PrimaryScrollController/内部状态，页签切换只换了 `switch` 的子树，滚动 offset 不变。
**怎么断**：面板持有 `ScrollController`，`_selectTab` 里 `jumpTo(0)`；加新页签时自动受益，不用逐个页面处理。

### /tap 只能点控件中心、注入不了长按与拖拽；真手测要走 SendInput + 抢前台　复发：✕（2026-11-24）
**现象**：验收要求「章末按钮可点、长按选文可用」两项真机手测。dev harness 的 `/tap` 用 `key`/`text` 匹配 widget 并点它的中心，`down→up` 只隔 50ms——既点不到正文右三分之一（正文 Text 是整段居中，中心永远在中间格），也造不出长按（>500ms）和拖拽（多次 move）两种手势。
**为什么**：`/tap` 是为「按控件找目标」设计的，不是通用指针注入；`dispatchTap` 的 `gap` 参数虽然可调，但没有 move 事件，`SelectionArea` 在桌面端靠 drag 选文，光按住不动不会出选区。
**怎么断**：要手测手势就绕开 `/tap`，用 PowerShell `SetCursorPos` + `mouse_event(DOWN)` → 循环 `SetCursorPos` → `mouse_event(UP)` 打真实指针事件。两个前提：① 先把目标窗口抢成前台，否则 `mouse_event` 打在别的窗口上（`SetForegroundWindow` 被前台锁拒绝时用 `AttachThreadInput` + 一次 ALT 键解锁）；② 截图是 1.5× 超采样，坐标要 ÷pixelRatio 换成逻辑坐标再叠窗口 `GetWindowRect` 的 Left/Top；沉浸式阅读页没有标题栏，不要再加 31px。

### 按「作用域」决定写哪个键，会把同一次改动的一部分悄悄丢掉　复发：✕（2026-11-25）
**现象**：「只改这本」下改菜单外观（图标文字、浮动行按钮），界面上开关确实拨过去了，重进书又变回去；查 kv 发现 `reader_settings` 没变、每书覆盖也是空。
**为什么**：每书覆盖只收白名单字段（背景/字体/翻页/动画/点击区），菜单布局不在里面。`applySettings` 在 book 作用域下只算白名单差异、把其余字段直接丢弃；保存又按 `scope == global` 才写 `reader_settings`，于是这次改动两条路都没落地。
**怎么断**：作用域只决定「可覆盖字段进哪」，**不可覆盖字段一律落全局**——把差异拆两半，白名单进覆盖、其余 `applyNovelReaderSettingsJson` 叠到全局；落盘不再按 scope 跳过，两份都写（覆盖为空时就是清空，成本可忽略）。`novel_book_override_controller_test` 用「book 作用域改菜单 + 等防抖 + 重新进书」守住，两条断言分别盯「覆盖里没有菜单字段」和「重进后菜单设置还在」。

### 内存版 kv 把内部 map 直接交出去，写一次就丢一次　复发：✕（2026-11-25）
**现象**：`NovelBookSettingsStore.save()` 写进 `{fontSize: 28}`，紧接着 `load()` 返回空；同一进程里连写两本，前一本消失。
**为什么**：`_readAll()` 在 prefs 为 null 时 `return _memory`，`save()` 拿到同一个 map 引用后 `remove`/赋值，再 `_writeAll` 里 `_memory..clear()..addAll(all)` —— `all` 就是 `_memory` 自己，先清空再 addAll 空 map，内容全没了。有 prefs 的路径也有同样隐患（`result` 与返回的是同一实例）。
**怎么断**：`_readAll` 恒返回深拷贝（`_copyAll`），调用方随便就地改；`novel_book_settings_test` 的「按 bookId 分条存」「保存空覆盖等于清掉这一本」「未注入 prefs 时读写落内存」三条各自覆盖一条路径。

### 动作注册表里「设置」不能复用点击区的「菜单」语义　复发：✕（2026-11-25）
**现象**：底栏按钮改成从注册表取之后，点齿轮图标不再打开阅读设置面板，而是把顶栏/底栏整块隐掉；`novel_reader_page_test` 的「改字号后仍停在原比例」直接找不到 `novel-settings-font-plus`。
**为什么**：注册表条目 `settings` 为了复用枚举挂了 `NovelClickAction.menu`，而点击区里的 `menu` 是「显隐浮层」（`openMenu()`）；同一个枚举名在两种语境下是两个副作用。
**怎么断**：`_menuActionTap` 先按 id 特判（`settings` → `_openSettings()`，`more` → `_openMore()` 等），只有真正属于点击区的动作才落 `dispatchClickAction`；`novel_menu_actions_test` 断言「顶栏专属动作没有 clickAction、其余都有」，避免下次又把两种语义混在一根枚举上。

### 桌面被锁屏时 SendKeys 抛 Access denied，dev harness 也没有输入端点　复发：✕（2026-11-25）
**现象**：要给设置搜索框打字做截图验收，PowerShell `SendKeys` 报 `Access is denied`，`GetForegroundWindow` 返回 `Windows Default Lock Screen`；dev harness 的端点只有 health/logs/route/state/tap/shot/navigate/eval/db，没有 enterText。
**为什么**：锁屏态下会话不在输入桌面，`SendKeys`/`mouse_event` 都被系统拒绝；`/tap` 只能点已有控件，造不出文本输入。
**怎么断**：走 VM service 在 app isolate 里 `evaluate` 一段表达式，遍历 element 树找到带 key 的 `TextField`，直接调它的 `onChanged`（必要时同步 `controller.text`）。脚本放 `tmp/`（临时区），用完删。要真手测键盘仍得先解锁桌面。

### SelectionArea 的 contextMenuBuilder 拿不到选中区间，别用工具栏锚点反推　复发：✕（2026-11-25）
**现象**：长按选词后自定义菜单里「划线 / 笔记」一直显灰（提示「跨段」）；用 `contextMenuAnchors` 的上下两个点反推段落，结果一个落在上一段的段距 padding 里，被判成跨段，或两个点同 x 塌缩成同一个字符偏移。
**为什么**：`TextSelectionToolbarAnchors` 是工具栏定位用的，给的是**选中矩形**的上下中点，不是选区端点；矩形可能只有一个字宽甚至塌缩。再拿屏幕坐标去 `RenderParagraph.getPositionForOffset` 只能猜，段落的外层 Padding 还包含段距，邻近判定必然出错。
**怎么断**：每段的正文外面包一层 `SelectionListener`，直接读 `SelectedContentRange.startOffset/endOffset`（相对这一段 Text 内容），再减去段首缩进；跨段时取最早一段的 start 与最晚一段的 end。`novel_selection_menu_test` 用长按选词 + 划线落库守住。

### 按段号复用 SelectionListenerNotifier：ListView 回收时新旧两个监听同时注册，断言炸红　复发：✕（2026-11-25）
**现象**：滚动阅读时偶发 `This SelectionListenerNotifier is already registered to another SelectionListener`，出现在 `novel_reader_gestures_test` 的章末按钮用例，报错位置是某个段落的 `SelectionListener`。
**为什么**：notifier 按段号存在页面 map 里，`ListView.builder` 回收/重建时新旧两个 `SelectionListener` 可能短暂同时挂同一个 notifier；Flutter 的注册断言不允许。
**怎么断**：每段一个 `_NovelSelectionProbe`（StatefulWidget）自己持有 notifier，`initState` 登记进页面、`dispose` 注销并释放；页面按 notifier 对象（不是段号）汇总选区。

### 刷新本章后对旧段落 Element 调 ensureVisible，抛「deactivated widget's ancestor」　复发：✕（2026-11-25）
**现象**：阅读页点「刷新本章」，正文已替换但有 FrameCallback 还在按旧 locator 落位，控制台报 `Looking up a deactivated widget's ancestor is unsafe`，页面右下弹出红条。
**为什么**：`_paragraphKeys` 里旧的 GlobalKey 在章节替换后 `currentContext` 仍可能非 null（已 deactivate），`Scrollable.ensureVisible` 会做 ancestor 查找。
**怎么断**：调用前检查 `target.mounted`，帧后再取时同样检查；`mounted == false` 直接放弃这次落位，下一帧会按新正文重新走恢复逻辑。

### 对话框在 initState 读 Theme.of，整页直接红屏　复发：✕（2026-11-25）
**现象**：点「新建高亮规则」后整个 app 变成红底异常页：`dependOnInheritedWidgetOfExactType<InheritedTheme>() ... called before _HighlightRuleDialogState.initState() completed`；对话框根本没建出来。
**为什么**：为了拿默认色，在 `initState` 里写了 `Theme.of(context)`。`Theme` 是 `InheritedWidget`，`initState` 阶段还不允许建立依赖；同样写法在页面 build 里没事，只有真正把对话框建出来才暴露。
**怎么断**：需要主题派生值的初始化放 `didChangeDependencies`（配一个 `_colorsReady` 只跑一次）；`initState` 只放不依赖 context 的字段。`novel_highlight_rules_page_test` 会真的点开对话框，不让这类错误留到截图阶段。

### 嵌入设置页在 SingleChildScrollView 里再放 ListView，底部弹面板整块空白　复发：✕（2026-11-25）
**现象**：小说模块侧栏点「设置」，弹面板只剩拖拽条和一片空白；日志报 `Vertical viewport was given unbounded height`，指向 `novel_settings_page.dart` 的 ListView。
**为什么**：模块页把 `settingsTab` 包在 `SingleChildScrollView` 里（漫画/音乐同款），但小说设置页无论 embedded 与否都用 ListView；外层滚动给了无限高，内层 ListView 无法布局。
**怎么断**：`embedded == true` 时正文用 `Column`（滚动交给外层），只有独立成页时才用 ListView；`novel_pages_test` 的设置页用例 + `/shot` 各守住一条。

### 替换预览拿「已净化文本」当样例，同一条规则被套两次　复发：✕（2026-11-25）
**现象**：从阅读页打开替换规则，样例正文已经是 `【艾琳娜】`；切到「本书有效替换」后对照显示 `前：【艾琳娜】 / 后：【【艾琳娜】】`，看起来像规则写错了。
**为什么**：编辑器把 `controller.content`（净化后的展示文本）当样例，`previewReplaceRules` 又按规则替换一遍；真实阅读只净化一次。
**怎么断**：控制器在净化前留一份 `rawContent`（有本地覆盖时就是覆盖文本），阅读页打开编辑器时传它；单测/手测都按「原文 → 一次替换」看结果。预览样例仍可手改，但不该默认喂展示文本。

### `showDialog` 的 Future 在 pop 时即完成，调用方随即 dispose controller 会红屏　复发：✕（2026-11-25）
**现象**：输入分组名/权重后点「确定」，列表刷新时抛
`A TextEditingController was used after being disposed`，紧跟一条
`'attached': is not true` 的渲染断言。
**为什么**：`showDialog` 返回的 Future 在 `Navigator.pop` 时就完成，而对话框的
退场动画还要再跑几百毫秒、期间 `TextField` 仍在读 controller；调用方拿到返回值
后立刻 `controller.dispose()`，动画帧就撞在已释放对象上。
**怎么断**：需要输入框的对话框做成自持 controller 的 StatefulWidget，在它自己的
`dispose()` 里释放（本仓实现见 `novel_source_manage_page.dart` 的
`_TextPromptDialog`）。别在 `await showDialog(...)` 之后手动 dispose。

### TabBar 忘了 controller，调试页一进去就红屏　复发：✕（2026-11-25）
**现象**：书源调试页右侧整块变成红色错误块：`No TabController for TabBar`。
**为什么**：`TabBar` 要么吃显式 `controller`，要么祖先有 `DefaultTabController`；
两者都没有时**不是编译错**，只有运行时断言。
**怎么断**：页面里直接放 `TabBar` 就同时建 `TabController`（`State` 混入
`SingleTickerProviderStateMixin` 并在 `dispose` 里释放）；widget 测试里断言四个
页签文本存在，能顺带把这条守住（`novel_source_debug_page_test`）。

### 长文本塞进不换行的 chip / tag，整行 Row 溢出　复发：✕（2026-11-25）
**现象**：书源校验失败时右栏红黄条，`A RenderFlex overflowed by 1171 pixels`；
左栏同一份错误消息把 `NovelSectionHeader.trailing` 撑爆。
**为什么**：`NovelTag` 内部是 `Text(maxLines: 1)` 不换行，`Row`/`SectionHeader`
的 trailing 槽位又没有宽度约束；错误消息动辄几百字符。
**怎么断**：chip/tag 只放短状态词（「通过」/「失败」），长文本进正文 `Text`
（自然换行）；确实要在横排里放一长串时用 `ListView(scrollDirection: horizontal)`
限高可滚，别用 `Wrap` 指望它兜住单条超长内容。

### `kDebugMode` 只把关「注册路由」不够：静态 import 仍会把 debug 页打进 release　复发：✕（2026-11-25）
**现象**：调试页的路由注册确实写了 `!kDebugMode ? null : (args) => NovelSourceDebugPage(...)`，
但规则管理页又 `import` 了同一个页面并自己 `Navigator.push`，于是 release 里
这条引用静态可达，调试页与整套追踪设施照样进包——违反「release 不打包调试面板」。
**为什么**：`kDebugMode` 是编译期常量，能剪掉**分支内的构造**，却剪不掉另一处
文件顶部的 `import` 与那条调用链；「只在 debug 用」必须让所有引用都不可达，
不能只把关一处。
**怎么断**：debug-only 页面的入口做成装配处注入的可空回调（本仓：管理页只持有
`openDebug(sourceKey)`，`novel_entry.dart` 在 `kDebugMode` 下才传），页面本身不被
任何 release 可达文件 import。验收别靠读代码：`flutter build windows --release` 后
用 UTF-16LE 在 `data/app.so` 里搜调试页独有文案应 ABSENT、搜生产页文案应 FOUND。

### 音量键 / 媒体键在 Flutter 侧根本收不到，必须走 Activity + 通道　复发：✕（2026-11-25）
**现象**：给阅读页加 `KeyboardListener` / `Shortcuts` 监听音量键毫无反应，以为通道
没接好；实际上事件从来没有到 Flutter。
**为什么**：音量键在 Android 上由系统（PhoneWindowManager / AudioManager）在
Activity 之前消费，不会传给 Flutter 的键盘管线；媒体键同理还得配 MediaSession。
**怎么断**：只能在 `MainActivity.dispatchKeyEvent` 拦截 + MethodChannel 回推。本仓
已有 `mimao/volume`（token 租约，1 = 上一页 / 2 = 下一页），Dart 侧控制器在
`lib/core/volume_keys.dart`，漫画与小说两个阅读器共用——**别为第二个阅读器再写一套
租约**，也别忘了桌面端 `supportsVolumeKeys == false` 时保持 no-op。

### 单端能力别引跨平台插件：screen_brightness / wakelock_plus 会牵连 Windows 构建面　复发：✕（2026-11-25）
**现象**：只想要「Android 真亮度 + 常亮」，一引 `screen_brightness` 就让 Windows
构建多出 `screen_brightness_windows` 这个 C++ 插件（`#pragma comment(lib,"Dxva2.lib")`），
`wakelock_plus` 还会牵进 `package_info_plus`/`win32` 一串传递依赖，并迫使
`pubspec.lock` 按镜像整体重生成。
**为什么**：Flutter 的联邦插件按平台注册，依赖一旦进 pubspec，桌面构建也会编；
「只在 Android 用」并不能阻止它在 Windows 参与编译。
**怎么断**：这类窗口级能力自己开 MethodChannel 只实现 Android 端（本仓
`mimao/display`：`window.attributes.screenBrightness` + `FLAG_KEEP_SCREEN_ON`，
都不需要 `WRITE_SETTINGS`，Activity 销毁自动恢复），Dart 侧用平台抽象隔离、
桌面返回 no-op；`pubspec.yaml` 一行不动，Windows 构建面零变化。

### 只隐藏一根系统栏时没有「粘性」模式：SystemUiMode.manual 唤出后不会自动收回　复发：✕（2026-11-25）
**现象**：把「隐藏状态栏 / 隐藏导航栏」拆成两个独立开关后，只关一根时用户从屏幕边缘
滑出系统栏，它就一直留着，不像两根都隐藏时的 `immersiveSticky` 会自动缩回。
**为什么**：Flutter 只有 `immersive`/`immersiveSticky` 这一组「两根都隐藏」的
粘性模式；单根控制必须用 `SystemUiMode.manual` + `overlays` 指定留下哪一根，而
manual 没有 sticky 语义。
**怎么断**：接受这个差异，两根都隐藏时继续走 `immersiveSticky`（观感与改造前完全
一致），并写进 `planNovelSystemBars` 的映射与测试；别为「单根也粘性」去写原生
`WindowInsetsController`，那是没有真机验证渠道的活。

### 没有真机/模拟器时，Android 专属能力只能验到 Dart 侧　复发：✕（2026-11-25）
**现象**：亮度、常亮、系统栏、方向、音量键全在 Android 才生效，但本机 `flutter
emulators` 无 AVD、SDK 无 system-image，`flutter devices` 只有 Windows——点不了、
截不了、看不出「真的变了」。
**为什么**：这些能力全在原生侧（窗口属性 / WindowInsetsController / 键事件），
Dart 侧测试只能证明「期望状态交给了平台」。
**怎么断**：平台调用全部收进 `NovelPlatform`，用 fake 断言调用序列与参数映射
（`novel_platform_test` / `novel_reader_platform_test`），提交 body 与本节明确写
「仅编译 + 逻辑单测通过，未真机验证」；真机效果列进待办，不拿「测试绿」冒充验收。

## 十、媒体播放器状态机（番剧模块已下线，坑对任何 media_kit 引擎都成立）

### 「起播成功」不能看头几百毫秒的 `playing=true`　复发：✕（2026-11-22）
**现象**：坏地址 `open()` 后约 428ms 引擎就报 `playing=true`，错误遮罩要到 +1.4s（404）或 +5s（TCP 拒绝/挂起）才出现；期间 UI 先显示「播放中」，又被 `playing=false` 校正成假的 `paused`，全程没有加载指示。
**为什么**：mpv 乐观起播，`stream.error` 迟到；controller 的 `_onSnapshot` 盲信快照里的 playing，没有「已起播」的正判据。
**怎么断**：起播成功要等 position 推进或 `duration > 0`；加载窗口内状态保持 loading，不落 paused。

### 从错误态恢复必须走重建路径，只清 `errorMessage` 等于骗自己　复发：✕（2026-11-22）
**现象**：错误态下按「播放」（非重试）按钮，`errorMessage` 被清掉、状态进 playing，但引擎已 idle，黑屏且再无事件。
**为什么**：恢复动作只清了 UI 字段，没走 `engine.open()`；只有 `start()` / `loadEpisode` 是真重建路径。
**怎么断**：所有「从错误恢复」的入口收敛到同一个重建函数；清 error 必须伴随一次 open（代次递增）。

### 换代时引擎必须丢旧代事件，归属判据不能用到达时刻　复发：✕（2026-11-22）
**现象**：`open()` 之后仍收到上一代的 `pos=7526ms`、`playing=false`，同步清理快照还携带旧代残留的 `playing=true`。
**为什么**：引擎对 playing/position/duration/buffering/error 六路事件无分代防护；error 类一旦泄漏就粘到下次 open（`_error` 只在 open 清一次）。
**怎么断**：带 generation/requestId 丢弃非当代事件；但归属不能按到达时刻判（旧代尾行与新代新错误都可能在 open 后到达），只能用错误文案 + 当前代 URL + 已上报集合匹配。

### 数错误流只数映射后的 `MPV-ERROR`，不数原始日志行　复发：✕（2026-11-22）
**现象**：日志里的 `lavf: Failed to create file cache.`（好地址也有）差点被当成 `stream.error` 追根因。
**为什么**：media_kit 的 error 映射是白名单，只有 prefix ∈ {file, ffmpeg(tcp:*), vd, ad, cplayer, stream} 才进 `stream.error`，lavf 不映射。
**怎么断**：先确认某行在不在白名单，再谈它能不能污染状态。

### 照「事故现场想象」的 bug 报告改引擎，是白改　复发：✕（2026-11-22）
**现象**：一份「遮罩出现后不自恢复」的报告，六场景全绿、本仓完全不复现；结构风险真实存在，但当前取消语义让它触发不了。
**为什么**：报告没有确定性复现脚本，来自对现场的想象。
**怎么断**：先写无 UI、自动退出、输出即证据的复现入口（`flutter run -d windows -t tool/diag_*.dart`，场景矩阵带 EXPECT 行）；不复现就只补回归契约测试（假后端加 `openFailures`/`pendingErrors`/`flushPendingErrors()` 对齐实测语义），引擎零改动，结构风险写进「潜在风险」留档不修。

## 十一、播放探针（音乐）

### 错误码→文案的映射必须收敛在一层，UI 永不裸暴露 code　复发：✕（2026-11-21）
**现象**：探针只看到「请先登录酷狗账号后播放」，分不清是「未登录」还是「没版权」。
**为什么**：匿名 `/v1/user_verify` 返回 `business/35002`，端点层只给 business；上游只有 `35005` 单列 authentication，展示层直接透传就把登录问题说成版权问题。
**怎么断**：映射收敛在 `KugouPlaybackApi`：匿名 user_verify business → `authentication`，已登录保持 `business`（文案「该曲目暂不可播（错误码 N）」），原始 code 留在异常里；每种映射配一条离线测试。

### 「未就绪」类错误码要做有上限的自动重试，别当业务错误抛给 UI　复发：✕（2026-11-21）
**现象**：设备注册 `/risk/v3/r_register_dev` 第一次返回 `device_registration_unassigned`，整条探针差点止步。
**为什么**：服务端偶发「未分配」，重试即拿到 24 位 dfid，不是终态错误。
**怎么断**：客户端做有上限自动重试；探针文档写清「首次失败 + 重试成功」是正常路径。

### 探针跑在依赖未就绪的分支上，结论只对当前快照成立　复发：✕（2026-11-21）
**现象**：探针得出「匿名态不可播、无 url、无声」，但登录线当时还没合入，url/出声/进度写入根本没验过。
**为什么**：并行多线里探针跑早了。
**怎么断**：探针必须写死「未覆盖形态 + 复测触发条件」；端到端（真实窗口 + SendInput 输入）与离线直调端点层两条证据交叉，不只信一边。

## 十二、规划与评审（跨项目复用）

### review 意见要有「处置单元」记账，不能按原始条数对账　复发：✕（2026-11-21）
**现象**：18 条意见「全部复核」，处置表却 26 行，正文说 25 条——A19 与 A2 是重复提交被合并，口径对不上。
**为什么**：没有逐条处置单元的记账规则，合并/重复就被悄悄吞掉，事后无法对账。
**怎么断**：成立的意见必须落进最终设计（可指到 §/文件），不成立必须写驳回理由 + 实测依据；处置表按**处置单元**计行并显式注明合并关系（A19=A2）。

### 体量靠想象而非实测，蓝图第一次生长就爆墙　复发：✕（2026-11-20）
**现象**：规划写「每模块终态 15–25 文件」，实测上游 `lib/` 有 409 个 Dart 文件；目录自报 21 实数 27。
**为什么**：数字靠想象，自报数字没有机器对账。
**怎么断**：规划前先实测体量（contents API / codeload 解包 grep），差一个数量级就改结构而非改期；所有数字只在一处维护，上游 commit/文件数开工当天重核。

### 最在意的口味要升成一票否决项 + 机器哨兵，约定才守得住　复发：✕（2026-11-20）
**现象**：三案对抗最后选「少一层是一层」，但目录繁乱与否只靠自觉，随人手漂。
**为什么**：口味分歧下折衷必出四不像；约定靠自觉会漂。
**怎么断**：把最在意的口味写成一票否决项 + 机器哨兵（`test/architecture/boundary_test.dart` 扫 import 断边界），选一个底子其余只做点状嫁接。

### 「无消费者不建」：没有调用方的抽象是先交概念税　复发：✕（2026-11-20）
**现象**：`drift` / `MobX` / `flutter_modular` / `AudioService.init` / 契约里的 `webviewFactory` 被反复拉扯，且都没人用。
**为什么**：口味问题与「无消费者」混在一起谈。
**怎么断**：口味分歧只标「临时决定 + 拍板期限」；纯口味别自己拍。「无消费者不建」作为纪律：不引入无人用的初始化、不加无消费者的契约成员。

### 双记账必须先定四条，否则必分叉　复发：✕（2026-11-21）
**现象**：统一书架出现「模块库记 ep5、统一表停 ep4」，关窗杀进程即可触发。
**为什么**：同一事实存两份，没有明文裁决规则，谁也不知道哪边权威。
**怎么断**：定四条——权威=模块库、写入点=持久化点、校正点=打开动作、壳只读公共列；公共列提前到建表时补齐。

### 门禁不分域，会把「别人的代码」按自写标准卡死　复发：✕（2026-11-20）
**现象**：CI 跑 `dart format .` / `analyze --fatal-infos` 覆盖全库，与「镜像上游目录以便机械 patch 重放」直接互拆。
**为什么**：门禁没分域。
**怎么断**：自写代码严格门，镜像进来的上游目录只守 error；`ci.yml` 按域执行。本仓当前无镜像目录，故三门统一扫 `lib/*`（见 `AGENTS.md`）。

### 交付物要两两对照，各文档内自洽但拼起来会炸　复发：✕（2026-11-20）
**现象**：整树搬运四个 GPL-3.0 上游，但仓库缺 LICENSE/NOTICE；文档用不存在的 `lib/modules/` 指代路径；`AudioHandler` 落位与「entry 唯一对外」冲突。
**为什么**：法律件、路径命名、铁律一致性没人对照。
**怎么断**：定稿后拿交付物两两对照（CI↔镜像、文档↔树、铁律↔落位）；整树分发当天补 LICENSE/NOTICE/署名；指代一律用实际存在的具体路径，不用别名。

### 想用编译期条件区分桌面/移动平台，Dart 做不到　复发：✕（2026-11-20）
**现象**：`window/` 起初想用条件导入双文件分 Windows/Android，行不通。
**为什么**：Dart 条件导入只有 `dart.library.*` 条件，分不开两个桌面/移动平台。
**怎么断**：平台分支用运行时判断（`if (isDesktop())`），单文件 `window.dart`；凡是想用编译期条件区分平台的方案，先确认该条件维度真的存在。
