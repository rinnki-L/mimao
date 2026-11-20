// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/shell/app_registry.dart';
import 'package:mimao/shell/library_page.dart';
import 'package:mimao/shell/settings_page.dart';
import 'package:mimao/shell/shell_store.dart';

/// 壳的导航与承载。M1 只有三个视图：入口拼贴页 / 模块层 / 统一时间线。
/// 壳不含任何业务——模块层的内容由 app_registry 查表得到（未接入则占位）。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  /// 入口色系铺开动画控制器。点击某入口时：从触点画一个该入口色系的圆
  /// 铺满全屏（遮盖入口页）→ 底下 AnimatedSwitcher 已切到模块层 → 圆淡出。
  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// 铺开动画是否进行中——驱动覆盖层的挂载/卸载。
  bool _revealing = false;

  /// 铺开动画期间显示的圆参数：中心/半径/色系。
  Offset _revealCenter = Offset.zero;
  double _revealMaxRadius = 0;
  Color _revealColor = Colors.transparent;
  Color _revealOnColor = Colors.transparent;
  IconData _revealIcon = Icons.zoom_in;
  String _revealLabel = '';

  @override
  void initState() {
    super.initState();
    // 动画结束/被反向重置时卸载覆盖层（视觉已透明，这一步只为清场）。
    _transition.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted && _revealing) {
        setState(() => _revealing = false);
      }
    });
  }

  @override
  void dispose() {
    _transition.dispose();
    super.dispose();
  }

  /// 由入口页点击回调：记下触点/目标色系，起铺开动画。
  /// 业务状态（activeModule）已由入口页的 onTapDown 同步切好，这里只管视觉。
  void _startReveal(MediaType type, Offset globalCenter) {
    // 圆要覆盖整个屏幕：取触点到四个角的最大距离。
    final screen = MediaQuery.of(context).size;
    var radius = 0.0;
    for (final corner in <Offset>[
      Offset.zero,
      Offset(screen.width, 0),
      Offset(0, screen.height),
      Offset(screen.width, screen.height),
    ]) {
      radius = math.max(radius, (globalCenter - corner).distance);
    }

    final cs = Theme.of(context).colorScheme;
    final (color, onColor) = switch (type) {
      MediaType.comic => (cs.secondary, cs.onSecondary),
      MediaType.novel => (cs.tertiary, cs.onTertiary),
      MediaType.music => (cs.primary, cs.onPrimary),
    };

    setState(() {
      _revealing = true;
      _revealCenter = globalCenter;
      _revealMaxRadius = radius;
      _revealColor = color;
      _revealOnColor = onColor;
      _revealIcon = type.icon;
      _revealLabel = type.label;
    });
    _transition.forward(from: 0);
  }

  /// 圆形覆盖层：0→0.62 铺满全屏，0.62→1 淡出露出底下的模块层。
  Widget _revealOverlay() {
    return AnimatedBuilder(
      animation: _transition,
      builder: (context, _) {
        final t = _transition.value;
        final radius = (t / 0.62).clamp(0.0, 1.0) * _revealMaxRadius;
        final opacity = t < 0.62 ? 1.0 : 1.0 - (t - 0.62) / 0.38;
        return IgnorePointer(
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: ClipPath(
              clipper: _CircleRevealClipper(
                center: _revealCenter,
                radius: radius,
              ),
              child: Container(
                color: _revealColor,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_revealIcon, size: 72, color: _revealOnColor),
                      const SizedBox(height: 12),
                      Text(
                        _revealLabel,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.apply(color: _revealOnColor),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = _InheritedLibrary.of(context);

    return Scaffold(
      body: Observer(
        builder: (_) {
          final Widget view = switch ((
            shellStore.activeModule,
            shellStore.showLibrary,
          )) {
            (final MediaType type, false) => _ModuleLayer(type: type),
            (null, true) => _LibraryLayer(repository: library),
            _ => _EntryPage(onEntryTap: _startReveal),
          };
          final normal = AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: view,
          );
          // 动画运行时叠一层圆形色系铺开，盖住切换过程；结束即移除。
          return Stack(children: [normal, if (_revealing) _revealOverlay()]);
        },
      ),
      endDrawer: const SettingsPage(),
      onEndDrawerChanged: (opened) {
        if (!opened && shellStore.settingsOpen) shellStore.closeSettings();
      },
    );
  }
}

/// 以触点为中心、给定半径裁一个圆（铺开动画用）。
class _CircleRevealClipper extends CustomClipper<Path> {
  final Offset center;
  final double radius;

  const _CircleRevealClipper({required this.center, required this.radius});

  @override
  Path getClip(Size size) =>
      Path()..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(_CircleRevealClipper old) =>
      old.center != center || old.radius != radius;
}

/// 把 LibraryRepository 从 main.dart 传到壳（壳不自己 new DB，便于测试替换）。
class LibraryScope extends StatelessWidget {
  final LibraryRepository repository;
  final Widget child;

  const LibraryScope({
    super.key,
    required this.repository,
    required this.child,
  });

  @override
  Widget build(BuildContext context) =>
      _InheritedLibrary(repository: repository, child: child);
}

class _InheritedLibrary extends InheritedWidget {
  final LibraryRepository repository;

  const _InheritedLibrary({required this.repository, required super.child});

  static LibraryRepository of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_InheritedLibrary>()!
      .repository;

  @override
  bool updateShouldNotify(_InheritedLibrary old) =>
      repository != old.repository;
}

// ────────────────────────────────────────────────────────────────
// 入口页：斜切拼贴（用户拍板，替换掉叠牌式）
//   用户拍板：番剧入口/模块已整体删除（Bangumi 搜索国内不可用），只保留漫画/小说/音乐。
//   三入口用三条平行斜带铺满整屏：没有任何水平分界，手机好看、桌面更舒展。
//   点某条带 → 按点击的 y 坐标换算落在哪一带 → 一步钻进该模块。
//   切换进来时三带自上而下依次滑入（easeOutCubic 分级间隔）。
// ────────────────────────────────────────────────────────────────

/// 入口页展示的媒体类型——三入口（漫画/小说/音乐）。
const List<MediaType> entryTypes = <MediaType>[
  MediaType.comic,
  MediaType.novel,
  MediaType.music,
];

class _EntryPage extends StatelessWidget {
  /// 点击入口时回调：传入目标类型与屏幕全局触点，供壳层起铺开动画。
  final void Function(MediaType type, Offset globalCenter)? onEntryTap;

  const _EntryPage({this.onEntryTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 品牌标题块（logo + mimao + 副标题）已按用户要求去掉——非商业
            // 软件不需要门面。只保留右上角书架/设置两个功能按钮。
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton.filledTonal(
                  tooltip: '统一书架',
                  icon: const Icon(Icons.collections_bookmark_outlined),
                  onPressed: shellStore.openLibrary,
                ),
                const SizedBox(width: 8),
                Builder(
                  builder: (iconContext) => IconButton.filledTonal(
                    tooltip: '设置',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => Scaffold.of(iconContext).openEndDrawer(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => _DiagonalEntry(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  onEntryTap: onEntryTap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 两条平行分界线：给出左边缘/右边缘处的 y 比例（斜率相同，故平行）。
const double _b1Left = 0.40;
const double _b1Right = 0.10;
const double _b2Left = 0.74;
const double _b2Right = 0.44;

class _DiagonalEntry extends StatefulWidget {
  final double width;
  final double height;
  final void Function(MediaType type, Offset globalCenter)? onEntryTap;

  const _DiagonalEntry({
    required this.width,
    required this.height,
    this.onEntryTap,
  });

  @override
  State<_DiagonalEntry> createState() => _DiagonalEntryState();
}

class _DiagonalEntryState extends State<_DiagonalEntry>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 920),
  );

  // 三条带自上而下依次滑入：每条用不同 Interval 做分级延迟。
  late final List<Animation<Offset>> _slides = List.generate(
    entryTypes.length,
    (i) =>
        Tween<Offset>(begin: const Offset(0, -1.15), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _ctrl,
            curve: Interval(
              i * 0.11,
              0.58 + i * 0.11,
              curve: Curves.easeOutCubic,
            ),
          ),
        ),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// 点任意位置 → 把点击 x 代入两条分界线方程，算出该处两条线的 y →
  /// 判断落在该 x 上的哪一条带 → 一步进对应模块。
  void _onTapDown(TapDownDetails details) {
    final w = widget.width;
    final h = widget.height;
    final x = details.localPosition.dx;
    final y = details.localPosition.dy;
    final b1 = (_b1Left + (_b1Right - _b1Left) * x / w) * h;
    final b2 = (_b2Left + (_b2Right - _b2Left) * x / w) * h;
    final index = y < b1 ? 0 : (y < b2 ? 1 : 2);
    final type = entryTypes[index];
    // 先同步业务状态（NavigationObserver/dev route 等依赖它），再起色系铺开动画。
    shellStore.openModule(type);
    final onTap = widget.onEntryTap;
    if (onTap != null) {
      onTap(type, details.globalPosition);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // opaque：斜带之外的透明区域也要能接到点击（否则 deferToChild 会漏）。
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      child: ClipRRect(
        borderRadius: MimaoShapes.xl,
        child: Stack(
          children: <Widget>[
            for (var i = 0; i < entryTypes.length; i++)
              _DiagonalBand(
                index: i,
                type: entryTypes[i],
                width: widget.width,
                height: widget.height,
                slide: _slides[i],
              ),
          ],
        ),
      ),
    );
  }
}

/// 一条斜带：带底色的斜切 Path + 叠在带内的文字（文字不进 clip，避免被裁）。
class _DiagonalBand extends StatelessWidget {
  final int index;
  final MediaType type;
  final double width;
  final double height;
  final Animation<Offset> slide;

  const _DiagonalBand({
    required this.index,
    required this.type,
    required this.width,
    required this.height,
    required this.slide,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (container, onContainer) = switch (type) {
      MediaType.comic => (cs.secondaryContainer, cs.onSecondaryContainer),
      MediaType.novel => (cs.tertiaryContainer, cs.onTertiaryContainer),
      MediaType.music => (cs.surfaceContainerHighest, cs.onSurface),
    };
    // 文字放在各带靠左、带高足够的位置（避开右端收窄的尖端）。
    final textTop = const <double>[0.05, 0.42, 0.76][index] * height;

    return SlideTransition(
      position: slide,
      child: Stack(
        children: <Widget>[
          ClipPath(
            clipper: _BandClipper(index: index),
            child: Container(width: width, height: height, color: container),
          ),
          Positioned(
            left: 28,
            top: textTop,
            child: Row(
              children: [
                Icon(type.icon, color: onContainer, size: 30),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.apply(color: onContainer),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      type.tagline,
                      style: Theme.of(context).textTheme.bodySmall?.apply(
                        color: onContainer.withValues(alpha: .8),
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

/// 按 index 裁出三条平行斜带之一（其余区域透明）。
class _BandClipper extends CustomClipper<Path> {
  final int index;

  const _BandClipper({required this.index});

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final b1l = _b1Left * h;
    final b1r = _b1Right * h;
    final b2l = _b2Left * h;
    final b2r = _b2Right * h;
    final path = Path();
    switch (index) {
      case 0:
        path
          ..moveTo(0, 0)
          ..lineTo(w, 0)
          ..lineTo(w, b1r)
          ..lineTo(0, b1l)
          ..close();
      case 1:
        path
          ..moveTo(0, b1l)
          ..lineTo(w, b1r)
          ..lineTo(w, b2r)
          ..lineTo(0, b2l)
          ..close();
      default:
        path
          ..moveTo(0, b2l)
          ..lineTo(w, b2r)
          ..lineTo(w, h)
          ..lineTo(0, h)
          ..close();
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _BandClipper old) => old.index != index;
}

// ────────────────────────────────────────────────────────────────
// 统一书架层：与模块层同一套顶部导航（返回 + 标题）——此前书架页
// 没有任何退出入口，真机验收（2026-11-18）发现，用 goHome() 修。
// ────────────────────────────────────────────────────────────────
class _LibraryLayer extends StatelessWidget {
  final LibraryRepository repository;

  const _LibraryLayer({required this.repository});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: '返回',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: shellStore.goHome,
                ),
                Text('统一书架', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
        ),
        Expanded(child: LibraryPage(repository: repository)),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────────
// 模块层：进入后另外两个入口消失。顶部只有"返回"和标题。
// 内容来自 app_registry 查表；未接入的模块显示占位页。
// ────────────────────────────────────────────────────────────────
class _ModuleLayer extends StatelessWidget {
  final MediaType type;

  const _ModuleLayer({required this.type});

  @override
  Widget build(BuildContext context) {
    final module = moduleFor(type);
    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                IconButton(
                  tooltip: '返回',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: shellStore.goHome,
                ),
                Text(type.label, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
        ),
        Expanded(
          child: module == null
              ? _UnimplementedModule(type: type)
              : module.buildHome(context),
        ),
      ],
    );
  }
}

/// 模块尚未接入时的占位页（app_registry 查表失败兜底）。番剧下线后，
/// 三入口均常驻注册，本页仅在某模块装配异常被移除时出现。
class _UnimplementedModule extends StatelessWidget {
  final MediaType type;

  const _UnimplementedModule({required this.type});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(type.icon, size: 64, color: cs.primary),
          const SizedBox(height: 16),
          Text(
            '${type.label}模块尚未接入',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            type.tagline,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.apply(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
