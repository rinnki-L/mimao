// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/shell/app_registry.dart';
import 'package:mimao/shell/shell_store.dart';

/// 全局设置抽屉——选择 C 拼贴 + **全局一个设置**（用户拍板）。
///
/// 一个总入口（仅入口页顶栏一枚齿轮，模块页不再放）；抽屉按
/// 「外观 / 存储 / 番剧 / 漫画 / 小说 / 音乐」分组，四个模块头首屏可见、
/// 可折叠。模块自己的设置内容等 M2 起由 app_registry 注册的 AppModule 提供。
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
          const Divider(),
          _ModuleGroup(type: MediaType.anime),
          _ModuleGroup(type: MediaType.comic),
          _ModuleGroup(type: MediaType.novel),
          _ModuleGroup(type: MediaType.music),
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Text('主题种子色', style: Theme.of(context).textTheme.labelLarge),
      ),
      Observer(
        builder: (_) => RadioGroup<String>(
          groupValue: shellStore.themeSeed,
          onChanged: (v) {
            if (v != null) shellStore.setThemeSeed(v);
          },
          child: Column(
            children: [
              for (final seed in <String, String>{
                'violet': '紫罗兰',
                'green': '青绿',
                'ochre': '赭黄',
              }.entries)
                ListTile(
                  title: Text(seed.value),
                  leading: Radio<String>(value: seed.key),
                ),
            ],
          ),
        ),
      ),
    ],
  );
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

class _ModuleGroup extends StatelessWidget {
  final MediaType type;

  const _ModuleGroup({required this.type});

  @override
  Widget build(BuildContext context) {
    final module = moduleFor(type);
    return ExpansionTile(
      leading: Icon(type.outlinedIcon),
      title: Text(type.label),
      children: <Widget>[
        if (module != null)
          module.buildSettings(context)
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Text(
              '${type.tagline} · 该模块设置将在接入后开放',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}
