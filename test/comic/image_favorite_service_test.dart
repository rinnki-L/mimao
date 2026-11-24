// 图片收藏：幂等收藏、封面保护、列表与计数、迁移。

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/comic_db.dart';
import 'package:mimao/comic/image_favorite_service.dart';

ImageFavoriteInput _input({
  int page = 2,
  String chapterId = 'ep-1',
  int chapterNumber = 1,
  String comicId = 'c1',
}) => ImageFavoriteInput(
  sourceName: 'src',
  comicId: comicId,
  comicTitle: '测试漫画',
  chapterId: chapterId,
  chapterNumber: chapterNumber,
  chapterTitle: '第 $chapterNumber 章',
  page: page,
  pageCount: 10,
  imageUrl: 'https://img/$chapterId/$page.jpg',
  coverUrl: 'https://img/cover.jpg',
);

void main() {
  late ComicDb db;
  late ComicImageFavoriteService service;

  setUp(() {
    db = ComicDb.forTesting(NativeDatabase.memory());
    service = ComicImageFavoriteService(db);
  });

  tearDown(() => db.close());

  test('收藏后能查到，重复收藏幂等不产生第二行', () async {
    expect(await service.toggle(_input()), ImageFavoriteResult.collected);
    expect(await service.toggle(_input()), ImageFavoriteResult.uncollected);
    expect(await service.toggle(_input()), ImageFavoriteResult.collected);

    final all = await service.forComic('src', 'c1');
    expect(all, hasLength(1));
    expect(all.single.page, 2);
    expect(await service.count(), 1);
  });

  test('第一页（封面）不允许取消', () async {
    expect(
      await service.toggle(_input(page: 1)),
      ImageFavoriteResult.collected,
    );
    expect(
      await service.toggle(_input(page: 1)),
      ImageFavoriteResult.protectedCover,
    );
    expect(await service.count(), 1, reason: '封面收藏仍在');
  });

  test('同一章不同页各自独立，按页号排序返回', () async {
    await service.toggle(_input(page: 5));
    await service.toggle(_input(page: 2));
    await service.toggle(_input(page: 9));

    final all = await service.forComic('src', 'c1');
    expect(all.map((f) => f.page), <int>[2, 5, 9]);
  });

  test('不同章按章号排序', () async {
    await service.toggle(_input(chapterId: 'ep-2', chapterNumber: 2, page: 3));
    await service.toggle(_input(chapterId: 'ep-1', chapterNumber: 1, page: 3));

    final all = await service.forComic('src', 'c1');
    expect(all.map((f) => f.chapterNumber), <int>[1, 2]);
  });

  test('contains 精确到章与页', () async {
    await service.toggle(_input(page: 4, chapterId: 'ep-1'));
    expect(
      await service.contains(
        sourceName: 'src',
        comicId: 'c1',
        chapterId: 'ep-1',
        page: 4,
      ),
      isTrue,
    );
    expect(
      await service.contains(
        sourceName: 'src',
        comicId: 'c1',
        chapterId: 'ep-2',
        page: 4,
      ),
      isFalse,
      reason: '换章不算收藏',
    );
  });

  test('不同作品互不影响', () async {
    await service.toggle(_input(comicId: 'c1'));
    await service.toggle(_input(comicId: 'c2'));

    expect(await service.forComic('src', 'c1'), hasLength(1));
    expect(await service.forComic('src', 'c2'), hasLength(1));
    expect(await service.count(), 2);
  });

  test('recent 按收藏时间倒序', () async {
    // 固定同一时刻会并列，这里用递增时钟模拟"先后收藏"。
    var tick = DateTime(2026, 1, 1);
    final timed = ComicImageFavoriteService(
      db,
      now: () => tick = tick.add(const Duration(seconds: 1)),
    );
    await timed.toggle(_input(page: 2));
    await timed.toggle(_input(page: 3));

    final recent = await timed.recent();
    expect(recent.first.page, 3, reason: '后收藏的在前');
  });

  test('removeComic 清掉该作品全部收藏', () async {
    await service.toggle(_input(page: 2));
    await service.toggle(_input(page: 3));
    await service.toggle(_input(comicId: 'c2'));

    expect(await service.removeComic('src', 'c1'), 2);
    expect(await service.forComic('src', 'c1'), isEmpty);
    expect(await service.count(), 1);
  });

  test('v2 → v3 迁移：旧库补出图片收藏表，旧数据保留', () async {
    final path =
        '${Directory.systemTemp.path}/mimao_mig_${DateTime.now().microsecondsSinceEpoch}.sqlite';
    final file = File(path);

    // 造一个"v2 库"：先按当前 schema 建库，再删掉新表并把 user_version 退回 2。
    final seed = ComicDb.forTesting(NativeDatabase(file));
    await seed.customStatement('DROP TABLE IF EXISTS comic_image_favorite');
    await seed.customStatement(
      "INSERT INTO comic_history (id, source_name, title, opened_at) "
      "VALUES ('old', 'src', '旧书', 1700000000)",
    );
    await seed.customStatement('PRAGMA user_version = 2');
    await seed.close();

    // 以当前版本重开 → 走 onUpgrade(from: 2) → 只补图片收藏表。
    final migrated = ComicDb.forTesting(NativeDatabase(file));
    final service2 = ComicImageFavoriteService(migrated);
    try {
      await service2.toggle(_input());
      expect(await service2.count(), 1, reason: '新表可用');

      final rows = await migrated
          .customSelect('SELECT title FROM comic_history')
          .get();
      expect(rows.single.read<String>('title'), '旧书', reason: '旧数据保留');
    } finally {
      await migrated.close();
      if (await file.exists()) await file.delete();
    }
  });
}
