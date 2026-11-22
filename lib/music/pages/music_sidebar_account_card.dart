// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 侧栏顶部的账号小卡片（2026-11-22 侧栏信息架构升级）。
///
/// 展示头像 + 昵称 + 听歌等级；由模块出口装配（认识 [MusicUserProfileApi]），
/// 模块层只负责选中态外框与点按 → 账号分区。窄侧栏（<120 可用宽）只留
/// 头像。登录态变化（[authEpoch]）自动重拉；未登录/拉取失败回退
/// 「未登录」占位，点按仍进账号分区（那里有登录入口）。
///
/// 资料模型里的 vipType 只是 wire 原始码（本仓没有可靠的品牌语义映射，
/// 会员明细在独立的 user_vip_detail 端点），卡片不猜标签——只画等级。
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/user_profile_api.dart';
import 'package:mimao/music/models/user_models.dart';

/// 账号小卡片内容（展示层；选中底色与点按由模块层侧栏包）。
class MusicSidebarAccountCard extends StatefulWidget {
  const MusicSidebarAccountCard({
    super.key,
    required this.profile,
    this.authEpoch,
  });

  /// 用户资料组接口（userDetail 提供昵称/头像/等级）。
  final MusicUserProfileApi profile;

  /// 登录态变化信号：登录/切号后自动重拉。
  final ValueListenable<int>? authEpoch;

  @override
  State<MusicSidebarAccountCard> createState() =>
      _MusicSidebarAccountCardState();
}

class _MusicSidebarAccountCardState extends State<MusicSidebarAccountCard> {
  MusicUserProfile? _profile;

  /// true = 资料拉取失败（含未登录的鉴权错）：画「未登录」占位而不是报错。
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    widget.authEpoch?.addListener(_reload);
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant MusicSidebarAccountCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.authEpoch != oldWidget.authEpoch) {
      oldWidget.authEpoch?.removeListener(_reload);
      widget.authEpoch?.addListener(_reload);
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
    widget.authEpoch?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final profile = await widget.profile.userDetail();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _failed = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _profile = null;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final profile = _profile;
    // 三态文案：失败（含未登录）→ 未登录；加载中 → 提示；成功 → 昵称 + 等级。
    final (title, subtitle) = _failed
        ? ('未登录', '')
        : profile == null
        ? ('加载中…', '')
        : (
            profile.nickname.isEmpty ? '—' : profile.nickname,
            profile.grade != null ? 'Lv.${profile.grade}' : '',
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 120;
        final avatar = _Avatar(url: profile?.avatarUrl ?? '');
        if (!wide) return avatar;
        return Row(
          children: <Widget>[
            avatar,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: MimaoFonts.bold,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 头像（36×36 圆形；无 URL/加载失败回退人形占位，账号页 _Avatar 同款缩小版）。
class _Avatar extends StatelessWidget {
  const _Avatar({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Widget fallback = CircleAvatar(
      radius: 18,
      backgroundColor: cs.surfaceContainerHighest,
      child: Icon(Icons.person, size: 20, color: cs.primary),
    );
    if (url.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        url,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}
