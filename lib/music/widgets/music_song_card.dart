// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 歌曲长条的共用卡片外壳。
///
/// 音乐入口各页的歌曲行（ListTile / InkWell+Row）形态不一，但都只是「封面 +
/// 歌名 + 歌手 + 播放按钮」的一行。这里不重写行组件，只在外层套一张带描边与
/// 阴影的卡片，让列表有层次感；child 的内部结构完全不变，测试仍能按
/// ListTile / 文本 / key 定位。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';

/// 歌曲长条卡片：圆角 lg + 细描边 + 1 级阴影，纵向留 4 的卡片间距。
class MusicSongCard extends StatelessWidget {
  const MusicSongCard({
    super.key,
    required this.child,
    this.horizontalMargin = 0,
  });

  /// 原歌曲行组件（ListTile / InkWell+Row 等）。
  final Widget child;

  /// 外层列表无横向内边距时传 16，避免卡片贴屏幕边缘；有 16 padding 的
  /// 列表保持默认 0。
  final double horizontalMargin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      // 项目 CardTheme 是 elevation 0 / 无描边，这里显式给阴影 + 细边，
      // 否则卡片与背景同色、看不出层次。
      elevation: 1,
      margin: EdgeInsets.symmetric(horizontal: horizontalMargin, vertical: 4),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: MimaoShapes.lg,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: child,
    );
  }
}
