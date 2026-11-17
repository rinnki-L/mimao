// 统一库单测（docs/directory-layout.md §1 test/core/library_test.dart）。
// 覆盖：CRUD / payload 原样往返 / starred 筛选 / 复合主键（同源不同源各一行）。

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';

void main() {
  late AppDb db;
  late LibraryRepository repo;

  setUp(() {
    db = AppDb.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seed({
    String id = 'kazumi:1001',
    MediaType type = MediaType.anime,
    String source = 'Demo番剧源',
    String title = '葬送的芙莉莲',
    String payload = '{"episode":12,"positionSec":843}',
    String progress = '看到第 12 话',
    bool starred = false,
    DateTime? opened,
  }) => repo.upsert(
    id: id,
    type: type,
    sourceName: source,
    title: title,
    payload: payload,
    progressText: progress,
    starred: starred,
    lastOpenedAt: opened ?? DateTime(2026, 11, 17),
  );

  test('upsert 后时间线读得到，公共列正确', () async {
    await seed();
    final rows = await repo.timeline();
    expect(rows, hasLength(1));
    expect(rows.first.title, '葬送的芙莉莲');
    expect(rows.first.type, MediaType.anime);
    expect(rows.first.progressText, '看到第 12 话');
    expect(rows.first.starred, isFalse);
  });

  test('payload 原样往返——core/壳都不解释它', () async {
    const raw = '{"chapter":45,"page":3,"note":"带中文与 \\"引号\\""}';
    await seed(payload: raw);
    final stored = await (db.select(db.mediaEntries)).getSingle();
    expect(stored.payload, raw);
  });

  test('时间线按 lastOpenedAt 倒序', () async {
    await seed(id: 'a:1', opened: DateTime(2026, 1, 1));
    await seed(id: 'a:2', opened: DateTime(2026, 11, 17));
    final rows = await repo.timeline();
    expect(rows.map((r) => r.id), ['a:2', 'a:1']);
  });

  test('按类型筛选', () async {
    await seed(type: MediaType.anime);
    await seed(
      id: 'venera:1',
      type: MediaType.comic,
      source: 'Demo漫画源',
      title: '尖帽子的魔法工坊',
    );
    final anime = await repo.timeline(type: MediaType.anime);
    expect(anime, hasLength(1));
    expect(anime.first.type, MediaType.anime);
  });

  test('收藏筛选 + setStarred 切换', () async {
    await seed(id: 'a:1', starred: false);
    await seed(id: 'a:2', starred: true, title: '已收藏');
    final starred = await repo.timeline(starredOnly: true);
    expect(starred, hasLength(1));
    expect(starred.first.title, '已收藏');

    await repo.setStarred(starred.first, starred: false);
    expect(await repo.timeline(starredOnly: true), isEmpty);
  });

  test('复合主键：同 id 不同源是两行；同源再写则覆盖', () async {
    await seed(id: 'x:1', source: '源A');
    await seed(id: 'x:1', source: '源B');
    expect(await repo.timeline(), hasLength(2));

    await seed(id: 'x:1', source: '源A', title: '源A更新后');
    final rows = await repo.timeline();
    expect(rows, hasLength(2));
    expect(rows.firstWhere((r) => r.sourceName == '源A').title, '源A更新后');
  });

  test('limit 生效', () async {
    for (var i = 0; i < 5; i++) {
      await seed(id: 'a:$i', opened: DateTime(2026, 1, i + 1));
    }
    expect(await repo.timeline(limit: 2), hasLength(2));
  });
}
