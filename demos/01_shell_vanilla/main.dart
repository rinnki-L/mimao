// ═══════════════════════════════════════════════════════════════
// Demo 01 — 极简 MD3 壳：vanilla 写法（零第三方依赖）
//
// 回答一个问题：我们的壳长什么样、四个模块从哪里长出来。
//
//   ┌ NavigationRail ── 桌面端第一公民（底部栏才是移动端形态）
//   │    番剧 / 漫画 / 小说 / 音乐 / 我的
//   └ 内容区 ── 按选中项切换。以后 Kazumi 的番剧模块搬进
//      PosterSection(anime) 的位置，Venera 的搬进 comic 的位置……
//
// 状态管理用最朴素的 setState —— 和 Demo 02 的 MobX 写法对照着看。
// 全部组件都是 Flutter 原生 Material 3，不依赖任何第三方包。
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

void main() => runApp(const AggregatorApp());

class AggregatorApp extends StatelessWidget {
  const AggregatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '聚合壳 Demo 01',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true, // Flutter 3.16+ 默认已是 M3，写出来仅为说明
        colorSchemeSeed: const Color(0xFF7C6BFF), // MD3 动态取色的种子色
      ),
      home: const HomeShell(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 壳：只负责「导航 + 承载」，不含任何业务逻辑。
// 模块各自拥有自己的页面/引擎/存储，壳只认识这张"目录表"。
// ─────────────────────────────────────────────────────────────
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _section = 0;

  static const _sections = [
    (icon: Icons.smart_display_outlined, selected: Icons.smart_display, label: '番剧'),
    (icon: Icons.image_outlined, selected: Icons.image, label: '漫画'),
    (icon: Icons.menu_book_outlined, selected: Icons.menu_book, label: '小说'),
    (icon: Icons.music_note_outlined, selected: Icons.music_note, label: '音乐'),
    (icon: Icons.collections_bookmark_outlined, selected: Icons.collections_bookmark, label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _section,
            onDestinationSelected: (i) => setState(() => _section = i),
            extended: true, // 展开文字。TODO：跟窗口宽度联动（窄窗收起）——Kazumi 桌面端有现成实现
            labelType: NavigationRailLabelType.none,
            destinations: [
              for (final s in _sections)
                NavigationRailDestination(
                  icon: Icon(s.icon),
                  selectedIcon: Icon(s.selected),
                  label: Text(s.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  // Dart 3 的 switch 表达式：选中项 → 模块页面
  Widget _body() => switch (_section) {
        0 => const PosterSection(MediaType.anime),
        1 => const PosterSection(MediaType.comic),
        2 => const NovelSection(),
        3 => const MusicSection(),
        _ => const LibrarySection(),
      };
}

// ─────────────────────────────────────────────────────────────
// 最小公共数据面（演示用）。真正的统一模型等模块都搬进来再收敛——
// 我们的原则是「先能跑，后抽象」。
// ─────────────────────────────────────────────────────────────
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
  final String subtitle; // 话数/章节/曲目……由各模块自己解释
  final String source; // 来自哪个源
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
// 海报区：番剧/漫画共用同一个组件，只是数据不同。
// 这就是"壳容纳不同媒体"的直觉：模块提供的只是数据 + 详情页。
// ─────────────────────────────────────────────────────────────
class PosterSection extends StatelessWidget {
  final MediaType type;
  const PosterSection(this.type, {super.key});

  @override
  Widget build(BuildContext context) {
    final entries = demoEntries.where((e) => e.type == type).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: SearchBar(
            hintText: '搜索（demo 占位）',
            leading: const Icon(Icons.search),
            onChanged: (_) {}, // 以后接各模块的规则引擎搜索
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180, // 宽窗口自动多列，桌面友好
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.62,
            ),
            itemCount: entries.length,
            itemBuilder: (context, i) => PosterCard(entry: entries[i]),
          ),
        ),
      ],
    );
  }
}

class PosterCard extends StatelessWidget {
  final MediaEntry entry;
  const PosterCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card.filled(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {}, // 之后接各模块的详情页
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              // 占位海报；真实实现里换成 cached_network_image
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [cs.primaryContainer, cs.tertiaryContainer],
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(entry.icon, size: 44, color: cs.onPrimaryContainer),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.apply(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 小说区：列表 + 阅读进度。大屏阅读是桌面端的加分项
// （legado 没有桌面版，这里等于填补空白）。
// ─────────────────────────────────────────────────────────────
class NovelSection extends StatelessWidget {
  const NovelSection({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = demoEntries.where((e) => e.type == MediaType.novel).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final e in entries)
          Card.filled(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.menu_book),
              title: Text(e.title),
              subtitle: Text('${e.subtitle} · ${e.source}'),
              trailing: const SizedBox(
                width: 96,
                child: LinearProgressIndicator(value: 0.32),
              ),
              onTap: () {}, // 接书源引擎（Demo 03/04 的方向）
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 音乐区：播放列表示意。以后 EchoMusic 的酷狗 API 层接这里，
// 播放走 media_kit（与番剧模块共用同一个播放内核）。
// ─────────────────────────────────────────────────────────────
class MusicSection extends StatelessWidget {
  const MusicSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final e in demoEntries.where((e) => e.type == MediaType.music))
          Card.filled(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.music_note),
              title: Text(e.title),
              subtitle: Text('${e.subtitle} · ${e.source}'),
              trailing: IconButton(
                icon: const Icon(Icons.play_circle_fill, size: 32),
                onPressed: () {}, // 接 media_kit 音频播放
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 我的：统一时间线 —— 四种媒体的收藏/进度混排。
// 数据怎么存见 Demo 04。这一页是"聚合"区别于"四个 app"的核心。
// ─────────────────────────────────────────────────────────────
class LibrarySection extends StatelessWidget {
  const LibrarySection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('统一时间线', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final e in demoEntries)
          ListTile(
            leading: Icon(e.icon),
            title: Text(e.title),
            subtitle: Text('${e.type.label} · ${e.subtitle}'),
            trailing: Chip(label: Text(e.source)),
            onTap: () {},
          ),
      ],
    );
  }
}
