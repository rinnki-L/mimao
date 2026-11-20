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
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Image.asset('assets/mimao.png', width: 44, height: 44),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'mimao',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      '漫画 · 小说 · 音乐，一站聚合',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.apply(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
                const Spacer(),
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
            const SizedBox(height: 18),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    constraints.maxWidth < 720 ? _bentoNarrow() : _bentoWide(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 宽窗：上行漫画(占 2 列) + 小说(1 列)，下行音乐全宽。
  Widget _bentoWide() => Column(
    children: [
      Expanded(
        child: Row(
          children: <Widget>[
            const Expanded(flex: 2, child: _BentoCard(MediaType.comic)),
            const SizedBox(width: 16),
            const Expanded(flex: 1, child: _BentoCard(MediaType.novel)),
          ],
        ),
      ),
      const SizedBox(height: 16),
      const Expanded(child: _BentoCard(MediaType.music)),
    ],
  );

  /// 窄窗：漫画全宽 → 小说/音乐并排，三个入口仍在屏内。
  Widget _bentoNarrow() => Column(
    children: <Widget>[
      const Expanded(child: _BentoCard(MediaType.comic)),
      const SizedBox(height: 12),
      const Expanded(
        child: Row(
          children: <Widget>[
            Expanded(child: _BentoCard(MediaType.novel)),
            SizedBox(width: 12),
            Expanded(child: _BentoCard(MediaType.music)),
          ],
        ),
      ),
    ],
  );
}

/// 一张拼贴入口卡：色调容器 + 图标 + 标题 + 一句话。
class _BentoCard extends StatelessWidget {
  final MediaType type;

  const _BentoCard(this.type);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (container, onContainer) = switch (type) {
      MediaType.anime => (cs.primaryContainer, cs.onPrimaryContainer),
      MediaType.comic => (cs.secondaryContainer, cs.onSecondaryContainer),
      MediaType.novel => (cs.tertiaryContainer, cs.onTertiaryContainer),
      MediaType.music => (cs.surfaceContainerHighest, cs.onSurface),
    };
    return Material(
      color: container,
      borderRadius: MimaoShapes.xl,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => shellStore.openModule(type),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(type.icon, color: onContainer, size: 26),
                  const SizedBox(width: 10),
                  Text(
                    type.label,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.apply(color: onContainer),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                type.tagline,
                style: Theme.of(context).textTheme.bodySmall?.apply(
                  color: onContainer.withValues(alpha: .78),
                ),
              ),
              const Spacer(),
              Align(
                alignment: Alignment.centerRight,
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: onContainer,
                ),
              ),
            ],
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
