// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'package:flutter/material.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/core/library.dart';

/// 「我的」统一时间线——只读 core 投影表，永不 import 任何模块。
/// 数据来自 demo 01 main.dart:293 LibrarySection 的真身化。
class LibraryPage extends StatelessWidget {
  final LibraryRepository repository;

  const LibraryPage({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MediaEntryView>>(
      future: repository.timeline(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('读取时间线失败：${snapshot.error}'));
        }
        final entries = snapshot.data ?? const <MediaEntryView>[];
        if (entries.isEmpty) {
          return _emptyState(context);
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          itemBuilder: (context, i) => _timelineTile(context, entries[i]),
        );
      },
    );
  }

  Widget _emptyState(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.collections_bookmark_outlined,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text('统一时间线', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          '还没有观看记录\n追番或播放后会出现在这里',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );

  Widget _timelineTile(BuildContext context, MediaEntryView entry) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.secondaryContainer,
        child: Icon(entry.type.icon, color: cs.onSecondaryContainer),
      ),
      title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${entry.type.label} · ${entry.progressText}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: entry.starred
          ? Icon(Icons.star, color: cs.primary)
          : Text(
              entry.sourceName,
              style: Theme.of(context).textTheme.labelSmall,
            ),
    );
  }
}
