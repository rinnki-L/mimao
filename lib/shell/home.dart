// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
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
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    // LibraryRepository 由 main.dart 经 LibraryScope 注入；壳只读 core 的 facade。
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
            _ => const _EntryPage(),
          };
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: view,
          );
        },
      ),
      endDrawer: const SettingsPage(),
      onEndDrawerChanged: (opened) {
        if (!opened && shellStore.settingsOpen) shellStore.closeSettings();
      },
    );
  }
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
// 入口页：C · 拼贴（用户拍板的方案）
//   用户拍板：番剧入口移除（Bangumi 搜索国内不可用），只保留漫画/小说/音乐。
//   非对称 bento：宽窗上行漫画(2列)+小说(1列)、下行音乐全宽；
//   窄窗漫画全宽、小说/音乐并排。点任意卡片 → 钻进该模块层。
//   番剧模块代码与注册保留（app_registry 仍注册），仅不再显示入口卡。
// ────────────────────────────────────────────────────────────────

/// 入口页展示的媒体类型——三入口（番剧代码保留但不进入口）。
const List<MediaType> entryTypes = <MediaType>[
  MediaType.comic,
  MediaType.novel,
  MediaType.music,
];

class _EntryPage extends StatelessWidget {
  const _EntryPage();

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
                builder: (context, constraints) => _StackOfCards(
                  compact: constraints.maxWidth < 720,
                  maxWidth: constraints.maxWidth,
                  maxHeight: constraints.maxHeight,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 叠牌入口：三张卡像一手扇开的扑克牌，各露一截标题。
//   点击"被压住"的卡 → 提到最上层；点击已在最上层的卡 → 钻进该模块。
//   这样既保留"另类错落"的基因，又让每张卡都能被点到（露出的边角可点）。
class _StackOfCards extends StatefulWidget {
  final bool compact;
  final double maxWidth;
  final double maxHeight;

  const _StackOfCards({
    required this.compact,
    required this.maxWidth,
    required this.maxHeight,
  });

  @override
  State<_StackOfCards> createState() => _StackOfCardsState();
}

class _StackOfCardsState extends State<_StackOfCards> {
  // 默认音乐置顶（视觉上它扇在最前）；stack 顺序 comic < novel < music。
  int _top = 2;

  // 从下往上排（z 序），每张卡相对容器中心做偏移与旋转。
  static const _layouts = [
    (-0.16, -0.10, -0.14), // 漫画：偏左上、逆时针
    (0.0, 0.0, 0.02), // 小说：居中、几乎正
    (0.16, 0.10, 0.14), // 音乐：偏右下、顺时针
  ];

  void _bringToFront(int index) {
    if (_top == index) {
      // 已在最上层 → 进入模块。
      shellStore.openModule(entryTypes[index]);
      return;
    }
    setState(() => _top = index);
  }

  @override
  Widget build(BuildContext context) {
    final usableW = widget.maxWidth.isFinite ? widget.maxWidth : 360.0;
    final usableH = widget.maxHeight.isFinite ? widget.maxHeight : 720.0;
    // 宽窗时卡片别拉得太宽，保持接近手机上的竖卡比例。
    final cardW = (widget.compact ? usableW : usableW * 0.42).clamp(
      200.0,
      360.0,
    );
    final cardH = (usableH * 0.82).clamp(300.0, cardW * 1.5);
    final baseLeft = (usableW - cardW) / 2;
    final baseTop = (usableH - cardH) / 2;

    // z 序：非置顶卡先画、置顶卡最后画（Flutter Stack 后画的在上层）。
    final order = <int>[
      for (var i = 0; i < entryTypes.length; i++)
        if (i != _top) i,
      _top,
    ];

    return Stack(
      children: <Widget>[
        for (final i in order)
          _StackCard(
            type: entryTypes[i],
            left: baseLeft + (i == _top ? 0 : _layouts[i].$1 * cardW),
            top: baseTop + (i == _top ? 0 : _layouts[i].$2 * cardH),
            angle: i == _top ? _layouts[i].$3 * 0.3 : _layouts[i].$3,
            width: cardW,
            height: cardH,
            onTap: () => _bringToFront(i),
            isTop: i == _top,
          ),
      ],
    );
  }
}

/// 叠牌中的一张卡：色调容器 + 图标 + 标题 + 一句话 + 箭头。
/// 整卡可点（露出的边角也响应），点击行为由父 [_StackOfCards] 决定。
class _StackCard extends StatelessWidget {
  final MediaType type;
  final double left;
  final double top;
  final double angle;
  final double width;
  final double height;
  final bool isTop;
  final VoidCallback onTap;

  const _StackCard({
    required this.type,
    required this.left,
    required this.top,
    required this.angle,
    required this.width,
    required this.height,
    required this.isTop,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (container, onContainer) = switch (type) {
      MediaType.anime => (cs.primaryContainer, cs.onPrimaryContainer),
      MediaType.comic => (cs.secondaryContainer, cs.onSecondaryContainer),
      MediaType.novel => (cs.tertiaryContainer, cs.onTertiaryContainer),
      MediaType.music => (cs.surfaceContainerHighest, cs.onSurface),
    };
    return AnimatedPositioned(
      left: left,
      top: top,
      width: width,
      height: height,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: AnimatedRotation(
        // 置顶卡略回正，强化"被抽到最前"的感觉。
        turns: angle / (2 * 3.141592653589793),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        child: Material(
          color: container,
          borderRadius: MimaoShapes.xl,
          clipBehavior: Clip.antiAlias,
          elevation: isTop ? 10 : 4,
          shadowColor: cs.shadow.withValues(alpha: .3),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(type.icon, color: onContainer, size: 28),
                      const SizedBox(width: 10),
                      Text(
                        type.label,
                        style: Theme.of(
                          context,
                        ).textTheme.headlineSmall?.apply(color: onContainer),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    type.tagline,
                    style: Theme.of(context).textTheme.bodyMedium?.apply(
                      color: onContainer.withValues(alpha: .8),
                    ),
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 22,
                      color: onContainer,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
// 模块层：进入后另外三个入口消失。顶部只有"返回"和标题。
// 内容来自 app_registry 查表；未接入的模块显示占位页（M1 四个都未接入）。
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

/// M1 占位页：模块尚未接入（docs/directory-layout.md §2 的开工当天状态）。
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
