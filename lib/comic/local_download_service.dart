import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/download.dart';
import 'package:mimao/comic/download_api.dart';
import 'package:mimao/comic/download_store.dart';
import 'package:mimao/comic/local_comic_manifest.dart';
import 'package:mimao/comic/local_comic_service.dart';
import 'package:mimao/comic/reader/reader_cache.dart' show cacheKey;
import 'package:path/path.dart' as p;

/// 真实漫画下载器（对齐 Venera Next 的「按章目录 + 页文件名排序」落盘）。
///
/// 落盘结构：
/// ```
/// <root>/<本地id>/cover.jpg
/// <root>/<本地id>/001-第1话/0001.jpg
/// <root>/<本地id>/002-第2话/0001.jpg
/// ```
/// 本地 id 由 `{sourceName,id}` 稳定哈希得到，重复下载同一部漫画不会产生
/// 第二个目录。元数据写 `comic_local`（payload = [LocalComicManifest]）。
///
/// 状态机沿用 `download.dart`：每章一个任务；`receivedBytes/totalBytes` 在
/// 漫画下载里**按页计数**（避免为每张图额外探测 Content-Length，进度同样
/// 可展示）。下载串行执行，防止多任务争抢同一目录/文件句柄。
class ComicLocalDownloadService implements ComicDownloadApi {
  ComicLocalDownloadService({
    required this.local,
    required this.store,
    required this.rootDirectory,
    required this.loadBytes,
    required this.loadChapterImages,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ComicLocalService local;
  final ComicDownloadStore store;

  /// 下载根目录（生产为应用支持目录下 `comic_downloads/`）。
  final Future<Directory> Function() rootDirectory;

  /// 取一张图的原始字节（生产走 ComicHttpClient，共享 UA/Cookie）。
  final Future<Uint8List> Function(String url) loadBytes;

  /// 取一章的图片地址（由源适配层注入）。
  final Future<List<String>> Function(ComicSummary item, ComicChapter chapter)
  loadChapterImages;

  final DateTime Function() _now;
  final _DownloadChanges _changes = _DownloadChanges();

  final Set<String> _scheduled = <String>{};
  final Set<String> _cancelled = <String>{};
  Future<void> _chain = Future<void>.value();

  @override
  Listenable get changes => _changes;

  @override
  Future<List<ComicChapterDownload>> tasksFor(ComicSummary item) async {
    final ref = _refOf(item);
    final tasks = await store.all();
    return [
      for (final task in tasks)
        if (task.ref == ref && task.chapterId.isNotEmpty)
          ComicChapterDownload(
            taskId: task.taskId,
            chapterUrl: task.chapterId,
            status: task.status,
            received: task.receivedBytes,
            total: task.totalBytes,
            error: task.error,
          ),
    ];
  }

  @override
  Future<void> downloadChapter(
    ComicSummary item,
    ComicDetail detail,
    ComicChapter chapter,
  ) async {
    final ref = _refOf(item);
    if (ref.sourceName == ComicRef.localSource) return;
    final taskId = downloadTaskId(ref, chapter);
    if (_scheduled.contains(taskId)) return;

    final existing = await store.find(taskId);
    if (existing != null && existing.status == ComicDownloadStatus.done) return;
    if (existing == null) {
      await store.enqueue(
        ComicDownloadTask(
          taskId: taskId,
          ref: ref,
          chapterId: chapter.url,
          status: ComicDownloadStatus.pending,
          updatedAt: _now(),
        ),
        now: _now(),
      );
    } else if (existing.status == ComicDownloadStatus.failed) {
      await store.transition(taskId, ComicDownloadStatus.pending, now: _now());
    } else if (existing.status == ComicDownloadStatus.running) {
      // 上次进程被杀留下的 running：没有内存任务在跑，重置后重新开始。
      await store.transition(taskId, ComicDownloadStatus.failed, now: _now());
      await store.transition(taskId, ComicDownloadStatus.pending, now: _now());
    }

    _scheduled.add(taskId);
    _cancelled.remove(taskId);
    _notify();
    _enqueue(() => _run(item, detail, chapter, ref, taskId));
  }

  @override
  Future<void> downloadAll(ComicSummary item, ComicDetail detail) async {
    for (final chapter in detail.chapters) {
      await downloadChapter(item, detail, chapter);
    }
  }

  @override
  Future<void> cancel(String taskId) async {
    _cancelled.add(taskId);
    final task = await store.find(taskId);
    if (task == null) return;
    if (_scheduled.contains(taskId)) {
      // 正在跑的任务由 _run 收尾时删除；这里只打取消标记。
      _notify();
      return;
    }
    await store.remove(taskId);
    _notify();
  }

  /// 等待当前排队的下载全部结束（测试与「退出前收尾」用）。
  Future<void> whenIdle() async {
    while (true) {
      final pending = _chain;
      await pending;
      if (identical(pending, _chain)) return;
    }
  }

  void dispose() => _changes.dispose();

  void _enqueue(Future<void> Function() job) {
    _chain = _chain.then((_) => job()).catchError((Object _) {
      // _run 内部已把失败写进任务表；这里吞掉链上的异常，避免后续任务
      // 因为前一个任务的错误被跳过。
    });
  }

  Future<void> _run(
    ComicSummary item,
    ComicDetail detail,
    ComicChapter chapter,
    ComicRef ref,
    String taskId,
  ) async {
    var comicDir = Directory('');
    var chapterDir = Directory('');
    try {
      await store.transition(taskId, ComicDownloadStatus.running, now: _now());
      _notify();
      if (_cancelled.contains(taskId)) return;

      final urls = await loadChapterImages(item, chapter);
      if (urls.isEmpty) {
        throw StateError('本章暂无图片');
      }

      final root = await rootDirectory();
      final folderId = localComicFolderId(ref);
      comicDir = Directory(p.join(root.path, folderId));
      await comicDir.create(recursive: true);

      final localRef = ComicRef.local(folderId);
      final existingEntry = await local.find(localRef);
      var manifest =
          LocalComicManifest.tryParse(existingEntry?.payload ?? '') ??
          const LocalComicManifest();
      final previous = _chapterByUrl(manifest, chapter.url);
      final chapterIndex = detail.chapters.indexWhere(
        (candidate) => candidate.url == chapter.url,
      );
      final dirName =
          previous?.dir ??
          chapterDirectoryName(
            chapterIndex < 0 ? manifest.chapters.length + 1 : chapterIndex + 1,
            chapter.title,
          );
      chapterDir = Directory(p.join(comicDir.path, dirName));
      await chapterDir.create(recursive: true);

      var done = 0;
      for (var i = 0; i < urls.length; i++) {
        if (_cancelled.contains(taskId)) break;
        final file = File(
          p.join(
            chapterDir.path,
            '${(i + 1).toString().padLeft(4, '0')}${_extensionOf(urls[i])}',
          ),
        );
        final reusable = await file.exists() && await file.length() > 0
            ? true
            : false;
        if (!reusable) {
          final bytes = await loadBytes(urls[i]);
          if (bytes.isEmpty) throw StateError('第 ${i + 1} 页图片为空');
          await file.writeAsBytes(bytes, flush: true);
        }
        done++;
        await store.updateProgress(
          taskId,
          receivedBytes: done,
          totalBytes: urls.length,
          now: _now(),
        );
        _notify();
      }

      if (_cancelled.contains(taskId)) return;

      // 封面：优先沿用已有本地封面，否则尽力下载一次；失败不影响阅读。
      var coverPath = existingEntry?.coverPath;
      if ((coverPath == null || coverPath.isEmpty) &&
          item.coverUrl.trim().isNotEmpty) {
        coverPath = await _downloadCover(item.coverUrl, comicDir);
      }

      final chapterInfo = LocalComicChapterInfo(
        id: chapter.url,
        title: chapter.title,
        dir: dirName,
        pages: urls.length,
      );
      final chapters = _mergeChapters(detail, manifest, chapterInfo);
      manifest = LocalComicManifest(
        sourceName: ref.sourceName,
        sourceTitle: detail.sourceName ?? ref.sourceName,
        detailUrl: detail.detailUrl,
        description: detail.description,
        cover: coverPath == null ? '' : p.basename(coverPath),
        chapters: chapters,
        downloadedAt: _now(),
      );
      final pageCount = manifest.pageCount;
      await local.import(
        ref: localRef,
        title: item.title,
        folderPath: comicDir.path,
        coverPath: coverPath,
        pageCount: pageCount,
        payload: manifest.encode(),
      );
      await store.transition(taskId, ComicDownloadStatus.done, now: _now());
    } on Object catch (error) {
      if (_cancelled.contains(taskId)) return;
      try {
        await store.transition(
          taskId,
          ComicDownloadStatus.failed,
          error: '$error',
          now: _now(),
        );
      } on Object {
        // 任务行被外部删掉时不再追写失败态。
      }
    } finally {
      _scheduled.remove(taskId);
      if (_cancelled.remove(taskId)) {
        await _cleanupCancelled(taskId, ref, chapter.url, chapterDir, comicDir);
      }
      _notify();
    }
  }

  Future<void> _cleanupCancelled(
    String taskId,
    ComicRef ref,
    String chapterUrl,
    Directory chapterDir,
    Directory comicDir,
  ) async {
    await store.remove(taskId);
    try {
      if (chapterDir.path.isNotEmpty && await chapterDir.exists()) {
        await chapterDir.delete(recursive: true);
      }
      if (comicDir.path.isNotEmpty && await comicDir.exists()) {
        final empty = await comicDir.list().isEmpty;
        if (empty) await comicDir.delete(recursive: true);
      }
    } on Object {
      // 文件被占用/权限问题：保留残留文件，任务已删，用户可稍后再清。
    }
  }

  List<LocalComicChapterInfo> _mergeChapters(
    ComicDetail detail,
    LocalComicManifest manifest,
    LocalComicChapterInfo chapter,
  ) {
    final byUrl = <String, LocalComicChapterInfo>{
      for (final existing in manifest.chapters) existing.id: existing,
      chapter.id: chapter,
    };
    final ordered = <LocalComicChapterInfo>[];
    for (final item in detail.chapters) {
      final info = byUrl.remove(item.url);
      if (info != null) ordered.add(info);
    }
    // 详情里已不存在的旧章节（源改版）仍保留，避免已下载页被静默丢弃。
    ordered.addAll(byUrl.values);
    return ordered;
  }

  LocalComicChapterInfo? _chapterByUrl(
    LocalComicManifest manifest,
    String url,
  ) {
    for (final chapter in manifest.chapters) {
      if (chapter.id == url) return chapter;
    }
    return null;
  }

  Future<String?> _downloadCover(String url, Directory comicDir) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
        return null;
      }
      final bytes = await loadBytes(url);
      if (bytes.isEmpty) return null;
      final file = File(p.join(comicDir.path, 'cover${_extensionOf(url)}'));
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } on Object {
      return null;
    }
  }

  ComicRef _refOf(ComicSummary item) => ComicRef(
    id: item.id,
    sourceName: (item.sourceName ?? '').trim().isEmpty
        ? '未知源'
        : item.sourceName!.trim(),
  );

  void _notify() {
    try {
      _changes.emit();
    } on Object {
      // 页面已销毁/监听器异常不影响下载本身。
    }
  }
}

/// ChangeNotifier 的 `notifyListeners` 是 protected，外部组合类不能直接
/// 调用；用一个只暴露 `emit()` 的子类包一层。
class _DownloadChanges extends ChangeNotifier {
  void emit() => notifyListeners();
}

/// 本地漫画的稳定目录 id（同一 `{sourceName,id}` 永远同目录）。
String localComicFolderId(ComicRef ref) =>
    'dl-${cacheKey('${ref.sourceName}|${ref.id}')}';

/// 下载任务 id（模块内唯一；同时把章节 URL 收进 task.chapterId）。
String downloadTaskId(ComicRef ref, ComicChapter chapter) =>
    'dl-${cacheKey('${ref.sourceName}|${ref.id}|${chapter.url}')}';

/// 章节落盘目录名：序号 + 清洗后的标题（保序、可读、跨平台安全）。
String chapterDirectoryName(int index, String title) {
  final sanitized = _sanitize(title);
  final base = sanitized.isEmpty ? 'chapter' : sanitized;
  return '${index.toString().padLeft(3, '0')}-${base.length > 60 ? base.substring(0, 60) : base}';
}

String _sanitize(String value) {
  var result = value.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
  result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
  result = result.replaceAll(RegExp(r'[. ]+$'), '');
  return result;
}

String _extensionOf(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final ext = p.extension(path).toLowerCase();
  const allowed = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.avif',
  };
  return allowed.contains(ext) ? ext : '.jpg';
}
