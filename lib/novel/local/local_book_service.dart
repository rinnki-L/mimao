/// 本地书的持久化与读写门面：探测 → 导入 → 目录 → 正文 → 重新定位。
///
/// 页面与引擎只依赖 [NovelLocalBookStorage] 窄接口；drift 细节留在本文件，
/// 测试注入 `NovelDb.forTesting(NativeDatabase.memory())` + 内存文件即可跑通，
/// 不碰真实文件系统。
///
/// 目录**落库**（`tocJson`）：打开书不必每次重扫全文，几 MB 的 TXT 只在导入
/// 与「重新分章」时扫一次。正文按章节的字节区间现读现解，不缓存全文。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:mimao/novel/local/local_encoding.dart';
import 'package:mimao/novel/local/local_epub.dart';
import 'package:mimao/novel/local/local_models.dart';
import 'package:mimao/novel/local/local_source.dart';
import 'package:mimao/novel/local/local_txt.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:path/path.dart' as p;

/// 本地书门面。
abstract interface class NovelLocalBookStorage {
  /// 全量列表（按导入时间倒序）。
  Future<List<NovelLocalBook>> list();

  /// 单本；null = 没导入过。
  Future<NovelLocalBook?> byId(String id);

  /// 探测一个文件（不落库）：格式、编码、目录、警告。
  Future<NovelLocalProbe> probe(
    NovelLocalBytes source, {
    String? titleHint,
    List<NovelTxtRule>? rules,
    void Function(double progress)? onProgress,
  });

  /// 导入（幂等：同一路径重复导入会更新目录与元数据，保留 id 与阅读进度）。
  Future<NovelLocalBook> importBook(
    NovelLocalBytes source, {
    String? titleHint,
    List<NovelTxtRule>? rules,
    void Function(double progress)? onProgress,
  });

  /// 用新规则重新分章（不改路径、不动阅读进度，进度可能落到别的章上）。
  Future<NovelLocalBook> resplit(
    String id, {
    List<NovelTxtRule>? rules,
    void Function(double progress)? onProgress,
  });

  /// 把某本书指到新路径（文件被移动后「重新定位」）。
  Future<NovelLocalBook> relocate(String id, String newPath);

  /// 删除导入记录（不删用户的文件）。
  Future<void> delete(String id);

  /// 读某一章的正文段落。
  Future<List<String>> readChapter(NovelLocalBook book, int chapterIndex);

  /// 探测时用的规则（未显式传时从规则服务取）。
  Future<List<NovelTxtRule>> rulesOrDefault();
}

/// 导入结果 + 探测信息（导入页一次拿全）。
class NovelLocalImportResult {
  const NovelLocalImportResult({required this.book, required this.probe});

  final NovelLocalBook book;
  final NovelLocalProbe probe;
}

/// drift + 真实文件实现。
class NovelLocalBookService implements NovelLocalBookStorage {
  NovelLocalBookService(
    this._db, {
    NovelTxtRuleStorage? rules,
    NovelLocalBytes Function(String path)? opener,
  }) : _rules = rules,
       _open = opener ?? NovelLocalFile.new;

  final NovelDb _db;
  final NovelTxtRuleStorage? _rules;

  /// 按落库路径重新打开文件。生产是 [NovelLocalFile]；测试注入内存文件，
  /// 「读正文」「重新分章」「重新定位」就完全不碰真实文件系统。
  final NovelLocalBytes Function(String path) _open;

  @override
  Future<List<NovelLocalBook>> list() async {
    final rows =
        await (_db.select(_db.novelLocalBooks)
              ..orderBy(<OrderClauseGenerator<$NovelLocalBooksTable>>[
                (table) => OrderingTerm.desc(table.addedAt),
              ]))
            .get();
    return <NovelLocalBook>[for (final row in rows) _fromRow(row)];
  }

  @override
  Future<NovelLocalBook?> byId(String id) async {
    final row = await (_db.select(
      _db.novelLocalBooks,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<List<NovelTxtRule>> rulesOrDefault() async {
    final storage = _rules;
    if (storage == null) return novelDefaultTxtRules;
    try {
      final rules = await storage.loadAll();
      return rules.isEmpty ? novelDefaultTxtRules : rules;
    } on Object {
      // 规则表读坏了不该让导入不可用：退回内置规则。
      return novelDefaultTxtRules;
    }
  }

  @override
  Future<NovelLocalProbe> probe(
    NovelLocalBytes source, {
    String? titleHint,
    List<NovelTxtRule>? rules,
    void Function(double progress)? onProgress,
  }) async {
    final format = NovelLocalFormat.fromPath(source.path);
    if (format == null) {
      throw NovelEpubFormatException(
        '不支持的文件类型：${p.basename(source.path)}。'
        '目前支持 TXT / EPUB / Markdown（.txt / .epub / .md）。',
      );
    }
    final size = await source.length();
    final fallbackTitle = _titleFromPath(source.path, titleHint);

    switch (format) {
      case NovelLocalFormat.epub:
        final epub = await parseNovelEpub(source);
        return NovelLocalProbe(
          format: format,
          title: _titleFromPath(source.path, titleHint).isEmpty
              ? epub.title
              : _titleFromPath(source.path, titleHint),
          author: epub.author,
          byteSize: size,
          toc: NovelLocalToc(chapters: epub.chapters, warning: epub.warning),
          warning: epub.warning,
        );
      case NovelLocalFormat.txt:
      case NovelLocalFormat.markdown:
        final head = await source.read(0, novelSniffWindow);
        final guess = sniffNovelEncoding(head);
        final effective = rules ?? await rulesOrDefault();
        final split = format == NovelLocalFormat.markdown
            ? await splitNovelMarkdown(source: source, encoding: guess.encoding)
            : await splitNovelTxt(
                source: source,
                encoding: guess.encoding,
                rules: effective,
                onProgress: onProgress,
              );
        final warnings = <String>[
          if (guess.warning != null) guess.warning!,
          if (split.warning != null) split.warning!,
        ];
        return NovelLocalProbe(
          format: format,
          title: fallbackTitle,
          byteSize: size,
          toc: NovelLocalToc(chapters: split.chapters, warning: split.warning),
          encoding: guess.encoding,
          lossy: guess.lossy,
          warning: warnings.isEmpty ? null : warnings.join('\n'),
        );
    }
  }

  @override
  Future<NovelLocalBook> importBook(
    NovelLocalBytes source, {
    String? titleHint,
    List<NovelTxtRule>? rules,
    void Function(double progress)? onProgress,
  }) async {
    final probed = await probe(
      source,
      titleHint: titleHint,
      rules: rules,
      onProgress: onProgress,
    );
    final id = novelLocalBookId(source.path);
    final now = DateTime.now();
    await _db
        .into(_db.novelLocalBooks)
        .insertOnConflictUpdate(
          NovelLocalBooksCompanion.insert(
            id: id,
            path: source.path,
            title: probed.title,
            author: Value(probed.author),
            format: probed.format.key,
            encoding: Value(probed.encoding?.key),
            byteSize: Value(probed.byteSize),
            chapterCount: Value(probed.toc.chapters.length),
            tocJson: Value(probed.toc.encode()),
            // 重复导入保留首次导入时间：书架排序不该因为「又点了一次导入」跳到最前。
            addedAt: now,
          ),
        );
    final saved = await byId(id);
    return saved ??
        NovelLocalBook(
          id: id,
          path: source.path,
          title: probed.title,
          author: probed.author,
          format: probed.format,
          encoding: probed.encoding,
          byteSize: probed.byteSize,
          chapterCount: probed.toc.chapters.length,
          chapters: probed.toc.chapters,
          addedAt: now,
        );
  }

  @override
  Future<NovelLocalBook> resplit(
    String id, {
    List<NovelTxtRule>? rules,
    void Function(double progress)? onProgress,
  }) async {
    final book = await byId(id);
    if (book == null) {
      throw NovelLocalFileMissing(id, '这本书不在本地书库里');
    }
    final source = _open(book.path);
    final probed = await probe(
      source,
      titleHint: book.title,
      rules: rules,
      onProgress: onProgress,
    );
    await (_db.update(
      _db.novelLocalBooks,
    )..where((t) => t.id.equals(id))).write(
      NovelLocalBooksCompanion(
        chapterCount: Value(probed.toc.chapters.length),
        tocJson: Value(probed.toc.encode()),
        byteSize: Value(probed.byteSize),
        encoding: Value(probed.encoding?.key),
      ),
    );
    final updated = await byId(id);
    return updated ?? book;
  }

  @override
  Future<NovelLocalBook> relocate(String id, String newPath) async {
    final book = await byId(id);
    if (book == null) {
      throw NovelLocalFileMissing(id, '这本书不在本地书库里');
    }
    final source = _open(newPath);
    // 先确认新文件真能读出目录，再改库：改完才发现读不了会让用户以为修好了。
    final probed = await probe(source, titleHint: book.title);
    await (_db.update(
      _db.novelLocalBooks,
    )..where((t) => t.id.equals(id))).write(
      NovelLocalBooksCompanion(
        path: Value(newPath),
        format: Value(probed.format.key),
        encoding: Value(probed.encoding?.key),
        byteSize: Value(probed.byteSize),
        chapterCount: Value(probed.toc.chapters.length),
        tocJson: Value(probed.toc.encode()),
      ),
    );
    final updated = await byId(id);
    return updated ?? book;
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.novelLocalBooks)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<List<String>> readChapter(
    NovelLocalBook book,
    int chapterIndex,
  ) async {
    if (chapterIndex < 0 || chapterIndex >= book.chapters.length) {
      return const <String>[];
    }
    final chapter = book.chapters[chapterIndex];
    final source = _open(book.path);

    if (book.format == NovelLocalFormat.epub) {
      if (chapter.href.isEmpty) return const <String>[];
      return readNovelEpubChapter(source, chapter.href);
    }

    final encoding = book.encoding ?? NovelTextEncoding.utf8;
    final total = await source.length();
    final start = chapter.start.clamp(0, total);
    final end = chapter.end.clamp(start, total);
    if (end <= start) return const <String>[];

    // 多读 4 字节再按安全边界裁掉尾巴：跨区段的多字节字符不会变成「�」。
    final raw = await source.read(start, end - start + 4);
    final safe = safeDecodeEnd(raw, 0, end - start, encoding);
    final text = decodeNovelText(
      Uint8List.sublistView(raw, 0, safe.clamp(0, raw.length)),
      encoding,
      lossy: true,
    );
    return paragraphsFromNovelText(text);
  }

  NovelLocalBook _fromRow(NovelLocalBookRow row) => NovelLocalBook(
    id: row.id,
    path: row.path,
    title: row.title,
    author: row.author,
    format: NovelLocalFormat.fromKey(row.format) ?? NovelLocalFormat.txt,
    encoding: NovelTextEncoding.fromKey(row.encoding),
    byteSize: row.byteSize,
    chapterCount: row.chapterCount,
    chapters: NovelLocalToc.decode(row.tocJson),
    addedAt: row.addedAt,
  );

  /// 书名：优先路由提示，其次文件名（去掉扩展名，`_` 换空格）。
  String _titleFromPath(String path, String? hint) {
    final trimmed = hint?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
    // 内存来源的 path 带 `memory:` 前缀（测试/预览用），书名里不该出现它。
    final cleaned = path.startsWith('memory:') ? path.substring(7) : path;
    final base = p.basenameWithoutExtension(cleaned);
    return base.replaceAll('_', ' ').trim();
  }
}

/// 由路径派生稳定 id（同文件重复导入 = 同一本书）。
///
/// 用路径的 sha256 前 16 位而不是原文：路径可能很长、含分隔符，直接当主键
/// 会撑爆书架查询与日志；前缀 `local:` 让书架一眼认出本地书。
String novelLocalBookId(String path) {
  final normalized = p.normalize(path).toLowerCase();
  final digest = sha256.convert(utf8.encode(normalized)).toString();
  return '$novelLocalBookIdPrefix${digest.substring(0, 16)}';
}

/// TXT 目录规则仓库窄接口（导入页与设置页共用）。
abstract interface class NovelTxtRuleStorage {
  Future<List<NovelTxtRule>> loadAll();

  /// 新建（id=0）或按 id 更新；返回带 id 的规则。
  Future<NovelTxtRule> save(NovelTxtRule rule);

  Future<void> setEnabled(int id, bool enabled);

  Future<bool> delete(int id);

  /// 恢复内置规则（保留用户自建规则，内置的按默认内容重写）。
  Future<void> restoreDefaults();
}

/// drift 实现：首次读取时把内置规则落库，之后以库为准（用户可改可停用）。
class NovelTxtRuleService implements NovelTxtRuleStorage {
  NovelTxtRuleService(this._db);

  final NovelDb _db;
  bool _seeded = false;

  @override
  Future<List<NovelTxtRule>> loadAll() async {
    await _ensureSeeded();
    final rows =
        await (_db.select(_db.novelTxtTocRules)
              ..orderBy(<OrderClauseGenerator<$NovelTxtTocRulesTable>>[
                (table) => OrderingTerm.asc(table.sortOrder),
                (table) => OrderingTerm.asc(table.id),
              ]))
            .get();
    return <NovelTxtRule>[for (final row in rows) _fromRow(row)];
  }

  Future<void> _ensureSeeded() async {
    if (_seeded) return;
    final existing = await _db.select(_db.novelTxtTocRules).get();
    if (existing.isEmpty) {
      final now = DateTime.now();
      await _db.batch((batch) {
        for (final rule in novelDefaultTxtRules) {
          batch.insert(
            _db.novelTxtTocRules,
            NovelTxtTocRulesCompanion.insert(
              name: rule.name,
              pattern: rule.pattern,
              enabled: Value(rule.enabled),
              builtin: const Value(true),
              sortOrder: Value(rule.sortOrder),
              updatedAt: now,
            ),
          );
        }
      });
    }
    _seeded = true;
  }

  @override
  Future<NovelTxtRule> save(NovelTxtRule rule) async {
    await _ensureSeeded();
    final now = DateTime.now();
    if (rule.id == 0) {
      final order = await _nextSortOrder();
      final id = await _db
          .into(_db.novelTxtTocRules)
          .insert(
            NovelTxtTocRulesCompanion.insert(
              name: rule.name,
              pattern: rule.pattern,
              enabled: Value(rule.enabled),
              sortOrder: Value(order),
              updatedAt: now,
            ),
          );
      return rule.copyWith(sortOrder: order).copyWithId(id);
    }
    await (_db.update(
      _db.novelTxtTocRules,
    )..where((t) => t.id.equals(rule.id))).write(
      NovelTxtTocRulesCompanion(
        name: Value(rule.name),
        pattern: Value(rule.pattern),
        enabled: Value(rule.enabled),
        updatedAt: Value(now),
      ),
    );
    return rule;
  }

  @override
  Future<void> setEnabled(int id, bool enabled) async {
    await _ensureSeeded();
    await (_db.update(
      _db.novelTxtTocRules,
    )..where((t) => t.id.equals(id))).write(
      NovelTxtTocRulesCompanion(
        enabled: Value(enabled),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  @override
  Future<bool> delete(int id) async {
    final deleted = await (_db.delete(
      _db.novelTxtTocRules,
    )..where((t) => t.id.equals(id))).go();
    return deleted > 0;
  }

  @override
  Future<void> restoreDefaults() async {
    await _ensureSeeded();
    final now = DateTime.now();
    final rows = await _db.select(_db.novelTxtTocRules).get();
    final builtinIds = <int>{};
    await _db.transaction(() async {
      for (final rule in novelDefaultTxtRules) {
        final match = rows.where((row) => row.builtin && row.name == rule.name);
        if (match.isEmpty) {
          await _db
              .into(_db.novelTxtTocRules)
              .insert(
                NovelTxtTocRulesCompanion.insert(
                  name: rule.name,
                  pattern: rule.pattern,
                  enabled: Value(rule.enabled),
                  builtin: const Value(true),
                  sortOrder: Value(rule.sortOrder),
                  updatedAt: now,
                ),
              );
          continue;
        }
        final row = match.first;
        builtinIds.add(row.id);
        await (_db.update(
          _db.novelTxtTocRules,
        )..where((t) => t.id.equals(row.id))).write(
          NovelTxtTocRulesCompanion(
            pattern: Value(rule.pattern),
            enabled: Value(rule.enabled),
            sortOrder: Value(rule.sortOrder),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  Future<int> _nextSortOrder() async {
    final rows = await _db.select(_db.novelTxtTocRules).get();
    if (rows.isEmpty) return 0;
    return rows.map((row) => row.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
  }

  NovelTxtRule _fromRow(NovelTxtTocRuleRow row) => NovelTxtRule(
    id: row.id,
    name: row.name,
    pattern: row.pattern,
    enabled: row.enabled,
    builtin: row.builtin,
    sortOrder: row.sortOrder,
  );
}

extension on NovelTxtRule {
  /// 只在本文件内用：新建后回填 id。
  NovelTxtRule copyWithId(int id) => NovelTxtRule(
    id: id,
    name: name,
    pattern: pattern,
    enabled: enabled,
    builtin: builtin,
    sortOrder: sortOrder,
  );
}
