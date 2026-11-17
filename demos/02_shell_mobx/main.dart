// ═══════════════════════════════════════════════════════════════
// Demo 02 — 同一个壳的 MobX 写法（Kazumi 的状态管理方式）
//
// 与 Demo 01 只有一处本质区别：状态住在哪里、UI 怎么知道要刷新。
//
//   Demo 01: 状态是 StatefulWidget 的字段，手动 setState 通知
//   Demo 02: 状态搬进 Store 类（@observable），UI 用 Observer 包住自动响应
//
// 多写一个 Store 类 + 需要代码生成，换来两样东西：
//   1. 状态可以离开 Widget 树被任何页面共享（"正在播放"要跨页访问时必需）
//   2. 修改状态的代码永远走 @action，出了 bug 好定位
//
// 跑起来需要（阅读为主，不必现在跑）：
//   dependencies: mobx ^2.6.0  flutter_mobx ^2.3.0
//   dev_dependencies: build_runner  mobx_codegen
//   然后 `dart run build_runner build` 生成 main.g.dart
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:mobx/mobx.dart';

part 'main.g.dart'; // build_runner 生成的桥接代码，不用手写

// ── 数据模型与 Demo 01 完全相同 ──────────────────────────────
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
}

class MediaEntry {
  final MediaType type;
  final String title;
  final String subtitle;
  final String source;
  const MediaEntry(this.type, this.title, this.subtitle, this.source);
}

const demoEntries = <MediaEntry>[
  MediaEntry(MediaType.anime, '葬送的芙莉莲', '28话 · 看到第12话', 'Demo番剧源'),
  MediaEntry(MediaType.anime, '败犬女主太多了！', '12话 · 未开始', 'Demo番剧源'),
  MediaEntry(MediaType.comic, '尖帽子的魔法工坊', '58话 · 已收藏', 'Demo漫画源'),
  MediaEntry(MediaType.comic, '小蜘蛛洛卡', '183话 · 看到第45话', 'Demo漫画源'),
  MediaEntry(MediaType.novel, '诡秘之主', '第1432章 · 32%', 'Demo书源'),
  MediaEntry(MediaType.music, '深夜驾驶歌单', '24首 · 播放到第7首', '酷狗概念版'),
];

// ─────────────────────────────────────────────────────────────
// Store：状态和"改状态的方法"住在这里。
// 这是 MobX 的样板写法：抽象 Store + part 桥接，Kazumi 里到处是这个形状。
// ─────────────────────────────────────────────────────────────
class ShellStore = _ShellStore with _$ShellStore;

abstract class _ShellStore with Store {
  @observable
  int sectionIndex = 0;

  @observable
  String searchQuery = '';

  @observable
  ObservableList<MediaEntry> favorites = ObservableList.of(demoEntries);

  @computed
  bool get onLibraryPage => sectionIndex == 4;

  @action
  void switchTo(int index) => sectionIndex = index;

  @action
  void search(String query) => searchQuery = query;

  @action
  void toggleFavorite(MediaEntry entry) {
    if (favorites.contains(entry)) {
      favorites.remove(entry);
    } else {
      favorites.add(entry);
    }
  }
}

// 最简做法：全局单例。Kazumi 用 flutter_modular 做依赖注入，
// 原理相同、更规范——等壳变大后再换，不影响 Store 本身的写法。
final shellStore = ShellStore();

class AggregatorApp extends StatelessWidget {
  const AggregatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '聚合壳 Demo 02 (MobX)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF7C6BFF)),
      home: const HomeShell(),
    );
  }
}

// 注意：HomeShell 变成了 StatelessWidget —— 它自己没有状态了！
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // MobX 的关键手感：Observer 只包住"依赖状态的那一小块"，
          // 范围越小，重建越少。（这里为了示例简单包了整个 Rail；
          // 真实项目里可以把 Observer 收缩到只包 selectedIndex 相关部分。）
          Observer(builder: (_) {
            return NavigationRail(
              selectedIndex: shellStore.sectionIndex,
              onDestinationSelected: shellStore.switchTo,
              extended: true,
              labelType: NavigationRailLabelType.none,
              destinations: const [
                NavigationRailDestination(
                    icon: Icon(Icons.smart_display_outlined),
                    selectedIcon: Icon(Icons.smart_display),
                    label: Text('番剧')),
                NavigationRailDestination(
                    icon: Icon(Icons.image_outlined),
                    selectedIcon: Icon(Icons.image),
                    label: Text('漫画')),
                NavigationRailDestination(
                    icon: Icon(Icons.menu_book_outlined),
                    selectedIcon: Icon(Icons.menu_book),
                    label: Text('小说')),
                NavigationRailDestination(
                    icon: Icon(Icons.music_note_outlined),
                    selectedIcon: Icon(Icons.music_note),
                    label: Text('音乐')),
                NavigationRailDestination(
                    icon: Icon(Icons.collections_bookmark_outlined),
                    selectedIcon: Icon(Icons.collections_bookmark),
                    label: Text('我的')),
              ],
            );
          }),
          const VerticalDivider(width: 1),
          const Expanded(child: SectionBody()),
        ],
      ),
    );
  }
}

class SectionBody extends StatelessWidget {
  const SectionBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) {
      return switch (shellStore.sectionIndex) {
        // 0~3 的界面与 Demo 01 相同，此处省略——demo 只聚焦状态差异
        0 => const _Placeholder(label: '番剧（界面与 Demo 01 相同）'),
        1 => const _Placeholder(label: '漫画（界面与 Demo 01 相同）'),
        2 => const _Placeholder(label: '小说（界面与 Demo 01 相同）'),
        3 => const _Placeholder(label: '音乐（界面与 Demo 01 相同）'),
        _ => const LibraryPage(),
      };
    });
  }
}

class _Placeholder extends StatelessWidget {
  final String label;
  const _Placeholder({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(shellStore.searchQuery,
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// "我的"页：观察 Observer 的数据流。
// 心形按钮只调用 store 的 @action，列表自己刷新——
// 不需要 setState，也不需要父组件传回调。这就是"状态共享"的代价与收益。
// ─────────────────────────────────────────────────────────────
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('统一时间线（${shellStore.favorites.length} 条）',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final e in shellStore.favorites)
            ListTile(
              leading: Icon(e.type.icon),
              title: Text(e.title),
              subtitle: Text('${e.type.label} · ${e.subtitle}'),
              trailing: IconButton(
                icon: const Icon(Icons.favorite),
                color: Theme.of(context).colorScheme.primary,
                onPressed: () => shellStore.toggleFavorite(e),
              ),
            ),
        ],
      );
    });
  }
}
