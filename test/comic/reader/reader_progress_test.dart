// 进度写 core 投影单测（验收：翻页/切章更新、重复 upsert 幂等、payload 原样往返）。
//
// 全程用内存 AppDb + 真实 LibraryRepository，验证 progressText / payload 由模块写、
// core 只做原样透传；不碰 A′ 源引擎/网络。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_progress.dart';
import 'package:mimao/core/contract.dart';

import 'reader_test_env.dart';

void main() {
  late ReaderTestEnv env;
  late ComicLibraryProgressRecorder recorder;

  setUp(() {
    env = ReaderTestEnv.create();
    recorder = ComicLibraryProgressRecorder(
      library: env.library,
      ref: kRef,
      title: '尖帽子的魔法工坊',
      coverUrl: 'https://example.test/cover.jpg',
      now: () => DateTime(2026, 11, 17, 20, 30),
    );
  });

  tearDown(() => env.close());

  test('翻页/切章更新：同一个投影行随进度前移，progressText 由模块写', () async {
    await recorder.persist(
      const ReadingProgress(
        chapter: 1,
        chapterTitle: '第 1 章',
        page: 2,
        pageCount: 10,
      ),
    );
    var rows = await env.library.timeline();
    expect(rows, hasLength(1));
    expect(rows.single.type, MediaType.comic);
    expect(rows.single.title, '尖帽子的魔法工坊');
    expect(rows.single.progressText, '第 1 章 · 第 2/10 页');

    // 翻页到第 5 页：仍是同一行，文案随之更新。
    await recorder.persist(
      const ReadingProgress(
        chapter: 1,
        chapterTitle: '第 1 章',
        page: 5,
        pageCount: 10,
      ),
    );
    rows = await env.library.timeline();
    expect(rows, hasLength(1));
    expect(rows.single.progressText, '第 1 章 · 第 5/10 页');

    // 切到第 2 章第 1 页。
    await recorder.persist(
      const ReadingProgress(
        chapter: 2,
        chapterTitle: '第 2 章',
        page: 1,
        pageCount: 8,
      ),
    );
    rows = await env.library.timeline();
    expect(rows, hasLength(1));
    expect(rows.single.progressText, '第 2 章 · 第 1/8 页');
    expect(rows.single.lastOpenedAt, DateTime(2026, 11, 17, 20, 30));
  });

  test('重复 upsert 幂等：相同 ref 重复写不产生第二行，最后一笔生效', () async {
    for (var i = 1; i <= 5; i++) {
      await recorder.persist(
        ReadingProgress(
          chapter: 1,
          chapterTitle: '第 1 章',
          page: i,
          pageCount: 10,
        ),
      );
    }
    final rows = await env.library.timeline();
    expect(rows, hasLength(1), reason: '同一 {id,type,sourceName} 只能有一行投影');
    final stored = await (env.appDb.select(env.appDb.mediaEntries)).getSingle();
    expect(jsonDecode(stored.payload)['page'], 5);
  });

  test('payload 原样往返：{chapter,page} 由模块写，core 不解释', () async {
    await recorder.persist(
      const ReadingProgress(
        chapter: 45,
        chapterTitle: '第 45 章',
        page: 3,
        pageCount: 20,
      ),
    );
    final stored = await (env.appDb.select(env.appDb.mediaEntries)).getSingle();
    final decoded = jsonDecode(stored.payload) as Map<String, dynamic>;
    expect(decoded, <String, dynamic>{'chapter': 45, 'page': 3});
    expect(stored.payload, '{"chapter":45,"page":3}');
  });

  test('未传 openedAt 时回退到当前时间（syncComicProgress 默认分支）', () async {
    final before = DateTime.now();
    await syncComicProgress(
      library: env.library,
      ref: kRef,
      title: '尖帽子的魔法工坊',
      chapter: 1,
      page: 1,
      pageCount: 5,
    );
    final after = DateTime.now();
    final row = (await env.library.timeline()).single;
    expect(
      row.lastOpenedAt.isBefore(before.subtract(const Duration(seconds: 1))),
      isFalse,
    );
    expect(
      row.lastOpenedAt.isAfter(after.add(const Duration(seconds: 1))),
      isFalse,
    );
  });

  test('负数进度被拒，投影不被改动', () async {
    await recorder.persist(
      const ReadingProgress(
        chapter: 1,
        chapterTitle: '第 1 章',
        page: 2,
        pageCount: 10,
      ),
    );
    await expectLater(
      recorder.persist(
        const ReadingProgress(
          chapter: 1,
          chapterTitle: '第 1 章',
          page: -1,
          pageCount: 10,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      (await env.library.timeline()).single.progressText,
      '第 1 章 · 第 2/10 页',
    );
  });
}
