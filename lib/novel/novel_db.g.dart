// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'novel_db.dart';

// ignore_for_file: type=lint
class $NovelCollectEntriesTable extends NovelCollectEntries
    with TableInfo<$NovelCollectEntriesTable, NovelCollectRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NovelCollectEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
    title,
    coverUrl,
    payload,
    collectedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'novel_collect';
  @override
  VerificationContext validateIntegrity(
    Insertable<NovelCollectRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NovelCollectRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NovelCollectRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
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
  $NovelCollectEntriesTable createAlias(String alias) {
    return $NovelCollectEntriesTable(attachedDatabase, alias);
  }
}

class NovelCollectRow extends DataClass implements Insertable<NovelCollectRow> {
  /// `NovelSummary.id`。
  final String id;
  final String title;
  final String? coverUrl;

  /// 书籍 JSON（完整 `NovelSummary.toJson`）；投影里的 payload 是进度摘要，
  /// 不是这一列。
  final String payload;
  final DateTime collectedAt;
  const NovelCollectRow({
    required this.id,
    required this.title,
    this.coverUrl,
    required this.payload,
    required this.collectedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || coverUrl != null) {
      map['cover_url'] = Variable<String>(coverUrl);
    }
    map['payload'] = Variable<String>(payload);
    map['collected_at'] = Variable<DateTime>(collectedAt);
    return map;
  }

  NovelCollectEntriesCompanion toCompanion(bool nullToAbsent) {
    return NovelCollectEntriesCompanion(
      id: Value(id),
      title: Value(title),
      coverUrl: coverUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(coverUrl),
      payload: Value(payload),
      collectedAt: Value(collectedAt),
    );
  }

  factory NovelCollectRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NovelCollectRow(
      id: serializer.fromJson<String>(json['id']),
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
      'title': serializer.toJson<String>(title),
      'coverUrl': serializer.toJson<String?>(coverUrl),
      'payload': serializer.toJson<String>(payload),
      'collectedAt': serializer.toJson<DateTime>(collectedAt),
    };
  }

  NovelCollectRow copyWith({
    String? id,
    String? title,
    Value<String?> coverUrl = const Value.absent(),
    String? payload,
    DateTime? collectedAt,
  }) => NovelCollectRow(
    id: id ?? this.id,
    title: title ?? this.title,
    coverUrl: coverUrl.present ? coverUrl.value : this.coverUrl,
    payload: payload ?? this.payload,
    collectedAt: collectedAt ?? this.collectedAt,
  );
  NovelCollectRow copyWithCompanion(NovelCollectEntriesCompanion data) {
    return NovelCollectRow(
      id: data.id.present ? data.id.value : this.id,
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
    return (StringBuffer('NovelCollectRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('payload: $payload, ')
          ..write('collectedAt: $collectedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, title, coverUrl, payload, collectedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelCollectRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.coverUrl == this.coverUrl &&
          other.payload == this.payload &&
          other.collectedAt == this.collectedAt);
}

class NovelCollectEntriesCompanion extends UpdateCompanion<NovelCollectRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> coverUrl;
  final Value<String> payload;
  final Value<DateTime> collectedAt;
  final Value<int> rowid;
  const NovelCollectEntriesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.payload = const Value.absent(),
    this.collectedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NovelCollectEntriesCompanion.insert({
    required String id,
    required String title,
    this.coverUrl = const Value.absent(),
    this.payload = const Value.absent(),
    required DateTime collectedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       collectedAt = Value(collectedAt);
  static Insertable<NovelCollectRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? coverUrl,
    Expression<String>? payload,
    Expression<DateTime>? collectedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (payload != null) 'payload': payload,
      if (collectedAt != null) 'collected_at': collectedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NovelCollectEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? coverUrl,
    Value<String>? payload,
    Value<DateTime>? collectedAt,
    Value<int>? rowid,
  }) {
    return NovelCollectEntriesCompanion(
      id: id ?? this.id,
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
    return (StringBuffer('NovelCollectEntriesCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('payload: $payload, ')
          ..write('collectedAt: $collectedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NovelHistoryEntriesTable extends NovelHistoryEntries
    with TableInfo<$NovelHistoryEntriesTable, NovelHistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NovelHistoryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _chapterIndexMeta = const VerificationMeta(
    'chapterIndex',
  );
  @override
  late final GeneratedColumn<int> chapterIndex = GeneratedColumn<int>(
    'chapter_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _chapterCountMeta = const VerificationMeta(
    'chapterCount',
  );
  @override
  late final GeneratedColumn<int> chapterCount = GeneratedColumn<int>(
    'chapter_count',
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
  static const VerificationMeta _readCountMeta = const VerificationMeta(
    'readCount',
  );
  @override
  late final GeneratedColumn<int> readCount = GeneratedColumn<int>(
    'read_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
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
    title,
    coverUrl,
    chapterIndex,
    chapterCount,
    openedAt,
    readCount,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'novel_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<NovelHistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
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
    if (data.containsKey('chapter_index')) {
      context.handle(
        _chapterIndexMeta,
        chapterIndex.isAcceptableOrUnknown(
          data['chapter_index']!,
          _chapterIndexMeta,
        ),
      );
    }
    if (data.containsKey('chapter_count')) {
      context.handle(
        _chapterCountMeta,
        chapterCount.isAcceptableOrUnknown(
          data['chapter_count']!,
          _chapterCountMeta,
        ),
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
    if (data.containsKey('read_count')) {
      context.handle(
        _readCountMeta,
        readCount.isAcceptableOrUnknown(data['read_count']!, _readCountMeta),
      );
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NovelHistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NovelHistoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      coverUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_url'],
      ),
      chapterIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_index'],
      )!,
      chapterCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_count'],
      )!,
      openedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}opened_at'],
      )!,
      readCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}read_count'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $NovelHistoryEntriesTable createAlias(String alias) {
    return $NovelHistoryEntriesTable(attachedDatabase, alias);
  }
}

class NovelHistoryRow extends DataClass implements Insertable<NovelHistoryRow> {
  final String id;
  final String title;
  final String? coverUrl;

  /// 当前读到的章节序号（从 1 起；0 表示无进度）。
  final int chapterIndex;

  /// 目录总章数（<=0 表示未知）。
  final int chapterCount;
  final DateTime openedAt;
  final int readCount;

  /// 书籍 JSON，历史续读据此重建 [NovelSummary]。
  final String payload;
  const NovelHistoryRow({
    required this.id,
    required this.title,
    this.coverUrl,
    required this.chapterIndex,
    required this.chapterCount,
    required this.openedAt,
    required this.readCount,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || coverUrl != null) {
      map['cover_url'] = Variable<String>(coverUrl);
    }
    map['chapter_index'] = Variable<int>(chapterIndex);
    map['chapter_count'] = Variable<int>(chapterCount);
    map['opened_at'] = Variable<DateTime>(openedAt);
    map['read_count'] = Variable<int>(readCount);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  NovelHistoryEntriesCompanion toCompanion(bool nullToAbsent) {
    return NovelHistoryEntriesCompanion(
      id: Value(id),
      title: Value(title),
      coverUrl: coverUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(coverUrl),
      chapterIndex: Value(chapterIndex),
      chapterCount: Value(chapterCount),
      openedAt: Value(openedAt),
      readCount: Value(readCount),
      payload: Value(payload),
    );
  }

  factory NovelHistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NovelHistoryRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      coverUrl: serializer.fromJson<String?>(json['coverUrl']),
      chapterIndex: serializer.fromJson<int>(json['chapterIndex']),
      chapterCount: serializer.fromJson<int>(json['chapterCount']),
      openedAt: serializer.fromJson<DateTime>(json['openedAt']),
      readCount: serializer.fromJson<int>(json['readCount']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'coverUrl': serializer.toJson<String?>(coverUrl),
      'chapterIndex': serializer.toJson<int>(chapterIndex),
      'chapterCount': serializer.toJson<int>(chapterCount),
      'openedAt': serializer.toJson<DateTime>(openedAt),
      'readCount': serializer.toJson<int>(readCount),
      'payload': serializer.toJson<String>(payload),
    };
  }

  NovelHistoryRow copyWith({
    String? id,
    String? title,
    Value<String?> coverUrl = const Value.absent(),
    int? chapterIndex,
    int? chapterCount,
    DateTime? openedAt,
    int? readCount,
    String? payload,
  }) => NovelHistoryRow(
    id: id ?? this.id,
    title: title ?? this.title,
    coverUrl: coverUrl.present ? coverUrl.value : this.coverUrl,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    chapterCount: chapterCount ?? this.chapterCount,
    openedAt: openedAt ?? this.openedAt,
    readCount: readCount ?? this.readCount,
    payload: payload ?? this.payload,
  );
  NovelHistoryRow copyWithCompanion(NovelHistoryEntriesCompanion data) {
    return NovelHistoryRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      coverUrl: data.coverUrl.present ? data.coverUrl.value : this.coverUrl,
      chapterIndex: data.chapterIndex.present
          ? data.chapterIndex.value
          : this.chapterIndex,
      chapterCount: data.chapterCount.present
          ? data.chapterCount.value
          : this.chapterCount,
      openedAt: data.openedAt.present ? data.openedAt.value : this.openedAt,
      readCount: data.readCount.present ? data.readCount.value : this.readCount,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NovelHistoryRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('chapterCount: $chapterCount, ')
          ..write('openedAt: $openedAt, ')
          ..write('readCount: $readCount, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    coverUrl,
    chapterIndex,
    chapterCount,
    openedAt,
    readCount,
    payload,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelHistoryRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.coverUrl == this.coverUrl &&
          other.chapterIndex == this.chapterIndex &&
          other.chapterCount == this.chapterCount &&
          other.openedAt == this.openedAt &&
          other.readCount == this.readCount &&
          other.payload == this.payload);
}

class NovelHistoryEntriesCompanion extends UpdateCompanion<NovelHistoryRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> coverUrl;
  final Value<int> chapterIndex;
  final Value<int> chapterCount;
  final Value<DateTime> openedAt;
  final Value<int> readCount;
  final Value<String> payload;
  final Value<int> rowid;
  const NovelHistoryEntriesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.chapterCount = const Value.absent(),
    this.openedAt = const Value.absent(),
    this.readCount = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NovelHistoryEntriesCompanion.insert({
    required String id,
    required String title,
    this.coverUrl = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.chapterCount = const Value.absent(),
    required DateTime openedAt,
    this.readCount = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       openedAt = Value(openedAt);
  static Insertable<NovelHistoryRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? coverUrl,
    Expression<int>? chapterIndex,
    Expression<int>? chapterCount,
    Expression<DateTime>? openedAt,
    Expression<int>? readCount,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (chapterIndex != null) 'chapter_index': chapterIndex,
      if (chapterCount != null) 'chapter_count': chapterCount,
      if (openedAt != null) 'opened_at': openedAt,
      if (readCount != null) 'read_count': readCount,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NovelHistoryEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? coverUrl,
    Value<int>? chapterIndex,
    Value<int>? chapterCount,
    Value<DateTime>? openedAt,
    Value<int>? readCount,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return NovelHistoryEntriesCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      chapterCount: chapterCount ?? this.chapterCount,
      openedAt: openedAt ?? this.openedAt,
      readCount: readCount ?? this.readCount,
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
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (coverUrl.present) {
      map['cover_url'] = Variable<String>(coverUrl.value);
    }
    if (chapterIndex.present) {
      map['chapter_index'] = Variable<int>(chapterIndex.value);
    }
    if (chapterCount.present) {
      map['chapter_count'] = Variable<int>(chapterCount.value);
    }
    if (openedAt.present) {
      map['opened_at'] = Variable<DateTime>(openedAt.value);
    }
    if (readCount.present) {
      map['read_count'] = Variable<int>(readCount.value);
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
    return (StringBuffer('NovelHistoryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('chapterCount: $chapterCount, ')
          ..write('openedAt: $openedAt, ')
          ..write('readCount: $readCount, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NovelSearchTermsTable extends NovelSearchTerms
    with TableInfo<$NovelSearchTermsTable, NovelSearchTermRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NovelSearchTermsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keywordMeta = const VerificationMeta(
    'keyword',
  );
  @override
  late final GeneratedColumn<String> keyword = GeneratedColumn<String>(
    'keyword',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _searchedAtMeta = const VerificationMeta(
    'searchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> searchedAt = GeneratedColumn<DateTime>(
    'searched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hitsMeta = const VerificationMeta('hits');
  @override
  late final GeneratedColumn<int> hits = GeneratedColumn<int>(
    'hits',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [keyword, searchedAt, hits];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'novel_search_term';
  @override
  VerificationContext validateIntegrity(
    Insertable<NovelSearchTermRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('keyword')) {
      context.handle(
        _keywordMeta,
        keyword.isAcceptableOrUnknown(data['keyword']!, _keywordMeta),
      );
    } else if (isInserting) {
      context.missing(_keywordMeta);
    }
    if (data.containsKey('searched_at')) {
      context.handle(
        _searchedAtMeta,
        searchedAt.isAcceptableOrUnknown(data['searched_at']!, _searchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_searchedAtMeta);
    }
    if (data.containsKey('hits')) {
      context.handle(
        _hitsMeta,
        hits.isAcceptableOrUnknown(data['hits']!, _hitsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {keyword};
  @override
  NovelSearchTermRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NovelSearchTermRow(
      keyword: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}keyword'],
      )!,
      searchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}searched_at'],
      )!,
      hits: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hits'],
      )!,
    );
  }

  @override
  $NovelSearchTermsTable createAlias(String alias) {
    return $NovelSearchTermsTable(attachedDatabase, alias);
  }
}

class NovelSearchTermRow extends DataClass
    implements Insertable<NovelSearchTermRow> {
  final String keyword;
  final DateTime searchedAt;
  final int hits;
  const NovelSearchTermRow({
    required this.keyword,
    required this.searchedAt,
    required this.hits,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['keyword'] = Variable<String>(keyword);
    map['searched_at'] = Variable<DateTime>(searchedAt);
    map['hits'] = Variable<int>(hits);
    return map;
  }

  NovelSearchTermsCompanion toCompanion(bool nullToAbsent) {
    return NovelSearchTermsCompanion(
      keyword: Value(keyword),
      searchedAt: Value(searchedAt),
      hits: Value(hits),
    );
  }

  factory NovelSearchTermRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NovelSearchTermRow(
      keyword: serializer.fromJson<String>(json['keyword']),
      searchedAt: serializer.fromJson<DateTime>(json['searchedAt']),
      hits: serializer.fromJson<int>(json['hits']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'keyword': serializer.toJson<String>(keyword),
      'searchedAt': serializer.toJson<DateTime>(searchedAt),
      'hits': serializer.toJson<int>(hits),
    };
  }

  NovelSearchTermRow copyWith({
    String? keyword,
    DateTime? searchedAt,
    int? hits,
  }) => NovelSearchTermRow(
    keyword: keyword ?? this.keyword,
    searchedAt: searchedAt ?? this.searchedAt,
    hits: hits ?? this.hits,
  );
  NovelSearchTermRow copyWithCompanion(NovelSearchTermsCompanion data) {
    return NovelSearchTermRow(
      keyword: data.keyword.present ? data.keyword.value : this.keyword,
      searchedAt: data.searchedAt.present
          ? data.searchedAt.value
          : this.searchedAt,
      hits: data.hits.present ? data.hits.value : this.hits,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NovelSearchTermRow(')
          ..write('keyword: $keyword, ')
          ..write('searchedAt: $searchedAt, ')
          ..write('hits: $hits')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(keyword, searchedAt, hits);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelSearchTermRow &&
          other.keyword == this.keyword &&
          other.searchedAt == this.searchedAt &&
          other.hits == this.hits);
}

class NovelSearchTermsCompanion extends UpdateCompanion<NovelSearchTermRow> {
  final Value<String> keyword;
  final Value<DateTime> searchedAt;
  final Value<int> hits;
  final Value<int> rowid;
  const NovelSearchTermsCompanion({
    this.keyword = const Value.absent(),
    this.searchedAt = const Value.absent(),
    this.hits = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NovelSearchTermsCompanion.insert({
    required String keyword,
    required DateTime searchedAt,
    this.hits = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : keyword = Value(keyword),
       searchedAt = Value(searchedAt);
  static Insertable<NovelSearchTermRow> custom({
    Expression<String>? keyword,
    Expression<DateTime>? searchedAt,
    Expression<int>? hits,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (keyword != null) 'keyword': keyword,
      if (searchedAt != null) 'searched_at': searchedAt,
      if (hits != null) 'hits': hits,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NovelSearchTermsCompanion copyWith({
    Value<String>? keyword,
    Value<DateTime>? searchedAt,
    Value<int>? hits,
    Value<int>? rowid,
  }) {
    return NovelSearchTermsCompanion(
      keyword: keyword ?? this.keyword,
      searchedAt: searchedAt ?? this.searchedAt,
      hits: hits ?? this.hits,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (keyword.present) {
      map['keyword'] = Variable<String>(keyword.value);
    }
    if (searchedAt.present) {
      map['searched_at'] = Variable<DateTime>(searchedAt.value);
    }
    if (hits.present) {
      map['hits'] = Variable<int>(hits.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NovelSearchTermsCompanion(')
          ..write('keyword: $keyword, ')
          ..write('searchedAt: $searchedAt, ')
          ..write('hits: $hits, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$NovelDb extends GeneratedDatabase {
  _$NovelDb(QueryExecutor e) : super(e);
  $NovelDbManager get managers => $NovelDbManager(this);
  late final $NovelCollectEntriesTable novelCollectEntries =
      $NovelCollectEntriesTable(this);
  late final $NovelHistoryEntriesTable novelHistoryEntries =
      $NovelHistoryEntriesTable(this);
  late final $NovelSearchTermsTable novelSearchTerms = $NovelSearchTermsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    novelCollectEntries,
    novelHistoryEntries,
    novelSearchTerms,
  ];
}

typedef $$NovelCollectEntriesTableCreateCompanionBuilder =
    NovelCollectEntriesCompanion Function({
      required String id,
      required String title,
      Value<String?> coverUrl,
      Value<String> payload,
      required DateTime collectedAt,
      Value<int> rowid,
    });
typedef $$NovelCollectEntriesTableUpdateCompanionBuilder =
    NovelCollectEntriesCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> coverUrl,
      Value<String> payload,
      Value<DateTime> collectedAt,
      Value<int> rowid,
    });

class $$NovelCollectEntriesTableFilterComposer
    extends Composer<_$NovelDb, $NovelCollectEntriesTable> {
  $$NovelCollectEntriesTableFilterComposer({
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

class $$NovelCollectEntriesTableOrderingComposer
    extends Composer<_$NovelDb, $NovelCollectEntriesTable> {
  $$NovelCollectEntriesTableOrderingComposer({
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

class $$NovelCollectEntriesTableAnnotationComposer
    extends Composer<_$NovelDb, $NovelCollectEntriesTable> {
  $$NovelCollectEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

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

class $$NovelCollectEntriesTableTableManager
    extends
        RootTableManager<
          _$NovelDb,
          $NovelCollectEntriesTable,
          NovelCollectRow,
          $$NovelCollectEntriesTableFilterComposer,
          $$NovelCollectEntriesTableOrderingComposer,
          $$NovelCollectEntriesTableAnnotationComposer,
          $$NovelCollectEntriesTableCreateCompanionBuilder,
          $$NovelCollectEntriesTableUpdateCompanionBuilder,
          (
            NovelCollectRow,
            BaseReferences<
              _$NovelDb,
              $NovelCollectEntriesTable,
              NovelCollectRow
            >,
          ),
          NovelCollectRow,
          PrefetchHooks Function()
        > {
  $$NovelCollectEntriesTableTableManager(
    _$NovelDb db,
    $NovelCollectEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NovelCollectEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NovelCollectEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$NovelCollectEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> coverUrl = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<DateTime> collectedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NovelCollectEntriesCompanion(
                id: id,
                title: title,
                coverUrl: coverUrl,
                payload: payload,
                collectedAt: collectedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> coverUrl = const Value.absent(),
                Value<String> payload = const Value.absent(),
                required DateTime collectedAt,
                Value<int> rowid = const Value.absent(),
              }) => NovelCollectEntriesCompanion.insert(
                id: id,
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

typedef $$NovelCollectEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$NovelDb,
      $NovelCollectEntriesTable,
      NovelCollectRow,
      $$NovelCollectEntriesTableFilterComposer,
      $$NovelCollectEntriesTableOrderingComposer,
      $$NovelCollectEntriesTableAnnotationComposer,
      $$NovelCollectEntriesTableCreateCompanionBuilder,
      $$NovelCollectEntriesTableUpdateCompanionBuilder,
      (
        NovelCollectRow,
        BaseReferences<_$NovelDb, $NovelCollectEntriesTable, NovelCollectRow>,
      ),
      NovelCollectRow,
      PrefetchHooks Function()
    >;
typedef $$NovelHistoryEntriesTableCreateCompanionBuilder =
    NovelHistoryEntriesCompanion Function({
      required String id,
      required String title,
      Value<String?> coverUrl,
      Value<int> chapterIndex,
      Value<int> chapterCount,
      required DateTime openedAt,
      Value<int> readCount,
      Value<String> payload,
      Value<int> rowid,
    });
typedef $$NovelHistoryEntriesTableUpdateCompanionBuilder =
    NovelHistoryEntriesCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> coverUrl,
      Value<int> chapterIndex,
      Value<int> chapterCount,
      Value<DateTime> openedAt,
      Value<int> readCount,
      Value<String> payload,
      Value<int> rowid,
    });

class $$NovelHistoryEntriesTableFilterComposer
    extends Composer<_$NovelDb, $NovelHistoryEntriesTable> {
  $$NovelHistoryEntriesTableFilterComposer({
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

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterCount => $composableBuilder(
    column: $table.chapterCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get readCount => $composableBuilder(
    column: $table.readCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NovelHistoryEntriesTableOrderingComposer
    extends Composer<_$NovelDb, $NovelHistoryEntriesTable> {
  $$NovelHistoryEntriesTableOrderingComposer({
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

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverUrl => $composableBuilder(
    column: $table.coverUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterCount => $composableBuilder(
    column: $table.chapterCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get readCount => $composableBuilder(
    column: $table.readCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NovelHistoryEntriesTableAnnotationComposer
    extends Composer<_$NovelDb, $NovelHistoryEntriesTable> {
  $$NovelHistoryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get coverUrl =>
      $composableBuilder(column: $table.coverUrl, builder: (column) => column);

  GeneratedColumn<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get chapterCount => $composableBuilder(
    column: $table.chapterCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get openedAt =>
      $composableBuilder(column: $table.openedAt, builder: (column) => column);

  GeneratedColumn<int> get readCount =>
      $composableBuilder(column: $table.readCount, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$NovelHistoryEntriesTableTableManager
    extends
        RootTableManager<
          _$NovelDb,
          $NovelHistoryEntriesTable,
          NovelHistoryRow,
          $$NovelHistoryEntriesTableFilterComposer,
          $$NovelHistoryEntriesTableOrderingComposer,
          $$NovelHistoryEntriesTableAnnotationComposer,
          $$NovelHistoryEntriesTableCreateCompanionBuilder,
          $$NovelHistoryEntriesTableUpdateCompanionBuilder,
          (
            NovelHistoryRow,
            BaseReferences<
              _$NovelDb,
              $NovelHistoryEntriesTable,
              NovelHistoryRow
            >,
          ),
          NovelHistoryRow,
          PrefetchHooks Function()
        > {
  $$NovelHistoryEntriesTableTableManager(
    _$NovelDb db,
    $NovelHistoryEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NovelHistoryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NovelHistoryEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$NovelHistoryEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> coverUrl = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<int> chapterCount = const Value.absent(),
                Value<DateTime> openedAt = const Value.absent(),
                Value<int> readCount = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NovelHistoryEntriesCompanion(
                id: id,
                title: title,
                coverUrl: coverUrl,
                chapterIndex: chapterIndex,
                chapterCount: chapterCount,
                openedAt: openedAt,
                readCount: readCount,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> coverUrl = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<int> chapterCount = const Value.absent(),
                required DateTime openedAt,
                Value<int> readCount = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NovelHistoryEntriesCompanion.insert(
                id: id,
                title: title,
                coverUrl: coverUrl,
                chapterIndex: chapterIndex,
                chapterCount: chapterCount,
                openedAt: openedAt,
                readCount: readCount,
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

typedef $$NovelHistoryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$NovelDb,
      $NovelHistoryEntriesTable,
      NovelHistoryRow,
      $$NovelHistoryEntriesTableFilterComposer,
      $$NovelHistoryEntriesTableOrderingComposer,
      $$NovelHistoryEntriesTableAnnotationComposer,
      $$NovelHistoryEntriesTableCreateCompanionBuilder,
      $$NovelHistoryEntriesTableUpdateCompanionBuilder,
      (
        NovelHistoryRow,
        BaseReferences<_$NovelDb, $NovelHistoryEntriesTable, NovelHistoryRow>,
      ),
      NovelHistoryRow,
      PrefetchHooks Function()
    >;
typedef $$NovelSearchTermsTableCreateCompanionBuilder =
    NovelSearchTermsCompanion Function({
      required String keyword,
      required DateTime searchedAt,
      Value<int> hits,
      Value<int> rowid,
    });
typedef $$NovelSearchTermsTableUpdateCompanionBuilder =
    NovelSearchTermsCompanion Function({
      Value<String> keyword,
      Value<DateTime> searchedAt,
      Value<int> hits,
      Value<int> rowid,
    });

class $$NovelSearchTermsTableFilterComposer
    extends Composer<_$NovelDb, $NovelSearchTermsTable> {
  $$NovelSearchTermsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get keyword => $composableBuilder(
    column: $table.keyword,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get searchedAt => $composableBuilder(
    column: $table.searchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hits => $composableBuilder(
    column: $table.hits,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NovelSearchTermsTableOrderingComposer
    extends Composer<_$NovelDb, $NovelSearchTermsTable> {
  $$NovelSearchTermsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get keyword => $composableBuilder(
    column: $table.keyword,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get searchedAt => $composableBuilder(
    column: $table.searchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hits => $composableBuilder(
    column: $table.hits,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NovelSearchTermsTableAnnotationComposer
    extends Composer<_$NovelDb, $NovelSearchTermsTable> {
  $$NovelSearchTermsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get keyword =>
      $composableBuilder(column: $table.keyword, builder: (column) => column);

  GeneratedColumn<DateTime> get searchedAt => $composableBuilder(
    column: $table.searchedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get hits =>
      $composableBuilder(column: $table.hits, builder: (column) => column);
}

class $$NovelSearchTermsTableTableManager
    extends
        RootTableManager<
          _$NovelDb,
          $NovelSearchTermsTable,
          NovelSearchTermRow,
          $$NovelSearchTermsTableFilterComposer,
          $$NovelSearchTermsTableOrderingComposer,
          $$NovelSearchTermsTableAnnotationComposer,
          $$NovelSearchTermsTableCreateCompanionBuilder,
          $$NovelSearchTermsTableUpdateCompanionBuilder,
          (
            NovelSearchTermRow,
            BaseReferences<
              _$NovelDb,
              $NovelSearchTermsTable,
              NovelSearchTermRow
            >,
          ),
          NovelSearchTermRow,
          PrefetchHooks Function()
        > {
  $$NovelSearchTermsTableTableManager(
    _$NovelDb db,
    $NovelSearchTermsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NovelSearchTermsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NovelSearchTermsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NovelSearchTermsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> keyword = const Value.absent(),
                Value<DateTime> searchedAt = const Value.absent(),
                Value<int> hits = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NovelSearchTermsCompanion(
                keyword: keyword,
                searchedAt: searchedAt,
                hits: hits,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String keyword,
                required DateTime searchedAt,
                Value<int> hits = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NovelSearchTermsCompanion.insert(
                keyword: keyword,
                searchedAt: searchedAt,
                hits: hits,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NovelSearchTermsTableProcessedTableManager =
    ProcessedTableManager<
      _$NovelDb,
      $NovelSearchTermsTable,
      NovelSearchTermRow,
      $$NovelSearchTermsTableFilterComposer,
      $$NovelSearchTermsTableOrderingComposer,
      $$NovelSearchTermsTableAnnotationComposer,
      $$NovelSearchTermsTableCreateCompanionBuilder,
      $$NovelSearchTermsTableUpdateCompanionBuilder,
      (
        NovelSearchTermRow,
        BaseReferences<_$NovelDb, $NovelSearchTermsTable, NovelSearchTermRow>,
      ),
      NovelSearchTermRow,
      PrefetchHooks Function()
    >;

class $NovelDbManager {
  final _$NovelDb _db;
  $NovelDbManager(this._db);
  $$NovelCollectEntriesTableTableManager get novelCollectEntries =>
      $$NovelCollectEntriesTableTableManager(_db, _db.novelCollectEntries);
  $$NovelHistoryEntriesTableTableManager get novelHistoryEntries =>
      $$NovelHistoryEntriesTableTableManager(_db, _db.novelHistoryEntries);
  $$NovelSearchTermsTableTableManager get novelSearchTerms =>
      $$NovelSearchTermsTableTableManager(_db, _db.novelSearchTerms);
}
