// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与其他模块页面同款说明；保持类型一致、patch 可重放。
/// 小说模块共用的视觉原语：页头、内容宽度、封面、卡片、统计卡、空/错/加载态、
/// 阅读目标半圆表盘、时长/进度文案。
///
/// 样式只从这里出，页面不手写颜色/圆角/字重：
/// - 颜色只取 `ColorScheme` 角色（封面上的遮罩/角标除外，那里没有语义色可依）；
/// - 圆角只用 [MimaoRadii]；
/// - 字重用 theme 里的 w400/w700，不写中间字重。
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

/// 页面内容的最大宽度（桌面宽窗不把一行拉成 1600px 的阅读灾难）。
const double novelPageMaxWidth = 1240;

/// 统一的页面内容容器：居中 + 限宽 + 响应式左右留白。
class NovelPageContent extends StatelessWidget {
  const NovelPageContent({
    super.key,
    required this.child,
    this.maxWidth = novelPageMaxWidth,
    this.padding = const EdgeInsets.fromLTRB(24, 8, 24, 24),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        final effective = narrow
            ? EdgeInsets.fromLTRB(
                padding.left.clamp(0.0, 16.0),
                padding.top,
                padding.right.clamp(0.0, 16.0),
                padding.bottom,
              )
            : padding;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(padding: effective, child: child),
          ),
        );
      },
    );
  }
}

/// 自带高度约束的居中内容容器：内部可安全使用 Expanded（页面型 tab 用）。
class NovelFillContent extends StatelessWidget {
  const NovelFillContent({
    super.key,
    required this.child,
    this.maxWidth = novelPageMaxWidth,
    this.padding = const EdgeInsets.fromLTRB(24, 8, 24, 0),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        final horizontal = narrow
            ? padding.left.clamp(0.0, 16.0).toDouble()
            : padding.left;
        final width = constraints.maxWidth.clamp(0.0, maxWidth).toDouble();
        return Center(
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontal,
                padding.top,
                horizontal,
                padding.bottom,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// 大标题页头（参考图里「首页 / 书架 / 发现」的观感），右侧放操作按钮。
class NovelPageHeader extends StatelessWidget {
  const NovelPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// 标题下方的附加行（搜索框、筛选 chip 等）。
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.headlineMedium),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (actions.isNotEmpty) ...<Widget>[
                const SizedBox(width: 12),
                Wrap(spacing: 8, children: actions),
              ],
            ],
          ),
          if (bottom != null) ...<Widget>[const SizedBox(height: 16), bottom!],
        ],
      ),
    );
  }
}

/// 圆形图标按钮（参考图右上角的浅色圆钮）。带 tooltip，桌面可 hover/focus。
class NovelCircleAction extends StatelessWidget {
  const NovelCircleAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}

/// 填充卡：无阴影、圆角 lg；可点时有水波纹 + hover/focus 反馈。
class NovelCard extends StatelessWidget {
  const NovelCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final body = Padding(padding: padding, child: child);
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? body
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              child: InkWell(onTap: onTap, child: body),
            ),
    );
  }
}

/// 卡片内的小节标题（图标 + 标题 + 可选右侧操作）。
class NovelSectionHeader extends StatelessWidget {
  const NovelSectionHeader({
    super.key,
    this.icon,
    required this.title,
    this.trailing,
  });

  final IconData? icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// 统计卡：图标 + 标签 + 大数字 + 单位（对应参考图的「累计阅读 / 阅读时长」）。
class NovelStatCard extends StatelessWidget {
  const NovelStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NovelCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(MimaoRadii.md),
            ),
            child: Icon(icon, size: 22, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        value,
                        style: theme.textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      unit,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 书封：网络/本地/asset 三路 + 无图时的稳定渐变占位（按标题取色）。
class NovelBookCover extends StatelessWidget {
  const NovelBookCover({
    super.key,
    required this.url,
    required this.title,
    this.borderRadius = MimaoRadii.md,
  });

  final String url;
  final String title;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final placeholder = _NovelCoverPlaceholder(title: title);
    final trimmed = url.trim();
    final Widget image;
    if (trimmed.isEmpty) {
      image = placeholder;
    } else if (trimmed.startsWith('assets/')) {
      image = Image.asset(
        trimmed,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      );
    } else if (_isLocalPath(trimmed)) {
      final path =
          trimmed.startsWith('file://') &&
              Uri.tryParse(trimmed)?.scheme == 'file'
          ? Uri.parse(trimmed).toFilePath()
          : trimmed;
      image = Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      );
    } else {
      image = Image.network(
        trimmed,
        fit: BoxFit.cover,
        // 部分书源站点会拒绝空 UA / Dart 默认 UA 的封面请求。
        headers: const <String, String>{
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
        },
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : placeholder,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: image,
    );
  }

  static bool _isLocalPath(String value) {
    if (value.startsWith('file://')) return true;
    if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) return true;
    return value.startsWith('/') && !value.startsWith('//');
  }
}

class _NovelCoverPlaceholder extends StatelessWidget {
  const _NovelCoverPlaceholder({required this.title});

  final String title;

  (Color, Color) _palette(ColorScheme cs) {
    final seed = title.runes.fold<int>(0, (sum, rune) => sum + rune);
    final palette = <(Color, Color)>[
      (cs.primaryContainer, cs.tertiaryContainer),
      (cs.secondaryContainer, cs.primaryContainer),
      (cs.tertiaryContainer, cs.secondaryContainer),
      (cs.surfaceContainerHighest, cs.primaryContainer),
    ];
    return palette[seed % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (from, to) = _palette(cs);
    final initial = title.isEmpty
        ? '?'
        : String.fromCharCode(title.runes.first);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 64;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[from, to],
            ),
          ),
          child: Center(
            child: compact
                ? Icon(
                    Icons.auto_stories_outlined,
                    size: 18,
                    color: cs.onSurface.withValues(alpha: .55),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.auto_stories_outlined,
                        size: 28,
                        color: cs.onSurface.withValues(alpha: .45),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        initial,
                        style: theme.textTheme.titleLarge?.apply(
                          color: cs.onSurface.withValues(alpha: .72),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// 书封右上角的白色数量角标（参考图里封面上的 128 / 943）。
class NovelCoverBadge extends StatelessWidget {
  const NovelCoverBadge({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(MimaoRadii.pill),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurface),
      ),
    );
  }
}

/// 药丸标签（分组、源类型）。
class NovelTag extends StatelessWidget {
  const NovelTag({super.key, required this.label, this.highlighted = false});

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: highlighted ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(MimaoRadii.pill),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: highlighted ? cs.onPrimaryContainer : cs.onSurfaceVariant,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// 选中态筛选 chip（在读/未读/已读/全部）。
class NovelFilterChip extends StatelessWidget {
  const NovelFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = count == null ? label : '$label  $count';
    return Semantics(
      selected: selected,
      label: label,
      child: Material(
        color: selected
            ? cs.primary
            : cs.surfaceContainerHighest.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(MimaoRadii.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(MimaoRadii.pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              text,
              style: theme.textTheme.labelLarge?.copyWith(
                color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 通用空态：说明"为什么空 + 下一步做什么"，不写"暂无数据"。
class NovelEmptyState extends StatelessWidget {
  const NovelEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: cs.primary),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (action != null) ...<Widget>[
                const SizedBox(height: 20),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 错误态：给可操作下一步，技术细节留给日志。
class NovelErrorState extends StatelessWidget {
  const NovelErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.hint,
  });

  final String message;
  final VoidCallback? onRetry;

  /// 可操作提示；null 时用旧版「检查书源」兜底（多数页面仍是抓取类错误）。
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return NovelEmptyState(
      icon: Icons.error_outline,
      title: '没能加载出来',
      message: '$message\n${hint ?? '可以重试一次；反复失败时去「我的 → 规则管理」检查书源是否可用。'}',
      action: onRetry == null
          ? null
          : FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
    );
  }
}

/// 加载态。
class NovelLoadingState extends StatelessWidget {
  const NovelLoadingState({super.key, this.label = '正在读取本地书架…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 阅读目标半圆表盘：深色进度 + 浅色轨道 + 中心「已读 / 目标 分钟」。
class NovelReadingGauge extends StatelessWidget {
  const NovelReadingGauge({
    super.key,
    required this.progress,
    required this.minutes,
    required this.goalMinutes,
    this.size = const Size(240, 132),
  });

  /// 0..1。
  final double progress;
  final int minutes;
  final int goalMinutes;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          CustomPaint(
            size: size,
            painter: _NovelGaugePainter(
              progress: progress.clamp(0.0, 1.0),
              trackColor: cs.surfaceContainerHighest,
              progressColor: cs.primary,
            ),
          ),
          Positioned(
            bottom: 6,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '$minutes / $goalMinutes',
                  style: theme.textTheme.headlineSmall,
                ),
                Text(
                  '分钟',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NovelGaugePainter extends CustomPainter {
  const _NovelGaugePainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    // 正方形外接框：宽 240 时画一个半径 113 的上半圆，底部自然裁掉。
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.width - stroke,
    );
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = progressColor;
    canvas.drawArc(rect, math.pi, math.pi, false, track);
    if (progress > 0) {
      canvas.drawArc(rect, math.pi, math.pi * progress, false, fill);
    }
  }

  @override
  bool shouldRepaint(_NovelGaugePainter old) =>
      old.progress != progress ||
      old.trackColor != trackColor ||
      old.progressColor != progressColor;
}

/// 书源图标底板：深色圆角方块 + 书名首字（参考图「订阅」页的源图标）。
class NovelSourceBadge extends StatelessWidget {
  const NovelSourceBadge({super.key, required this.name, this.size = 44});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final initial = name.isEmpty ? '书' : String.fromCharCode(name.runes.first);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(MimaoRadii.md),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: theme.textTheme.titleMedium?.copyWith(
          color: cs.onInverseSurface,
        ),
      ),
    );
  }
}

/// 一条书源卡片：图标 + 名称/地址/分组标签 + 启用开关。
///
/// 发现与订阅两页共用；点击整卡进入书源管理，开关直接落仓库（乐观更新由
/// 页面负责，失败回滚）。
class NovelSourceCard extends StatelessWidget {
  const NovelSourceCard({
    super.key,
    required this.source,
    required this.onToggle,
    this.onTap,
    this.trailing,
  });

  final NovelBookSource source;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NovelCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      child: Row(
        children: <Widget>[
          NovelSourceBadge(name: source.name),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        source.name,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    NovelTag(label: source.typeLabel),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  source.url,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: <Widget>[
                    for (final group in source.groups.take(3))
                      NovelTag(label: group),
                    if (source.groups.isEmpty) const NovelTag(label: '未分组'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (trailing != null) trailing!,
          Switch(value: source.enabled, onChanged: onToggle),
        ],
      ),
    );
  }
}

/// 今日阅读目标编辑对话框（首页与设置页共用）。返回分钟数，取消返回 null。
class NovelGoalDialog extends StatefulWidget {
  const NovelGoalDialog({super.key, required this.initialMinutes});

  final int initialMinutes;

  @override
  State<NovelGoalDialog> createState() => _NovelGoalDialogState();
}

class _NovelGoalDialogState extends State<NovelGoalDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.initialMinutes}',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < 0 || value > 1440) {
      setState(() {
        _error = '请输入 0–1440 之间的整数（0 = 关闭目标）';
      });
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('今日阅读目标'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: InputDecoration(
              labelText: '每天阅读分钟数',
              helperText: '按阅读页实际停留时间累计',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

/// 阅读时长（秒）→ (数值, 单位) 两段，供统计卡排版。
///
/// 0 秒显示「0 分钟」；不足 1 分钟显示「不到 1 分钟」；1 小时内按分钟取整；
/// 超过 1 小时保留一位小数（对齐全书统计里 119.6 小时的写法）。
(String, String) novelDurationParts(int seconds) {
  if (seconds <= 0) return ('0', '分钟');
  if (seconds < 60) return ('不到 1', '分钟');
  if (seconds < 3600) return ('${seconds ~/ 60}', '分钟');
  final hours = seconds / 3600;
  // 一位小数（119.6 小时）；整点小时不带 .0。
  final text = hours.toStringAsFixed(1);
  return (
    text.endsWith('.0') ? text.substring(0, text.length - 2) : text,
    '小时',
  );
}

/// 阅读进度百分比（0..100）；无法计算时 null。
int? novelBookPercent({required int chapterIndex, required int chapterCount}) {
  if (chapterCount <= 0 || chapterIndex <= 0) return null;
  return ((chapterIndex / chapterCount) * 100).clamp(0, 100).round();
}

/// 相对时间文案（列表副标题用）。
String novelRelativeTime(DateTime at, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final delta = current.difference(at);
  if (delta.inMinutes < 1) return '刚刚';
  if (delta.inHours < 1) return '${delta.inMinutes} 分钟前';
  if (delta.inDays < 1) return '${delta.inHours} 小时前';
  if (delta.inDays < 7) return '${delta.inDays} 天前';
  final local = at.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

/// 章节显示名：章名已自带章号（「第 3 章」「第五章」「Chapter 5」）时只显示
/// 章名，避免拼成「第 3 章 · 第 3 章」「第 5 章 · 第五章 夜航」。
///
/// 书源目录的章名原文千奇百怪，这里只认最常见的几种「章号前缀」；认不出来
/// 就老老实实拼上阿拉伯数字章号（[chapterIndex] 是 1 起，0 = 未知）。
String novelChapterLabel({
  required int chapterIndex,
  required String chapterName,
  String unknown = '章号未知',
}) {
  if (chapterIndex <= 0) return unknown;
  final numbered = '第 $chapterIndex 章';
  final name = chapterName.trim();
  if (name.isEmpty) return numbered;
  if (name.contains(numbered)) return name;
  // 中文数字 / 英文 Chapter 前缀：任何「第…章」或「Chapter N」开头都算自带章号。
  if (RegExp(r'^第\s*[0-9一二三四五六七八九十百千零〇两]+\s*[章节回]').hasMatch(name) ||
      RegExp(r'^chapter\s*\d+', caseSensitive: false).hasMatch(name)) {
    return name;
  }
  return '$numbered · $name';
}

/// 日键（`yyyy-MM-dd`）→ 时间轴分组标题：今天 / 昨天 / `M 月 d 日 · 周X`。
String novelDayLabel(String dayKey, {DateTime? now}) {
  final parts = dayKey.split('-');
  if (parts.length != 3) return dayKey;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final date = int.tryParse(parts[2]);
  if (year == null || month == null || date == null) return dayKey;
  final day = DateTime(year, month, date);
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final delta = today.difference(day).inDays;
  if (delta == 0) return '今天';
  if (delta == 1) return '昨天';
  const weekdays = <String>['一', '二', '三', '四', '五', '六', '日'];
  final weekday = weekdays[(day.weekday - 1).clamp(0, 6)];
  final prefix = year == current.year ? '' : '$year 年 ';
  return '$prefix$month 月 $date 日 · 周$weekday';
}

/// 水平书架条（首页的横向封面行）：鼠标可拖、末尾留白。
class NovelCoverStrip extends StatelessWidget {
  const NovelCoverStrip({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 218,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 4),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) =>
            SizedBox(width: 116, child: itemBuilder(context, index)),
      ),
    );
  }
}
