// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'package:flutter/material.dart';

import 'anime_image_mirror.dart';

/// 封面：网络图 + 离线渐变占位。
///
/// fixture 的 coverUrl 为空串（测试完全离线）；真实数据填 http(s) 地址或
/// `assets/` 路径即可。加载失败/加载中一律回落到占位图，不抛异常。
///
/// [mirror] 注入镜像开关控制器后，网络图会按当前开关改写成代理地址以绕过
/// 防盗链；设置页拨动开关时封面即时重建。不注入时（widget 测试）行为不变。
class AnimeCover extends StatefulWidget {
  const AnimeCover({
    super.key,
    required this.url,
    required this.title,
    this.radius = 16,
    this.mirror,
  });

  final String url;
  final String title;
  final double radius;

  /// 镜像开关控制器；null 表示不走镜像（fixture / 未注入的测试）。
  final AnimeImageMirrorController? mirror;

  @override
  State<AnimeCover> createState() => _AnimeCoverState();
}

class _AnimeCoverState extends State<AnimeCover> {
  @override
  void initState() {
    super.initState();
    widget.mirror?.addListener(_onMirrorChanged);
  }

  @override
  void didUpdateWidget(AnimeCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mirror != widget.mirror) {
      oldWidget.mirror?.removeListener(_onMirrorChanged);
      widget.mirror?.addListener(_onMirrorChanged);
    }
  }

  @override
  void dispose() {
    widget.mirror?.removeListener(_onMirrorChanged);
    super.dispose();
  }

  void _onMirrorChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = _CoverPlaceholder(title: widget.title);
    // 有控制器时按当前开关改写；无控制器时不镜像，保持离线测试行为。
    final trimmed = widget.mirror == null
        ? widget.url.trim()
        : widget.mirror!.mirror(widget.url);
    final Widget image;
    if (trimmed.isEmpty) {
      image = placeholder;
    } else if (trimmed.startsWith('assets/')) {
      image = Image.asset(
        trimmed,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
      );
    } else {
      image = Image.network(
        trimmed,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : placeholder,
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: image,
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.title});

  final String title;

  /// 按标题稳定取一组色调容器色，让列表里的占位封面不千篇一律。
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
    final cs = Theme.of(context).colorScheme;
    final (from, to) = _palette(cs);
    final initial = title.isEmpty
        ? '?'
        : String.fromCharCode(title.runes.first);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 72;
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
                    Icons.smart_display_outlined,
                    size: 20,
                    color: cs.onSurface.withValues(alpha: .55),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.smart_display_outlined,
                        size: 34,
                        color: cs.onSurface.withValues(alpha: .45),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        initial,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.apply(color: cs.onSurface.withValues(alpha: .72)),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
