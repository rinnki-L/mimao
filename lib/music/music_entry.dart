// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 comic/anime 入口同款说明。
/// 音乐模块对壳的唯一出口——实现 [AppModule]，由 app_registry 注入全部依赖
/// （docs/architecture.md §4.3，M4 骨架）。
///
/// 本类不 new 任何服务：API 门面从构造参数进来，测试可整体替换。骨架期
/// 不带 MusicDb（收藏/历史双记账随歌单/播放器切片落），也不带 player/
/// ——不建空目录（directory-layout.md 增长规则）。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/music_store.dart';
import 'package:mimao/music/pages/music_module_page.dart';
import 'package:mimao/music/pages/music_module_settings.dart';

/// 音乐模块入口。
class MusicModule implements AppModule {
  MusicModule({required MusicApi api, MusicStore? store})
    : _api = api,
      store = store ?? MusicStore(api);

  final MusicApi _api;

  /// 模块生命周期内唯一的 store（壳在入口卡片与设置抽屉间切换时，
  /// 搜索结果等状态保持）。
  final MusicStore store;

  @override
  MediaType get type => MediaType.music;

  @override
  String get label => '音乐';

  @override
  IconData get icon => MediaType.music.icon;

  @override
  Widget buildHome(BuildContext context) {
    return MusicModulePage(store: store, embedded: true);
  }

  @override
  Widget buildSettings(BuildContext context) {
    return MusicModuleSettings(api: _api);
  }
}
