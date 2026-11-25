// 恢复合并：进度规则、收藏并集与冲突、书签去重与墓碑、阅读时长幂等、设置分档。
// 纯函数测试，不碰 drift / 网络。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/backup/backup_document.dart';
import 'package:mimao/novel/backup/backup_plan.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/reader/novel_locator.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

void main() {
  group('进度合并', () {
    test('章号大者胜：本地第 10 章，远端第 3 章 → 不动', () {
      final plan = planNovelRestore(
        local: _doc(
          histories: <NovelBackupHistory>[
            _history('b1', 10, at: DateTime.utc(2026, 11, 1)),
          ],
        ),
        remote: _doc(
          progress: <NovelBackupProgress>[
            _progress('b1', 3, at: DateTime.utc(2026, 11, 20)),
          ],
        ),
      );
      expect(plan.counts.updated, 0);
      expect(plan.counts.unchanged, 1);
      expect(plan.ops, isEmpty);
    });

    test('章号更大者胜：本地第 3 章，远端第 10 章 → 更新', () {
      final plan = planNovelRestore(
        local: _doc(
          histories: <NovelBackupHistory>[
            _history('b1', 3, at: DateTime.utc(2026, 11, 20)),
          ],
        ),
        remote: _doc(
          progress: <NovelBackupProgress>[
            _progress('b1', 10, at: DateTime.utc(2026, 11, 1)),
          ],
        ),
      );
      expect(plan.counts.updated, 1);
      final op = plan.ops.single;
      expect(op.target, NovelBackupTarget.progress);
      expect(op.payload['chapterIndex'], 10);
    });

    test('同章取时间更新者', () {
      final newer = planNovelRestore(
        local: _doc(
          histories: <NovelBackupHistory>[
            _history('b1', 10, at: DateTime.utc(2026, 11, 1)),
          ],
        ),
        remote: _doc(
          progress: <NovelBackupProgress>[
            _progress(
              'b1',
              10,
              at: DateTime.utc(2026, 11, 20),
              locator: const NovelLocator(chapterIndex: 9, paragraph: 4),
            ),
          ],
        ),
      );
      expect(newer.counts.updated, 1);
      expect(newer.ops.single.payload['locator'], isNotNull);

      final older = planNovelRestore(
        local: _doc(
          histories: <NovelBackupHistory>[
            _history('b1', 10, at: DateTime.utc(2026, 11, 20)),
          ],
        ),
        remote: _doc(
          progress: <NovelBackupProgress>[
            _progress('b1', 10, at: DateTime.utc(2026, 11, 1)),
          ],
        ),
      );
      expect(older.ops, isEmpty);
      expect(older.counts.unchanged, 1);
    });

    test('远端没有这本书：跳过，不造幽灵条目', () {
      final plan = planNovelRestore(
        local: _doc(),
        remote: _doc(progress: <NovelBackupProgress>[_progress('ghost', 5)]),
      );
      expect(plan.ops, isEmpty);
      expect(plan.counts.skipped, 1);
    });

    test('老数据只有 bookId（无 sourceKey）：仍认作同一本', () {
      final plan = planNovelRestore(
        local: _doc(
          histories: <NovelBackupHistory>[
            _history('b1', 2, at: DateTime.utc(2026, 11, 1)),
          ],
        ),
        remote: _doc(
          progress: <NovelBackupProgress>[
            _progress(
              'b1',
              9,
              sourceKey: 'src-a',
              at: DateTime.utc(2026, 11, 5),
            ),
          ],
        ),
      );
      expect(plan.counts.updated, 1);
    });
  });

  group('收藏合并', () {
    test('并集：远端独有 → 新增；本地独有 → 保留不动', () {
      final plan = planNovelRestore(
        local: _doc(
          collects: <NovelBackupCollect>[_collect('b1', '三体', group: '科幻')],
        ),
        remote: _doc(
          collects: <NovelBackupCollect>[
            _collect('b1', '三体', group: '科幻'),
            _collect('b2', '球状闪电'),
          ],
        ),
      );
      expect(plan.counts.added, 1);
      expect(plan.ops.single.key, 'b2');
    });

    test('字段补空：本地无分组，远端有 → 写回远端的分组', () {
      final plan = planNovelRestore(
        local: _doc(collects: <NovelBackupCollect>[_collect('b1', '三体')]),
        remote: _doc(
          collects: <NovelBackupCollect>[
            _collect('b1', '三体', group: '科幻', note: '很好'),
          ],
        ),
      );
      expect(plan.counts.updated, 1);
      expect(plan.ops.single.payload['groupName'], '科幻');
      expect(plan.ops.single.payload['note'], '很好');
    });

    test('分组冲突：两侧都有且不同 → 列冲突，默认保本地', () {
      final plan = planNovelRestore(
        local: _doc(
          collects: <NovelBackupCollect>[_collect('b1', '三体', group: '科幻')],
        ),
        remote: _doc(
          collects: <NovelBackupCollect>[_collect('b1', '三体', group: '待读')],
        ),
      );
      expect(plan.counts.conflicts, 1);
      expect(plan.counts.updated, 0);
      final conflict = plan.conflicts.single;
      expect(conflict.target, NovelBackupTarget.collect);
      expect(conflict.detail, contains('分组'));

      final keepLocal = plan.resolveConflicts(const <String, bool>{});
      expect(keepLocal.ops, isEmpty);

      final takeRemote = plan.resolveConflicts(<String, bool>{
        conflict.id: true,
      });
      expect(takeRemote.ops.single.payload['groupName'], '待读');
    });

    test('系列名称并集', () {
      final plan = planNovelRestore(
        local: _doc(
          series: const <NovelBackupSeries>[NovelBackupSeries(name: '三部曲')],
        ),
        remote: _doc(
          series: const <NovelBackupSeries>[
            NovelBackupSeries(name: '三部曲'),
            NovelBackupSeries(name: '银河帝国'),
          ],
        ),
      );
      expect(plan.counts.added, 1);
      expect(plan.ops.single.key, '银河帝国');
    });
  });

  group('书签 / 划线合并', () {
    test('并集去重：同锚点只留一条', () {
      final plan = planNovelRestore(
        local: _doc(
          bookmarks: <NovelBackupBookmark>[_bookmark('b1', 3, 1, 10)],
        ),
        remote: _doc(
          bookmarks: <NovelBackupBookmark>[
            _bookmark('b1', 3, 1, 10),
            _bookmark('b1', 4, 0, 0),
          ],
        ),
      );
      expect(plan.counts.added, 1);
      expect(plan.ops.single.key, 'b1||4|0|0|0');
    });

    test('同锚点内容不同：列冲突', () {
      final plan = planNovelRestore(
        local: _doc(
          bookmarks: <NovelBackupBookmark>[
            _bookmark('b1', 3, 1, 10, excerpt: '甲'),
          ],
        ),
        remote: _doc(
          bookmarks: <NovelBackupBookmark>[
            _bookmark('b1', 3, 1, 10, excerpt: '乙'),
          ],
        ),
      );
      expect(plan.counts.conflicts, 1);
    });

    test('本地墓碑压过远端较旧的行：不复活', () {
      final deletedAt = DateTime.utc(2026, 11, 20);
      final plan = planNovelRestore(
        local: _doc(
          tombstones: <NovelBackupTombstone>[
            NovelBackupTombstone(
              kind: novelTombstoneBookmark,
              key: _bookmark('b1', 3, 1, 10).key,
              deviceId: 'device-a',
              deletedAt: deletedAt,
            ),
          ],
        ),
        remote: _doc(
          bookmarks: <NovelBackupBookmark>[
            _bookmark('b1', 3, 1, 10, createdAt: DateTime.utc(2026, 11, 1)),
          ],
        ),
      );
      expect(plan.ops, isEmpty);
      expect(plan.counts.skipped, 1);
    });

    test('远端墓碑删掉本地较旧的行', () {
      final plan = planNovelRestore(
        local: _doc(
          bookmarks: <NovelBackupBookmark>[
            _bookmark('b1', 3, 1, 10, createdAt: DateTime.utc(2026, 11, 1)),
          ],
        ),
        remote: _doc(
          tombstones: <NovelBackupTombstone>[
            NovelBackupTombstone(
              kind: novelTombstoneBookmark,
              key: _bookmark('b1', 3, 1, 10).key,
              deviceId: 'device-b',
              deletedAt: DateTime.utc(2026, 11, 20),
            ),
          ],
        ),
      );
      expect(plan.counts.removed, 1);
      expect(plan.ops.first.action, NovelBackupAction.delete);
    });
  });

  group('阅读时长合并', () {
    test('同键取 max，重复导入幂等', () {
      final plan = planNovelRestore(
        local: _doc(
          readRecords: <NovelBackupReadRecord>[
            _record(seconds: 600, lastReadAt: DateTime.utc(2026, 11, 2)),
          ],
        ),
        remote: _doc(
          readRecords: <NovelBackupReadRecord>[
            _record(seconds: 900, lastReadAt: DateTime.utc(2026, 11, 5)),
          ],
        ),
      );
      expect(plan.ops.single.payload['seconds'], 900);
      expect(
        DateTime.parse('${plan.ops.single.payload['lastReadAt']}'),
        DateTime.utc(2026, 11, 5),
      );
    });

    test('两侧一致 → 不动', () {
      final plan = planNovelRestore(
        local: _doc(
          readRecords: <NovelBackupReadRecord>[_record(seconds: 900)],
        ),
        remote: _doc(
          readRecords: <NovelBackupReadRecord>[_record(seconds: 900)],
        ),
      );
      expect(plan.ops, isEmpty);
      expect(plan.counts.unchanged, 1);
    });
  });

  group('设置合并', () {
    test('跨设备共享项：远端赢', () {
      final plan = planNovelRestore(
        local: _doc(
          prefs: <String, String>{novelPrefReaderSettings: '{"font":22}'},
        ),
        remote: _doc(
          prefs: <String, String>{novelPrefReaderSettings: '{"font":26}'},
        ),
      );
      expect(plan.ops.single.payload['value'], '{"font":26}');
    });

    test('设备本地项：本地赢', () {
      final plan = planNovelRestore(
        local: _doc(prefs: <String, String>{novelPrefGoalMinutes: '30'}),
        remote: _doc(prefs: <String, String>{novelPrefGoalMinutes: '90'}),
      );
      expect(plan.ops, isEmpty);
      expect(plan.counts.unchanged, 1);
    });

    test('设备本地项本地缺值时才接受远端', () {
      final plan = planNovelRestore(
        local: _doc(),
        remote: _doc(
          prefs: <String, String>{novelPrefShelfView: '{"layout":"grid"}'},
        ),
      );
      expect(plan.ops.single.payload['value'], '{"layout":"grid"}');
    });

    test('凭据键永不同步', () {
      final plan = planNovelRestore(
        local: _doc(),
        remote: _doc(prefs: <String, String>{'webdav_password': 'secret'}),
      );
      expect(plan.ops, isEmpty);
    });

    test('每书阅读设置按 bookId 并集，冲突保本地', () {
      final plan = planNovelRestore(
        local: _doc(
          prefs: <String, String>{
            novelPrefReaderBookSettings: '{"b1":{"fontSize":30}}',
          },
        ),
        remote: _doc(
          prefs: <String, String>{
            novelPrefReaderBookSettings:
                '{"b1":{"fontSize":20},"b2":{"fontSize":18}}',
          },
        ),
      );
      final value = '${plan.ops.single.payload['value']}';
      expect(value, contains('"b2"'));
      expect(value, contains('30'));
      expect(value, isNot(contains('20')));
    });
  });

  group('书源合并', () {
    test('新 key 新增；同 key 内容不同 → 冲突', () {
      final sourceA = _source('k1', '源甲', url: 'https://a.example');
      final sourceAChanged = _source('k1', '源甲', url: 'https://a2.example');
      final plan = planNovelRestore(
        local: _doc(sources: <NovelBookSource>[sourceA]),
        remote: _doc(
          sources: <NovelBookSource>[sourceAChanged, _source('k2', '源乙')],
        ),
      );
      expect(plan.counts.added, 1);
      expect(plan.counts.conflicts, 1);
      expect(plan.conflicts.single.target, NovelBackupTarget.source);
    });
  });

  test('计数与分类明细：预览页同一份数据', () {
    final plan = planNovelRestore(
      local: _doc(
        collects: <NovelBackupCollect>[_collect('b1', '三体', group: '科幻')],
        histories: <NovelBackupHistory>[
          _history('b1', 10, at: DateTime.utc(2026, 11, 1)),
        ],
      ),
      remote: _doc(
        collects: <NovelBackupCollect>[
          _collect('b1', '三体', group: '科幻'),
          _collect('b2', '球状闪电'),
          _collect('b3', '全频带阻塞', group: '待读'),
        ],
        progress: <NovelBackupProgress>[_progress('b1', 12)],
        searchKeywords: const <String>['三体'],
      ),
    );
    final counts = plan.counts;
    expect(counts.added, 3); // b2, b3, 搜索词
    expect(counts.updated, 1); // 进度
    expect(counts.total, counts.added + counts.updated + counts.removed);
    expect(counts.summary, '新增 3 · 更新 1 · 冲突 0');
    final collectRow = plan.byTarget.firstWhere(
      (row) => row.target == NovelBackupTarget.collect,
    );
    expect(collectRow.added, 2);
  });
}

// ── 测试夹具 ────────────────────────────────────────────────────────────────

NovelBackupDocument _doc({
  List<NovelBackupCollect> collects = const <NovelBackupCollect>[],
  List<NovelBackupHistory> histories = const <NovelBackupHistory>[],
  List<String> searchKeywords = const <String>[],
  List<NovelBookSource> sources = const <NovelBookSource>[],
  Map<String, String> prefs = const <String, String>{},
  List<NovelBackupProgress> progress = const <NovelBackupProgress>[],
  List<NovelBackupSeries> series = const <NovelBackupSeries>[],
  List<NovelBackupBookmark> bookmarks = const <NovelBackupBookmark>[],
  List<NovelBackupMarking> markings = const <NovelBackupMarking>[],
  List<NovelBackupReadRecord> readRecords = const <NovelBackupReadRecord>[],
  List<NovelBackupTombstone> tombstones = const <NovelBackupTombstone>[],
}) => NovelBackupDocument(
  collects: collects,
  histories: histories,
  searchKeywords: searchKeywords,
  sources: sources,
  prefs: prefs,
  exportedAt: DateTime.utc(2026, 11, 25),
  deviceId: 'device-local',
  progress: progress,
  series: series,
  bookmarks: bookmarks,
  markings: markings,
  readRecords: readRecords,
  tombstones: tombstones,
);

NovelSummary _book(String id, String title) =>
    NovelSummary(id: id, title: title, coverUrl: '');

NovelBackupProgress _progress(
  String id,
  int chapter, {
  String sourceKey = '',
  DateTime? at,
  NovelLocator? locator,
}) => NovelBackupProgress(
  bookId: id,
  sourceKey: sourceKey,
  chapterIndex: chapter,
  chapterCount: 400,
  updatedAt: at,
  locator: locator,
);

NovelBackupCollect _collect(
  String id,
  String title, {
  String? group,
  String note = '',
  String? series,
}) => NovelBackupCollect(
  book: _book(id, title),
  groupName: group,
  note: note,
  seriesName: series,
  updatedAt: DateTime.utc(2026, 11, 1),
);

NovelBackupHistory _history(String id, int chapter, {DateTime? at}) =>
    NovelBackupHistory(
      book: _book(id, '书$id'),
      chapterIndex: chapter,
      chapterCount: 400,
      openedAt: at,
    );

NovelBackupBookmark _bookmark(
  String id,
  int chapter,
  int paragraph,
  int offset, {
  String excerpt = '',
  DateTime? createdAt,
}) => NovelBackupBookmark(
  bookId: id,
  chapterIndex: chapter,
  paragraph: paragraph,
  charOffset: offset,
  excerpt: excerpt,
  createdAt: createdAt ?? DateTime.utc(2026, 11, 1),
);

NovelBackupReadRecord _record({int seconds = 600, DateTime? lastReadAt}) {
  final at = lastReadAt ?? DateTime.utc(2026, 11, 1);
  return NovelBackupReadRecord(
    deviceId: 'device-a',
    bookId: 'b1',
    chapterIndex: 3,
    day: '2026-11-01',
    seconds: seconds,
    firstReadAt: DateTime.utc(2026, 11, 1),
    lastReadAt: at,
  );
}

NovelBookSource _source(String key, String name, {String url = ''}) =>
    NovelBookSource(
      key: key,
      name: name,
      url: url,
      type: 0,
      enabled: true,
      raw: const <String, dynamic>{},
    );
