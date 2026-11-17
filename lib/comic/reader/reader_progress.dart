// 阅读进度的**持久化点**：调 core 的 LibraryRepository.upsert 写统一书架投影。
//
// 与番剧线的对应：番剧经 AnimeHistoryService.saveProgress → syncAnimeProjection；
// 阅读器内核（B′）走的是"阅读器自己的持久化点"：recorder 直接调本文件的
// syncComicProgress 写 core 投影，payload 固定为 {chapter, page}（模块私有 JSON，
// core/壳都不解释），progressText 也由本模块写好。
//
// 与 A′/存储线的 ComicHistoryService.saveProgress（payload 为 {chapterId,page,pageCount}）
// 并存：两者都是合法投影写入口，写入同一 {id, type=comic, sourceName} 复合主键，
// InsertMode.insertOrReplace 保证同一作品只有最新一笔投影。联调时集成方择一驱动。

import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/core/library.dart';

import 'reader_models.dart';

/// 一次进度持久化事件的运行时值（controller → recorder）。
class ReadingProgress {
  final int chapter;
  final String chapterTitle;
  final int page;
  final int pageCount;

  const ReadingProgress({
    required this.chapter,
    required this.chapterTitle,
    required this.page,
    required this.pageCount,
  });
}

/// controller 与持久化层之间的窄接口：单测注入假实现即可，不碰数据库。
abstract interface class ProgressRecorder {
  Future<void> persist(ReadingProgress progress);
}

/// 把一次阅读进度写进 core 统一书架投影（persist 的唯一落点）。
///
/// 元数据由调用方提供；`ref.id`/`ref.sourceName` + `MediaType.comic` 组成复合主键，
/// 因此同一作品重复 upsert 是幂等的（InsertMode.insertOrReplace）。
Future<void> syncComicProgress({
  required LibraryRepository library,
  required ComicRef ref,
  required String title,
  String? coverUrl,
  required int chapter,
  required int page,
  required int pageCount,
  bool starred = false,
  DateTime? openedAt,
}) async {
  if (chapter < 0 || page < 0) {
    throw ArgumentError('章节与页码不能为负数');
  }
  await library.upsert(
    id: ref.id,
    type: MediaType.comic,
    sourceName: ref.sourceName,
    title: title,
    coverUrl: coverUrl,
    payload: readerProgressPayload(chapter: chapter, page: page),
    progressText: readerProgressText(
      chapter: chapter,
      page: page,
      pageCount: pageCount,
    ),
    starred: starred,
    lastOpenedAt: openedAt ?? DateTime.now(),
  );
}

/// [ProgressRecorder] 的唯一写入实现：把 [ReadingProgress] 适配到
/// [syncComicProgress]。自身不持有存储，也不解释 payload。
class ComicLibraryProgressRecorder implements ProgressRecorder {
  ComicLibraryProgressRecorder({
    required this.library,
    required this.ref,
    required this.title,
    this.coverUrl,
    this.starred = false,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final LibraryRepository library;
  final ComicRef ref;
  final String title;
  final String? coverUrl;
  final bool starred;
  final DateTime Function() now;

  @override
  Future<void> persist(ReadingProgress progress) => syncComicProgress(
    library: library,
    ref: ref,
    title: title,
    coverUrl: coverUrl,
    chapter: progress.chapter,
    page: progress.page,
    pageCount: progress.pageCount,
    starred: starred,
    openedAt: now(),
  );
}
