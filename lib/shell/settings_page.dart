// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mimao/shell/app.dart';
import 'package:mimao/shell/shell_store.dart';

/// 全局设置抽屉——只放**通用**设置（外观 / 存储）。
///
/// 用户拍板：总设置与各入口设置分开——各入口的设置放进各模块主页，
/// 作为底部导航最右侧「设置」tab（见各 AppModule.buildSettings）；
/// 本抽屉不再出现四个模块的分组，只有入口页顶栏一枚齿轮打开它。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => Drawer(
    child: SafeArea(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Text('设置', style: Theme.of(context).textTheme.headlineSmall),
          ),
          const _AppearanceGroup(),
          const Divider(),
          const _StorageGroup(),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
}

class _AppearanceGroup extends StatelessWidget {
  const _AppearanceGroup();

  @override
  Widget build(BuildContext context) => ExpansionTile(
    leading: const Icon(Icons.palette_outlined),
    title: const Text('外观'),
    initiallyExpanded: true,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Text('主题模式', style: Theme.of(context).textTheme.labelLarge),
      ),
      // MD3 SegmentedButton：跟随系统 / 浅色 / 深色，一段即一个选项。
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: _ThemeModeSegmented(),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
        child: Text('主题种子色', style: Theme.of(context).textTheme.labelLarge),
      ),
      // 紧凑色块（而非纵向 ListTile + RadioGroup）：8 色两行排完，
      // 抽屉不至于过长。每个 chip 自己 Observer 选中态。
      // （childrenPadding 由 expansionTileTheme 统一给 16，这里再补 8 = 原 24。）
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in MimaoApp.seedColors.entries)
              _SeedChip(
                keyName: entry.key,
                label: entry.value.$1,
                color: entry.value.$2,
              ),
            const _SystemSeedChip(),
          ],
        ),
      ),
      const SizedBox(height: 8),
    ],
  );
}

/// 主题模式三段选择：读 shellStore.themeMode 渲染选中态，
/// 点按 setThemeMode —— app.dart 的 Observer 消费 themeMode 即时换肤。
class _ThemeModeSegmented extends StatelessWidget {
  const _ThemeModeSegmented();

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (context) {
        final mode = shellStore.themeMode;
        return SegmentedButton<ThemeMode>(
          key: const Key('theme-mode-segmented'),
          segments: const <ButtonSegment<ThemeMode>>[
            ButtonSegment<ThemeMode>(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto_outlined),
              label: Text('系统'),
            ),
            ButtonSegment<ThemeMode>(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode_outlined),
              label: Text('浅色'),
            ),
            ButtonSegment<ThemeMode>(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode_outlined),
              label: Text('深色'),
            ),
          ],
          selected: <ThemeMode>{mode},
          onSelectionChanged: (selection) =>
              shellStore.setThemeMode(selection.first),
        );
      },
    );
  }
}

/// 单个种子色选项：色点 + 名称，选中态用色块描边 + 对勾。
class _SeedChip extends StatelessWidget {
  final String keyName;
  final String label;
  final Color color;

  const _SeedChip({
    required this.keyName,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Observer(
      builder: (_) {
        final selected = shellStore.themeSeed == keyName;
        return ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 7, backgroundColor: color),
              const SizedBox(width: 6),
              Text(label),
            ],
          ),
          selected: selected,
          onSelected: (_) => shellStore.setThemeSeed(keyName),
          showCheckmark: false,
          selectedColor: color.withValues(alpha: 0.22),
          side: selected
              ? BorderSide(color: color, width: 2)
              : BorderSide(color: cs.outlineVariant),
        );
      },
    );
  }
}

/// “跟随系统强调色”chip——第 9 枚，不在 seedColors 色板里，用系统图标标识。
/// 选中态同样用 Observer 读 themeSeed == 'system'，点击直接切到该系统模式。
class _SystemSeedChip extends StatelessWidget {
  const _SystemSeedChip();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Observer(
      builder: (_) {
        final selected = shellStore.themeSeed == 'system';
        return ChoiceChip(
          key: const Key('theme-seed-system'),
          avatar: const Icon(Icons.auto_mode, size: 18),
          label: const Text('跟随系统'),
          selected: selected,
          onSelected: (_) => shellStore.setThemeSeed('system'),
          showCheckmark: false,
          side: selected
              ? BorderSide(color: cs.primary, width: 2)
              : BorderSide(color: cs.outlineVariant),
        );
      },
    );
  }
}

/// 存储分组：展示统一库/壳数据实际落盘目录（docs/architecture.md §3.3：
/// %APPDATA% 应用支持目录，path_provider 定根），以及当前库文件名。
class _StorageGroup extends StatelessWidget {
  const _StorageGroup();

  @override
  Widget build(BuildContext context) => ExpansionTile(
    leading: const Icon(Icons.folder_outlined),
    title: const Text('存储'),
    children: [
      FutureBuilder<String>(
        future: _supportDir(),
        builder: (context, snapshot) => ListTile(
          title: const Text('数据目录'),
          subtitle: Text(
            snapshot.data ?? '读取中…',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ),
      const ListTile(
        title: Text('统一书架'),
        subtitle: Text('mimao.db（与模块内部存储分离，模块存储为权威）'),
      ),
    ],
  );

  Future<String> _supportDir() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return dir.path;
    } catch (e) {
      return '不可用：$e';
    }
  }
}
