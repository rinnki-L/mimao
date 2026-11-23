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
  static const VerificationMeta _groupNameMeta = const VerificationMeta(
    'groupName',
  );
  @override
  late final GeneratedColumn<String> groupName = GeneratedColumn<String>(
    'group_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    groupName,
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
    if (data.containsKey('group_name')) {
      context.handle(
        _groupNameMeta,
        groupName.isAcceptableOrUnknown(data['group_name']!, _groupNameMeta),
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
      groupName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_name'],
      ),
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

  /// 书架自定义分组名；null = 未分组。单本书只属于一个分组（与书架分组
  /// 管理的"一组多本"对应，足够覆盖筛选场景，不做多标签）。
  final String? groupName;
  final DateTime collectedAt;
  const NovelCollectRow({
    required this.id,
    required this.title,
    this.coverUrl,
    required this.payload,
    this.groupName,
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
    if (!nullToAbsent || groupName != null) {
      map['group_name'] = Variable<String>(groupName);
    }
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
      groupName: groupName == null && nullToAbsent
          ? const Value.absent()
          : Value(groupName),
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
      groupName: serializer.fromJson<String?>(json['groupName']),
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
      'groupName': serializer.toJson<String?>(groupName),
      'collectedAt': serializer.toJson<DateTime>(collectedAt),
    };
  }

  NovelCollectRow copyWith({
    String? id,
    String? title,
    Value<String?> coverUrl = const Value.absent(),
    String? payload,
    Value<String?> groupName = const Value.absent(),
    DateTime? collectedAt,
  }) => NovelCollectRow(
    id: id ?? this.id,
    title: title ?? this.title,
    coverUrl: coverUrl.present ? coverUrl.value : this.coverUrl,
    payload: payload ?? this.payload,
    groupName: groupName.present ? groupName.value : this.groupName,
    collectedAt: collectedAt ?? this.collectedAt,
  );
  NovelCollectRow copyWithCompanion(NovelCollectEntriesCompanion data) {
    return NovelCollectRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      coverUrl: data.coverUrl.present ? data.coverUrl.value : this.coverUrl,
      payload: data.payload.present ? data.payload.value : this.payload,
      groupName: data.groupName.present ? data.groupName.value : this.groupName,
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
          ..write('groupName: $groupName, ')
          ..write('collectedAt: $collectedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, title, coverUrl, payload, groupName, collectedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelCollectRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.coverUrl == this.coverUrl &&
          other.payload == this.payload &&
          other.groupName == this.groupName &&
          other.collectedAt == this.collectedAt);
}

class NovelCollectEntriesCompanion extends UpdateCompanion<NovelCollectRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> coverUrl;
  final Value<String> payload;
  final Value<String?> groupName;
  final Value<DateTime> collectedAt;
  final Value<int> rowid;
  const NovelCollectEntriesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.payload = const Value.absent(),
    this.groupName = const Value.absent(),
    this.collectedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NovelCollectEntriesCompanion.insert({
    required String id,
    required String title,
    this.coverUrl = const Value.absent(),
    this.payload = const Value.absent(),
    this.groupName = const Value.absent(),
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
    Expression<String>? groupName,
    Expression<DateTime>? collectedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (payload != null) 'payload': payload,
      if (groupName != null) 'group_name': groupName,
      if (collectedAt != null) 'collected_at': collectedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NovelCollectEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? coverUrl,
    Value<String>? payload,
    Value<String?>? groupName,
    Value<DateTime>? collectedAt,
    Value<int>? rowid,
  }) {
    return NovelCollectEntriesCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      payload: payload ?? this.payload,
      groupName: groupName ?? this.groupName,
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
    if (groupName.present) {
      map['group_name'] = Variable<String>(groupName.value);
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
          ..write('groupName: $groupName, ')
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

  /// 当前读到的章号（从 1 起；0 表示无进度）。
  /// 注意：书源引擎产出的 `NovelChapter.index` 是 0 起（对齐 legado），
  /// 阅读页落库时 +1 转成章号（novel_reader_page.dart），续读时再 -1 取目录
  /// 下标（novel_book_detail_page.dart）。0 是"没读"哨兵，不是第 1 章。
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

class $NovelPrefsTable extends NovelPrefs
    with TableInfo<$NovelPrefsTable, NovelPrefRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NovelPrefsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'novel_pref';
  @override
  VerificationContext validateIntegrity(
    Insertable<NovelPrefRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  NovelPrefRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NovelPrefRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $NovelPrefsTable createAlias(String alias) {
    return $NovelPrefsTable(attachedDatabase, alias);
  }
}

class NovelPrefRow extends DataClass implements Insertable<NovelPrefRow> {
  final String key;
  final String value;
  const NovelPrefRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  NovelPrefsCompanion toCompanion(bool nullToAbsent) {
    return NovelPrefsCompanion(key: Value(key), value: Value(value));
  }

  factory NovelPrefRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NovelPrefRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  NovelPrefRow copyWith({String? key, String? value}) =>
      NovelPrefRow(key: key ?? this.key, value: value ?? this.value);
  NovelPrefRow copyWithCompanion(NovelPrefsCompanion data) {
    return NovelPrefRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NovelPrefRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelPrefRow &&
          other.key == this.key &&
          other.value == this.value);
}

class NovelPrefsCompanion extends UpdateCompanion<NovelPrefRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const NovelPrefsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NovelPrefsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<NovelPrefRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NovelPrefsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return NovelPrefsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NovelPrefsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NovelReadingDaysTable extends NovelReadingDays
    with TableInfo<$NovelReadingDaysTable, NovelReadingDayRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NovelReadingDaysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
    'day',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _secondsMeta = const VerificationMeta(
    'seconds',
  );
  @override
  late final GeneratedColumn<int> seconds = GeneratedColumn<int>(
    'seconds',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
  List<GeneratedColumn> get $columns => [day, seconds, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'novel_reading_day';
  @override
  VerificationContext validateIntegrity(
    Insertable<NovelReadingDayRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('seconds')) {
      context.handle(
        _secondsMeta,
        seconds.isAcceptableOrUnknown(data['seconds']!, _secondsMeta),
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
  Set<GeneratedColumn> get $primaryKey => {day};
  @override
  NovelReadingDayRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NovelReadingDayRow(
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day'],
      )!,
      seconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seconds'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $NovelReadingDaysTable createAlias(String alias) {
    return $NovelReadingDaysTable(attachedDatabase, alias);
  }
}

class NovelReadingDayRow extends DataClass
    implements Insertable<NovelReadingDayRow> {
  /// 本地日期 `yyyy-MM-dd`（阅读时长按用户本地日切分）。
  final String day;
  final int seconds;
  final DateTime updatedAt;
  const NovelReadingDayRow({
    required this.day,
    required this.seconds,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['day'] = Variable<String>(day);
    map['seconds'] = Variable<int>(seconds);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  NovelReadingDaysCompanion toCompanion(bool nullToAbsent) {
    return NovelReadingDaysCompanion(
      day: Value(day),
      seconds: Value(seconds),
      updatedAt: Value(updatedAt),
    );
  }

  factory NovelReadingDayRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NovelReadingDayRow(
      day: serializer.fromJson<String>(json['day']),
      seconds: serializer.fromJson<int>(json['seconds']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'day': serializer.toJson<String>(day),
      'seconds': serializer.toJson<int>(seconds),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  NovelReadingDayRow copyWith({
    String? day,
    int? seconds,
    DateTime? updatedAt,
  }) => NovelReadingDayRow(
    day: day ?? this.day,
    seconds: seconds ?? this.seconds,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  NovelReadingDayRow copyWithCompanion(NovelReadingDaysCompanion data) {
    return NovelReadingDayRow(
      day: data.day.present ? data.day.value : this.day,
      seconds: data.seconds.present ? data.seconds.value : this.seconds,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NovelReadingDayRow(')
          ..write('day: $day, ')
          ..write('seconds: $seconds, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(day, seconds, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelReadingDayRow &&
          other.day == this.day &&
          other.seconds == this.seconds &&
          other.updatedAt == this.updatedAt);
}

class NovelReadingDaysCompanion extends UpdateCompanion<NovelReadingDayRow> {
  final Value<String> day;
  final Value<int> seconds;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const NovelReadingDaysCompanion({
    this.day = const Value.absent(),
    this.seconds = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NovelReadingDaysCompanion.insert({
    required String day,
    this.seconds = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : day = Value(day),
       updatedAt = Value(updatedAt);
  static Insertable<NovelReadingDayRow> custom({
    Expression<String>? day,
    Expression<int>? seconds,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (day != null) 'day': day,
      if (seconds != null) 'seconds': seconds,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NovelReadingDaysCompanion copyWith({
    Value<String>? day,
    Value<int>? seconds,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return NovelReadingDaysCompanion(
      day: day ?? this.day,
      seconds: seconds ?? this.seconds,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (seconds.present) {
      map['seconds'] = Variable<int>(seconds.value);
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
    return (StringBuffer('NovelReadingDaysCompanion(')
          ..write('day: $day, ')
          ..write('seconds: $seconds, ')
          ..write('updatedAt: $updatedAt, ')
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
  late final $NovelPrefsTable novelPrefs = $NovelPrefsTable(this);
  late final $NovelReadingDaysTable novelReadingDays = $NovelReadingDaysTable(
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
    novelPrefs,
    novelReadingDays,
  ];
}

typedef $$NovelCollectEntriesTableCreateCompanionBuilder =
    NovelCollectEntriesCompanion Function({
      required String id,
      required String title,
      Value<String?> coverUrl,
      Value<String> payload,
      Value<String?> groupName,
      required DateTime collectedAt,
      Value<int> rowid,
    });
typedef $$NovelCollectEntriesTableUpdateCompanionBuilder =
    NovelCollectEntriesCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> coverUrl,
      Value<String> payload,
      Value<String?> groupName,
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

  ColumnFilters<String> get groupName => $composableBuilder(
    column: $table.groupName,
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

  ColumnOrderings<String> get groupName => $composableBuilder(
    column: $table.groupName,
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

  GeneratedColumn<String> get groupName =>
      $composableBuilder(column: $table.groupName, builder: (column) => column);

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
                Value<String?> groupName = const Value.absent(),
                Value<DateTime> collectedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NovelCollectEntriesCompanion(
                id: id,
                title: title,
                coverUrl: coverUrl,
                payload: payload,
                groupName: groupName,
                collectedAt: collectedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> coverUrl = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String?> groupName = const Value.absent(),
                required DateTime collectedAt,
                Value<int> rowid = const Value.absent(),
              }) => NovelCollectEntriesCompanion.insert(
                id: id,
                title: title,
                coverUrl: coverUrl,
                payload: payload,
                groupName: groupName,
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
typedef $$NovelPrefsTableCreateCompanionBuilder =
    NovelPrefsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$NovelPrefsTableUpdateCompanionBuilder =
    NovelPrefsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$NovelPrefsTableFilterComposer
    extends Composer<_$NovelDb, $NovelPrefsTable> {
  $$NovelPrefsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NovelPrefsTableOrderingComposer
    extends Composer<_$NovelDb, $NovelPrefsTable> {
  $$NovelPrefsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NovelPrefsTableAnnotationComposer
    extends Composer<_$NovelDb, $NovelPrefsTable> {
  $$NovelPrefsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$NovelPrefsTableTableManager
    extends
        RootTableManager<
          _$NovelDb,
          $NovelPrefsTable,
          NovelPrefRow,
          $$NovelPrefsTableFilterComposer,
          $$NovelPrefsTableOrderingComposer,
          $$NovelPrefsTableAnnotationComposer,
          $$NovelPrefsTableCreateCompanionBuilder,
          $$NovelPrefsTableUpdateCompanionBuilder,
          (
            NovelPrefRow,
            BaseReferences<_$NovelDb, $NovelPrefsTable, NovelPrefRow>,
          ),
          NovelPrefRow,
          PrefetchHooks Function()
        > {
  $$NovelPrefsTableTableManager(_$NovelDb db, $NovelPrefsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NovelPrefsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NovelPrefsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NovelPrefsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NovelPrefsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => NovelPrefsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NovelPrefsTableProcessedTableManager =
    ProcessedTableManager<
      _$NovelDb,
      $NovelPrefsTable,
      NovelPrefRow,
      $$NovelPrefsTableFilterComposer,
      $$NovelPrefsTableOrderingComposer,
      $$NovelPrefsTableAnnotationComposer,
      $$NovelPrefsTableCreateCompanionBuilder,
      $$NovelPrefsTableUpdateCompanionBuilder,
      (NovelPrefRow, BaseReferences<_$NovelDb, $NovelPrefsTable, NovelPrefRow>),
      NovelPrefRow,
      PrefetchHooks Function()
    >;
typedef $$NovelReadingDaysTableCreateCompanionBuilder =
    NovelReadingDaysCompanion Function({
      required String day,
      Value<int> seconds,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$NovelReadingDaysTableUpdateCompanionBuilder =
    NovelReadingDaysCompanion Function({
      Value<String> day,
      Value<int> seconds,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$NovelReadingDaysTableFilterComposer
    extends Composer<_$NovelDb, $NovelReadingDaysTable> {
  $$NovelReadingDaysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seconds => $composableBuilder(
    column: $table.seconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NovelReadingDaysTableOrderingComposer
    extends Composer<_$NovelDb, $NovelReadingDaysTable> {
  $$NovelReadingDaysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seconds => $composableBuilder(
    column: $table.seconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NovelReadingDaysTableAnnotationComposer
    extends Composer<_$NovelDb, $NovelReadingDaysTable> {
  $$NovelReadingDaysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<int> get seconds =>
      $composableBuilder(column: $table.seconds, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$NovelReadingDaysTableTableManager
    extends
        RootTableManager<
          _$NovelDb,
          $NovelReadingDaysTable,
          NovelReadingDayRow,
          $$NovelReadingDaysTableFilterComposer,
          $$NovelReadingDaysTableOrderingComposer,
          $$NovelReadingDaysTableAnnotationComposer,
          $$NovelReadingDaysTableCreateCompanionBuilder,
          $$NovelReadingDaysTableUpdateCompanionBuilder,
          (
            NovelReadingDayRow,
            BaseReferences<
              _$NovelDb,
              $NovelReadingDaysTable,
              NovelReadingDayRow
            >,
          ),
          NovelReadingDayRow,
          PrefetchHooks Function()
        > {
  $$NovelReadingDaysTableTableManager(
    _$NovelDb db,
    $NovelReadingDaysTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NovelReadingDaysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NovelReadingDaysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NovelReadingDaysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> day = const Value.absent(),
                Value<int> seconds = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NovelReadingDaysCompanion(
                day: day,
                seconds: seconds,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String day,
                Value<int> seconds = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => NovelReadingDaysCompanion.insert(
                day: day,
                seconds: seconds,
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

typedef $$NovelReadingDaysTableProcessedTableManager =
    ProcessedTableManager<
      _$NovelDb,
      $NovelReadingDaysTable,
      NovelReadingDayRow,
      $$NovelReadingDaysTableFilterComposer,
      $$NovelReadingDaysTableOrderingComposer,
      $$NovelReadingDaysTableAnnotationComposer,
      $$NovelReadingDaysTableCreateCompanionBuilder,
      $$NovelReadingDaysTableUpdateCompanionBuilder,
      (
        NovelReadingDayRow,
        BaseReferences<_$NovelDb, $NovelReadingDaysTable, NovelReadingDayRow>,
      ),
      NovelReadingDayRow,
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
  $$NovelPrefsTableTableManager get novelPrefs =>
      $$NovelPrefsTableTableManager(_db, _db.novelPrefs);
  $$NovelReadingDaysTableTableManager get novelReadingDays =>
      $$NovelReadingDaysTableTableManager(_db, _db.novelReadingDays);
}
