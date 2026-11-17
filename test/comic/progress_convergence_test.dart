// closure-02 §2 核心回归：进度收敛后的双记账一致性。
//
// B′ 旧路径（syncComicProgress 直写投影）会把收藏漫画的 starred 冲成 false、
// 清空 coverUrl、重置 createdAt。收敛后唯一生产写入口是
// ComicLibraryProgressRecorder → ComicHistoryService.saveProgress
// → syncComicProjection，本文件验证收藏元数据在写进度后保持不变，
// 以及 open() 的打开点校正。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/reader/reader_progress.dart';
import 'package:mimao/core/contract.dart';

import 'comic_test_env.dart';

void main() {
  late ComicTestEnv env;
  late ComicLibraryProgressRecorder recorder;

  const ComicRef ref = ComicRef(id: 'comic:fav', sourceName: 'bilimanga');

  setUp(() {
    env = ComicTestEnv.create();
    recorder = ComicLibraryProgressRecorder(
      history: env.comicHistory,
      ref: ref,
      title: '收藏的漫画',
      coverUrl: 'https://new.test/cover.jpg',
      now: () => DateTime(2026, 11, 17, 12, 0),
    );
  });

  tearDown(() => env.close());

  Future<Map<String, dynamic>> projectionRow() async {
    final row = await (env.appDb.select(env.appDb.mediaEntries)).getSingle();
    return row.toJson();
  }

  test('先收藏后写进度：starred/coverUrl/createdAt 不被冲掉', () async {
    // 收藏（投影 createdAt 取 collectedAt）。
    await env.comicCollect.collect(
      ref,
      title: '收藏的漫画',
      coverUrl: 'https://collect.test/cover.jpg',
      collectedAt: DateTime(2026, 11, 1, 9, 0),
    );

    // 生产 recorder 写进度——旧 B′ 路径在这里会把 starred 冲成 false。
    await recorder.persist(
      const ReadingProgress(
        chapter: 2,
        chapterId: 'ep-2',
        chapterTitle: '第二话',
        page: 10,
        pageCount: 20,
      ),
    );

    final row = await projectionRow();
    final decoded =
        jsonDecode(row['payload'] as String) as Map<String, dynamic>;

    expect(row['starred'], isTrue, reason: 'starred 必须保留');
    expect(
      row['coverUrl'],
      'https://collect.test/cover.jpg',
      reason: 'coverUrl 以收藏行为权威，不被进度写覆盖',
    );
    expect(decoded, <String, dynamic>{
      'chapterId': 'ep-2',
      'page': 10,
      'pageCount': 20,
    }, reason: 'payload 统一为 C′ 格式');
    expect(
      (await env.library.timeline()).single.progressText,
      'ep-2 · 第 10 页 · 50%',
    );
  });

  test('先写进度后收藏：标题/封面切到收藏行，进度保留', () async {
    await recorder.persist(
      const ReadingProgress(
        chapter: 1,
        chapterId: 'ep-1',
        chapterTitle: '第一话',
        page: 3,
        pageCount: 10,
      ),
    );
    await env.comicCollect.collect(
      ref,
      title: '收藏的漫画',
      coverUrl: 'https://collect.test/cover.jpg',
      collectedAt: DateTime(2026, 11, 2, 9, 0),
    );

    final row = await projectionRow();
    expect(row['starred'], isTrue);
    expect(
      row['coverUrl'],
      'https://collect.test/cover.jpg',
      reason: '收藏行优先于历史行',
    );
    expect(
      (await env.library.timeline()).single.progressText,
      'ep-1 · 第 3 页 · 30%',
      reason: '收藏动作不覆盖进度',
    );
  });

  test('打开点校正：投影停第 8 页、内部第 10 页，open 后回到第 10 页', () async {
    await env.comicCollect.collect(
      ref,
      title: '收藏的漫画',
      coverUrl: 'https://collect.test/cover.jpg',
    );
    await recorder.persist(
      const ReadingProgress(
        chapter: 1,
        chapterId: 'ep-1',
        chapterTitle: '第一话',
        page: 10,
        pageCount: 20,
      ),
    );

    // 模拟杀进程前最后一笔投影没落盘：把投影手工压回第 8 页。
    await env.library.upsert(
      id: ref.id,
      type: MediaType.comic,
      sourceName: ref.sourceName,
      title: '收藏的漫画',
      coverUrl: 'https://collect.test/cover.jpg',
      payload: '{"chapterId":"ep-1","page":8,"pageCount":20}',
      progressText: 'ep-1 · 第 8 页 · 40%',
      starred: true,
      lastOpenedAt: DateTime(2026, 11, 17, 11, 0),
    );
    expect(
      (await env.library.timeline()).single.progressText,
      'ep-1 · 第 8 页 · 40%',
    );

    // 打开详情/阅读器时的校正动作。
    await env.comicHistory.open(ref);

    final view = (await env.library.timeline()).single;
    expect(view.progressText, 'ep-1 · 第 10 页 · 50%');
    final row = await projectionRow();
    final decoded =
        jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    expect(decoded['page'], 10);
  });

  test('同一 id 不同 sourceName：两条历史/投影互不覆盖', () async {
    const other = ComicRef(id: 'comic:fav', sourceName: 'othermanga');
    final otherRecorder = ComicLibraryProgressRecorder(
      history: env.comicHistory,
      ref: other,
      title: '同名不同源',
      now: () => DateTime(2026, 11, 17, 13, 0),
    );

    await recorder.persist(
      const ReadingProgress(
        chapter: 1,
        chapterId: 'ep-1',
        chapterTitle: '第一话',
        page: 5,
        pageCount: 10,
      ),
    );
    await otherRecorder.persist(
      const ReadingProgress(
        chapter: 1,
        chapterId: 'ep-1',
        chapterTitle: '第一话',
        page: 9,
        pageCount: 10,
      ),
    );

    final rows = await env.library.timeline();
    expect(rows, hasLength(2));
    final bySource = {for (final row in rows) row.sourceName: row};
    expect(bySource['bilimanga']!.progressText, 'ep-1 · 第 5 页 · 50%');
    expect(bySource['othermanga']!.progressText, 'ep-1 · 第 9 页 · 90%');
  });

  test('无历史时 open 不写投影：点开详情不会凭空出现在书架', () async {
    await env.comicHistory.open(ref);
    expect(await env.library.timeline(), isEmpty);
  });
}
