// 书签 / 划线 / 笔记服务：`bookmark` 与 `marking` 两张表的唯一读写口。
//
// 页面和阅读控制器只依赖 [NovelBookmarkApi] 窄接口（测试可注入内存 fake），
// drift 细节留在本文件。所有写操作都做三件事：
// 1. 锚点去重（同一位置重复加 = 删）；
// 2. 区间校验（start/end 交换、越界 clamp，空区间不落库）；
// 3. 换源后按「章标题归一 + 段落序号」尽力重定位，失败标 unresolved 而不是删行。

import 'package:drift/drift.dart';
import 'package:mimao/novel/backup/novel_tombstone_service.dart';
import 'package:mimao/novel/bookmark/novel_bookmark_models.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';

/// 一次「加/删书签」的结果：同一位置再点即删。
class NovelBookmarkToggleResult {
  const NovelBookmarkToggleResult({
    required this.bookmark,
    required this.removed,
  });

  /// 删除时是被删掉的那条；新增时是刚写入的（含 id）。
  final NovelBookmark bookmark;

  /// true = 命中已有书签并删除；false = 新建。
  final bool removed;
}

/// 书签/划线门面。
abstract interface class NovelBookmarkApi {
  /// 一本书的全部书签，按创建时间倒序。
  Future<List<NovelBookmark>> bookmarksForBook(
    String bookId, {
    String? sourceKey,
  });

  /// 全部书的书签（「我的 → 书签」，按创建时间倒序）。
  Future<List<NovelBookmark>> allBookmarks({int limit = 500});

  /// 目录角标：有书签的章下标集合。
  Future<Set<int>> bookmarkedChapterIndexes(String bookId, {String? sourceKey});

  /// 精确位置查书签；没有返回 null。
  Future<NovelBookmark?> bookmarkAt(NovelTextAnchor anchor);

  /// 同一位置再点即删；否则新建。
  Future<NovelBookmarkToggleResult> toggleBookmark({
    required NovelTextAnchor anchor,
    required String chapterName,
    String bookTitle = '',
    String bookAuthor = '',
    String bookUrl = '',
    String excerpt = '',
    DateTime? now,
  });

  /// 显式新建（不查重时用；仍会覆盖同位置旧行）。
  Future<NovelBookmark> addBookmark({
    required NovelTextAnchor anchor,
    required String chapterName,
    String bookTitle = '',
    String bookAuthor = '',
    String bookUrl = '',
    String excerpt = '',
    DateTime? now,
  });

  Future<bool> removeBookmark(int id);

  Future<void> removeBookmarksForBook(String bookId);

  /// 一章的全部划线，按段落、起点升序。
  Future<List<NovelMarking>> markingsForChapter(
    String bookId,
    int chapterIndex, {
    String? sourceKey,
  });

  /// 新建划线/笔记；区间非法（空/越界到 0 长）时返回 null 并拒绝落库。
  Future<NovelMarking?> addMarking({
    required NovelTextAnchor anchor,
    required int endOffset,
    required NovelMarkingStyle style,
    String note = '',
    required String chapterName,
    String bookTitle = '',
    String bookAuthor = '',
    String bookUrl = '',
    int? paragraphLength,
    DateTime? now,
  });

  /// 改样式 / 备注 / 区间。区间仍走同一套校验。
  Future<NovelMarking?> updateMarking(
    int id, {
    NovelMarkingStyle? style,
    String? note,
    int? startOffset,
    int? endOffset,
    int? paragraphLength,
    DateTime? now,
  });

  Future<bool> removeMarking(int id);

  /// 换源后重定位：按归一化章标题找新章下标；找不到标 unresolved。
  Future<NovelRelocateResult> relocateBookmarks(
    String bookId,
    List<NovelChapter> chapters, {
    String sourceKey = '',
  });

  Future<NovelRelocateResult> relocateMarkings(
    String bookId,
    List<NovelChapter> chapters, {
    String sourceKey = '',
  });
}

/// drift 实现。`NovelDb` 与阅读器共用同一实例（装配处注入）。
class NovelBookmarkService implements NovelBookmarkApi {
  NovelBookmarkService(this.db);

  final NovelDb db;

  /// 删除墓碑：书签/划线的删除要能跨设备传播，否则合并只会把旧副本复活。
  late final NovelTombstoneService _tombstones = NovelTombstoneService(db);

  @override
  Future<List<NovelBookmark>> bookmarksForBook(
    String bookId, {
    String? sourceKey,
  }) async {
    final query = db.select(db.novelBookmarkEntries)
      ..where((t) => t.bookId.equals(bookId));
    if (sourceKey != null && sourceKey.isNotEmpty) {
      query.where((t) => t.sourceKey.equals(sourceKey));
    }
    query.orderBy([
      (t) => OrderingTerm.desc(t.createdAt),
      (t) => OrderingTerm.desc(t.id),
    ]);
    final rows = await query.get();
    return <NovelBookmark>[for (final row in rows) _bookmarkOf(row)];
  }

  @override
  Future<List<NovelBookmark>> allBookmarks({int limit = 500}) async {
    final rows =
        await (db.select(db.novelBookmarkEntries)
              ..orderBy([
                (t) => OrderingTerm.desc(t.createdAt),
                (t) => OrderingTerm.desc(t.id),
              ])
              ..limit(limit))
            .get();
    return <NovelBookmark>[for (final row in rows) _bookmarkOf(row)];
  }

  @override
  Future<Set<int>> bookmarkedChapterIndexes(
    String bookId, {
    String? sourceKey,
  }) async {
    final query = db.selectOnly(db.novelBookmarkEntries)
      ..addColumns(<Expression<Object>>[db.novelBookmarkEntries.chapterIndex])
      ..where(db.novelBookmarkEntries.bookId.equals(bookId));
    if (sourceKey != null && sourceKey.isNotEmpty) {
      query.where(db.novelBookmarkEntries.sourceKey.equals(sourceKey));
    }
    final rows = await query.get();
    return <int>{
      for (final row in rows)
        row.read(db.novelBookmarkEntries.chapterIndex) ?? 0,
    };
  }

  @override
  Future<NovelBookmark?> bookmarkAt(NovelTextAnchor anchor) async {
    final row = await _findBookmarkRow(anchor);
    return row == null ? null : _bookmarkOf(row);
  }

  @override
  Future<NovelBookmarkToggleResult> toggleBookmark({
    required NovelTextAnchor anchor,
    required String chapterName,
    String bookTitle = '',
    String bookAuthor = '',
    String bookUrl = '',
    String excerpt = '',
    DateTime? now,
  }) async {
    return db.transaction(() async {
      final existing = await _findBookmarkRow(anchor);
      if (existing != null) {
        final removed = _bookmarkOf(existing);
        await _tombstones.recordBookmark(existing);
        await (db.delete(
          db.novelBookmarkEntries,
        )..where((t) => t.id.equals(existing.id))).go();
        return NovelBookmarkToggleResult(bookmark: removed, removed: true);
      }
      final created = await addBookmark(
        anchor: anchor,
        chapterName: chapterName,
        bookTitle: bookTitle,
        bookAuthor: bookAuthor,
        bookUrl: bookUrl,
        excerpt: excerpt,
        now: now,
      );
      return NovelBookmarkToggleResult(bookmark: created, removed: false);
    });
  }

  @override
  Future<NovelBookmark> addBookmark({
    required NovelTextAnchor anchor,
    required String chapterName,
    String bookTitle = '',
    String bookAuthor = '',
    String bookUrl = '',
    String excerpt = '',
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    // 同位置先删再插：即使并发/历史脏数据漏进两条，也收敛成一条。
    final existing = await _findBookmarkRow(anchor);
    if (existing != null) {
      await (db.delete(
        db.novelBookmarkEntries,
      )..where((t) => t.id.equals(existing.id))).go();
    }
    final id = await db
        .into(db.novelBookmarkEntries)
        .insert(
          NovelBookmarkEntriesCompanion.insert(
            bookId: anchor.bookId,
            sourceKey: Value(anchor.sourceKey),
            bookTitle: Value(bookTitle),
            bookAuthor: Value(bookAuthor),
            bookUrl: Value(bookUrl),
            chapterIndex: anchor.chapterIndex,
            paragraph: Value(anchor.paragraph),
            charOffset: Value(anchor.charOffset),
            chapterName: Value(chapterName),
            excerpt: Value(excerpt),
            createdAt: at,
          ),
        );
    return NovelBookmark(
      id: id,
      bookId: anchor.bookId,
      sourceKey: anchor.sourceKey,
      bookTitle: bookTitle,
      bookAuthor: bookAuthor,
      bookUrl: bookUrl,
      chapterIndex: anchor.chapterIndex,
      paragraph: anchor.paragraph,
      charOffset: anchor.charOffset,
      chapterName: chapterName,
      excerpt: excerpt,
      createdAt: at,
    );
  }

  @override
  Future<bool> removeBookmark(int id) async {
    final row = await (db.select(
      db.novelBookmarkEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return false;
    await _tombstones.recordBookmark(row);
    final affected = await (db.delete(
      db.novelBookmarkEntries,
    )..where((t) => t.id.equals(id))).go();
    return affected > 0;
  }

  @override
  Future<void> removeBookmarksForBook(String bookId) async {
    final rows = await (db.select(
      db.novelBookmarkEntries,
    )..where((t) => t.bookId.equals(bookId))).get();
    for (final row in rows) {
      await _tombstones.recordBookmark(row);
    }
    await (db.delete(
      db.novelBookmarkEntries,
    )..where((t) => t.bookId.equals(bookId))).go();
  }

  @override
  Future<List<NovelMarking>> markingsForChapter(
    String bookId,
    int chapterIndex, {
    String? sourceKey,
  }) async {
    final query = db.select(db.novelMarkingEntries)
      ..where(
        (t) =>
            t.bookId.equals(bookId) &
            t.chapterIndex.equals(chapterIndex) &
            (sourceKey == null || sourceKey.isEmpty
                ? const Constant(true)
                : t.sourceKey.equals(sourceKey)),
      );
    query.orderBy([
      (t) => OrderingTerm.asc(t.paragraph),
      (t) => OrderingTerm.asc(t.startOffset),
      (t) => OrderingTerm.asc(t.id),
    ]);
    final rows = await query.get();
    return <NovelMarking>[for (final row in rows) _markingOf(row)];
  }

  @override
  Future<NovelMarking?> addMarking({
    required NovelTextAnchor anchor,
    required int endOffset,
    required NovelMarkingStyle style,
    String note = '',
    required String chapterName,
    String bookTitle = '',
    String bookAuthor = '',
    String bookUrl = '',
    int? paragraphLength,
    DateTime? now,
  }) async {
    final range = _validRange(
      start: anchor.charOffset,
      end: endOffset,
      paragraphLength: paragraphLength,
    );
    if (range == null) return null;
    final at = now ?? DateTime.now();
    final id = await db
        .into(db.novelMarkingEntries)
        .insert(
          NovelMarkingEntriesCompanion.insert(
            bookId: anchor.bookId,
            sourceKey: Value(anchor.sourceKey),
            bookTitle: Value(bookTitle),
            bookAuthor: Value(bookAuthor),
            bookUrl: Value(bookUrl),
            chapterIndex: anchor.chapterIndex,
            paragraph: Value(anchor.paragraph),
            startOffset: Value(range.start),
            endOffset: Value(range.end),
            chapterName: Value(chapterName),
            styleJson: Value(style.encode()),
            note: Value(note),
            createdAt: at,
            updatedAt: at,
          ),
        );
    return NovelMarking(
      id: id,
      bookId: anchor.bookId,
      sourceKey: anchor.sourceKey,
      bookTitle: bookTitle,
      bookAuthor: bookAuthor,
      bookUrl: bookUrl,
      chapterIndex: anchor.chapterIndex,
      paragraph: anchor.paragraph,
      startOffset: range.start,
      endOffset: range.end,
      style: style,
      note: note,
      chapterName: chapterName,
      createdAt: at,
      updatedAt: at,
    );
  }

  @override
  Future<NovelMarking?> updateMarking(
    int id, {
    NovelMarkingStyle? style,
    String? note,
    int? startOffset,
    int? endOffset,
    int? paragraphLength,
    DateTime? now,
  }) async {
    final row = await (db.select(
      db.novelMarkingEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    var nextStart = startOffset ?? row.startOffset;
    var nextEnd = endOffset ?? row.endOffset;
    if (startOffset != null || endOffset != null) {
      final range = _validRange(
        start: nextStart,
        end: nextEnd,
        paragraphLength: paragraphLength,
      );
      if (range == null) return null;
      nextStart = range.start;
      nextEnd = range.end;
    }
    final nextStyle = style ?? _markingOf(row).style;
    final at = now ?? DateTime.now();
    await (db.update(
      db.novelMarkingEntries,
    )..where((t) => t.id.equals(id))).write(
      NovelMarkingEntriesCompanion(
        startOffset: Value(nextStart),
        endOffset: Value(nextEnd),
        styleJson: Value(nextStyle.encode()),
        note: note == null ? const Value.absent() : Value(note),
        updatedAt: Value(at),
      ),
    );
    return _markingOf(
      NovelMarkingRow(
        id: row.id,
        bookId: row.bookId,
        sourceKey: row.sourceKey,
        bookTitle: row.bookTitle,
        bookAuthor: row.bookAuthor,
        bookUrl: row.bookUrl,
        chapterIndex: row.chapterIndex,
        paragraph: row.paragraph,
        startOffset: nextStart,
        endOffset: nextEnd,
        chapterName: row.chapterName,
        styleJson: nextStyle.encode(),
        note: note ?? row.note,
        unresolved: row.unresolved,
        createdAt: row.createdAt,
        updatedAt: at,
      ),
    );
  }

  @override
  Future<bool> removeMarking(int id) async {
    final row = await (db.select(
      db.novelMarkingEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return false;
    await _tombstones.recordMarking(row);
    final affected = await (db.delete(
      db.novelMarkingEntries,
    )..where((t) => t.id.equals(id))).go();
    return affected > 0;
  }

  @override
  Future<NovelRelocateResult> relocateBookmarks(
    String bookId,
    List<NovelChapter> chapters, {
    String sourceKey = '',
  }) {
    return _relocate(
      bookId: bookId,
      chapters: chapters,
      sourceKey: sourceKey,
      rows: () => (db.select(
        db.novelBookmarkEntries,
      )..where((t) => t.bookId.equals(bookId))).get(),
      apply: (row, chapterIndex, unresolved) =>
          (db.update(
            db.novelBookmarkEntries,
          )..where((t) => t.id.equals(row.id))).write(
            NovelBookmarkEntriesCompanion(
              chapterIndex: Value(chapterIndex),
              // 没找回来的行继续挂旧源：新源目录里没有它，改了源反而会让它
              // 从「无法定位」列表里消失。
              sourceKey: (sourceKey.isEmpty || unresolved)
                  ? const Value.absent()
                  : Value(sourceKey),
              unresolved: Value(unresolved),
            ),
          ),
      chapterIndexOf: (row) => row.chapterIndex,
      nameOf: (row) => row.chapterName,
    );
  }

  @override
  Future<NovelRelocateResult> relocateMarkings(
    String bookId,
    List<NovelChapter> chapters, {
    String sourceKey = '',
  }) {
    return _relocate(
      bookId: bookId,
      chapters: chapters,
      sourceKey: sourceKey,
      rows: () => (db.select(
        db.novelMarkingEntries,
      )..where((t) => t.bookId.equals(bookId))).get(),
      apply: (row, chapterIndex, unresolved) =>
          (db.update(
            db.novelMarkingEntries,
          )..where((t) => t.id.equals(row.id))).write(
            NovelMarkingEntriesCompanion(
              chapterIndex: Value(chapterIndex),
              sourceKey: (sourceKey.isEmpty || unresolved)
                  ? const Value.absent()
                  : Value(sourceKey),
              unresolved: Value(unresolved),
            ),
          ),
      chapterIndexOf: (row) => row.chapterIndex,
      nameOf: (row) => row.chapterName,
    );
  }

  /// 两类行（书签/划线）共用的重定位流程。
  Future<NovelRelocateResult> _relocate<T>({
    required String bookId,
    required List<NovelChapter> chapters,
    required String sourceKey,
    required Future<List<T>> Function() rows,
    required Future<void> Function(T row, int chapterIndex, bool unresolved)
    apply,
    required int Function(T row) chapterIndexOf,
    required String Function(T row) nameOf,
  }) async {
    final all = await rows();
    if (all.isEmpty) {
      return const NovelRelocateResult(total: 0, relocated: 0, unresolved: 0);
    }
    final indexByTitle = <String, int>{};
    for (var i = 0; i < chapters.length; i++) {
      final chapter = chapters[i];
      if (chapter.isVolume) continue;
      final key = normalizeNovelChapterTitle(chapter.title);
      if (key.isEmpty) continue;
      indexByTitle.putIfAbsent(key, () => i);
    }

    var relocated = 0;
    var unresolved = 0;
    await db.transaction(() async {
      for (final row in all) {
        final key = normalizeNovelChapterTitle(nameOf(row));
        if (key.isNotEmpty && indexByTitle.containsKey(key)) {
          relocated++;
          await apply(row, indexByTitle[key]!, false);
          continue;
        }
        final index = chapterIndexOf(row);
        final hasValidIndex =
            index >= 0 && index < chapters.length && !chapters[index].isVolume;
        if (key.isEmpty && hasValidIndex) {
          // 老数据没存章名：索引还在范围内就不算失败，保持可用。
          relocated++;
          await apply(row, index, false);
          continue;
        }
        unresolved++;
        await apply(row, index, true);
      }
    });
    return NovelRelocateResult(
      total: all.length,
      relocated: relocated,
      unresolved: unresolved,
    );
  }

  ({int start, int end})? _validRange({
    required int start,
    required int end,
    required int? paragraphLength,
  }) {
    if (paragraphLength != null) {
      return normalizeNovelMarkingRange(
        start: start,
        end: end,
        paragraphLength: paragraphLength,
      );
    }
    // 调用方没给段落长度（例如正文还没加载）：至少保证 start < end。
    var from = start < 0 ? 0 : start;
    var to = end < 0 ? 0 : end;
    if (from > to) {
      final swap = from;
      from = to;
      to = swap;
    }
    if (to <= from) return null;
    return (start: from, end: to);
  }

  Future<NovelBookmarkRow?> _findBookmarkRow(NovelTextAnchor anchor) {
    return (db.select(db.novelBookmarkEntries)..where(
          (t) =>
              t.bookId.equals(anchor.bookId) &
              t.sourceKey.equals(anchor.sourceKey) &
              t.chapterIndex.equals(anchor.chapterIndex) &
              t.paragraph.equals(anchor.paragraph) &
              t.charOffset.equals(anchor.charOffset),
        ))
        .getSingleOrNull();
  }

  NovelBookmark _bookmarkOf(NovelBookmarkRow row) => NovelBookmark(
    id: row.id,
    bookId: row.bookId,
    sourceKey: row.sourceKey,
    bookTitle: row.bookTitle,
    bookAuthor: row.bookAuthor,
    bookUrl: row.bookUrl,
    chapterIndex: row.chapterIndex,
    paragraph: row.paragraph,
    charOffset: row.charOffset,
    chapterName: row.chapterName,
    excerpt: row.excerpt,
    unresolved: row.unresolved,
    createdAt: row.createdAt,
  );

  NovelMarking _markingOf(NovelMarkingRow row) => NovelMarking(
    id: row.id,
    bookId: row.bookId,
    sourceKey: row.sourceKey,
    bookTitle: row.bookTitle,
    bookAuthor: row.bookAuthor,
    bookUrl: row.bookUrl,
    chapterIndex: row.chapterIndex,
    paragraph: row.paragraph,
    startOffset: row.startOffset,
    endOffset: row.endOffset,
    style: NovelMarkingStyle.decode(row.styleJson),
    note: row.note,
    chapterName: row.chapterName,
    unresolved: row.unresolved,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );
}
