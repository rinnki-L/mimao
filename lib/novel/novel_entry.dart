// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart，与 music_entry.dart 同款说明。
/// 小说模块对壳的唯一出口——实现 [AppModule]，由 app_registry 注入全部依赖
/// （docs/architecture.md §4.3）。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/novel/engine/engine.dart';
import 'package:mimao/novel/library_api.dart';

class NovelModule implements AppModule {
  NovelModule({
    this.engine,
    this.dataSource,
    this.collect,
    this.history,
    this.searchHistory,
    this.sourceStore,
  });

  final NovelEngine? engine;
  final NovelDataSource? dataSource;
  final NovelCollectApi? collect;
  final NovelHistoryApi? history;
  final NovelSearchHistoryApi? searchHistory;
  final Object? sourceStore; // 书源仓库缝，后续切片替换为具体类型

  @override
  MediaType get type => MediaType.novel;
  @override
  String get label => '小说';
  @override
  IconData get icon => MediaType.novel.icon;

  @override
  Widget buildHome(BuildContext context) {
    // 本阶段占位页：解析后续接入。不依赖任何注入字段、不崩。
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(MediaType.novel.icon, size: 64),
            const SizedBox(height: 16),
            const Text('小说模块契约骨架已就绪，书源解析后续接入'),
          ],
        ),
      ),
    );
  }

  @override
  Widget buildSettings(BuildContext context) => const SizedBox.shrink();
}
