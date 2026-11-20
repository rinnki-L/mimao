// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'package:flutter/material.dart';

/// 四种媒体——全库共用的最小分类词表（demo 01/02 已验证够用）。
///
/// 刻意不建"统一内容模型"：跨类型的共同列在 core/db.dart 的投影表里，
/// 各类型的私有结构留在模块的 payload 里（docs/architecture.md 锁定决策）。
enum MediaType { anime, comic, novel, music }

extension MediaTypeX on MediaType {
  String get label => switch (this) {
    MediaType.anime => '番剧',
    MediaType.comic => '漫画',
    MediaType.novel => '小说',
    MediaType.music => '音乐',
  };

  IconData get icon => switch (this) {
    MediaType.anime => Icons.smart_display,
    MediaType.comic => Icons.image,
    MediaType.novel => Icons.menu_book,
    MediaType.music => Icons.music_note,
  };

  IconData get outlinedIcon => switch (this) {
    MediaType.anime => Icons.smart_display_outlined,
    MediaType.comic => Icons.image_outlined,
    MediaType.novel => Icons.menu_book_outlined,
    MediaType.music => Icons.music_note_outlined,
  };

  /// 入口卡片上的一句话说明（docs/demos/entry_variants.html DATA[*].tag）。
  String get tagline => switch (this) {
    MediaType.anime => '追更 · 弹幕 · 时间表',
    MediaType.comic => '多源 · 阅读器 · 本地',
    MediaType.novel => '书源 · 离线 · 朗读',
    MediaType.music => '登录态 · 歌单 · 后台播放',
  };
}

/// 应用级目录表的"一行"——模块唯一对外面。
///
/// 模块在 M2 起各自实现本接口；壳只认这张表，不认识任何模块内部类型。
/// 约定而非 Dart 语言机制：由 test/architecture/boundary_test.dart 把守
/// "shell/ 中只有 app_registry.dart 允许 import 模块目录"（铁律④）。
abstract class AppModule {
  MediaType get type;
  String get label;
  IconData get icon;

  /// 模块主页——钻进入口卡片后看到的那一层。
  Widget buildHome(BuildContext context);

  /// 模块自己的设置内容——作为模块主页底部导航最右侧「设置」tab 的页面。
  ///
  /// 全局抽屉只保留通用设置（外观/存储）；各模块设置由自己的 buildHome
  /// 收进模块页，用户拍板「各入口的设置放到各入口里面去」。
  Widget buildSettings(BuildContext context);
}
