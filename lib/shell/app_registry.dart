import 'package:mimao/core/contract.dart';

/// 全库**唯一**允许 import 四个模块目录（`anime/`、`comic/`、`music/`、
/// `novel/`）的文件——第四条铁律的载体（docs/architecture.md §2）。
///
/// M1 尚无模块：这张目录为空。M2 起每接入一个模块，在这里加一行 import +
/// 注册一个 [AppModule] 实现；删模块 = 删目录 + 删这里一行，机械可验证。
/// 唯一 AudioHandler 也经本文件从 anime_entry 取出并注册（§6.2，M2）。
final Map<MediaType, AppModule> appModules = <MediaType, AppModule>{};

/// 壳查询某类型的模块实现；返回 null 表示"尚未接入"，由壳显示占位页。
AppModule? moduleFor(MediaType type) => appModules[type];
