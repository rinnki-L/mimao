/// 正文缓存/离线下载仓储窄接口（M5 骨架）：路径由实现方注入，本阶段只有接口缝，
/// 不落盘、不实现。语义见 docs/architecture.md §4.4。
library;

import 'package:mimao/novel/models/novel_models.dart';

abstract class NovelCache {
  Future<NovelContent?> read(NovelRef ref, NovelChapter chapter);
  Future<void> write(NovelRef ref, NovelChapter chapter, NovelContent content);
  Future<void> clear(NovelRef ref);
}
