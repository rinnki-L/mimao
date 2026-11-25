/// 单章正文本地覆盖：`novel_content_override` 表的唯一读写口。
///
/// 语义与 legado 的「正文编辑」一致：用户改过的章节落本地，下次打开这本书
/// 优先用它；「恢复原样」只删这一章的覆盖，网络/缓存正文照旧可用。
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';

/// 一章的稳定覆盖键：优先章节 id（引擎里通常是章节 URL），其次 url，
/// 最后退到「章下标 + 标题」——与阅读器/编辑页共用，避免两处各算一套。
String novelChapterOverrideKey(NovelChapter chapter) {
  if (chapter.id.isNotEmpty) return chapter.id;
  if (chapter.url.isNotEmpty) return chapter.url;
  return '${chapter.index}:${chapter.title}';
}

/// 内容覆盖仓库窄接口（阅读控制器 / 编辑页共用）。
abstract interface class NovelContentOverrideStorage {
  /// 读一章的本地覆盖；没有返回 null。
  Future<NovelContent?> load({
    required String bookId,
    required String sourceKey,
    required String chapterKey,
  });

  /// 有覆盖就返回 true（编辑页据此显示「恢复原样」）。
  Future<bool> has({
    required String bookId,
    required String sourceKey,
    required String chapterKey,
  });

  /// 写入/覆盖一章的正文；段落按顺序落 JSON 数组。
  Future<void> save({
    required String bookId,
    required String sourceKey,
    required String chapterKey,
    required String chapterTitle,
    required List<String> paragraphs,
    String title = '',
    DateTime? now,
  });

  /// 删除这一章的覆盖；返回是否真的删了。
  Future<bool> remove({
    required String bookId,
    required String sourceKey,
    required String chapterKey,
  });
}

/// drift 实现，与阅读器、书签共用同一个 [NovelDb]。
class NovelContentOverrideService implements NovelContentOverrideStorage {
  NovelContentOverrideService(this._db);

  final NovelDb _db;

  @override
  Future<NovelContent?> load({
    required String bookId,
    required String sourceKey,
    required String chapterKey,
  }) async {
    final row = await _row(bookId, sourceKey, chapterKey);
    if (row == null) return null;
    final paragraphs = _decodeParagraphs(row.paragraphsJson);
    if (paragraphs.isEmpty) return null;
    final title = row.title.trim();
    return NovelContent(
      chapterId: row.chapterKey,
      title: title.isEmpty ? row.chapterTitle : title,
      paragraphs: paragraphs,
    );
  }

  @override
  Future<bool> has({
    required String bookId,
    required String sourceKey,
    required String chapterKey,
  }) async => await _row(bookId, sourceKey, chapterKey) != null;

  @override
  Future<void> save({
    required String bookId,
    required String sourceKey,
    required String chapterKey,
    required String chapterTitle,
    required List<String> paragraphs,
    String title = '',
    DateTime? now,
  }) async {
    final cleaned = <String>[
      for (final paragraph in paragraphs)
        if (paragraph.trim().isNotEmpty) paragraph,
    ];
    await _db
        .into(_db.novelContentOverrides)
        .insertOnConflictUpdate(
          NovelContentOverridesCompanion.insert(
            bookId: bookId,
            sourceKey: Value(sourceKey),
            chapterKey: chapterKey,
            chapterTitle: Value(chapterTitle),
            title: Value(title),
            paragraphsJson: jsonEncode(cleaned),
            paragraphCount: Value(cleaned.length),
            updatedAt: now ?? DateTime.now(),
          ),
        );
  }

  @override
  Future<bool> remove({
    required String bookId,
    required String sourceKey,
    required String chapterKey,
  }) async {
    final removed =
        await (_db.delete(_db.novelContentOverrides)..where(
              (table) =>
                  table.bookId.equals(bookId) &
                  table.sourceKey.equals(sourceKey) &
                  table.chapterKey.equals(chapterKey),
            ))
            .go();
    return removed > 0;
  }

  Future<NovelContentOverrideRow?> _row(
    String bookId,
    String sourceKey,
    String chapterKey,
  ) =>
      (_db.select(_db.novelContentOverrides)..where(
            (table) =>
                table.bookId.equals(bookId) &
                table.sourceKey.equals(sourceKey) &
                table.chapterKey.equals(chapterKey),
          ))
          .getSingleOrNull();

  List<String> _decodeParagraphs(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      return <String>[
        for (final item in decoded)
          if (item is String && item.trim().isNotEmpty) item,
      ];
    } on Object {
      return const <String>[];
    }
  }
}
