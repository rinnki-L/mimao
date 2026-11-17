// 进度收敛后的 recorder 单测：唯一生产实现委托 ComicHistoryService.saveProgress。
//
// 验证点：内部 comic_history 权威行 + core 投影一次成对落账、payload 为
// {chapterId,page,pageCount}、重复写幂等、负数进度被拒。收藏元数据不被冲掉
// 的专项回归在 test/comic/progress_convergence_test.dart。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/reader/reader_progress.dart';
import 'package:mimao/core/contract.dart';

import '../comic_test_env.dart';

void main() {
  late ComicTestEnv env;
  late ComicLibraryProgressRecorder recorder;

  const ComicRef ref = ComicRef(id: 'comic:sample', sourceName: 'bilimanga');

  setUp(() {
    env = ComicTestEnv.create();
    recorder = ComicLibraryProgressRecorder(
      history: env.comicHistory,
      ref: ref,
      title: '尖帽子的魔法工坊',
      coverUrl: 'https://example.test/cover.jpg',
      now: () => DateTime(2026, 11, 17, 20, 30),
    );
  });

  tearDown(() => env.close());

  test('persist 写内部权威行 + 投影：payload/文案为 C′ 格式', () async {
    await recorder.persist(
      const ReadingProgress(
        chapter: 1,
        chapterId: 'ep-1',
        chapterTitle: '第一话',
        page: 2,
        pageCount: 10,
      ),
    );

    // 内部权威行。
    final row = await env.comicDb.historyRow(ref);
    expect(row, isNotNull);
    expect(row!.chapterId, 'ep-1');
    expect(row.page, 2);
    expect(row.pageCount, 10);
    expect(row.title, '尖帽子的魔法工坊');
    expect(row.coverUrl, 'https://example.test/cover.jpg');
    expect(row.openedAt, DateTime(2026, 11, 17, 20, 30));

    // core 投影。
    final rows = await env.library.timeline();
    expect(rows, hasLength(1));
    final view = rows.single;
    expect(view.type, MediaType.comic);
    expect(view.title, '尖帽子的魔法工坊');
    // chapterId 非数值 → 原样展示（决策②）。
    expect(view.progressText, 'ep-1 · 第 2 页 · 20%');
    final stored = await (env.appDb.select(env.appDb.mediaEntries)).getSingle();
    final decoded = jsonDecode(stored.payload) as Map<String, dynamic>;
    expect(decoded, <String, dynamic>{
      'chapterId': 'ep-1',
      'page': 2,
      'pageCount': 10,
    });
  });

  test('数值型 chapterId 展示为「第 N 章」', () async {
    await recorder.persist(
      const ReadingProgress(
        chapter: 12,
        chapterId: '12',
        chapterTitle: '第 12 话',
        page: 3,
        pageCount: 20,
      ),
    );
    final view = (await env.library.timeline()).single;
    expect(view.progressText, '第 12 章 · 第 3 页 · 15%');
  });

  test('重复 upsert 幂等：同一投影行随进度前移', () async {
    for (var i = 1; i <= 3; i++) {
      await recorder.persist(
        ReadingProgress(
          chapter: 1,
          chapterId: 'ep-1',
          chapterTitle: '第一话',
          page: i,
          pageCount: 10,
        ),
      );
    }
    final rows = await env.library.timeline();
    expect(rows, hasLength(1), reason: '同一 {id,type,sourceName} 只能有一行投影');
    expect(rows.single.progressText, 'ep-1 · 第 3 页 · 30%');

    final history = await env.comicHistory.latest(ref);
    expect(history!.page, 3);
  });

  test('切章换 chapterId：进度权威行随之更新', () async {
    await recorder.persist(
      const ReadingProgress(
        chapter: 1,
        chapterId: 'ep-1',
        chapterTitle: '第一话',
        page: 5,
        pageCount: 10,
      ),
    );
    await recorder.persist(
      const ReadingProgress(
        chapter: 2,
        chapterId: 'ep-2',
        chapterTitle: '第二话',
        page: 1,
        pageCount: 8,
      ),
    );
    final history = await env.comicHistory.latest(ref);
    expect(history!.chapterId, 'ep-2');
    expect(history.page, 1);
    expect(history.pageCount, 8);
    expect(
      (await env.library.timeline()).single.progressText,
      'ep-2 · 第 1 页 · 13%',
    );
  });

  test('chapterId 缺省为空串：payload chapterId 为空、文案无章节前缀', () async {
    await recorder.persist(
      const ReadingProgress(
        chapter: 1,
        chapterTitle: '本地章',
        page: 2,
        pageCount: 4,
      ),
    );
    final stored = await (env.appDb.select(env.appDb.mediaEntries)).getSingle();
    final decoded = jsonDecode(stored.payload) as Map<String, dynamic>;
    expect(decoded['chapterId'], '');
    expect(stored.progressText, '第 2 页 · 50%');
  });

  test('负数进度被拒（saveProgress 校验），投影不被改动', () async {
    await recorder.persist(
      const ReadingProgress(
        chapter: 1,
        chapterId: 'ep-1',
        chapterTitle: '第一话',
        page: 2,
        pageCount: 10,
      ),
    );
    await expectLater(
      recorder.persist(
        const ReadingProgress(
          chapter: 1,
          chapterId: 'ep-1',
          chapterTitle: '第一话',
          page: -1,
          pageCount: 10,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      (await env.library.timeline()).single.progressText,
      'ep-1 · 第 2 页 · 20%',
    );
  });
}
