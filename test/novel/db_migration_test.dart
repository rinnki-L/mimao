// 小说库 v1→v2 迁移回归：老用户升级时加列/建表且旧数据不丢。
//
// 手造 v1 的 novel_collect（无 group_name）与一条旧行，再直接驱动
// NovelDb.migration.onUpgrade(m, 1, 2)，验证加列/建表且旧行保留——避免
// 只测全新库走 onCreate 的盲区。
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/novel_db.dart';

/// 最小 QueryExecutorUser：让 executor 通过 ensureOpen 的开启检查。
class _OpenUser implements QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

void main() {
  test('v1→v2 迁移：新列/新表建成，旧行保留', () async {
    final executor = NativeDatabase.memory();
    await executor.ensureOpen(_OpenUser());

    await executor.runCustom(
      'CREATE TABLE novel_collect (id TEXT NOT NULL PRIMARY KEY, '
      'title TEXT NOT NULL, cover_url TEXT NULL, payload TEXT NOT NULL '
      "DEFAULT '{}', collected_at INTEGER NOT NULL)",
    );
    await executor.runCustom(
      'INSERT INTO novel_collect (id, title, payload, collected_at) '
      "VALUES ('b1', '老书', '{}', 0)",
    );

    final db = NovelDb.forTesting(executor);
    addTearDown(() => db.close());

    // 直接驱动迁移策略，绕开 drift 对已打开 executor 不再重跑迁移的行为。
    final migrator = Migrator(db);
    await db.migration.onUpgrade(migrator, 1, 2);

    // 迁移后旧行可查询且 groupName 为空。
    final rows = await db.select(db.novelCollectEntries).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, 'b1');
    expect(rows.single.title, '老书');
    expect(rows.single.groupName, isNull);

    // v2 新表建成且可写可读。
    await db
        .into(db.novelPrefs)
        .insert(NovelPrefsCompanion.insert(key: 'k', value: 'v'));
    expect((await db.select(db.novelPrefs).get()).single.value, 'v');

    await db
        .into(db.novelReadingDays)
        .insert(
          NovelReadingDaysCompanion.insert(
            day: '2026-11-23',
            updatedAt: DateTime(2026, 11, 23),
          ),
        );
    expect(
      (await db.select(db.novelReadingDays).get()).single.day,
      '2026-11-23',
    );
  });
}
