/// 小说备份文档 v2：一个可合并、可预览、可选加密的数据包。
///
/// 这一层是**纯 Dart**：只有值对象、编解码与 v1→v2 归一化，没有任何 IO。
/// 合并策略在 `backup_plan.dart`（同样是纯函数），落库在 `backup_apply.dart`。
///
/// 口径（与库表一一对应，不要另立一套）：
/// - `chapterIndex` 是 **1 起的章号**，0 = 未读（与 `novel_history.chapter_index` 同）；
/// - `locator.chapterIndex` 是 **0 起的章下标**（与 `NovelLocator` 同）；
/// - 书签/划线的 `chapterIndex` 是 0 起（与 `bookmark` / `marking` 表同）。
///
/// 版本策略：`version` 是文档格式版本（本文件负责），`schemaVersion` 是落库时的
/// drift schema 版本，只用于诊断——旧 schema 的文档照样能读，缺的字段按默认值补。
library;

import 'dart:convert';

import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/reader/novel_locator.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

/// 备份文件格式标识（明文与加密包共用同一个族名）。
const String novelBackupFormat = 'mimao-novel-backup';

/// 加密包的外层格式标识。
const String novelBackupEncryptedFormat = 'mimao-novel-backup-encrypted';

/// 当前文档格式版本。v1 只能读、不能写——写一律 v2。
const int novelBackupVersion = 2;

/// 加密信封版本（与文档版本各自演进，互不牵连）。
const int novelBackupEnvelopeVersion = 1;

/// 写备份时记录的 drift schema 版本，仅供诊断。
const int novelBackupSchemaVersion = 9;

/// 备份内容分级。
enum NovelBackupKind {
  /// 全量：书源 / 收藏 / 历史 / 设置 / 书签 / 划线 / 统计。
  full('full'),

  /// 进度专用：只有各书的 `(chapterIndex, locator, 时间)`。
  progress('progress');

  const NovelBackupKind(this.key);

  final String key;

  static NovelBackupKind parse(Object? raw) =>
      raw == progress.key ? progress : full;
}

/// 单本书的进度。
class NovelBackupProgress {
  const NovelBackupProgress({
    required this.bookId,
    this.sourceKey = '',
    this.chapterIndex = 0,
    this.chapterCount = 0,
    this.readCount = 1,
    this.locator,
    this.updatedAt,
  });

  final String bookId;

  /// 书源主键；空串 = 老数据不知道源。
  final String sourceKey;

  /// 1 起章号；0 = 未读。
  final int chapterIndex;

  /// 目录总章数；<=0 = 未知。
  final int chapterCount;

  /// 累计打开次数（合并取 max，不求和——重复导入不是"读了两次"）。
  final int readCount;

  /// 章内位置（0 起章下标）；null = 只有章级进度。
  final NovelLocator? locator;

  /// 这次进度的时间戳：章级取 `novel_history.opened_at`，有章内位置时取两者较新者。
  final DateTime? updatedAt;

  /// 合并键：同一本书按源区分（换源后进度不该串）。
  String get key => novelBackupBookKey(bookId, sourceKey);

  NovelBackupProgress copyWith({
    int? chapterIndex,
    int? chapterCount,
    int? readCount,
    NovelLocator? locator,
    DateTime? updatedAt,
  }) => NovelBackupProgress(
    bookId: bookId,
    sourceKey: sourceKey,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    chapterCount: chapterCount ?? this.chapterCount,
    readCount: readCount ?? this.readCount,
    locator: locator ?? this.locator,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'bookId': bookId,
    if (sourceKey.isNotEmpty) 'sourceKey': sourceKey,
    'chapterIndex': chapterIndex,
    'chapterCount': chapterCount,
    if (readCount > 1) 'readCount': readCount,
    if (locator != null) 'locator': locator!.toJson(),
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  factory NovelBackupProgress.fromJson(Map<String, Object?> json) =>
      NovelBackupProgress(
        bookId: '${json['bookId'] ?? json['id'] ?? ''}',
        sourceKey: '${json['sourceKey'] ?? ''}',
        chapterIndex: _intOf(json['chapterIndex']),
        chapterCount: _intOf(json['chapterCount']),
        readCount: json['readCount'] is num
            ? (json['readCount']! as num).toInt()
            : 1,
        locator: NovelLocator.fromJson(json['locator']),
        updatedAt: _dateOf(json['updatedAt']),
      );
}

/// 合并键：`bookId|sourceKey`。sourceKey 为空时退化成纯 bookId（老数据兼容）。
String novelBackupBookKey(String bookId, String sourceKey) =>
    sourceKey.isEmpty ? bookId : '$bookId|$sourceKey';

/// 备份里的一本收藏（书籍快照 + 分组 + 备注 + 系列 + 进度摘要）。
class NovelBackupCollect {
  const NovelBackupCollect({
    required this.book,
    this.groupName,
    this.note = '',
    this.seriesName,
    this.chapterIndex = 0,
    this.chapterCount = 0,
    this.updatedAt,
  });

  final NovelSummary book;

  /// 书架自定义分组；null = 未分组。
  final String? groupName;

  /// 手写备注（空串 = 无）。
  final String note;

  /// 所属系列名（按名字对齐，避免不同设备的自增 id 串）。
  final String? seriesName;

  final int chapterIndex;
  final int chapterCount;

  /// 收藏时间（也是分组/备注这类无独立时间戳字段的合并基准）。
  final DateTime? updatedAt;

  String get key => novelBackupBookKey(book.id, book.sourceKey);

  Map<String, Object?> toJson() => <String, Object?>{
    'book': book.toJson(),
    if (groupName != null && groupName!.isNotEmpty) 'groupName': groupName,
    if (note.isNotEmpty) 'note': note,
    if (seriesName != null && seriesName!.isNotEmpty) 'seriesName': seriesName,
    'chapterIndex': chapterIndex,
    'chapterCount': chapterCount,
    if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
  };

  factory NovelBackupCollect.fromJson(Map<String, Object?> json) {
    final rawBook = json['book'];
    final book = rawBook is Map
        ? NovelSummary.fromJson(Map<String, Object?>.from(rawBook))
        : NovelSummary(
            id: '${json['id'] ?? ''}',
            title: '${json['title'] ?? ''}',
            coverUrl: '',
          );
    final group = json['groupName'];
    final series = json['seriesName'];
    return NovelBackupCollect(
      book: book,
      groupName: group is String && group.trim().isNotEmpty ? group : null,
      note: '${json['note'] ?? ''}',
      seriesName: series is String && series.trim().isNotEmpty ? series : null,
      chapterIndex: _intOf(json['chapterIndex']),
      chapterCount: _intOf(json['chapterCount']),
      updatedAt: _dateOf(json['openedAt'] ?? json['updatedAt']),
    );
  }
}

/// 备份里的一条阅读历史。
class NovelBackupHistory {
  const NovelBackupHistory({
    required this.book,
    this.chapterIndex = 0,
    this.chapterCount = 0,
    this.readCount = 1,
    this.openedAt,
  });

  final NovelSummary book;
  final int chapterIndex;
  final int chapterCount;
  final int readCount;

  /// 最后一次打开时间（合并时作进度时间戳）。
  final DateTime? openedAt;

  String get key => book.id;

  Map<String, Object?> toJson() => <String, Object?>{
    'book': book.toJson(),
    'chapterIndex': chapterIndex,
    'chapterCount': chapterCount,
    'readCount': readCount,
    if (openedAt != null) 'openedAt': openedAt!.toIso8601String(),
  };

  factory NovelBackupHistory.fromJson(Map<String, Object?> json) {
    final rawBook = json['book'];
    final book = rawBook is Map
        ? NovelSummary.fromJson(Map<String, Object?>.from(rawBook))
        : NovelSummary(
            id: '${json['id'] ?? ''}',
            title: '${json['title'] ?? ''}',
            coverUrl: '',
          );
    return NovelBackupHistory(
      book: book,
      chapterIndex: _intOf(json['chapterIndex']),
      chapterCount: _intOf(json['chapterCount']),
      readCount: json['readCount'] is num
          ? (json['readCount']! as num).toInt()
          : 1,
      openedAt: _dateOf(json['openedAt']),
    );
  }
}

/// 备份里的一个书架系列（作品集）。
class NovelBackupSeries {
  const NovelBackupSeries({required this.name, this.createdAt});

  final String name;
  final DateTime? createdAt;

  String get key => name;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
  };

  factory NovelBackupSeries.fromJson(Map<String, Object?> json) =>
      NovelBackupSeries(
        name: '${json['name'] ?? ''}',
        createdAt: _dateOf(json['createdAt']),
      );
}

/// 备份里的一条书签。
class NovelBackupBookmark {
  const NovelBackupBookmark({
    required this.bookId,
    this.sourceKey = '',
    this.bookTitle = '',
    this.bookAuthor = '',
    this.bookUrl = '',
    required this.chapterIndex,
    this.paragraph = 0,
    this.charOffset = 0,
    this.chapterName = '',
    this.excerpt = '',
    this.unresolved = false,
    required this.createdAt,
  });

  final String bookId;
  final String sourceKey;
  final String bookTitle;
  final String bookAuthor;
  final String bookUrl;

  /// 0 起章下标（与 `bookmark.chapter_index` 同）。
  final int chapterIndex;
  final int paragraph;
  final int charOffset;
  final String chapterName;
  final String excerpt;
  final bool unresolved;
  final DateTime createdAt;

  /// 自然键：锚点即身份（自增 id 不跨设备）。
  String get key => novelBackupAnchorKey(
    bookId: bookId,
    sourceKey: sourceKey,
    chapterIndex: chapterIndex,
    paragraph: paragraph,
    start: charOffset,
    end: charOffset,
  );

  /// 合并时的"内容时间"：书签只有创建时间。
  DateTime get stamp => createdAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'bookId': bookId,
    if (sourceKey.isNotEmpty) 'sourceKey': sourceKey,
    if (bookTitle.isNotEmpty) 'bookTitle': bookTitle,
    if (bookAuthor.isNotEmpty) 'bookAuthor': bookAuthor,
    if (bookUrl.isNotEmpty) 'bookUrl': bookUrl,
    'chapterIndex': chapterIndex,
    'paragraph': paragraph,
    'charOffset': charOffset,
    if (chapterName.isNotEmpty) 'chapterName': chapterName,
    if (excerpt.isNotEmpty) 'excerpt': excerpt,
    if (unresolved) 'unresolved': true,
    'createdAt': createdAt.toIso8601String(),
  };

  factory NovelBackupBookmark.fromJson(Map<String, Object?> json) =>
      NovelBackupBookmark(
        bookId: '${json['bookId'] ?? ''}',
        sourceKey: '${json['sourceKey'] ?? ''}',
        bookTitle: '${json['bookTitle'] ?? ''}',
        bookAuthor: '${json['bookAuthor'] ?? ''}',
        bookUrl: '${json['bookUrl'] ?? ''}',
        chapterIndex: _intOf(json['chapterIndex']),
        paragraph: _intOf(json['paragraph']),
        charOffset: _intOf(json['charOffset']),
        chapterName: '${json['chapterName'] ?? ''}',
        excerpt: '${json['excerpt'] ?? ''}',
        unresolved: json['unresolved'] == true,
        createdAt: _dateOf(json['createdAt']) ?? DateTime.now(),
      );
}

/// 备份里的一条划线/笔记。
class NovelBackupMarking {
  const NovelBackupMarking({
    required this.bookId,
    this.sourceKey = '',
    this.bookTitle = '',
    this.bookAuthor = '',
    this.bookUrl = '',
    required this.chapterIndex,
    this.paragraph = 0,
    this.startOffset = 0,
    this.endOffset = 0,
    this.chapterName = '',
    this.styleJson = '{}',
    this.note = '',
    this.unresolved = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String bookId;
  final String sourceKey;
  final String bookTitle;
  final String bookAuthor;
  final String bookUrl;
  final int chapterIndex;
  final int paragraph;
  final int startOffset;
  final int endOffset;
  final String chapterName;
  final String styleJson;
  final String note;
  final bool unresolved;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get key => novelBackupAnchorKey(
    bookId: bookId,
    sourceKey: sourceKey,
    chapterIndex: chapterIndex,
    paragraph: paragraph,
    start: startOffset,
    end: endOffset,
  );

  DateTime get stamp => updatedAt;

  /// 同键不同内容才算冲突：样式与备注是用户编辑的东西。
  String get contentSignature => '$styleJson\u0000$note';

  Map<String, Object?> toJson() => <String, Object?>{
    'bookId': bookId,
    if (sourceKey.isNotEmpty) 'sourceKey': sourceKey,
    if (bookTitle.isNotEmpty) 'bookTitle': bookTitle,
    if (bookAuthor.isNotEmpty) 'bookAuthor': bookAuthor,
    if (bookUrl.isNotEmpty) 'bookUrl': bookUrl,
    'chapterIndex': chapterIndex,
    'paragraph': paragraph,
    'startOffset': startOffset,
    'endOffset': endOffset,
    if (chapterName.isNotEmpty) 'chapterName': chapterName,
    if (styleJson.isNotEmpty && styleJson != '{}') 'styleJson': styleJson,
    if (note.isNotEmpty) 'note': note,
    if (unresolved) 'unresolved': true,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory NovelBackupMarking.fromJson(Map<String, Object?> json) {
    final created = _dateOf(json['createdAt']) ?? DateTime.now();
    return NovelBackupMarking(
      bookId: '${json['bookId'] ?? ''}',
      sourceKey: '${json['sourceKey'] ?? ''}',
      bookTitle: '${json['bookTitle'] ?? ''}',
      bookAuthor: '${json['bookAuthor'] ?? ''}',
      bookUrl: '${json['bookUrl'] ?? ''}',
      chapterIndex: _intOf(json['chapterIndex']),
      paragraph: _intOf(json['paragraph']),
      startOffset: _intOf(json['startOffset']),
      endOffset: _intOf(json['endOffset']),
      chapterName: '${json['chapterName'] ?? ''}',
      styleJson: '${json['styleJson'] ?? '{}'}',
      note: '${json['note'] ?? ''}',
      unresolved: json['unresolved'] == true,
      createdAt: created,
      updatedAt: _dateOf(json['updatedAt']) ?? created,
    );
  }
}

/// 书签/划线共用的自然键。
String novelBackupAnchorKey({
  required String bookId,
  required String sourceKey,
  required int chapterIndex,
  required int paragraph,
  required int start,
  required int end,
}) => '$bookId|$sourceKey|$chapterIndex|$paragraph|$start|$end';

/// 备份里的一条阅读时长记录（设备 × 书 × 章 × 日）。
class NovelBackupReadRecord {
  const NovelBackupReadRecord({
    required this.deviceId,
    required this.bookId,
    this.bookTitle = '',
    this.chapterIndex = 0,
    this.chapterName = '',
    required this.day,
    this.seconds = 0,
    required this.firstReadAt,
    required this.lastReadAt,
  });

  final String deviceId;
  final String bookId;
  final String bookTitle;
  final int chapterIndex;
  final String chapterName;

  /// 本地日 `yyyy-MM-dd`。
  final String day;
  final int seconds;
  final DateTime firstReadAt;
  final DateTime lastReadAt;

  String get key => '$deviceId|$bookId|$chapterIndex|$day';

  NovelBackupReadRecord copyWith({
    int? seconds,
    DateTime? firstReadAt,
    DateTime? lastReadAt,
    String? bookTitle,
    String? chapterName,
  }) => NovelBackupReadRecord(
    deviceId: deviceId,
    bookId: bookId,
    bookTitle: bookTitle ?? this.bookTitle,
    chapterIndex: chapterIndex,
    chapterName: chapterName ?? this.chapterName,
    day: day,
    seconds: seconds ?? this.seconds,
    firstReadAt: firstReadAt ?? this.firstReadAt,
    lastReadAt: lastReadAt ?? this.lastReadAt,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'deviceId': deviceId,
    'bookId': bookId,
    if (bookTitle.isNotEmpty) 'bookTitle': bookTitle,
    'chapterIndex': chapterIndex,
    if (chapterName.isNotEmpty) 'chapterName': chapterName,
    'day': day,
    'seconds': seconds,
    'firstReadAt': firstReadAt.toIso8601String(),
    'lastReadAt': lastReadAt.toIso8601String(),
  };

  factory NovelBackupReadRecord.fromJson(Map<String, Object?> json) {
    final first = _dateOf(json['firstReadAt']) ?? DateTime.now();
    return NovelBackupReadRecord(
      deviceId: '${json['deviceId'] ?? ''}',
      bookId: '${json['bookId'] ?? ''}',
      bookTitle: '${json['bookTitle'] ?? ''}',
      chapterIndex: _intOf(json['chapterIndex']),
      chapterName: '${json['chapterName'] ?? ''}',
      day: '${json['day'] ?? ''}',
      seconds: _intOf(json['seconds']),
      firstReadAt: first,
      lastReadAt: _dateOf(json['lastReadAt']) ?? first,
    );
  }
}

/// 删除墓碑：让「删掉的书签/划线」能跨设备传播，不会被对侧合并复活。
///
/// 范围刻意只含 [novelTombstoneBookmark] / [novelTombstoneMarking]；
/// 取消收藏的传播牵涉"恢复要不要删书"，不在这里。
const String novelTombstoneBookmark = 'bookmark';
const String novelTombstoneMarking = 'marking';

class NovelBackupTombstone {
  const NovelBackupTombstone({
    required this.kind,
    required this.key,
    required this.deviceId,
    required this.deletedAt,
  });

  /// [novelTombstoneBookmark] / [novelTombstoneMarking]。
  final String kind;

  /// 被删行的自然键（与合并用的键同口径）。
  final String key;

  /// 哪台设备删的（诊断用）。
  final String deviceId;

  final DateTime deletedAt;

  String get id => '$kind|$key';

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'key': key,
    'deviceId': deviceId,
    'deletedAt': deletedAt.toIso8601String(),
  };

  factory NovelBackupTombstone.fromJson(Map<String, Object?> json) =>
      NovelBackupTombstone(
        kind: '${json['kind'] ?? ''}',
        key: '${json['key'] ?? ''}',
        deviceId: '${json['deviceId'] ?? ''}',
        deletedAt: _dateOf(json['deletedAt']) ?? DateTime.now(),
      );
}

/// 备份文档。本地快照与远端文档**同一个类型**——合并就是两个文档相比。
class NovelBackupDocument {
  const NovelBackupDocument({
    required this.collects,
    required this.histories,
    required this.searchKeywords,
    required this.sources,
    required this.prefs,
    required this.exportedAt,
    this.kind = NovelBackupKind.full,
    this.deviceId,
    this.deviceName = '',
    this.progress = const <NovelBackupProgress>[],
    this.series = const <NovelBackupSeries>[],
    this.bookmarks = const <NovelBackupBookmark>[],
    this.markings = const <NovelBackupMarking>[],
    this.readRecords = const <NovelBackupReadRecord>[],
    this.tombstones = const <NovelBackupTombstone>[],
    this.legacyV1 = false,
  });

  final List<NovelBackupCollect> collects;
  final List<NovelBackupHistory> histories;
  final List<String> searchKeywords;
  final List<NovelBookSource> sources;

  /// 模块 kv 白名单（值原样字符串）。
  final Map<String, String> prefs;
  final DateTime exportedAt;
  final NovelBackupKind kind;

  /// 导出这份文档的设备；v1 文档没有该字段（null），恢复时按本机设备处理。
  final String? deviceId;
  final String deviceName;
  final List<NovelBackupProgress> progress;
  final List<NovelBackupSeries> series;
  final List<NovelBackupBookmark> bookmarks;
  final List<NovelBackupMarking> markings;
  final List<NovelBackupReadRecord> readRecords;
  final List<NovelBackupTombstone> tombstones;

  /// true = 由 v1 文档归一化而来（缺设备维度、缺书签/划线/统计）。
  final bool legacyV1;

  NovelBackupDocument copyWith({
    List<NovelBackupCollect>? collects,
    List<NovelBackupHistory>? histories,
    List<String>? searchKeywords,
    List<NovelBookSource>? sources,
    Map<String, String>? prefs,
    DateTime? exportedAt,
    NovelBackupKind? kind,
    String? deviceId,
    String? deviceName,
    List<NovelBackupProgress>? progress,
    List<NovelBackupSeries>? series,
    List<NovelBackupBookmark>? bookmarks,
    List<NovelBackupMarking>? markings,
    List<NovelBackupReadRecord>? readRecords,
    List<NovelBackupTombstone>? tombstones,
  }) => NovelBackupDocument(
    collects: collects ?? this.collects,
    histories: histories ?? this.histories,
    searchKeywords: searchKeywords ?? this.searchKeywords,
    sources: sources ?? this.sources,
    prefs: prefs ?? this.prefs,
    exportedAt: exportedAt ?? this.exportedAt,
    kind: kind ?? this.kind,
    deviceId: deviceId ?? this.deviceId,
    deviceName: deviceName ?? this.deviceName,
    progress: progress ?? this.progress,
    series: series ?? this.series,
    bookmarks: bookmarks ?? this.bookmarks,
    markings: markings ?? this.markings,
    readRecords: readRecords ?? this.readRecords,
    tombstones: tombstones ?? this.tombstones,
  );

  /// 进度专用文档：只带进度段，体积压到最小。
  NovelBackupDocument progressOnly() => NovelBackupDocument(
    collects: const <NovelBackupCollect>[],
    histories: const <NovelBackupHistory>[],
    searchKeywords: const <String>[],
    sources: const <NovelBookSource>[],
    prefs: const <String, String>{},
    exportedAt: exportedAt,
    kind: NovelBackupKind.progress,
    deviceId: deviceId,
    deviceName: deviceName,
    progress: progress,
  );

  int get itemCount =>
      collects.length +
      histories.length +
      bookmarks.length +
      markings.length +
      readRecords.length +
      progress.length;

  String encode() =>
      '${const JsonEncoder.withIndent('  ').convert(toJson())}\n';

  Map<String, Object?> toJson() => <String, Object?>{
    'format': novelBackupFormat,
    'version': novelBackupVersion,
    'schemaVersion': novelBackupSchemaVersion,
    'kind': kind.key,
    if (deviceId != null) 'deviceId': deviceId,
    if (deviceName.isNotEmpty) 'deviceName': deviceName,
    'exportedAt': exportedAt.toIso8601String(),
    if (kind == NovelBackupKind.progress)
      'progress': <Object?>[for (final item in progress) item.toJson()]
    else ...<String, Object?>{
      'collects': <Object?>[for (final item in collects) item.toJson()],
      'histories': <Object?>[for (final item in histories) item.toJson()],
      'searchKeywords': <Object?>[...searchKeywords],
      'sources': <Object?>[for (final source in sources) source.toJson()],
      'prefs': <String, Object?>{...prefs},
      'progress': <Object?>[for (final item in progress) item.toJson()],
      'series': <Object?>[for (final item in series) item.toJson()],
      'bookmarks': <Object?>[for (final item in bookmarks) item.toJson()],
      'markings': <Object?>[for (final item in markings) item.toJson()],
      'readRecords': <Object?>[for (final item in readRecords) item.toJson()],
      'tombstones': <Object?>[for (final item in tombstones) item.toJson()],
    },
  };

  /// 解析并校验格式；不合法抛 [FormatException]。
  ///
  /// v1 文档走 [migrateNovelBackupV1]：没有设备维度、没有书签/划线/统计，
  /// 进度从收藏/历史里合成；恢复时一律按本机设备落库。
  static NovelBackupDocument decode(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('备份文件不是 JSON 对象');
    final format = decoded['format'];
    if (format == novelBackupEncryptedFormat) {
      throw const FormatException('这是加密备份，需要先输入密码解开');
    }
    if (format != novelBackupFormat) {
      throw const FormatException('不是 mimao 小说备份文件');
    }
    final version = decoded['version'];
    if (version is! int || version < 1 || version > novelBackupVersion) {
      throw const FormatException('备份版本不兼容');
    }
    final map = Map<String, Object?>.from(decoded);
    if (version == 1) return migrateNovelBackupV1(map);
    return _decodeV2(map);
  }
}

/// 把 v1 文档归一化成 v2。v1 缺的东西（设备维度、书签/划线/统计/墓碑）
/// 一律留空，进度由收藏/历史合成。
NovelBackupDocument migrateNovelBackupV1(Map<String, Object?> map) {
  final doc = _decodeV2(map);
  final progress = <String, NovelBackupProgress>{};
  void put(
    NovelSummary book,
    int chapterIndex,
    int chapterCount,
    DateTime? at,
  ) {
    if (book.id.isEmpty || chapterIndex <= 0) return;
    final key = novelBackupBookKey(book.id, book.sourceKey);
    final existing = progress[key];
    if (existing == null ||
        chapterIndex > existing.chapterIndex ||
        (chapterIndex == existing.chapterIndex &&
            (at != null &&
                (existing.updatedAt == null ||
                    at.isAfter(existing.updatedAt!))))) {
      progress[key] = NovelBackupProgress(
        bookId: book.id,
        sourceKey: book.sourceKey,
        chapterIndex: chapterIndex,
        chapterCount: chapterCount,
        updatedAt: at,
      );
    }
  }

  for (final item in doc.collects) {
    put(item.book, item.chapterIndex, item.chapterCount, item.updatedAt);
  }
  for (final item in doc.histories) {
    put(item.book, item.chapterIndex, item.chapterCount, item.openedAt);
  }
  return NovelBackupDocument(
    collects: doc.collects,
    histories: doc.histories,
    searchKeywords: doc.searchKeywords,
    sources: doc.sources,
    prefs: doc.prefs,
    exportedAt: doc.exportedAt,
    kind: doc.kind,
    deviceId: doc.deviceId,
    deviceName: doc.deviceName,
    progress: progress.values.toList(growable: false),
    series: doc.series,
    bookmarks: doc.bookmarks,
    markings: doc.markings,
    readRecords: doc.readRecords,
    tombstones: doc.tombstones,
    legacyV1: true,
  );
}

NovelBackupDocument _decodeV2(Map<String, Object?> decoded) {
  List<Map<String, Object?>> mapsOf(Object? value) {
    if (value is! List) return const <Map<String, Object?>>[];
    return <Map<String, Object?>>[
      for (final raw in value)
        if (raw is Map) Map<String, Object?>.from(raw),
    ];
  }

  final collects = <NovelBackupCollect>[];
  for (final item in mapsOf(decoded['collects'])) {
    final collect = NovelBackupCollect.fromJson(item);
    if (collect.book.id.isNotEmpty) collects.add(collect);
  }
  final histories = <NovelBackupHistory>[];
  for (final item in mapsOf(decoded['histories'])) {
    final history = NovelBackupHistory.fromJson(item);
    if (history.book.id.isNotEmpty) histories.add(history);
  }
  final progress = <NovelBackupProgress>[];
  for (final item in mapsOf(decoded['progress'])) {
    final entry = NovelBackupProgress.fromJson(item);
    if (entry.bookId.isNotEmpty) progress.add(entry);
  }
  final bookmarks = <NovelBackupBookmark>[];
  for (final item in mapsOf(decoded['bookmarks'])) {
    final bookmark = NovelBackupBookmark.fromJson(item);
    if (bookmark.bookId.isNotEmpty) bookmarks.add(bookmark);
  }
  final markings = <NovelBackupMarking>[];
  for (final item in mapsOf(decoded['markings'])) {
    final marking = NovelBackupMarking.fromJson(item);
    if (marking.bookId.isNotEmpty) markings.add(marking);
  }
  final readRecords = <NovelBackupReadRecord>[];
  for (final item in mapsOf(decoded['readRecords'])) {
    final record = NovelBackupReadRecord.fromJson(item);
    if (record.day.isNotEmpty) readRecords.add(record);
  }
  final tombstones = <NovelBackupTombstone>[];
  for (final item in mapsOf(decoded['tombstones'])) {
    final tombstone = NovelBackupTombstone.fromJson(item);
    if (tombstone.kind.isNotEmpty && tombstone.key.isNotEmpty) {
      tombstones.add(tombstone);
    }
  }
  final series = <NovelBackupSeries>[];
  for (final item in mapsOf(decoded['series'])) {
    final entry = NovelBackupSeries.fromJson(item);
    if (entry.name.trim().isNotEmpty) series.add(entry);
  }
  final searchKeywords = <String>[];
  final rawKeywords = decoded['searchKeywords'];
  if (rawKeywords is List) {
    for (final keyword in rawKeywords) {
      final text = keyword?.toString().trim() ?? '';
      if (text.isNotEmpty) searchKeywords.add(text);
    }
  }
  final sources = <NovelBookSource>[];
  for (final item in mapsOf(decoded['sources'])) {
    try {
      sources.add(NovelBookSource.fromJson(item));
    } on Object {
      // 单条坏源不影响其余。
    }
  }
  final prefs = <String, String>{};
  final rawPrefs = decoded['prefs'];
  if (rawPrefs is Map) {
    for (final entry in rawPrefs.entries) {
      prefs['${entry.key}'] = '${entry.value}';
    }
  }
  final rawDevice = decoded['deviceId'];
  return NovelBackupDocument(
    collects: collects,
    histories: histories,
    searchKeywords: searchKeywords,
    sources: sources,
    prefs: prefs,
    exportedAt: _dateOf(decoded['exportedAt']) ?? DateTime.now(),
    kind: NovelBackupKind.parse(decoded['kind']),
    deviceId: rawDevice is String && rawDevice.trim().isNotEmpty
        ? rawDevice.trim()
        : null,
    deviceName: '${decoded['deviceName'] ?? ''}',
    progress: progress,
    series: series,
    bookmarks: bookmarks,
    markings: markings,
    readRecords: readRecords,
    tombstones: tombstones,
  );
}

int _intOf(Object? raw) => raw is num ? raw.toInt() : 0;

DateTime? _dateOf(Object? raw) => raw is String ? DateTime.tryParse(raw) : null;
