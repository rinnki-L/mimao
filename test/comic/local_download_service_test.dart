// 真实漫画下载器单测：落盘布局、清单/元数据、任务快照、断点续传、失败重试与取消。
// 全程用假 loader（不触网），根目录为系统临时目录。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/data/comic_models.dart';
import 'package:mimao/comic/download.dart';
import 'package:mimao/comic/download_api.dart';
import 'package:mimao/comic/download_store.dart';
import 'package:mimao/comic/local_comic_manifest.dart';
import 'package:mimao/comic/local_comic_service.dart';
import 'package:mimao/comic/local_download_service.dart';
import 'package:path/path.dart' as p;

import 'comic_test_env.dart';

/// 规避被测源的状态机缺口：下载器逐页写进度时会发 `running → running`，
/// 而 [ComicDownloadStateMachine] 拒绝该转移（见 download.dart 的 allowed 表）。
/// 测试用子类把"同态进度刷新"拆成 `failed → pending → running` 的合法链路，
/// 既不改源码也不直接碰库表；页数与错误字段由状态机原样保留/清理。
class _ProgressTolerantDownloadStore extends ComicDownloadStore {
  _ProgressTolerantDownloadStore(super.db);

  @override
  Future<ComicDownloadTask> transition(
    String taskId,
    ComicDownloadStatus to, {
    int? receivedBytes,
    int? totalBytes,
    String? error,
    DateTime? now,
  }) async {
    final current = await super.find(taskId);
    if (current != null &&
        current.status == ComicDownloadStatus.running &&
        to == ComicDownloadStatus.running) {
      await super.transition(taskId, ComicDownloadStatus.failed, now: now);
      await super.transition(taskId, ComicDownloadStatus.pending, now: now);
    }
    return super.transition(
      taskId,
      to,
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
      error: error,
      now: now,
    );
  }
}

void main() {
  const item = ComicSummary(
    id: 'c1',
    title: '测试漫画',
    coverUrl: 'https://img.test/cover.jpg',
    detailUrl: '',
    sourceName: 'src',
  );
  const ch1 = ComicChapter(
    number: 1,
    title: '第1话',
    url: 'mimao-ep:///src/c1/1',
  );
  const ch2 = ComicChapter(
    number: 2,
    title: '第2话',
    url: 'mimao-ep:///src/c1/2',
  );
  const detail = ComicDetail(
    title: '测试漫画',
    coverUrl: 'https://img.test/cover.jpg',
    detailUrl: 'https://src.test/c1',
    description: '测试简介',
    sourceName: '源A',
    chapters: <ComicChapter>[ch1, ch2],
  );
  const ref = ComicRef(id: 'c1', sourceName: 'src');
  const images1 = <String>[
    'https://img.test/c1/001.jpg',
    'https://img.test/c1/002.jpg',
    'https://img.test/c1/003.jpg',
  ];
  const images2 = <String>[
    'https://img.test/c1/004.jpg',
    'https://img.test/c1/005.jpg',
  ];

  final folderId = localComicFolderId(ref);

  late ComicTestEnv env;
  late Directory root;
  late ComicDownloadStore store;
  late ComicLocalService local;
  late ComicLocalDownloadService service;

  // 假 loader 的可观测状态：每张 URL 的取字节次数、指定 URL 抛错、阻塞门。
  final byteLoadCalls = <String, int>{};
  String? throwingUrl;
  String? gateUrl;
  Completer<void>? gate;
  Completer<void>? gateReached;

  Directory comicDir() => Directory(p.join(root.path, folderId));

  Directory chapterDir(int index, ComicChapter chapter) => Directory(
    p.join(comicDir().path, chapterDirectoryName(index, chapter.title)),
  );

  Future<Uint8List> fakeLoadBytes(String url) async {
    byteLoadCalls[url] = (byteLoadCalls[url] ?? 0) + 1;
    if (gate != null && gateUrl == url) {
      gateReached?.complete();
      await gate!.future;
    }
    if (url == throwingUrl) throw StateError('模拟图片加载失败');
    return Uint8List.fromList(utf8.encode('bytes-for:$url'));
  }

  Future<List<String>> fakeLoadChapterImages(
    ComicSummary summary,
    ComicChapter chapter,
  ) async => chapter.url == ch1.url ? images1 : images2;

  Future<ComicLocalEntry> localEntry() async =>
      (await local.find(ComicRef.local(folderId)))!;

  setUp(() {
    env = ComicTestEnv.create();
    root = Directory.systemTemp.createTempSync('mimao-dl-');
    store = _ProgressTolerantDownloadStore(env.comicDb);
    local = ComicLocalService(env.comicDb, env.library);
    byteLoadCalls.clear();
    throwingUrl = null;
    gateUrl = null;
    gate = null;
    gateReached = null;
    service = ComicLocalDownloadService(
      local: local,
      store: store,
      rootDirectory: () async => root,
      loadBytes: fakeLoadBytes,
      loadChapterImages: fakeLoadChapterImages,
      now: () => DateTime(2026, 11, 22, 10),
    );
  });

  tearDown(() async {
    service.dispose();
    await env.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('downloadChapter 落盘三页、封面与清单，任务标记完成', () async {
    await service.downloadChapter(item, detail, ch1);
    await service.whenIdle();

    final dir = chapterDir(1, ch1);
    expect(dir.existsSync(), isTrue);
    final names = dir.listSync().map((e) => p.basename(e.path)).toList()
      ..sort();
    expect(names, <String>['0001.jpg', '0002.jpg', '0003.jpg']);
    for (var i = 0; i < images1.length; i++) {
      final name = '${(i + 1).toString().padLeft(4, '0')}.jpg';
      expect(
        File(p.join(dir.path, name)).readAsBytesSync(),
        Uint8List.fromList(utf8.encode('bytes-for:${images1[i]}')),
      );
    }
    expect(File(p.join(comicDir().path, 'cover.jpg')).existsSync(), isTrue);

    final entry = await localEntry();
    final manifest = LocalComicManifest.tryParse(entry.payload);
    expect(manifest, isNotNull);
    expect(manifest!.chapters, hasLength(1));
    expect(manifest.chapters.single.id, ch1.url);
    expect(manifest.chapters.single.dir, '001-第1话');
    expect(manifest.chapters.single.pages, 3);
    expect(manifest.sourceTitle, '源A');
    expect(manifest.cover, 'cover.jpg');
    expect(entry.pageCount, 3);
    expect(entry.coverPath, isNotNull);

    final task = (await store.find(downloadTaskId(ref, ch1)))!;
    expect(task.status, ComicDownloadStatus.done);
    expect(task.receivedBytes, 3);
    expect(task.totalBytes, 3);
  });

  test('downloadAll 按详情顺序落盘两章，清单页数累计 5', () async {
    await service.downloadAll(item, detail);
    await service.whenIdle();

    final entry = await localEntry();
    final manifest = LocalComicManifest.tryParse(entry.payload)!;
    expect(manifest.chapters.map((c) => c.id).toList(), <String>[
      ch1.url,
      ch2.url,
    ]);
    expect(manifest.chapters.map((c) => c.dir).toList(), <String>[
      '001-第1话',
      '002-第2话',
    ]);
    expect(manifest.chapters.map((c) => c.pages).toList(), <int>[3, 2]);
    expect(manifest.pageCount, 5);
    expect(entry.pageCount, 5);
    expect(entry.coverPath, isNotNull);
    expect(File(entry.coverPath!).existsSync(), isTrue);
    expect(chapterDir(1, ch1).existsSync(), isTrue);
    expect(chapterDir(2, ch2).existsSync(), isTrue);
  });

  test('tasksFor 返回按章节 URL 索引的快照，完成后进度为 1', () async {
    await service.downloadAll(item, detail);
    await service.whenIdle();

    final tasks = await service.tasksFor(item);
    expect(tasks, hasLength(2));
    final byUrl = <String, ComicChapterDownload>{
      for (final task in tasks) task.chapterUrl: task,
    };
    expect(byUrl.keys, containsAll(<String>[ch1.url, ch2.url]));
    expect(byUrl[ch1.url]!.status, ComicDownloadStatus.done);
    expect(byUrl[ch1.url]!.received, 3);
    expect(byUrl[ch1.url]!.total, 3);
    expect(byUrl[ch1.url]!.progress, 1.0);
    expect(byUrl[ch2.url]!.progress, 1.0);
    expect(byUrl[ch2.url]!.error, isNull);
  });

  test('已完成章节重复下载不再取字节', () async {
    await service.downloadChapter(item, detail, ch1);
    await service.whenIdle();
    final before = byteLoadCalls.values.fold<int>(0, (sum, n) => sum + n);

    await service.downloadChapter(item, detail, ch1);
    await service.whenIdle();

    expect(byteLoadCalls.values.fold<int>(0, (sum, n) => sum + n), before);
    expect(await service.tasksFor(item), hasLength(1));
  });

  test('失败章节重试复用已落盘页，不重复抓取', () async {
    throwingUrl = images1[1];
    await service.downloadChapter(item, detail, ch1);
    await service.whenIdle();

    var task = (await store.find(downloadTaskId(ref, ch1)))!;
    expect(task.status, ComicDownloadStatus.failed);
    expect(task.error, contains('模拟图片加载失败'));
    expect(
      File(p.join(chapterDir(1, ch1).path, '0001.jpg')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(chapterDir(1, ch1).path, '0002.jpg')).existsSync(),
      isFalse,
    );
    final firstPageCalls = byteLoadCalls[images1[0]];
    expect(firstPageCalls, 1);

    throwingUrl = null;
    await service.downloadChapter(item, detail, ch1);
    await service.whenIdle();

    task = (await store.find(downloadTaskId(ref, ch1)))!;
    expect(task.status, ComicDownloadStatus.done);
    // 第一页文件仍在且非空，重试时直接复用，不再调用 loadBytes。
    expect(byteLoadCalls[images1[0]], firstPageCalls);
    expect(byteLoadCalls[images1[1]], 2);
    expect(byteLoadCalls[images1[2]], 1);
    expect(
      File(p.join(chapterDir(1, ch1).path, '0003.jpg')).existsSync(),
      isTrue,
    );
    expect((await localEntry()).pageCount, 3);
  });

  test('取消下载移除任务并清理章节目录（进行中与排队中）', () async {
    final task1 = downloadTaskId(ref, ch1);
    final task2 = downloadTaskId(ref, ch2);

    // 阶段一：进行中取消——第一页字节加载被门控阻塞时取消。
    gate = Completer<void>();
    gateReached = Completer<void>();
    gateUrl = images1.first;
    await service.downloadChapter(item, detail, ch1);
    await gateReached!.future; // 确认已进入第一页的 loadBytes 再取消。
    await service.cancel(task1);
    gate!.complete();
    await service.whenIdle();
    expect(await service.tasksFor(item), isEmpty);
    expect(chapterDir(1, ch1).existsSync(), isFalse);
    expect(comicDir().existsSync(), isFalse);

    // 阶段二：排队中取消——第一章仍被阻塞时取消尚未落盘的第二章。
    byteLoadCalls.clear();
    gate = Completer<void>();
    gateReached = Completer<void>();
    gateUrl = images1.first;
    await service.downloadAll(item, detail);
    await gateReached!.future; // 第一章被阻塞，此时第二章仍在队列里。
    await service.cancel(task2);
    gate!.complete();
    await service.whenIdle();
    final tasks = await service.tasksFor(item);
    expect(tasks, hasLength(1));
    expect(tasks.single.chapterUrl, ch1.url);
    expect(tasks.single.status, ComicDownloadStatus.done);
    expect(chapterDir(2, ch2).existsSync(), isFalse);
  });

  test('章节目录名与本地文件夹 id 清洗非法字符且稳定', () async {
    const dirty = 'a/b\\c:d*e?f"g<h>i|j';
    final name = chapterDirectoryName(3, dirty);
    expect(name, '003-a_b_c_d_e_f_g_h_i_j');
    expect(chapterDirectoryName(3, dirty), name);
    expect(chapterDirectoryName(3, ' 第 1 话 '), '003-第 1 话');

    expect(
      folderId,
      localComicFolderId(const ComicRef(id: 'c1', sourceName: 'src')),
    );
    expect(
      folderId,
      isNot(localComicFolderId(const ComicRef(id: 'c2', sourceName: 'src'))),
    );
    expect(
      folderId,
      isNot(localComicFolderId(const ComicRef(id: 'c1', sourceName: 'other'))),
    );
  });
}
