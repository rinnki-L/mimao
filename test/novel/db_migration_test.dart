// 小说库 v1→v2 迁移回归：老用户升级时加列/建表且旧数据不丢。
//
// 手造 v1 的 novel_collect（无 group_name）与一条旧行，再直接驱动
// NovelDb.migration.onUpgrade(m, 1, 2)，验证加列/建表且旧行保留——避免
// 只测全新库走 onCreate 的盲区。
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/models/novel_models.dart';
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

    // 阅读记录表在 v8 才建（v2 只建 kv）；这里不再断言旧 `novel_reading_day`。
  });

  test('v5→v6 迁移：备注/自定义封面/系列列与系列表建成，旧行保留', () async {
    final executor = NativeDatabase.memory();
    await executor.ensureOpen(_OpenUser());

    // 手造 v5 形态的收藏表（有 group_name，没有 note/custom_cover_path/series_id）。
    await executor.runCustom(
      'CREATE TABLE novel_collect (id TEXT NOT NULL PRIMARY KEY, '
      'title TEXT NOT NULL, cover_url TEXT NULL, payload TEXT NOT NULL '
      "DEFAULT '{}', group_name TEXT NULL, collected_at INTEGER NOT NULL)",
    );
    await executor.runCustom(
      'INSERT INTO novel_collect (id, title, payload, group_name, collected_at) '
      "VALUES ('b1', '老书', '{}', '科幻', 0)",
    );

    final db = NovelDb.forTesting(executor);
    addTearDown(() => db.close());

    final migrator = Migrator(db);
    await db.migration.onUpgrade(migrator, 5, 6);

    final rows = await db.select(db.novelCollectEntries).get();
    expect(rows, hasLength(1));
    expect(rows.single.groupName, '科幻');
    // 新列取默认值，无需回填。
    expect(rows.single.note, '');
    expect(rows.single.customCoverPath, isNull);
    expect(rows.single.seriesId, isNull);

    // 系列表建成且可写；外键列能指向它。
    final seriesId = await db
        .into(db.novelSeriesEntries)
        .insert(
          NovelSeriesEntriesCompanion.insert(
            name: '地球往事',
            createdAt: DateTime(2026, 11, 25),
          ),
        );
    await (db.update(db.novelCollectEntries)..where((t) => t.id.equals('b1')))
        .write(NovelCollectEntriesCompanion(seriesId: Value(seriesId)));
    final updated = await db.collectRow(NovelRef(id: 'b1'));
    expect(updated?.seriesId, seriesId);
  });

  test('v6→v7 迁移：本地书表与 TXT 规则表建成，旧收藏行不受影响', () async {
    final executor = NativeDatabase.memory();
    await executor.ensureOpen(_OpenUser());
    await executor.runCustom(
      'CREATE TABLE novel_collect (id TEXT NOT NULL PRIMARY KEY, '
      'title TEXT NOT NULL, cover_url TEXT NULL, payload TEXT NOT NULL '
      "DEFAULT '{}', group_name TEXT NULL, note TEXT NOT NULL DEFAULT '', "
      'custom_cover_path TEXT NULL, series_id INTEGER NULL, '
      'collected_at INTEGER NOT NULL)',
    );
    await executor.runCustom(
      'INSERT INTO novel_collect (id, title, payload, collected_at) '
      "VALUES ('b1', '老书', '{}', 0)",
    );

    final db = NovelDb.forTesting(executor);
    addTearDown(() => db.close());

    final migrator = Migrator(db);
    await db.migration.onUpgrade(migrator, 6, 7);

    // 旧收藏行原样保留（本地书是增量能力，不该动到已有数据）。
    final rows = await db.select(db.novelCollectEntries).get();
    expect(rows, hasLength(1));
    expect(rows.single.title, '老书');

    // 本地书表建成且可写可读。
    await db
        .into(db.novelLocalBooks)
        .insert(
          NovelLocalBooksCompanion.insert(
            id: 'local:abc',
            path: '/books/a.txt',
            title: '本地书',
            format: 'txt',
            addedAt: DateTime(2026, 11, 25),
          ),
        );
    final local = await db.select(db.novelLocalBooks).getSingle();
    expect(local.id, 'local:abc');
    expect(local.tocJson, '[]');
    expect(local.chapterCount, 0);

    // TXT 规则表建成；迁移不写业务数据，内置规则由服务首次读取时补。
    expect(await db.select(db.novelTxtTocRules).get(), isEmpty);
    await db
        .into(db.novelTxtTocRules)
        .insert(
          NovelTxtTocRulesCompanion.insert(
            name: '测试规则',
            pattern: r'^第.+章$',
            updatedAt: DateTime(2026, 11, 25),
          ),
        );
    expect((await db.select(db.novelTxtTocRules).getSingle()).name, '测试规则');
  });

  test('v8→v9 迁移：三张规则表建成，旧收藏行不受影响', () async {
    final executor = NativeDatabase.memory();
    await executor.ensureOpen(_OpenUser());
    await executor.runCustom(
      'CREATE TABLE novel_collect (id TEXT NOT NULL PRIMARY KEY, '
      'title TEXT NOT NULL, cover_url TEXT NULL, payload TEXT NOT NULL '
      "DEFAULT '{}', group_name TEXT NULL, note TEXT NOT NULL DEFAULT '', "
      'custom_cover_path TEXT NULL, series_id INTEGER NULL, '
      'collected_at INTEGER NOT NULL)',
    );
    await executor.runCustom(
      'INSERT INTO novel_collect (id, title, payload, collected_at) '
      "VALUES ('b1', '老书', '{}', 0)",
    );

    final db = NovelDb.forTesting(executor);
    addTearDown(() => db.close());

    final migrator = Migrator(db);
    await db.migration.onUpgrade(migrator, 8, 9);

    final rows = await db.select(db.novelCollectEntries).get();
    expect(rows, hasLength(1));
    expect(rows.single.title, '老书');
    expect(rows.single.groupName, isNull);

    // 三张新表都可写可读；迁移不补业务数据（内置词典规则由服务首次读取时补）。
    expect(await db.select(db.novelDictRules).get(), isEmpty);
    await db
        .into(db.novelDictRules)
        .insert(
          NovelDictRulesCompanion.insert(
            name: '测试词典',
            urlRule: 'https://dict.test/{{key}}',
            updatedAt: DateTime(2026, 11, 25),
          ),
        );
    expect((await db.select(db.novelDictRules).getSingle()).name, '测试词典');

    expect(await db.select(db.novelTagGroupRules).get(), isEmpty);
    await db
        .into(db.novelTagGroupRules)
        .insert(
          NovelTagGroupRulesCompanion.insert(
            name: '修仙',
            pattern: '修真',
            updatedAt: DateTime(2026, 11, 25),
          ),
        );
    expect((await db.select(db.novelTagGroupRules).getSingle()).name, '修仙');

    expect(await db.select(db.novelThemePackages).get(), isEmpty);
    await db
        .into(db.novelThemePackages)
        .insert(
          NovelThemePackagesCompanion.insert(
            name: '主题',
            packageJson: '{}',
            importedAt: DateTime(2026, 11, 25),
          ),
        );
    expect((await db.select(db.novelThemePackages).getSingle()).name, '主题');
  });
}
