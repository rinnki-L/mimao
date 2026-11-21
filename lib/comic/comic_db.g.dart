// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'comic_db.dart';

// ignore_for_file: type=lint
class $ComicCollectEntriesTable extends ComicCollectEntries
    with TableInfo<$ComicCollectEntriesTable, ComicCollectRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ComicCollectEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceNameMeta = const VerificationMeta(
    'sourceName',
  );
  @override
  late final GeneratedColumn<String> sourceName = GeneratedColumn<String>(
    'source_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverUrlMeta = const VerificationMeta(
    'coverUrl',
  );
  @override
  late final GeneratedColumn<String> coverUrl = GeneratedColumn<String>(
    'cover_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _collectedAtMeta = const VerificationMeta(
    'collectedAt',
  );
  @override
  late final GeneratedColumn<DateTime> collectedAt = GeneratedColumn<DateTime>(
    'collected_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceName,
    title,
    coverUrl,
    payload,
    collectedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'comic_collect';
  @override
  VerificationContext validateIntegrity(
    Insertable<ComicCollectRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source_name')) {
      context.handle(
        _sourceNameMeta,
        sourceName.isAcceptableOrUnknown(data['source_name']!, _sourceNameMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceNameMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('cover_url')) {
      context.handle(
        _coverUrlMeta,
        coverUrl.isAcceptableOrUnknown(data['cover_url']!, _coverUrlMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('collected_at')) {
      context.handle(
        _collectedAtMeta,
        collectedAt.isAcceptableOrUnknown(
          data['collected_at']!,
          _collectedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_collectedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, sourceName};
  @override
  ComicCollectRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ComicCollectRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sourceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_name'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      coverUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_url'],
      ),
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      collectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}collected_at'],
      )!,
    );
  }

  @override
  $ComicCollectEntriesTable createAlias(String alias) {
    return $ComicCollectEntriesTable(attachedDatabase, alias);
  }
}

class ComicCollectRow extends DataClass implements Insertable<ComicCollectRow> {
  final String id;
  final String sourceName;
  final String title;
  final String? coverUrl;

  /// 模块私有 JSON；投影里的 payload 是投影函数另写的摘要，不是这一列。
  final String payload;
  final DateTime collectedAt;
  const ComicCollectRow({
    required this.id,
    required this.sourceName,
    required this.title,
    this.coverUrl,
    required this.payload,
    required this.collectedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['source_name'] = Variable<String>(sourceName);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || coverUrl != null) {
      map['cover_url'] = Variable<String>(coverUrl);
    }
    map['payload'] = Variable<String>(payload);
    map['collected_at'] = Variable<DateTime>(collectedAt);
    return map;
  }

  ComicCollectEntriesCompanion toCompanion(bool nullToAbsent) {
    return ComicCollectEntriesCompanion(
      id: Value(id),
      sourceName: Value(sourceName),
      title: Value(title),
      coverUrl: coverUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(coverUrl),
      payload: Value(payload),
      collectedAt: Value(collectedAt),
    );
  }

  factory ComicCollectRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ComicCollectRow(
      id: serializer.fromJson<String>(json['id']),
      sourceName: serializer.fromJson<String>(json['sourceName']),
      title: serializer.fromJson<String>(json['title']),
      coverUrl: serializer.fromJson<String?>(json['coverUrl']),
      payload: serializer.fromJson<String>(json['payload']),
      collectedAt: serializer.fromJson<DateTime>(json['collectedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sourceName': serializer.toJson<String>(sourceName),
      'title': serializer.toJson<String>(title),
      'coverUrl': serializer.toJson<String?>(coverUrl),
      'payload': serializer.toJson<String>(payload),
      'collectedAt': serializer.toJson<DateTime>(collectedAt),
    };
  }

  ComicCollectRow copyWith({
    String? id,
    String? sourceName,
    String? title,
    Value<String?> coverUrl = const Value.absent(),
    String? payload,
    DateTime? collectedAt,
  }) => ComicCollectRow(
    id: id ?? this.id,
    sourceName: sourceName ?? this.sourceName,
    title: title ?? this.title,
    coverUrl: coverUrl.present ? coverUrl.value : this.coverUrl,
    payload: payload ?? this.payload,
    collectedAt: collectedAt ?? this.collectedAt,
  );
  ComicCollectRow copyWithCompanion(ComicCollectEntriesCompanion data) {
    return ComicCollectRow(
      id: data.id.present ? data.id.value : this.id,
      sourceName: data.sourceName.present
          ? data.sourceName.value
          : this.sourceName,
      title: data.title.present ? data.title.value : this.title,
      coverUrl: data.coverUrl.present ? data.coverUrl.value : this.coverUrl,
      payload: data.payload.present ? data.payload.value : this.payload,
      collectedAt: data.collectedAt.present
          ? data.collectedAt.value
          : this.collectedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ComicCollectRow(')
          ..write('id: $id, ')
          ..write('sourceName: $sourceName, ')
          ..write('title: $title, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('payload: $payload, ')
          ..write('collectedAt: $collectedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, sourceName, title, coverUrl, payload, collectedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ComicCollectRow &&
          other.id == this.id &&
          other.sourceName == this.sourceName &&
          other.title == this.title &&
          other.coverUrl == this.coverUrl &&
          other.payload == this.payload &&
          other.collectedAt == this.collectedAt);
}

class ComicCollectEntriesCompanion extends UpdateCompanion<ComicCollectRow> {
  final Value<String> id;
  final Value<String> sourceName;
  final Value<String> title;
  final Value<String?> coverUrl;
  final Value<String> payload;
  final Value<DateTime> collectedAt;
  final Value<int> rowid;
  const ComicCollectEntriesCompanion({
    this.id = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.title = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.payload = const Value.absent(),
    this.collectedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ComicCollectEntriesCompanion.insert({
    required String id,
    required String sourceName,
    required String title,
    this.coverUrl = const Value.absent(),
    this.payload = const Value.absent(),
    required DateTime collectedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sourceName = Value(sourceName),
       title = Value(title),
       collectedAt = Value(collectedAt);
  static Insertable<ComicCollectRow> custom({
    Expression<String>? id,
    Expression<String>? sourceName,
    Expression<String>? title,
    Expression<String>? coverUrl,
    Expression<String>? payload,
    Expression<DateTime>? collectedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceName != null) 'source_name': sourceName,
      if (title != null) 'title': title,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (payload != null) 'payload': payload,
      if (collectedAt != null) 'collected_at': collectedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ComicCollectEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? sourceName,
    Value<String>? title,
    Value<String?>? coverUrl,
    Value<String>? payload,
    Value<DateTime>? collectedAt,
    Value<int>? rowid,
  }) {
    return ComicCollectEntriesCompanion(
      id: id ?? this.id,
      sourceName: sourceName ?? this.sourceName,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      payload: payload ?? this.payload,
      collectedAt: collectedAt ?? this.collectedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sourceName.present) {
      map['source_name'] = Variable<String>(sourceName.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (coverUrl.present) {
      map['cover_url'] = Variable<String>(coverUrl.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (collectedAt.present) {
      map['collected_at'] = Variable<DateTime>(collectedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ComicCollectEntriesCompanion(')
          ..write('id: $id, ')
          ..write('sourceName: $sourceName, ')
          ..write('title: $title, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('payload: $payload, ')
          ..write('collectedAt: $collectedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ComicHistoryEntriesTable extends ComicHistoryEntries
    with TableInfo<$ComicHistoryEntriesTable, ComicHistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ComicHistoryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceNameMeta = const VerificationMeta(
    'sourceName',
  );
  @override
  late final GeneratedColumn<String> sourceName = GeneratedColumn<String>(
    'source_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverUrlMeta = const VerificationMeta(
    'coverUrl',
  );
  @override
  late final GeneratedColumn<String> coverUrl = GeneratedColumn<String>(
    'cover_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _chapterIdMeta = const VerificationMeta(
    'chapterId',
  );
  @override
  late final GeneratedColumn<String> chapterId = GeneratedColumn<String>(
    'chapter_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _pageMeta = const VerificationMeta('page');
  @override
  late final GeneratedColumn<int> page = GeneratedColumn<int>(
    'page',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pageCountMeta = const VerificationMeta(
    'pageCount',
  );
  @override
  late final GeneratedColumn<int> pageCount = GeneratedColumn<int>(
    'page_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _openedAtMeta = const VerificationMeta(
    'openedAt',
  );
  @override
  late final GeneratedColumn<DateTime> openedAt = GeneratedColumn<DateTime>(
    'opened_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceName,
    title,
    coverUrl,
    chapterId,
    page,
    pageCount,
    openedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'comic_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<ComicHistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source_name')) {
      context.handle(
        _sourceNameMeta,
        sourceName.isAcceptableOrUnknown(data['source_name']!, _sourceNameMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceNameMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('cover_url')) {
      context.handle(
        _coverUrlMeta,
        coverUrl.isAcceptableOrUnknown(data['cover_url']!, _coverUrlMeta),
      );
    }
    if (data.containsKey('chapter_id')) {
      context.handle(
        _chapterIdMeta,
        chapterId.isAcceptableOrUnknown(data['chapter_id']!, _chapterIdMeta),
      );
    }
    if (data.containsKey('page')) {
      context.handle(
        _pageMeta,
        page.isAcceptableOrUnknown(data['page']!, _pageMeta),
      );
    }
    if (data.containsKey('page_count')) {
      context.handle(
        _pageCountMeta,
        pageCount.isAcceptableOrUnknown(data['page_count']!, _pageCountMeta),
      );
    }
    if (data.containsKey('opened_at')) {
      context.handle(
        _openedAtMeta,
        openedAt.isAcceptableOrUnknown(data['opened_at']!, _openedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_openedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, sourceName};
  @override
  ComicHistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ComicHistoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sourceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_name'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      coverUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_url'],
      ),
      chapterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_id'],
      )!,
      page: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page'],
      )!,
      pageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_count'],
      )!,
      openedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}opened_at'],
      )!,
    );
  }

  @override
  $ComicHistoryEntriesTable createAlias(String alias) {
    return $ComicHistoryEntriesTable(attachedDatabase, alias);
  }
}

class ComicHistoryRow extends DataClass implements Insertable<ComicHistoryRow> {
  final String id;
  final String sourceName;

  /// 打开历史时来源可能已下线，标题/封面随历史一起留底。
  final String title;
  final String? coverUrl;

  /// 章节 id（可选，仅作展示辅助；进度权威是 page/pageCount）。
  final String chapterId;
  final int page;
  final int pageCount;
  final DateTime openedAt;
  const ComicHistoryRow({
    required this.id,
    required this.sourceName,
    required this.title,
    this.coverUrl,
    required this.chapterId,
    required this.page,
    required this.pageCount,
    required this.openedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['source_name'] = Variable<String>(sourceName);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || coverUrl != null) {
      map['cover_url'] = Variable<String>(coverUrl);
    }
    map['chapter_id'] = Variable<String>(chapterId);
    map['page'] = Variable<int>(page);
    map['page_count'] = Variable<int>(pageCount);
    map['opened_at'] = Variable<DateTime>(openedAt);
    return map;
  }

  ComicHistoryEntriesCompanion toCompanion(bool nullToAbsent) {
    return ComicHistoryEntriesCompanion(
      id: Value(id),
      sourceName: Value(sourceName),
      title: Value(title),
      coverUrl: coverUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(coverUrl),
      chapterId: Value(chapterId),
      page: Value(page),
      pageCount: Value(pageCount),
      openedAt: Value(openedAt),
    );
  }

  factory ComicHistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ComicHistoryRow(
      id: serializer.fromJson<String>(json['id']),
      sourceName: serializer.fromJson<String>(json['sourceName']),
      title: serializer.fromJson<String>(json['title']),
      coverUrl: serializer.fromJson<String?>(json['coverUrl']),
      chapterId: serializer.fromJson<String>(json['chapterId']),
      page: serializer.fromJson<int>(json['page']),
      pageCount: serializer.fromJson<int>(json['pageCount']),
      openedAt: serializer.fromJson<DateTime>(json['openedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sourceName': serializer.toJson<String>(sourceName),
      'title': serializer.toJson<String>(title),
      'coverUrl': serializer.toJson<String?>(coverUrl),
      'chapterId': serializer.toJson<String>(chapterId),
      'page': serializer.toJson<int>(page),
      'pageCount': serializer.toJson<int>(pageCount),
      'openedAt': serializer.toJson<DateTime>(openedAt),
    };
  }

  ComicHistoryRow copyWith({
    String? id,
    String? sourceName,
    String? title,
    Value<String?> coverUrl = const Value.absent(),
    String? chapterId,
    int? page,
    int? pageCount,
    DateTime? openedAt,
  }) => ComicHistoryRow(
    id: id ?? this.id,
    sourceName: sourceName ?? this.sourceName,
    title: title ?? this.title,
    coverUrl: coverUrl.present ? coverUrl.value : this.coverUrl,
    chapterId: chapterId ?? this.chapterId,
    page: page ?? this.page,
    pageCount: pageCount ?? this.pageCount,
    openedAt: openedAt ?? this.openedAt,
  );
  ComicHistoryRow copyWithCompanion(ComicHistoryEntriesCompanion data) {
    return ComicHistoryRow(
      id: data.id.present ? data.id.value : this.id,
      sourceName: data.sourceName.present
          ? data.sourceName.value
          : this.sourceName,
      title: data.title.present ? data.title.value : this.title,
      coverUrl: data.coverUrl.present ? data.coverUrl.value : this.coverUrl,
      chapterId: data.chapterId.present ? data.chapterId.value : this.chapterId,
      page: data.page.present ? data.page.value : this.page,
      pageCount: data.pageCount.present ? data.pageCount.value : this.pageCount,
      openedAt: data.openedAt.present ? data.openedAt.value : this.openedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ComicHistoryRow(')
          ..write('id: $id, ')
          ..write('sourceName: $sourceName, ')
          ..write('title: $title, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('chapterId: $chapterId, ')
          ..write('page: $page, ')
          ..write('pageCount: $pageCount, ')
          ..write('openedAt: $openedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sourceName,
    title,
    coverUrl,
    chapterId,
    page,
    pageCount,
    openedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ComicHistoryRow &&
          other.id == this.id &&
          other.sourceName == this.sourceName &&
          other.title == this.title &&
          other.coverUrl == this.coverUrl &&
          other.chapterId == this.chapterId &&
          other.page == this.page &&
          other.pageCount == this.pageCount &&
          other.openedAt == this.openedAt);
}

class ComicHistoryEntriesCompanion extends UpdateCompanion<ComicHistoryRow> {
  final Value<String> id;
  final Value<String> sourceName;
  final Value<String> title;
  final Value<String?> coverUrl;
  final Value<String> chapterId;
  final Value<int> page;
  final Value<int> pageCount;
  final Value<DateTime> openedAt;
  final Value<int> rowid;
  const ComicHistoryEntriesCompanion({
    this.id = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.title = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.page = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.openedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ComicHistoryEntriesCompanion.insert({
    required String id,
    required String sourceName,
    required String title,
    this.coverUrl = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.page = const Value.absent(),
    this.pageCount = const Value.absent(),
    required DateTime openedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sourceName = Value(sourceName),
       title = Value(title),
       openedAt = Value(openedAt);
  static Insertable<ComicHistoryRow> custom({
    Expression<String>? id,
    Expression<String>? sourceName,
    Expression<String>? title,
    Expression<String>? coverUrl,
    Expression<String>? chapterId,
    Expression<int>? page,
    Expression<int>? pageCount,
    Expression<DateTime>? openedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceName != null) 'source_name': sourceName,
      if (title != null) 'title': title,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (chapterId != null) 'chapter_id': chapterId,
      if (page != null) 'page': page,
      if (pageCount != null) 'page_count': pageCount,
      if (openedAt != null) 'opened_at': openedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ComicHistoryEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? sourceName,
    Value<String>? title,
    Value<String?>? coverUrl,
    Value<String>? chapterId,
    Value<int>? page,
    Value<int>? pageCount,
    Value<DateTime>? openedAt,
    Value<int>? rowid,
  }) {
    return ComicHistoryEntriesCompanion(
      id: id ?? this.id,
      sourceName: sourceName ?? this.sourceName,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      chapterId: chapterId ?? this.chapterId,
      page: page ?? this.page,
      pageCount: pageCount ?? this.pageCount,
      openedAt: openedAt ?? this.openedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sourceName.present) {
      map['source_name'] = Variable<String>(sourceName.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (coverUrl.present) {
      map['cover_url'] = Variable<String>(coverUrl.value);
    }
    if (chapterId.present) {
      map['chapter_id'] = Variable<String>(chapterId.value);
    }
    if (page.present) {
      map['page'] = Variable<int>(page.value);
    }
    if (pageCount.present) {
      map['page_count'] = Variable<int>(pageCount.value);
    }
    if (openedAt.present) {
      map['opened_at'] = Variable<DateTime>(openedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ComicHistoryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('sourceName: $sourceName, ')
          ..write('title: $title, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('chapterId: $chapterId, ')
          ..write('page: $page, ')
          ..write('pageCount: $pageCount, ')
          ..write('openedAt: $openedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ComicReadLaterEntriesTable extends ComicReadLaterEntries
    with TableInfo<$ComicReadLaterEntriesTable, ComicReadLaterRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ComicReadLaterEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceNameMeta = const VerificationMeta(
    'sourceName',
  );
  @override
  late final GeneratedColumn<String> sourceName = GeneratedColumn<String>(
    'source_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverUrlMeta = const VerificationMeta(
    'coverUrl',
  );
  @override
  late final GeneratedColumn<String> coverUrl = GeneratedColumn<String>(
    'cover_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _detailUrlMeta = const VerificationMeta(
    'detailUrl',
  );
  @override
  late final GeneratedColumn<String> detailUrl = GeneratedColumn<String>(
    'detail_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceName,
    title,
    coverUrl,
    detailUrl,
    addedAt,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'comic_read_later';
  @override
  VerificationContext validateIntegrity(
    Insertable<ComicReadLaterRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source_name')) {
      context.handle(
        _sourceNameMeta,
        sourceName.isAcceptableOrUnknown(data['source_name']!, _sourceNameMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceNameMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('cover_url')) {
      context.handle(
        _coverUrlMeta,
        coverUrl.isAcceptableOrUnknown(data['cover_url']!, _coverUrlMeta),
      );
    }
    if (data.containsKey('detail_url')) {
      context.handle(
        _detailUrlMeta,
        detailUrl.isAcceptableOrUnknown(data['detail_url']!, _detailUrlMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, sourceName};
  @override
  ComicReadLaterRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ComicReadLaterRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sourceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_name'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      coverUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_url'],
      ),
      detailUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detail_url'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $ComicReadLaterEntriesTable createAlias(String alias) {
    return $ComicReadLaterEntriesTable(attachedDatabase, alias);
  }
}

class ComicReadLaterRow extends DataClass
    implements Insertable<ComicReadLaterRow> {
  final String id;
  final String sourceName;
  final String title;
  final String? coverUrl;

  /// 源内的详情标识（通常就是 [id]）留底，便于将来换源/迁移。
  final String detailUrl;
  final DateTime addedAt;

  /// 模块私有 JSON（预留；core 不解释）。
  final String payload;
  const ComicReadLaterRow({
    required this.id,
    required this.sourceName,
    required this.title,
    this.coverUrl,
    required this.detailUrl,
    required this.addedAt,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['source_name'] = Variable<String>(sourceName);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || coverUrl != null) {
      map['cover_url'] = Variable<String>(coverUrl);
    }
    map['detail_url'] = Variable<String>(detailUrl);
    map['added_at'] = Variable<DateTime>(addedAt);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  ComicReadLaterEntriesCompanion toCompanion(bool nullToAbsent) {
    return ComicReadLaterEntriesCompanion(
      id: Value(id),
      sourceName: Value(sourceName),
      title: Value(title),
      coverUrl: coverUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(coverUrl),
      detailUrl: Value(detailUrl),
      addedAt: Value(addedAt),
      payload: Value(payload),
    );
  }

  factory ComicReadLaterRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ComicReadLaterRow(
      id: serializer.fromJson<String>(json['id']),
      sourceName: serializer.fromJson<String>(json['sourceName']),
      title: serializer.fromJson<String>(json['title']),
      coverUrl: serializer.fromJson<String?>(json['coverUrl']),
      detailUrl: serializer.fromJson<String>(json['detailUrl']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sourceName': serializer.toJson<String>(sourceName),
      'title': serializer.toJson<String>(title),
      'coverUrl': serializer.toJson<String?>(coverUrl),
      'detailUrl': serializer.toJson<String>(detailUrl),
      'addedAt': serializer.toJson<DateTime>(addedAt),
      'payload': serializer.toJson<String>(payload),
    };
  }

  ComicReadLaterRow copyWith({
    String? id,
    String? sourceName,
    String? title,
    Value<String?> coverUrl = const Value.absent(),
    String? detailUrl,
    DateTime? addedAt,
    String? payload,
  }) => ComicReadLaterRow(
    id: id ?? this.id,
    sourceName: sourceName ?? this.sourceName,
    title: title ?? this.title,
    coverUrl: coverUrl.present ? coverUrl.value : this.coverUrl,
    detailUrl: detailUrl ?? this.detailUrl,
    addedAt: addedAt ?? this.addedAt,
    payload: payload ?? this.payload,
  );
  ComicReadLaterRow copyWithCompanion(ComicReadLaterEntriesCompanion data) {
    return ComicReadLaterRow(
      id: data.id.present ? data.id.value : this.id,
      sourceName: data.sourceName.present
          ? data.sourceName.value
          : this.sourceName,
      title: data.title.present ? data.title.value : this.title,
      coverUrl: data.coverUrl.present ? data.coverUrl.value : this.coverUrl,
      detailUrl: data.detailUrl.present ? data.detailUrl.value : this.detailUrl,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ComicReadLaterRow(')
          ..write('id: $id, ')
          ..write('sourceName: $sourceName, ')
          ..write('title: $title, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('detailUrl: $detailUrl, ')
          ..write('addedAt: $addedAt, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, sourceName, title, coverUrl, detailUrl, addedAt, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ComicReadLaterRow &&
          other.id == this.id &&
          other.sourceName == this.sourceName &&
          other.title == this.title &&
          other.coverUrl == this.coverUrl &&
          other.detailUrl == this.detailUrl &&
          other.addedAt == this.addedAt &&
          other.payload == this.payload);
}

class ComicReadLaterEntriesCompanion
    extends UpdateCompanion<ComicReadLaterRow> {
  final Value<String> id;
  final Value<String> sourceName;
  final Value<String> title;
  final Value<String?> coverUrl;
  final Value<String> detailUrl;
  final Value<DateTime> addedAt;
  final Value<String> payload;
  final Value<int> rowid;
  const ComicReadLaterEntriesCompanion({
    this.id = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.title = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.detailUrl = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ComicReadLaterEntriesCompanion.insert({
    required String id,
    required String sourceName,
    required String title,
    this.coverUrl = const Value.absent(),
    this.detailUrl = const Value.absent(),
    required DateTime addedAt,
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sourceName = Value(sourceName),
       title = Value(title),
       addedAt = Value(addedAt);
  static Insertable<ComicReadLaterRow> custom({
    Expression<String>? id,
    Expression<String>? sourceName,
    Expression<String>? title,
    Expression<String>? coverUrl,
    Expression<String>? detailUrl,
    Expression<DateTime>? addedAt,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceName != null) 'source_name': sourceName,
      if (title != null) 'title': title,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (detailUrl != null) 'detail_url': detailUrl,
      if (addedAt != null) 'added_at': addedAt,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ComicReadLaterEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? sourceName,
    Value<String>? title,
    Value<String?>? coverUrl,
    Value<String>? detailUrl,
    Value<DateTime>? addedAt,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return ComicReadLaterEntriesCompanion(
      id: id ?? this.id,
      sourceName: sourceName ?? this.sourceName,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      detailUrl: detailUrl ?? this.detailUrl,
      addedAt: addedAt ?? this.addedAt,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sourceName.present) {
      map['source_name'] = Variable<String>(sourceName.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (coverUrl.present) {
      map['cover_url'] = Variable<String>(coverUrl.value);
    }
    if (detailUrl.present) {
      map['detail_url'] = Variable<String>(detailUrl.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ComicReadLaterEntriesCompanion(')
          ..write('id: $id, ')
          ..write('sourceName: $sourceName, ')
          ..write('title: $title, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('detailUrl: $detailUrl, ')
          ..write('addedAt: $addedAt, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ComicSearchTermsTable extends ComicSearchTerms
    with TableInfo<$ComicSearchTermsTable, ComicSearchTermRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ComicSearchTermsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _termMeta = const VerificationMeta('term');
  @override
  late final GeneratedColumn<String> term = GeneratedColumn<String>(
    'term',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastUsedAtMeta = const VerificationMeta(
    'lastUsedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastUsedAt = GeneratedColumn<DateTime>(
    'last_used_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [term, lastUsedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'comic_search_term';
  @override
  VerificationContext validateIntegrity(
    Insertable<ComicSearchTermRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('term')) {
      context.handle(
        _termMeta,
        term.isAcceptableOrUnknown(data['term']!, _termMeta),
      );
    } else if (isInserting) {
      context.missing(_termMeta);
    }
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastUsedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {term};
  @override
  ComicSearchTermRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ComicSearchTermRow(
      term: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}term'],
      )!,
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used_at'],
      )!,
    );
  }

  @override
  $ComicSearchTermsTable createAlias(String alias) {
    return $ComicSearchTermsTable(attachedDatabase, alias);
  }
}

class ComicSearchTermRow extends DataClass
    implements Insertable<ComicSearchTermRow> {
  final String term;
  final DateTime lastUsedAt;
  const ComicSearchTermRow({required this.term, required this.lastUsedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['term'] = Variable<String>(term);
    map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    return map;
  }

  ComicSearchTermsCompanion toCompanion(bool nullToAbsent) {
    return ComicSearchTermsCompanion(
      term: Value(term),
      lastUsedAt: Value(lastUsedAt),
    );
  }

  factory ComicSearchTermRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ComicSearchTermRow(
      term: serializer.fromJson<String>(json['term']),
      lastUsedAt: serializer.fromJson<DateTime>(json['lastUsedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'term': serializer.toJson<String>(term),
      'lastUsedAt': serializer.toJson<DateTime>(lastUsedAt),
    };
  }

  ComicSearchTermRow copyWith({String? term, DateTime? lastUsedAt}) =>
      ComicSearchTermRow(
        term: term ?? this.term,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );
  ComicSearchTermRow copyWithCompanion(ComicSearchTermsCompanion data) {
    return ComicSearchTermRow(
      term: data.term.present ? data.term.value : this.term,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ComicSearchTermRow(')
          ..write('term: $term, ')
          ..write('lastUsedAt: $lastUsedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(term, lastUsedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ComicSearchTermRow &&
          other.term == this.term &&
          other.lastUsedAt == this.lastUsedAt);
}

class ComicSearchTermsCompanion extends UpdateCompanion<ComicSearchTermRow> {
  final Value<String> term;
  final Value<DateTime> lastUsedAt;
  final Value<int> rowid;
  const ComicSearchTermsCompanion({
    this.term = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ComicSearchTermsCompanion.insert({
    required String term,
    required DateTime lastUsedAt,
    this.rowid = const Value.absent(),
  }) : term = Value(term),
       lastUsedAt = Value(lastUsedAt);
  static Insertable<ComicSearchTermRow> custom({
    Expression<String>? term,
    Expression<DateTime>? lastUsedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (term != null) 'term': term,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ComicSearchTermsCompanion copyWith({
    Value<String>? term,
    Value<DateTime>? lastUsedAt,
    Value<int>? rowid,
  }) {
    return ComicSearchTermsCompanion(
      term: term ?? this.term,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (term.present) {
      map['term'] = Variable<String>(term.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ComicSearchTermsCompanion(')
          ..write('term: $term, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ComicDownloadTasksTable extends ComicDownloadTasks
    with TableInfo<$ComicDownloadTasksTable, ComicDownloadRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ComicDownloadTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
    'task_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceNameMeta = const VerificationMeta(
    'sourceName',
  );
  @override
  late final GeneratedColumn<String> sourceName = GeneratedColumn<String>(
    'source_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterIdMeta = const VerificationMeta(
    'chapterId',
  );
  @override
  late final GeneratedColumn<String> chapterId = GeneratedColumn<String>(
    'chapter_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _receivedBytesMeta = const VerificationMeta(
    'receivedBytes',
  );
  @override
  late final GeneratedColumn<int> receivedBytes = GeneratedColumn<int>(
    'received_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _totalBytesMeta = const VerificationMeta(
    'totalBytes',
  );
  @override
  late final GeneratedColumn<int> totalBytes = GeneratedColumn<int>(
    'total_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    taskId,
    id,
    sourceName,
    chapterId,
    status,
    receivedBytes,
    totalBytes,
    error,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'comic_download_task';
  @override
  VerificationContext validateIntegrity(
    Insertable<ComicDownloadRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('task_id')) {
      context.handle(
        _taskIdMeta,
        taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta),
      );
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source_name')) {
      context.handle(
        _sourceNameMeta,
        sourceName.isAcceptableOrUnknown(data['source_name']!, _sourceNameMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceNameMeta);
    }
    if (data.containsKey('chapter_id')) {
      context.handle(
        _chapterIdMeta,
        chapterId.isAcceptableOrUnknown(data['chapter_id']!, _chapterIdMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('received_bytes')) {
      context.handle(
        _receivedBytesMeta,
        receivedBytes.isAcceptableOrUnknown(
          data['received_bytes']!,
          _receivedBytesMeta,
        ),
      );
    }
    if (data.containsKey('total_bytes')) {
      context.handle(
        _totalBytesMeta,
        totalBytes.isAcceptableOrUnknown(data['total_bytes']!, _totalBytesMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {taskId};
  @override
  ComicDownloadRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ComicDownloadRow(
      taskId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}task_id'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sourceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_name'],
      )!,
      chapterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      receivedBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}received_bytes'],
      )!,
      totalBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_bytes'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ComicDownloadTasksTable createAlias(String alias) {
    return $ComicDownloadTasksTable(attachedDatabase, alias);
  }
}

class ComicDownloadRow extends DataClass
    implements Insertable<ComicDownloadRow> {
  /// 任务 id（模块内唯一，不与媒体主键绑定）。
  final String taskId;
  final String id;
  final String sourceName;

  /// 章节 id；整本下载时留空串。
  final String chapterId;

  /// 状态机字符串：pending/running/done/failed；合法性由 download.dart 把守。
  final String status;
  final int receivedBytes;
  final int totalBytes;

  /// 仅 failed 时有值。
  final String? error;
  final DateTime updatedAt;
  const ComicDownloadRow({
    required this.taskId,
    required this.id,
    required this.sourceName,
    required this.chapterId,
    required this.status,
    required this.receivedBytes,
    required this.totalBytes,
    this.error,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['task_id'] = Variable<String>(taskId);
    map['id'] = Variable<String>(id);
    map['source_name'] = Variable<String>(sourceName);
    map['chapter_id'] = Variable<String>(chapterId);
    map['status'] = Variable<String>(status);
    map['received_bytes'] = Variable<int>(receivedBytes);
    map['total_bytes'] = Variable<int>(totalBytes);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ComicDownloadTasksCompanion toCompanion(bool nullToAbsent) {
    return ComicDownloadTasksCompanion(
      taskId: Value(taskId),
      id: Value(id),
      sourceName: Value(sourceName),
      chapterId: Value(chapterId),
      status: Value(status),
      receivedBytes: Value(receivedBytes),
      totalBytes: Value(totalBytes),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      updatedAt: Value(updatedAt),
    );
  }

  factory ComicDownloadRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ComicDownloadRow(
      taskId: serializer.fromJson<String>(json['taskId']),
      id: serializer.fromJson<String>(json['id']),
      sourceName: serializer.fromJson<String>(json['sourceName']),
      chapterId: serializer.fromJson<String>(json['chapterId']),
      status: serializer.fromJson<String>(json['status']),
      receivedBytes: serializer.fromJson<int>(json['receivedBytes']),
      totalBytes: serializer.fromJson<int>(json['totalBytes']),
      error: serializer.fromJson<String?>(json['error']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'taskId': serializer.toJson<String>(taskId),
      'id': serializer.toJson<String>(id),
      'sourceName': serializer.toJson<String>(sourceName),
      'chapterId': serializer.toJson<String>(chapterId),
      'status': serializer.toJson<String>(status),
      'receivedBytes': serializer.toJson<int>(receivedBytes),
      'totalBytes': serializer.toJson<int>(totalBytes),
      'error': serializer.toJson<String?>(error),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ComicDownloadRow copyWith({
    String? taskId,
    String? id,
    String? sourceName,
    String? chapterId,
    String? status,
    int? receivedBytes,
    int? totalBytes,
    Value<String?> error = const Value.absent(),
    DateTime? updatedAt,
  }) => ComicDownloadRow(
    taskId: taskId ?? this.taskId,
    id: id ?? this.id,
    sourceName: sourceName ?? this.sourceName,
    chapterId: chapterId ?? this.chapterId,
    status: status ?? this.status,
    receivedBytes: receivedBytes ?? this.receivedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
    error: error.present ? error.value : this.error,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ComicDownloadRow copyWithCompanion(ComicDownloadTasksCompanion data) {
    return ComicDownloadRow(
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      id: data.id.present ? data.id.value : this.id,
      sourceName: data.sourceName.present
          ? data.sourceName.value
          : this.sourceName,
      chapterId: data.chapterId.present ? data.chapterId.value : this.chapterId,
      status: data.status.present ? data.status.value : this.status,
      receivedBytes: data.receivedBytes.present
          ? data.receivedBytes.value
          : this.receivedBytes,
      totalBytes: data.totalBytes.present
          ? data.totalBytes.value
          : this.totalBytes,
      error: data.error.present ? data.error.value : this.error,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ComicDownloadRow(')
          ..write('taskId: $taskId, ')
          ..write('id: $id, ')
          ..write('sourceName: $sourceName, ')
          ..write('chapterId: $chapterId, ')
          ..write('status: $status, ')
          ..write('receivedBytes: $receivedBytes, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('error: $error, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    taskId,
    id,
    sourceName,
    chapterId,
    status,
    receivedBytes,
    totalBytes,
    error,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ComicDownloadRow &&
          other.taskId == this.taskId &&
          other.id == this.id &&
          other.sourceName == this.sourceName &&
          other.chapterId == this.chapterId &&
          other.status == this.status &&
          other.receivedBytes == this.receivedBytes &&
          other.totalBytes == this.totalBytes &&
          other.error == this.error &&
          other.updatedAt == this.updatedAt);
}

class ComicDownloadTasksCompanion extends UpdateCompanion<ComicDownloadRow> {
  final Value<String> taskId;
  final Value<String> id;
  final Value<String> sourceName;
  final Value<String> chapterId;
  final Value<String> status;
  final Value<int> receivedBytes;
  final Value<int> totalBytes;
  final Value<String?> error;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ComicDownloadTasksCompanion({
    this.taskId = const Value.absent(),
    this.id = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.status = const Value.absent(),
    this.receivedBytes = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.error = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ComicDownloadTasksCompanion.insert({
    required String taskId,
    required String id,
    required String sourceName,
    this.chapterId = const Value.absent(),
    required String status,
    this.receivedBytes = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.error = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : taskId = Value(taskId),
       id = Value(id),
       sourceName = Value(sourceName),
       status = Value(status),
       updatedAt = Value(updatedAt);
  static Insertable<ComicDownloadRow> custom({
    Expression<String>? taskId,
    Expression<String>? id,
    Expression<String>? sourceName,
    Expression<String>? chapterId,
    Expression<String>? status,
    Expression<int>? receivedBytes,
    Expression<int>? totalBytes,
    Expression<String>? error,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (taskId != null) 'task_id': taskId,
      if (id != null) 'id': id,
      if (sourceName != null) 'source_name': sourceName,
      if (chapterId != null) 'chapter_id': chapterId,
      if (status != null) 'status': status,
      if (receivedBytes != null) 'received_bytes': receivedBytes,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (error != null) 'error': error,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ComicDownloadTasksCompanion copyWith({
    Value<String>? taskId,
    Value<String>? id,
    Value<String>? sourceName,
    Value<String>? chapterId,
    Value<String>? status,
    Value<int>? receivedBytes,
    Value<int>? totalBytes,
    Value<String?>? error,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ComicDownloadTasksCompanion(
      taskId: taskId ?? this.taskId,
      id: id ?? this.id,
      sourceName: sourceName ?? this.sourceName,
      chapterId: chapterId ?? this.chapterId,
      status: status ?? this.status,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      error: error ?? this.error,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sourceName.present) {
      map['source_name'] = Variable<String>(sourceName.value);
    }
    if (chapterId.present) {
      map['chapter_id'] = Variable<String>(chapterId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (receivedBytes.present) {
      map['received_bytes'] = Variable<int>(receivedBytes.value);
    }
    if (totalBytes.present) {
      map['total_bytes'] = Variable<int>(totalBytes.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ComicDownloadTasksCompanion(')
          ..write('taskId: $taskId, ')
          ..write('id: $id, ')
          ..write('sourceName: $sourceName, ')
          ..write('chapterId: $chapterId, ')
          ..write('status: $status, ')
          ..write('receivedBytes: $receivedBytes, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('error: $error, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ComicImageCacheEntriesTable extends ComicImageCacheEntries
    with TableInfo<$ComicImageCacheEntriesTable, ComicImageCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ComicImageCacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _cacheKeyMeta = const VerificationMeta(
    'cacheKey',
  );
  @override
  late final GeneratedColumn<String> cacheKey = GeneratedColumn<String>(
    'cache_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceNameMeta = const VerificationMeta(
    'sourceName',
  );
  @override
  late final GeneratedColumn<String> sourceName = GeneratedColumn<String>(
    'source_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterIdMeta = const VerificationMeta(
    'chapterId',
  );
  @override
  late final GeneratedColumn<String> chapterId = GeneratedColumn<String>(
    'chapter_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    cacheKey,
    id,
    sourceName,
    chapterId,
    filePath,
    cachedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'comic_image_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<ComicImageCacheRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('cache_key')) {
      context.handle(
        _cacheKeyMeta,
        cacheKey.isAcceptableOrUnknown(data['cache_key']!, _cacheKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_cacheKeyMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source_name')) {
      context.handle(
        _sourceNameMeta,
        sourceName.isAcceptableOrUnknown(data['source_name']!, _sourceNameMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceNameMeta);
    }
    if (data.containsKey('chapter_id')) {
      context.handle(
        _chapterIdMeta,
        chapterId.isAcceptableOrUnknown(data['chapter_id']!, _chapterIdMeta),
      );
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {cacheKey};
  @override
  ComicImageCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ComicImageCacheRow(
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sourceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_name'],
      )!,
      chapterId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_id'],
      )!,
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
    );
  }

  @override
  $ComicImageCacheEntriesTable createAlias(String alias) {
    return $ComicImageCacheEntriesTable(attachedDatabase, alias);
  }
}

class ComicImageCacheRow extends DataClass
    implements Insertable<ComicImageCacheRow> {
  /// 缓存键：章节下每张图的稳定标识（如 URL 或本地相对路径）。
  final String cacheKey;
  final String id;
  final String sourceName;
  final String chapterId;

  /// 缓存文件路径（模块自己定，core 不解释）。
  final String filePath;
  final DateTime cachedAt;
  const ComicImageCacheRow({
    required this.cacheKey,
    required this.id,
    required this.sourceName,
    required this.chapterId,
    required this.filePath,
    required this.cachedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cache_key'] = Variable<String>(cacheKey);
    map['id'] = Variable<String>(id);
    map['source_name'] = Variable<String>(sourceName);
    map['chapter_id'] = Variable<String>(chapterId);
    map['file_path'] = Variable<String>(filePath);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    return map;
  }

  ComicImageCacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return ComicImageCacheEntriesCompanion(
      cacheKey: Value(cacheKey),
      id: Value(id),
      sourceName: Value(sourceName),
      chapterId: Value(chapterId),
      filePath: Value(filePath),
      cachedAt: Value(cachedAt),
    );
  }

  factory ComicImageCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ComicImageCacheRow(
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      id: serializer.fromJson<String>(json['id']),
      sourceName: serializer.fromJson<String>(json['sourceName']),
      chapterId: serializer.fromJson<String>(json['chapterId']),
      filePath: serializer.fromJson<String>(json['filePath']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cacheKey': serializer.toJson<String>(cacheKey),
      'id': serializer.toJson<String>(id),
      'sourceName': serializer.toJson<String>(sourceName),
      'chapterId': serializer.toJson<String>(chapterId),
      'filePath': serializer.toJson<String>(filePath),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
    };
  }

  ComicImageCacheRow copyWith({
    String? cacheKey,
    String? id,
    String? sourceName,
    String? chapterId,
    String? filePath,
    DateTime? cachedAt,
  }) => ComicImageCacheRow(
    cacheKey: cacheKey ?? this.cacheKey,
    id: id ?? this.id,
    sourceName: sourceName ?? this.sourceName,
    chapterId: chapterId ?? this.chapterId,
    filePath: filePath ?? this.filePath,
    cachedAt: cachedAt ?? this.cachedAt,
  );
  ComicImageCacheRow copyWithCompanion(ComicImageCacheEntriesCompanion data) {
    return ComicImageCacheRow(
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      id: data.id.present ? data.id.value : this.id,
      sourceName: data.sourceName.present
          ? data.sourceName.value
          : this.sourceName,
      chapterId: data.chapterId.present ? data.chapterId.value : this.chapterId,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ComicImageCacheRow(')
          ..write('cacheKey: $cacheKey, ')
          ..write('id: $id, ')
          ..write('sourceName: $sourceName, ')
          ..write('chapterId: $chapterId, ')
          ..write('filePath: $filePath, ')
          ..write('cachedAt: $cachedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(cacheKey, id, sourceName, chapterId, filePath, cachedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ComicImageCacheRow &&
          other.cacheKey == this.cacheKey &&
          other.id == this.id &&
          other.sourceName == this.sourceName &&
          other.chapterId == this.chapterId &&
          other.filePath == this.filePath &&
          other.cachedAt == this.cachedAt);
}

class ComicImageCacheEntriesCompanion
    extends UpdateCompanion<ComicImageCacheRow> {
  final Value<String> cacheKey;
  final Value<String> id;
  final Value<String> sourceName;
  final Value<String> chapterId;
  final Value<String> filePath;
  final Value<DateTime> cachedAt;
  final Value<int> rowid;
  const ComicImageCacheEntriesCompanion({
    this.cacheKey = const Value.absent(),
    this.id = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.chapterId = const Value.absent(),
    this.filePath = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ComicImageCacheEntriesCompanion.insert({
    required String cacheKey,
    required String id,
    required String sourceName,
    this.chapterId = const Value.absent(),
    required String filePath,
    required DateTime cachedAt,
    this.rowid = const Value.absent(),
  }) : cacheKey = Value(cacheKey),
       id = Value(id),
       sourceName = Value(sourceName),
       filePath = Value(filePath),
       cachedAt = Value(cachedAt);
  static Insertable<ComicImageCacheRow> custom({
    Expression<String>? cacheKey,
    Expression<String>? id,
    Expression<String>? sourceName,
    Expression<String>? chapterId,
    Expression<String>? filePath,
    Expression<DateTime>? cachedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cacheKey != null) 'cache_key': cacheKey,
      if (id != null) 'id': id,
      if (sourceName != null) 'source_name': sourceName,
      if (chapterId != null) 'chapter_id': chapterId,
      if (filePath != null) 'file_path': filePath,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ComicImageCacheEntriesCompanion copyWith({
    Value<String>? cacheKey,
    Value<String>? id,
    Value<String>? sourceName,
    Value<String>? chapterId,
    Value<String>? filePath,
    Value<DateTime>? cachedAt,
    Value<int>? rowid,
  }) {
    return ComicImageCacheEntriesCompanion(
      cacheKey: cacheKey ?? this.cacheKey,
      id: id ?? this.id,
      sourceName: sourceName ?? this.sourceName,
      chapterId: chapterId ?? this.chapterId,
      filePath: filePath ?? this.filePath,
      cachedAt: cachedAt ?? this.cachedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sourceName.present) {
      map['source_name'] = Variable<String>(sourceName.value);
    }
    if (chapterId.present) {
      map['chapter_id'] = Variable<String>(chapterId.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ComicImageCacheEntriesCompanion(')
          ..write('cacheKey: $cacheKey, ')
          ..write('id: $id, ')
          ..write('sourceName: $sourceName, ')
          ..write('chapterId: $chapterId, ')
          ..write('filePath: $filePath, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ComicLocalEntriesTable extends ComicLocalEntries
    with TableInfo<$ComicLocalEntriesTable, ComicLocalRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ComicLocalEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceNameMeta = const VerificationMeta(
    'sourceName',
  );
  @override
  late final GeneratedColumn<String> sourceName = GeneratedColumn<String>(
    'source_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _folderPathMeta = const VerificationMeta(
    'folderPath',
  );
  @override
  late final GeneratedColumn<String> folderPath = GeneratedColumn<String>(
    'folder_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _coverPathMeta = const VerificationMeta(
    'coverPath',
  );
  @override
  late final GeneratedColumn<String> coverPath = GeneratedColumn<String>(
    'cover_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pageCountMeta = const VerificationMeta(
    'pageCount',
  );
  @override
  late final GeneratedColumn<int> pageCount = GeneratedColumn<int>(
    'page_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _importedAtMeta = const VerificationMeta(
    'importedAt',
  );
  @override
  late final GeneratedColumn<DateTime> importedAt = GeneratedColumn<DateTime>(
    'imported_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceName,
    title,
    folderPath,
    coverPath,
    pageCount,
    payload,
    importedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'comic_local';
  @override
  VerificationContext validateIntegrity(
    Insertable<ComicLocalRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('source_name')) {
      context.handle(
        _sourceNameMeta,
        sourceName.isAcceptableOrUnknown(data['source_name']!, _sourceNameMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceNameMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('folder_path')) {
      context.handle(
        _folderPathMeta,
        folderPath.isAcceptableOrUnknown(data['folder_path']!, _folderPathMeta),
      );
    } else if (isInserting) {
      context.missing(_folderPathMeta);
    }
    if (data.containsKey('cover_path')) {
      context.handle(
        _coverPathMeta,
        coverPath.isAcceptableOrUnknown(data['cover_path']!, _coverPathMeta),
      );
    }
    if (data.containsKey('page_count')) {
      context.handle(
        _pageCountMeta,
        pageCount.isAcceptableOrUnknown(data['page_count']!, _pageCountMeta),
      );
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('imported_at')) {
      context.handle(
        _importedAtMeta,
        importedAt.isAcceptableOrUnknown(data['imported_at']!, _importedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_importedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, sourceName};
  @override
  ComicLocalRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ComicLocalRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sourceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_name'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      folderPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_path'],
      )!,
      coverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_path'],
      ),
      pageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_count'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      importedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}imported_at'],
      )!,
    );
  }

  @override
  $ComicLocalEntriesTable createAlias(String alias) {
    return $ComicLocalEntriesTable(attachedDatabase, alias);
  }
}

class ComicLocalRow extends DataClass implements Insertable<ComicLocalRow> {
  final String id;
  final String sourceName;
  final String title;
  final String folderPath;
  final String? coverPath;
  final int pageCount;

  /// 模块私有 JSON；core 投影不解析。
  final String payload;
  final DateTime importedAt;
  const ComicLocalRow({
    required this.id,
    required this.sourceName,
    required this.title,
    required this.folderPath,
    this.coverPath,
    required this.pageCount,
    required this.payload,
    required this.importedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['source_name'] = Variable<String>(sourceName);
    map['title'] = Variable<String>(title);
    map['folder_path'] = Variable<String>(folderPath);
    if (!nullToAbsent || coverPath != null) {
      map['cover_path'] = Variable<String>(coverPath);
    }
    map['page_count'] = Variable<int>(pageCount);
    map['payload'] = Variable<String>(payload);
    map['imported_at'] = Variable<DateTime>(importedAt);
    return map;
  }

  ComicLocalEntriesCompanion toCompanion(bool nullToAbsent) {
    return ComicLocalEntriesCompanion(
      id: Value(id),
      sourceName: Value(sourceName),
      title: Value(title),
      folderPath: Value(folderPath),
      coverPath: coverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverPath),
      pageCount: Value(pageCount),
      payload: Value(payload),
      importedAt: Value(importedAt),
    );
  }

  factory ComicLocalRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ComicLocalRow(
      id: serializer.fromJson<String>(json['id']),
      sourceName: serializer.fromJson<String>(json['sourceName']),
      title: serializer.fromJson<String>(json['title']),
      folderPath: serializer.fromJson<String>(json['folderPath']),
      coverPath: serializer.fromJson<String?>(json['coverPath']),
      pageCount: serializer.fromJson<int>(json['pageCount']),
      payload: serializer.fromJson<String>(json['payload']),
      importedAt: serializer.fromJson<DateTime>(json['importedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sourceName': serializer.toJson<String>(sourceName),
      'title': serializer.toJson<String>(title),
      'folderPath': serializer.toJson<String>(folderPath),
      'coverPath': serializer.toJson<String?>(coverPath),
      'pageCount': serializer.toJson<int>(pageCount),
      'payload': serializer.toJson<String>(payload),
      'importedAt': serializer.toJson<DateTime>(importedAt),
    };
  }

  ComicLocalRow copyWith({
    String? id,
    String? sourceName,
    String? title,
    String? folderPath,
    Value<String?> coverPath = const Value.absent(),
    int? pageCount,
    String? payload,
    DateTime? importedAt,
  }) => ComicLocalRow(
    id: id ?? this.id,
    sourceName: sourceName ?? this.sourceName,
    title: title ?? this.title,
    folderPath: folderPath ?? this.folderPath,
    coverPath: coverPath.present ? coverPath.value : this.coverPath,
    pageCount: pageCount ?? this.pageCount,
    payload: payload ?? this.payload,
    importedAt: importedAt ?? this.importedAt,
  );
  ComicLocalRow copyWithCompanion(ComicLocalEntriesCompanion data) {
    return ComicLocalRow(
      id: data.id.present ? data.id.value : this.id,
      sourceName: data.sourceName.present
          ? data.sourceName.value
          : this.sourceName,
      title: data.title.present ? data.title.value : this.title,
      folderPath: data.folderPath.present
          ? data.folderPath.value
          : this.folderPath,
      coverPath: data.coverPath.present ? data.coverPath.value : this.coverPath,
      pageCount: data.pageCount.present ? data.pageCount.value : this.pageCount,
      payload: data.payload.present ? data.payload.value : this.payload,
      importedAt: data.importedAt.present
          ? data.importedAt.value
          : this.importedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ComicLocalRow(')
          ..write('id: $id, ')
          ..write('sourceName: $sourceName, ')
          ..write('title: $title, ')
          ..write('folderPath: $folderPath, ')
          ..write('coverPath: $coverPath, ')
          ..write('pageCount: $pageCount, ')
          ..write('payload: $payload, ')
          ..write('importedAt: $importedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sourceName,
    title,
    folderPath,
    coverPath,
    pageCount,
    payload,
    importedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ComicLocalRow &&
          other.id == this.id &&
          other.sourceName == this.sourceName &&
          other.title == this.title &&
          other.folderPath == this.folderPath &&
          other.coverPath == this.coverPath &&
          other.pageCount == this.pageCount &&
          other.payload == this.payload &&
          other.importedAt == this.importedAt);
}

class ComicLocalEntriesCompanion extends UpdateCompanion<ComicLocalRow> {
  final Value<String> id;
  final Value<String> sourceName;
  final Value<String> title;
  final Value<String> folderPath;
  final Value<String?> coverPath;
  final Value<int> pageCount;
  final Value<String> payload;
  final Value<DateTime> importedAt;
  final Value<int> rowid;
  const ComicLocalEntriesCompanion({
    this.id = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.title = const Value.absent(),
    this.folderPath = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.payload = const Value.absent(),
    this.importedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ComicLocalEntriesCompanion.insert({
    required String id,
    required String sourceName,
    required String title,
    required String folderPath,
    this.coverPath = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.payload = const Value.absent(),
    required DateTime importedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sourceName = Value(sourceName),
       title = Value(title),
       folderPath = Value(folderPath),
       importedAt = Value(importedAt);
  static Insertable<ComicLocalRow> custom({
    Expression<String>? id,
    Expression<String>? sourceName,
    Expression<String>? title,
    Expression<String>? folderPath,
    Expression<String>? coverPath,
    Expression<int>? pageCount,
    Expression<String>? payload,
    Expression<DateTime>? importedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceName != null) 'source_name': sourceName,
      if (title != null) 'title': title,
      if (folderPath != null) 'folder_path': folderPath,
      if (coverPath != null) 'cover_path': coverPath,
      if (pageCount != null) 'page_count': pageCount,
      if (payload != null) 'payload': payload,
      if (importedAt != null) 'imported_at': importedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ComicLocalEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? sourceName,
    Value<String>? title,
    Value<String>? folderPath,
    Value<String?>? coverPath,
    Value<int>? pageCount,
    Value<String>? payload,
    Value<DateTime>? importedAt,
    Value<int>? rowid,
  }) {
    return ComicLocalEntriesCompanion(
      id: id ?? this.id,
      sourceName: sourceName ?? this.sourceName,
      title: title ?? this.title,
      folderPath: folderPath ?? this.folderPath,
      coverPath: coverPath ?? this.coverPath,
      pageCount: pageCount ?? this.pageCount,
      payload: payload ?? this.payload,
      importedAt: importedAt ?? this.importedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sourceName.present) {
      map['source_name'] = Variable<String>(sourceName.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (folderPath.present) {
      map['folder_path'] = Variable<String>(folderPath.value);
    }
    if (coverPath.present) {
      map['cover_path'] = Variable<String>(coverPath.value);
    }
    if (pageCount.present) {
      map['page_count'] = Variable<int>(pageCount.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (importedAt.present) {
      map['imported_at'] = Variable<DateTime>(importedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ComicLocalEntriesCompanion(')
          ..write('id: $id, ')
          ..write('sourceName: $sourceName, ')
          ..write('title: $title, ')
          ..write('folderPath: $folderPath, ')
          ..write('coverPath: $coverPath, ')
          ..write('pageCount: $pageCount, ')
          ..write('payload: $payload, ')
          ..write('importedAt: $importedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ComicDb extends GeneratedDatabase {
  _$ComicDb(QueryExecutor e) : super(e);
  $ComicDbManager get managers => $ComicDbManager(this);
  late final $ComicCollectEntriesTable comicCollectEntries =
      $ComicCollectEntriesTable(this);
  late final $ComicHistoryEntriesTable comicHistoryEntries =
      $ComicHistoryEntriesTable(this);
  late final $ComicReadLaterEntriesTable comicReadLaterEntries =
      $ComicReadLaterEntriesTable(this);
  late final $ComicSearchTermsTable comicSearchTerms = $ComicSearchTermsTable(
    this,
  );
  late final $ComicDownloadTasksTable comicDownloadTasks =
      $ComicDownloadTasksTable(this);
  late final $ComicImageCacheEntriesTable comicImageCacheEntries =
      $ComicImageCacheEntriesTable(this);
  late final $ComicLocalEntriesTable comicLocalEntries =
      $ComicLocalEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    comicCollectEntries,
    comicHistoryEntries,
    comicReadLaterEntries,
    comicSearchTerms,
    comicDownloadTasks,
    comicImageCacheEntries,
    comicLocalEntries,
  ];
}

typedef $$ComicCollectEntriesTableCreateCompanionBuilder =
    ComicCollectEntriesCompanion Function({
      required String id,
      required String sourceName,
      required String title,
      Value<String?> coverUrl,
      Value<String> payload,
      required DateTime collectedAt,
      Value<int> rowid,
    });
typedef $$ComicCollectEntriesTableUpdateCompanionBuilder =
    ComicCollectEntriesCompanion Function({
      Value<String> id,
      Value<String> sourceName,
      Value<String> title,
      Value<String?> coverUrl,
      Value<String> payload,
      Value<DateTime> collectedAt,
      Value<int> rowid,
    });

class $$ComicCollectEntriesTableFilterComposer
    extends Composer<_$ComicDb, $ComicCollectEntriesTable> {
  $$ComicCollectEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get collectedAt => $composableBuilder(
    column: $table.collectedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ComicCollectEntriesTableOrderingComposer
    extends Composer<_$ComicDb, $ComicCollectEntriesTable> {
  $$ComicCollectEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get collectedAt => $composableBuilder(
    column: $table.collectedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ComicCollectEntriesTableAnnotationComposer
    extends Composer<_$ComicDb, $ComicCollectEntriesTable> {
  $$ComicCollectEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get coverUrl =>
      $composableBuilder(column: $table.coverUrl, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get collectedAt => $composableBuilder(
    column: $table.collectedAt,
    builder: (column) => column,
  );
}

class $$ComicCollectEntriesTableTableManager
    extends
        RootTableManager<
          _$ComicDb,
          $ComicCollectEntriesTable,
          ComicCollectRow,
          $$ComicCollectEntriesTableFilterComposer,
          $$ComicCollectEntriesTableOrderingComposer,
          $$ComicCollectEntriesTableAnnotationComposer,
          $$ComicCollectEntriesTableCreateCompanionBuilder,
          $$ComicCollectEntriesTableUpdateCompanionBuilder,
          (
            ComicCollectRow,
            BaseReferences<
              _$ComicDb,
              $ComicCollectEntriesTable,
              ComicCollectRow
            >,
          ),
          ComicCollectRow,
          PrefetchHooks Function()
        > {
  $$ComicCollectEntriesTableTableManager(
    _$ComicDb db,
    $ComicCollectEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ComicCollectEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ComicCollectEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ComicCollectEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sourceName = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> coverUrl = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> collectedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ComicCollectEntriesCompanion(
                id: id,
                sourceName: sourceName,
                title: title,
                coverUrl: coverUrl,
                payload: payload,
                collectedAt: collectedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sourceName,
                required String title,
                Value<String?> coverUrl = const Value.absent(),
                Value<String> payload = const Value.absent(),
                required DateTime collectedAt,
                Value<int> rowid = const Value.absent(),
              }) => ComicCollectEntriesCompanion.insert(
                id: id,
                sourceName: sourceName,
                title: title,
                coverUrl: coverUrl,
                payload: payload,
                collectedAt: collectedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ComicCollectEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$ComicDb,
      $ComicCollectEntriesTable,
      ComicCollectRow,
      $$ComicCollectEntriesTableFilterComposer,
      $$ComicCollectEntriesTableOrderingComposer,
      $$ComicCollectEntriesTableAnnotationComposer,
      $$ComicCollectEntriesTableCreateCompanionBuilder,
      $$ComicCollectEntriesTableUpdateCompanionBuilder,
      (
        ComicCollectRow,
        BaseReferences<_$ComicDb, $ComicCollectEntriesTable, ComicCollectRow>,
      ),
      ComicCollectRow,
      PrefetchHooks Function()
    >;
typedef $$ComicHistoryEntriesTableCreateCompanionBuilder =
    ComicHistoryEntriesCompanion Function({
      required String id,
      required String sourceName,
      required String title,
      Value<String?> coverUrl,
      Value<String> chapterId,
      Value<int> page,
      Value<int> pageCount,
      required DateTime openedAt,
      Value<int> rowid,
    });
typedef $$ComicHistoryEntriesTableUpdateCompanionBuilder =
    ComicHistoryEntriesCompanion Function({
      Value<String> id,
      Value<String> sourceName,
      Value<String> title,
      Value<String?> coverUrl,
      Value<String> chapterId,
      Value<int> page,
      Value<int> pageCount,
      Value<DateTime> openedAt,
      Value<int> rowid,
    });

class $$ComicHistoryEntriesTableFilterComposer
    extends Composer<_$ComicDb, $ComicHistoryEntriesTable> {
  $$ComicHistoryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get page => $composableBuilder(
    column: $table.page,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ComicHistoryEntriesTableOrderingComposer
    extends Composer<_$ComicDb, $ComicHistoryEntriesTable> {
  $$ComicHistoryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get page => $composableBuilder(
    column: $table.page,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ComicHistoryEntriesTableAnnotationComposer
    extends Composer<_$ComicDb, $ComicHistoryEntriesTable> {
  $$ComicHistoryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get coverUrl =>
      $composableBuilder(column: $table.coverUrl, builder: (column) => column);

  GeneratedColumn<String> get chapterId =>
      $composableBuilder(column: $table.chapterId, builder: (column) => column);

  GeneratedColumn<int> get page =>
      $composableBuilder(column: $table.page, builder: (column) => column);

  GeneratedColumn<int> get pageCount =>
      $composableBuilder(column: $table.pageCount, builder: (column) => column);

  GeneratedColumn<DateTime> get openedAt =>
      $composableBuilder(column: $table.openedAt, builder: (column) => column);
}

class $$ComicHistoryEntriesTableTableManager
    extends
        RootTableManager<
          _$ComicDb,
          $ComicHistoryEntriesTable,
          ComicHistoryRow,
          $$ComicHistoryEntriesTableFilterComposer,
          $$ComicHistoryEntriesTableOrderingComposer,
          $$ComicHistoryEntriesTableAnnotationComposer,
          $$ComicHistoryEntriesTableCreateCompanionBuilder,
          $$ComicHistoryEntriesTableUpdateCompanionBuilder,
          (
            ComicHistoryRow,
            BaseReferences<
              _$ComicDb,
              $ComicHistoryEntriesTable,
              ComicHistoryRow
            >,
          ),
          ComicHistoryRow,
          PrefetchHooks Function()
        > {
  $$ComicHistoryEntriesTableTableManager(
    _$ComicDb db,
    $ComicHistoryEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ComicHistoryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ComicHistoryEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ComicHistoryEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sourceName = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> coverUrl = const Value.absent(),
                Value<String> chapterId = const Value.absent(),
                Value<int> page = const Value.absent(),
                Value<int> pageCount = const Value.absent(),
                Value<DateTime> openedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ComicHistoryEntriesCompanion(
                id: id,
                sourceName: sourceName,
                title: title,
                coverUrl: coverUrl,
                chapterId: chapterId,
                page: page,
                pageCount: pageCount,
                openedAt: openedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sourceName,
                required String title,
                Value<String?> coverUrl = const Value.absent(),
                Value<String> chapterId = const Value.absent(),
                Value<int> page = const Value.absent(),
                Value<int> pageCount = const Value.absent(),
                required DateTime openedAt,
                Value<int> rowid = const Value.absent(),
              }) => ComicHistoryEntriesCompanion.insert(
                id: id,
                sourceName: sourceName,
                title: title,
                coverUrl: coverUrl,
                chapterId: chapterId,
                page: page,
                pageCount: pageCount,
                openedAt: openedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ComicHistoryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$ComicDb,
      $ComicHistoryEntriesTable,
      ComicHistoryRow,
      $$ComicHistoryEntriesTableFilterComposer,
      $$ComicHistoryEntriesTableOrderingComposer,
      $$ComicHistoryEntriesTableAnnotationComposer,
      $$ComicHistoryEntriesTableCreateCompanionBuilder,
      $$ComicHistoryEntriesTableUpdateCompanionBuilder,
      (
        ComicHistoryRow,
        BaseReferences<_$ComicDb, $ComicHistoryEntriesTable, ComicHistoryRow>,
      ),
      ComicHistoryRow,
      PrefetchHooks Function()
    >;
typedef $$ComicReadLaterEntriesTableCreateCompanionBuilder =
    ComicReadLaterEntriesCompanion Function({
      required String id,
      required String sourceName,
      required String title,
      Value<String?> coverUrl,
      Value<String> detailUrl,
      required DateTime addedAt,
      Value<String> payload,
      Value<int> rowid,
    });
typedef $$ComicReadLaterEntriesTableUpdateCompanionBuilder =
    ComicReadLaterEntriesCompanion Function({
      Value<String> id,
      Value<String> sourceName,
      Value<String> title,
      Value<String?> coverUrl,
      Value<String> detailUrl,
      Value<DateTime> addedAt,
      Value<String> payload,
      Value<int> rowid,
    });

class $$ComicReadLaterEntriesTableFilterComposer
    extends Composer<_$ComicDb, $ComicReadLaterEntriesTable> {
  $$ComicReadLaterEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detailUrl => $composableBuilder(
    column: $table.detailUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ComicReadLaterEntriesTableOrderingComposer
    extends Composer<_$ComicDb, $ComicReadLaterEntriesTable> {
  $$ComicReadLaterEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detailUrl => $composableBuilder(
    column: $table.detailUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ComicReadLaterEntriesTableAnnotationComposer
    extends Composer<_$ComicDb, $ComicReadLaterEntriesTable> {
  $$ComicReadLaterEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get coverUrl =>
      $composableBuilder(column: $table.coverUrl, builder: (column) => column);

  GeneratedColumn<String> get detailUrl =>
      $composableBuilder(column: $table.detailUrl, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$ComicReadLaterEntriesTableTableManager
    extends
        RootTableManager<
          _$ComicDb,
          $ComicReadLaterEntriesTable,
          ComicReadLaterRow,
          $$ComicReadLaterEntriesTableFilterComposer,
          $$ComicReadLaterEntriesTableOrderingComposer,
          $$ComicReadLaterEntriesTableAnnotationComposer,
          $$ComicReadLaterEntriesTableCreateCompanionBuilder,
          $$ComicReadLaterEntriesTableUpdateCompanionBuilder,
          (
            ComicReadLaterRow,
            BaseReferences<
              _$ComicDb,
              $ComicReadLaterEntriesTable,
              ComicReadLaterRow
            >,
          ),
          ComicReadLaterRow,
          PrefetchHooks Function()
        > {
  $$ComicReadLaterEntriesTableTableManager(
    _$ComicDb db,
    $ComicReadLaterEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ComicReadLaterEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ComicReadLaterEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ComicReadLaterEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sourceName = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> coverUrl = const Value.absent(),
                Value<String> detailUrl = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ComicReadLaterEntriesCompanion(
                id: id,
                sourceName: sourceName,
                title: title,
                coverUrl: coverUrl,
                detailUrl: detailUrl,
                addedAt: addedAt,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sourceName,
                required String title,
                Value<String?> coverUrl = const Value.absent(),
                Value<String> detailUrl = const Value.absent(),
                required DateTime addedAt,
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ComicReadLaterEntriesCompanion.insert(
                id: id,
                sourceName: sourceName,
                title: title,
                coverUrl: coverUrl,
                detailUrl: detailUrl,
                addedAt: addedAt,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ComicReadLaterEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$ComicDb,
      $ComicReadLaterEntriesTable,
      ComicReadLaterRow,
      $$ComicReadLaterEntriesTableFilterComposer,
      $$ComicReadLaterEntriesTableOrderingComposer,
      $$ComicReadLaterEntriesTableAnnotationComposer,
      $$ComicReadLaterEntriesTableCreateCompanionBuilder,
      $$ComicReadLaterEntriesTableUpdateCompanionBuilder,
      (
        ComicReadLaterRow,
        BaseReferences<
          _$ComicDb,
          $ComicReadLaterEntriesTable,
          ComicReadLaterRow
        >,
      ),
      ComicReadLaterRow,
      PrefetchHooks Function()
    >;
typedef $$ComicSearchTermsTableCreateCompanionBuilder =
    ComicSearchTermsCompanion Function({
      required String term,
      required DateTime lastUsedAt,
      Value<int> rowid,
    });
typedef $$ComicSearchTermsTableUpdateCompanionBuilder =
    ComicSearchTermsCompanion Function({
      Value<String> term,
      Value<DateTime> lastUsedAt,
      Value<int> rowid,
    });

class $$ComicSearchTermsTableFilterComposer
    extends Composer<_$ComicDb, $ComicSearchTermsTable> {
  $$ComicSearchTermsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get term => $composableBuilder(
    column: $table.term,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ComicSearchTermsTableOrderingComposer
    extends Composer<_$ComicDb, $ComicSearchTermsTable> {
  $$ComicSearchTermsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get term => $composableBuilder(
    column: $table.term,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ComicSearchTermsTableAnnotationComposer
    extends Composer<_$ComicDb, $ComicSearchTermsTable> {
  $$ComicSearchTermsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get term =>
      $composableBuilder(column: $table.term, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );
}

class $$ComicSearchTermsTableTableManager
    extends
        RootTableManager<
          _$ComicDb,
          $ComicSearchTermsTable,
          ComicSearchTermRow,
          $$ComicSearchTermsTableFilterComposer,
          $$ComicSearchTermsTableOrderingComposer,
          $$ComicSearchTermsTableAnnotationComposer,
          $$ComicSearchTermsTableCreateCompanionBuilder,
          $$ComicSearchTermsTableUpdateCompanionBuilder,
          (
            ComicSearchTermRow,
            BaseReferences<
              _$ComicDb,
              $ComicSearchTermsTable,
              ComicSearchTermRow
            >,
          ),
          ComicSearchTermRow,
          PrefetchHooks Function()
        > {
  $$ComicSearchTermsTableTableManager(
    _$ComicDb db,
    $ComicSearchTermsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ComicSearchTermsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ComicSearchTermsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ComicSearchTermsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> term = const Value.absent(),
                Value<DateTime> lastUsedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ComicSearchTermsCompanion(
                term: term,
                lastUsedAt: lastUsedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String term,
                required DateTime lastUsedAt,
                Value<int> rowid = const Value.absent(),
              }) => ComicSearchTermsCompanion.insert(
                term: term,
                lastUsedAt: lastUsedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ComicSearchTermsTableProcessedTableManager =
    ProcessedTableManager<
      _$ComicDb,
      $ComicSearchTermsTable,
      ComicSearchTermRow,
      $$ComicSearchTermsTableFilterComposer,
      $$ComicSearchTermsTableOrderingComposer,
      $$ComicSearchTermsTableAnnotationComposer,
      $$ComicSearchTermsTableCreateCompanionBuilder,
      $$ComicSearchTermsTableUpdateCompanionBuilder,
      (
        ComicSearchTermRow,
        BaseReferences<_$ComicDb, $ComicSearchTermsTable, ComicSearchTermRow>,
      ),
      ComicSearchTermRow,
      PrefetchHooks Function()
    >;
typedef $$ComicDownloadTasksTableCreateCompanionBuilder =
    ComicDownloadTasksCompanion Function({
      required String taskId,
      required String id,
      required String sourceName,
      Value<String> chapterId,
      required String status,
      Value<int> receivedBytes,
      Value<int> totalBytes,
      Value<String?> error,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ComicDownloadTasksTableUpdateCompanionBuilder =
    ComicDownloadTasksCompanion Function({
      Value<String> taskId,
      Value<String> id,
      Value<String> sourceName,
      Value<String> chapterId,
      Value<String> status,
      Value<int> receivedBytes,
      Value<int> totalBytes,
      Value<String?> error,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ComicDownloadTasksTableFilterComposer
    extends Composer<_$ComicDb, $ComicDownloadTasksTable> {
  $$ComicDownloadTasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get receivedBytes => $composableBuilder(
    column: $table.receivedBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ComicDownloadTasksTableOrderingComposer
    extends Composer<_$ComicDb, $ComicDownloadTasksTable> {
  $$ComicDownloadTasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get taskId => $composableBuilder(
    column: $table.taskId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get receivedBytes => $composableBuilder(
    column: $table.receivedBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ComicDownloadTasksTableAnnotationComposer
    extends Composer<_$ComicDb, $ComicDownloadTasksTable> {
  $$ComicDownloadTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get chapterId =>
      $composableBuilder(column: $table.chapterId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get receivedBytes => $composableBuilder(
    column: $table.receivedBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ComicDownloadTasksTableTableManager
    extends
        RootTableManager<
          _$ComicDb,
          $ComicDownloadTasksTable,
          ComicDownloadRow,
          $$ComicDownloadTasksTableFilterComposer,
          $$ComicDownloadTasksTableOrderingComposer,
          $$ComicDownloadTasksTableAnnotationComposer,
          $$ComicDownloadTasksTableCreateCompanionBuilder,
          $$ComicDownloadTasksTableUpdateCompanionBuilder,
          (
            ComicDownloadRow,
            BaseReferences<
              _$ComicDb,
              $ComicDownloadTasksTable,
              ComicDownloadRow
            >,
          ),
          ComicDownloadRow,
          PrefetchHooks Function()
        > {
  $$ComicDownloadTasksTableTableManager(
    _$ComicDb db,
    $ComicDownloadTasksTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ComicDownloadTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ComicDownloadTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ComicDownloadTasksTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> taskId = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> sourceName = const Value.absent(),
                Value<String> chapterId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> receivedBytes = const Value.absent(),
                Value<int> totalBytes = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ComicDownloadTasksCompanion(
                taskId: taskId,
                id: id,
                sourceName: sourceName,
                chapterId: chapterId,
                status: status,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes,
                error: error,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String taskId,
                required String id,
                required String sourceName,
                Value<String> chapterId = const Value.absent(),
                required String status,
                Value<int> receivedBytes = const Value.absent(),
                Value<int> totalBytes = const Value.absent(),
                Value<String?> error = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ComicDownloadTasksCompanion.insert(
                taskId: taskId,
                id: id,
                sourceName: sourceName,
                chapterId: chapterId,
                status: status,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes,
                error: error,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ComicDownloadTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$ComicDb,
      $ComicDownloadTasksTable,
      ComicDownloadRow,
      $$ComicDownloadTasksTableFilterComposer,
      $$ComicDownloadTasksTableOrderingComposer,
      $$ComicDownloadTasksTableAnnotationComposer,
      $$ComicDownloadTasksTableCreateCompanionBuilder,
      $$ComicDownloadTasksTableUpdateCompanionBuilder,
      (
        ComicDownloadRow,
        BaseReferences<_$ComicDb, $ComicDownloadTasksTable, ComicDownloadRow>,
      ),
      ComicDownloadRow,
      PrefetchHooks Function()
    >;
typedef $$ComicImageCacheEntriesTableCreateCompanionBuilder =
    ComicImageCacheEntriesCompanion Function({
      required String cacheKey,
      required String id,
      required String sourceName,
      Value<String> chapterId,
      required String filePath,
      required DateTime cachedAt,
      Value<int> rowid,
    });
typedef $$ComicImageCacheEntriesTableUpdateCompanionBuilder =
    ComicImageCacheEntriesCompanion Function({
      Value<String> cacheKey,
      Value<String> id,
      Value<String> sourceName,
      Value<String> chapterId,
      Value<String> filePath,
      Value<DateTime> cachedAt,
      Value<int> rowid,
    });

class $$ComicImageCacheEntriesTableFilterComposer
    extends Composer<_$ComicDb, $ComicImageCacheEntriesTable> {
  $$ComicImageCacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ComicImageCacheEntriesTableOrderingComposer
    extends Composer<_$ComicDb, $ComicImageCacheEntriesTable> {
  $$ComicImageCacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get cacheKey => $composableBuilder(
    column: $table.cacheKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterId => $composableBuilder(
    column: $table.chapterId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ComicImageCacheEntriesTableAnnotationComposer
    extends Composer<_$ComicDb, $ComicImageCacheEntriesTable> {
  $$ComicImageCacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get chapterId =>
      $composableBuilder(column: $table.chapterId, builder: (column) => column);

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);
}

class $$ComicImageCacheEntriesTableTableManager
    extends
        RootTableManager<
          _$ComicDb,
          $ComicImageCacheEntriesTable,
          ComicImageCacheRow,
          $$ComicImageCacheEntriesTableFilterComposer,
          $$ComicImageCacheEntriesTableOrderingComposer,
          $$ComicImageCacheEntriesTableAnnotationComposer,
          $$ComicImageCacheEntriesTableCreateCompanionBuilder,
          $$ComicImageCacheEntriesTableUpdateCompanionBuilder,
          (
            ComicImageCacheRow,
            BaseReferences<
              _$ComicDb,
              $ComicImageCacheEntriesTable,
              ComicImageCacheRow
            >,
          ),
          ComicImageCacheRow,
          PrefetchHooks Function()
        > {
  $$ComicImageCacheEntriesTableTableManager(
    _$ComicDb db,
    $ComicImageCacheEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ComicImageCacheEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ComicImageCacheEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ComicImageCacheEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> cacheKey = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> sourceName = const Value.absent(),
                Value<String> chapterId = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ComicImageCacheEntriesCompanion(
                cacheKey: cacheKey,
                id: id,
                sourceName: sourceName,
                chapterId: chapterId,
                filePath: filePath,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String cacheKey,
                required String id,
                required String sourceName,
                Value<String> chapterId = const Value.absent(),
                required String filePath,
                required DateTime cachedAt,
                Value<int> rowid = const Value.absent(),
              }) => ComicImageCacheEntriesCompanion.insert(
                cacheKey: cacheKey,
                id: id,
                sourceName: sourceName,
                chapterId: chapterId,
                filePath: filePath,
                cachedAt: cachedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ComicImageCacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$ComicDb,
      $ComicImageCacheEntriesTable,
      ComicImageCacheRow,
      $$ComicImageCacheEntriesTableFilterComposer,
      $$ComicImageCacheEntriesTableOrderingComposer,
      $$ComicImageCacheEntriesTableAnnotationComposer,
      $$ComicImageCacheEntriesTableCreateCompanionBuilder,
      $$ComicImageCacheEntriesTableUpdateCompanionBuilder,
      (
        ComicImageCacheRow,
        BaseReferences<
          _$ComicDb,
          $ComicImageCacheEntriesTable,
          ComicImageCacheRow
        >,
      ),
      ComicImageCacheRow,
      PrefetchHooks Function()
    >;
typedef $$ComicLocalEntriesTableCreateCompanionBuilder =
    ComicLocalEntriesCompanion Function({
      required String id,
      required String sourceName,
      required String title,
      required String folderPath,
      Value<String?> coverPath,
      Value<int> pageCount,
      Value<String> payload,
      required DateTime importedAt,
      Value<int> rowid,
    });
typedef $$ComicLocalEntriesTableUpdateCompanionBuilder =
    ComicLocalEntriesCompanion Function({
      Value<String> id,
      Value<String> sourceName,
      Value<String> title,
      Value<String> folderPath,
      Value<String?> coverPath,
      Value<int> pageCount,
      Value<String> payload,
      Value<DateTime> importedAt,
      Value<int> rowid,
    });

class $$ComicLocalEntriesTableFilterComposer
    extends Composer<_$ComicDb, $ComicLocalEntriesTable> {
  $$ComicLocalEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folderPath => $composableBuilder(
    column: $table.folderPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ComicLocalEntriesTableOrderingComposer
    extends Composer<_$ComicDb, $ComicLocalEntriesTable> {
  $$ComicLocalEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folderPath => $composableBuilder(
    column: $table.folderPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ComicLocalEntriesTableAnnotationComposer
    extends Composer<_$ComicDb, $ComicLocalEntriesTable> {
  $$ComicLocalEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourceName => $composableBuilder(
    column: $table.sourceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get folderPath => $composableBuilder(
    column: $table.folderPath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coverPath =>
      $composableBuilder(column: $table.coverPath, builder: (column) => column);

  GeneratedColumn<int> get pageCount =>
      $composableBuilder(column: $table.pageCount, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<DateTime> get importedAt => $composableBuilder(
    column: $table.importedAt,
    builder: (column) => column,
  );
}

class $$ComicLocalEntriesTableTableManager
    extends
        RootTableManager<
          _$ComicDb,
          $ComicLocalEntriesTable,
          ComicLocalRow,
          $$ComicLocalEntriesTableFilterComposer,
          $$ComicLocalEntriesTableOrderingComposer,
          $$ComicLocalEntriesTableAnnotationComposer,
          $$ComicLocalEntriesTableCreateCompanionBuilder,
          $$ComicLocalEntriesTableUpdateCompanionBuilder,
          (
            ComicLocalRow,
            BaseReferences<_$ComicDb, $ComicLocalEntriesTable, ComicLocalRow>,
          ),
          ComicLocalRow,
          PrefetchHooks Function()
        > {
  $$ComicLocalEntriesTableTableManager(
    _$ComicDb db,
    $ComicLocalEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ComicLocalEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ComicLocalEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ComicLocalEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sourceName = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> folderPath = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<int> pageCount = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> importedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ComicLocalEntriesCompanion(
                id: id,
                sourceName: sourceName,
                title: title,
                folderPath: folderPath,
                coverPath: coverPath,
                pageCount: pageCount,
                payload: payload,
                importedAt: importedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sourceName,
                required String title,
                required String folderPath,
                Value<String?> coverPath = const Value.absent(),
                Value<int> pageCount = const Value.absent(),
                Value<String> payload = const Value.absent(),
                required DateTime importedAt,
                Value<int> rowid = const Value.absent(),
              }) => ComicLocalEntriesCompanion.insert(
                id: id,
                sourceName: sourceName,
                title: title,
                folderPath: folderPath,
                coverPath: coverPath,
                pageCount: pageCount,
                payload: payload,
                importedAt: importedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ComicLocalEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$ComicDb,
      $ComicLocalEntriesTable,
      ComicLocalRow,
      $$ComicLocalEntriesTableFilterComposer,
      $$ComicLocalEntriesTableOrderingComposer,
      $$ComicLocalEntriesTableAnnotationComposer,
      $$ComicLocalEntriesTableCreateCompanionBuilder,
      $$ComicLocalEntriesTableUpdateCompanionBuilder,
      (
        ComicLocalRow,
        BaseReferences<_$ComicDb, $ComicLocalEntriesTable, ComicLocalRow>,
      ),
      ComicLocalRow,
      PrefetchHooks Function()
    >;

class $ComicDbManager {
  final _$ComicDb _db;
  $ComicDbManager(this._db);
  $$ComicCollectEntriesTableTableManager get comicCollectEntries =>
      $$ComicCollectEntriesTableTableManager(_db, _db.comicCollectEntries);
  $$ComicHistoryEntriesTableTableManager get comicHistoryEntries =>
      $$ComicHistoryEntriesTableTableManager(_db, _db.comicHistoryEntries);
  $$ComicReadLaterEntriesTableTableManager get comicReadLaterEntries =>
      $$ComicReadLaterEntriesTableTableManager(_db, _db.comicReadLaterEntries);
  $$ComicSearchTermsTableTableManager get comicSearchTerms =>
      $$ComicSearchTermsTableTableManager(_db, _db.comicSearchTerms);
  $$ComicDownloadTasksTableTableManager get comicDownloadTasks =>
      $$ComicDownloadTasksTableTableManager(_db, _db.comicDownloadTasks);
  $$ComicImageCacheEntriesTableTableManager get comicImageCacheEntries =>
      $$ComicImageCacheEntriesTableTableManager(
        _db,
        _db.comicImageCacheEntries,
      );
  $$ComicLocalEntriesTableTableManager get comicLocalEntries =>
      $$ComicLocalEntriesTableTableManager(_db, _db.comicLocalEntries);
}
