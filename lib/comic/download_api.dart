/// 漫画下载能力：详情页按钮与状态展示只认这里的模型/接口。
///
/// 页面不 import 下载实现或 drift：状态由 [ComicDownloadApi.changes] 通知，
/// 任务快照经 [tasksFor] 读取。实现见 `local_download_service.dart`。
library;

import 'package:flutter/foundation.dart';

import 'data/comic_models.dart';
import 'download.dart';

/// 一章的下载状态快照（页面按 [chapterUrl] 与章节行匹配）。
class ComicChapterDownload {
  final String taskId;
  final String chapterUrl;
  final ComicDownloadStatus status;

  /// 已下载页数 / 总页数（漫画以页计数，不逐字节探测 Content-Length）。
  final int received;
  final int total;

  final String? error;

  const ComicChapterDownload({
    required this.taskId,
    required this.chapterUrl,
    required this.status,
    this.received = 0,
    this.total = 0,
    this.error,
  });

  double get progress {
    if (total <= 0) return 0;
    return (received / total).clamp(0, 1).toDouble();
  }

  bool get isDone => status == ComicDownloadStatus.done;
  bool get isFailed => status == ComicDownloadStatus.failed;
  bool get isActive =>
      status == ComicDownloadStatus.pending ||
      status == ComicDownloadStatus.running;

  String get message {
    if (isFailed) return error ?? '下载失败';
    if (status == ComicDownloadStatus.pending) return '等待下载';
    if (status == ComicDownloadStatus.running) {
      return total > 0 ? '$received/$total 页' : '下载中…';
    }
    return '已下载';
  }
}

/// 漫画下载入口（详情页调用）。
abstract interface class ComicDownloadApi {
  /// 任务状态变化通知（进度、完成、失败）。页面应监听并重读 [tasksFor]。
  Listenable get changes;

  /// 某部漫画的全部章节下载任务快照（按 chapterUrl 索引）。
  Future<List<ComicChapterDownload>> tasksFor(ComicSummary item);

  /// 下载单章；已下载直接返回，失败任务会重置为重新下载。
  Future<void> downloadChapter(
    ComicSummary item,
    ComicDetail detail,
    ComicChapter chapter,
  );

  /// 加入整本下载（逐章排队）；已下载章节跳过。
  Future<void> downloadAll(ComicSummary item, ComicDetail detail);

  /// 取消/删除一个任务（含未完成的章节文件）。
  Future<void> cancel(String taskId);
}

/// 任务与 UI 章节行匹配用的稳定键（章节 URL 在详情内唯一）。
String comicChapterDownloadKey(ComicChapter chapter) => chapter.url;
