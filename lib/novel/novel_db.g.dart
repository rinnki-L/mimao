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
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _customCoverPathMeta = const VerificationMeta(
    'customCoverPath',
  );
  @override
  late final GeneratedColumn<String> customCoverPath = GeneratedColumn<String>(
    'custom_cover_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<int> seriesId = GeneratedColumn<int>(
    'series_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
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
    note,
    customCoverPath,
    seriesId,
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
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('custom_cover_path')) {
      context.handle(
        _customCoverPathMeta,
        customCoverPath.isAcceptableOrUnknown(
          data['custom_cover_path']!,
          _customCoverPathMeta,
        ),
      );
    }
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
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
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      customCoverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_cover_path'],
      ),
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}series_id'],
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

  /// 用户手写备注（自由文本，空串 = 无备注）。与"分组/系列"不同，它是
  /// 给人看的碎碎念，不参与筛选与排序。
  final String note;

  /// 自定义封面：本地图片路径（复制进应用支持目录后存的绝对路径）；
  /// null = 继续用书籍自带的 coverUrl。
  final String? customCoverPath;

  /// 所属系列（`novel_series.id`）；null = 不属于任何系列。
  /// 系列与分组正交：分组是"我把它放哪"，系列是"这本书属于哪个作品集"。
  final int? seriesId;
  final DateTime collectedAt;
  const NovelCollectRow({
    required this.id,
    required this.title,
    this.coverUrl,
    required this.payload,
    this.groupName,
    required this.note,
    this.customCoverPath,
    this.seriesId,
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
    map['note'] = Variable<String>(note);
    if (!nullToAbsent || customCoverPath != null) {
      map['custom_cover_path'] = Variable<String>(customCoverPath);
    }
    if (!nullToAbsent || seriesId != null) {
      map['series_id'] = Variable<int>(seriesId);
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
      note: Value(note),
      customCoverPath: customCoverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(customCoverPath),
      seriesId: seriesId == null && nullToAbsent
          ? const Value.absent()
          : Value(seriesId),
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
      note: serializer.fromJson<String>(json['note']),
      customCoverPath: serializer.fromJson<String?>(json['customCoverPath']),
      seriesId: serializer.fromJson<int?>(json['seriesId']),
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
      'note': serializer.toJson<String>(note),
      'customCoverPath': serializer.toJson<String?>(customCoverPath),
      'seriesId': serializer.toJson<int?>(seriesId),
      'collectedAt': serializer.toJson<DateTime>(collectedAt),
    };
  }

  NovelCollectRow copyWith({
    String? id,
    String? title,
    Value<String?> coverUrl = const Value.absent(),
    String? payload,
    Value<String?> groupName = const Value.absent(),
    String? note,
    Value<String?> customCoverPath = const Value.absent(),
    Value<int?> seriesId = const Value.absent(),
    DateTime? collectedAt,
  }) => NovelCollectRow(
    id: id ?? this.id,
    title: title ?? this.title,
    coverUrl: coverUrl.present ? coverUrl.value : this.coverUrl,
    payload: payload ?? this.payload,
    groupName: groupName.present ? groupName.value : this.groupName,
    note: note ?? this.note,
    customCoverPath: customCoverPath.present
        ? customCoverPath.value
        : this.customCoverPath,
    seriesId: seriesId.present ? seriesId.value : this.seriesId,
    collectedAt: collectedAt ?? this.collectedAt,
  );
  NovelCollectRow copyWithCompanion(NovelCollectEntriesCompanion data) {
    return NovelCollectRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      coverUrl: data.coverUrl.present ? data.coverUrl.value : this.coverUrl,
      payload: data.payload.present ? data.payload.value : this.payload,
      groupName: data.groupName.present ? data.groupName.value : this.groupName,
      note: data.note.present ? data.note.value : this.note,
      customCoverPath: data.customCoverPath.present
          ? data.customCoverPath.value
          : this.customCoverPath,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
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
          ..write('note: $note, ')
          ..write('customCoverPath: $customCoverPath, ')
          ..write('seriesId: $seriesId, ')
          ..write('collectedAt: $collectedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    coverUrl,
    payload,
    groupName,
    note,
    customCoverPath,
    seriesId,
    collectedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelCollectRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.coverUrl == this.coverUrl &&
          other.payload == this.payload &&
          other.groupName == this.groupName &&
          other.note == this.note &&
          other.customCoverPath == this.customCoverPath &&
          other.seriesId == this.seriesId &&
          other.collectedAt == this.collectedAt);
}

class NovelCollectEntriesCompanion extends UpdateCompanion<NovelCollectRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> coverUrl;
  final Value<String> payload;
  final Value<String?> groupName;
  final Value<String> note;
  final Value<String?> customCoverPath;
  final Value<int?> seriesId;
  final Value<DateTime> collectedAt;
  final Value<int> rowid;
  const NovelCollectEntriesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.payload = const Value.absent(),
    this.groupName = const Value.absent(),
    this.note = const Value.absent(),
    this.customCoverPath = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.collectedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NovelCollectEntriesCompanion.insert({
    required String id,
    required String title,
    this.coverUrl = const Value.absent(),
    this.payload = const Value.absent(),
    this.groupName = const Value.absent(),
    this.note = const Value.absent(),
    this.customCoverPath = const Value.absent(),
    this.seriesId = const Value.absent(),
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
    Expression<String>? note,
    Expression<String>? customCoverPath,
    Expression<int>? seriesId,
    Expression<DateTime>? collectedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (payload != null) 'payload': payload,
      if (groupName != null) 'group_name': groupName,
      if (note != null) 'note': note,
      if (customCoverPath != null) 'custom_cover_path': customCoverPath,
      if (seriesId != null) 'series_id': seriesId,
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
    Value<String>? note,
    Value<String?>? customCoverPath,
    Value<int?>? seriesId,
    Value<DateTime>? collectedAt,
    Value<int>? rowid,
  }) {
    return NovelCollectEntriesCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      payload: payload ?? this.payload,
      groupName: groupName ?? this.groupName,
      note: note ?? this.note,
      customCoverPath: customCoverPath ?? this.customCoverPath,
      seriesId: seriesId ?? this.seriesId,
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
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (customCoverPath.present) {
      map['custom_cover_path'] = Variable<String>(customCoverPath.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<int>(seriesId.value);
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
          ..write('note: $note, ')
          ..write('customCoverPath: $customCoverPath, ')
          ..write('seriesId: $seriesId, ')
          ..write('collectedAt: $collectedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NovelSeriesEntriesTable extends NovelSeriesEntries
    with TableInfo<$NovelSeriesEntriesTable, NovelSeriesRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NovelSeriesEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'novel_series';
  @override
  VerificationContext validateIntegrity(
    Insertable<NovelSeriesRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NovelSeriesRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NovelSeriesRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $NovelSeriesEntriesTable createAlias(String alias) {
    return $NovelSeriesEntriesTable(attachedDatabase, alias);
  }
}

class NovelSeriesRow extends DataClass implements Insertable<NovelSeriesRow> {
  final int id;
  final String name;
  final DateTime createdAt;
  const NovelSeriesRow({
    required this.id,
    required this.name,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  NovelSeriesEntriesCompanion toCompanion(bool nullToAbsent) {
    return NovelSeriesEntriesCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
    );
  }

  factory NovelSeriesRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NovelSeriesRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  NovelSeriesRow copyWith({int? id, String? name, DateTime? createdAt}) =>
      NovelSeriesRow(
        id: id ?? this.id,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
      );
  NovelSeriesRow copyWithCompanion(NovelSeriesEntriesCompanion data) {
    return NovelSeriesRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NovelSeriesRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelSeriesRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt);
}

class NovelSeriesEntriesCompanion extends UpdateCompanion<NovelSeriesRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  const NovelSeriesEntriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  NovelSeriesEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required DateTime createdAt,
  }) : name = Value(name),
       createdAt = Value(createdAt);
  static Insertable<NovelSeriesRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  NovelSeriesEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<DateTime>? createdAt,
  }) {
    return NovelSeriesEntriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NovelSeriesEntriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
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

class $NovelReadRecordsTable extends NovelReadRecords
    with TableInfo<$NovelReadRecordsTable, NovelReadRecordRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NovelReadRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookTitleMeta = const VerificationMeta(
    'bookTitle',
  );
  @override
  late final GeneratedColumn<String> bookTitle = GeneratedColumn<String>(
    'book_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
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
  static const VerificationMeta _chapterNameMeta = const VerificationMeta(
    'chapterName',
  );
  @override
  late final GeneratedColumn<String> chapterName = GeneratedColumn<String>(
    'chapter_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
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
  static const VerificationMeta _firstReadAtMeta = const VerificationMeta(
    'firstReadAt',
  );
  @override
  late final GeneratedColumn<DateTime> firstReadAt = GeneratedColumn<DateTime>(
    'first_read_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastReadAtMeta = const VerificationMeta(
    'lastReadAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastReadAt = GeneratedColumn<DateTime>(
    'last_read_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    deviceId,
    bookId,
    bookTitle,
    chapterIndex,
    chapterName,
    day,
    seconds,
    firstReadAt,
    lastReadAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'novel_read_record';
  @override
  VerificationContext validateIntegrity(
    Insertable<NovelReadRecordRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('book_title')) {
      context.handle(
        _bookTitleMeta,
        bookTitle.isAcceptableOrUnknown(data['book_title']!, _bookTitleMeta),
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
    if (data.containsKey('chapter_name')) {
      context.handle(
        _chapterNameMeta,
        chapterName.isAcceptableOrUnknown(
          data['chapter_name']!,
          _chapterNameMeta,
        ),
      );
    }
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
    if (data.containsKey('first_read_at')) {
      context.handle(
        _firstReadAtMeta,
        firstReadAt.isAcceptableOrUnknown(
          data['first_read_at']!,
          _firstReadAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstReadAtMeta);
    }
    if (data.containsKey('last_read_at')) {
      context.handle(
        _lastReadAtMeta,
        lastReadAt.isAcceptableOrUnknown(
          data['last_read_at']!,
          _lastReadAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastReadAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId, bookId, chapterIndex, day};
  @override
  NovelReadRecordRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NovelReadRecordRow(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      bookTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_title'],
      )!,
      chapterIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_index'],
      )!,
      chapterName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_name'],
      )!,
      day: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}day'],
      )!,
      seconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seconds'],
      )!,
      firstReadAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}first_read_at'],
      )!,
      lastReadAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_read_at'],
      )!,
    );
  }

  @override
  $NovelReadRecordsTable createAlias(String alias) {
    return $NovelReadRecordsTable(attachedDatabase, alias);
  }
}

class NovelReadRecordRow extends DataClass
    implements Insertable<NovelReadRecordRow> {
  /// 设备 ID（`novel_pref.device_id`；旧数据迁移时填本机）。
  final String deviceId;

  /// 书籍主键；空串 = 旧数据/未关联书籍。
  final String bookId;

  /// 书名快照：时间轴不必回查收藏/历史表，删书后记录仍可读。
  final String bookTitle;

  /// 章号（1 起；0 = 未知），与 `novel_history.chapter_index` 同口径。
  final int chapterIndex;
  final String chapterName;

  /// 本地日期 `yyyy-MM-dd`（阅读时长按用户本地日切分）。
  final String day;
  final int seconds;
  final DateTime firstReadAt;
  final DateTime lastReadAt;
  const NovelReadRecordRow({
    required this.deviceId,
    required this.bookId,
    required this.bookTitle,
    required this.chapterIndex,
    required this.chapterName,
    required this.day,
    required this.seconds,
    required this.firstReadAt,
    required this.lastReadAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['book_id'] = Variable<String>(bookId);
    map['book_title'] = Variable<String>(bookTitle);
    map['chapter_index'] = Variable<int>(chapterIndex);
    map['chapter_name'] = Variable<String>(chapterName);
    map['day'] = Variable<String>(day);
    map['seconds'] = Variable<int>(seconds);
    map['first_read_at'] = Variable<DateTime>(firstReadAt);
    map['last_read_at'] = Variable<DateTime>(lastReadAt);
    return map;
  }

  NovelReadRecordsCompanion toCompanion(bool nullToAbsent) {
    return NovelReadRecordsCompanion(
      deviceId: Value(deviceId),
      bookId: Value(bookId),
      bookTitle: Value(bookTitle),
      chapterIndex: Value(chapterIndex),
      chapterName: Value(chapterName),
      day: Value(day),
      seconds: Value(seconds),
      firstReadAt: Value(firstReadAt),
      lastReadAt: Value(lastReadAt),
    );
  }

  factory NovelReadRecordRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NovelReadRecordRow(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      bookId: serializer.fromJson<String>(json['bookId']),
      bookTitle: serializer.fromJson<String>(json['bookTitle']),
      chapterIndex: serializer.fromJson<int>(json['chapterIndex']),
      chapterName: serializer.fromJson<String>(json['chapterName']),
      day: serializer.fromJson<String>(json['day']),
      seconds: serializer.fromJson<int>(json['seconds']),
      firstReadAt: serializer.fromJson<DateTime>(json['firstReadAt']),
      lastReadAt: serializer.fromJson<DateTime>(json['lastReadAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'bookId': serializer.toJson<String>(bookId),
      'bookTitle': serializer.toJson<String>(bookTitle),
      'chapterIndex': serializer.toJson<int>(chapterIndex),
      'chapterName': serializer.toJson<String>(chapterName),
      'day': serializer.toJson<String>(day),
      'seconds': serializer.toJson<int>(seconds),
      'firstReadAt': serializer.toJson<DateTime>(firstReadAt),
      'lastReadAt': serializer.toJson<DateTime>(lastReadAt),
    };
  }

  NovelReadRecordRow copyWith({
    String? deviceId,
    String? bookId,
    String? bookTitle,
    int? chapterIndex,
    String? chapterName,
    String? day,
    int? seconds,
    DateTime? firstReadAt,
    DateTime? lastReadAt,
  }) => NovelReadRecordRow(
    deviceId: deviceId ?? this.deviceId,
    bookId: bookId ?? this.bookId,
    bookTitle: bookTitle ?? this.bookTitle,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    chapterName: chapterName ?? this.chapterName,
    day: day ?? this.day,
    seconds: seconds ?? this.seconds,
    firstReadAt: firstReadAt ?? this.firstReadAt,
    lastReadAt: lastReadAt ?? this.lastReadAt,
  );
  NovelReadRecordRow copyWithCompanion(NovelReadRecordsCompanion data) {
    return NovelReadRecordRow(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      bookTitle: data.bookTitle.present ? data.bookTitle.value : this.bookTitle,
      chapterIndex: data.chapterIndex.present
          ? data.chapterIndex.value
          : this.chapterIndex,
      chapterName: data.chapterName.present
          ? data.chapterName.value
          : this.chapterName,
      day: data.day.present ? data.day.value : this.day,
      seconds: data.seconds.present ? data.seconds.value : this.seconds,
      firstReadAt: data.firstReadAt.present
          ? data.firstReadAt.value
          : this.firstReadAt,
      lastReadAt: data.lastReadAt.present
          ? data.lastReadAt.value
          : this.lastReadAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NovelReadRecordRow(')
          ..write('deviceId: $deviceId, ')
          ..write('bookId: $bookId, ')
          ..write('bookTitle: $bookTitle, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('chapterName: $chapterName, ')
          ..write('day: $day, ')
          ..write('seconds: $seconds, ')
          ..write('firstReadAt: $firstReadAt, ')
          ..write('lastReadAt: $lastReadAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    deviceId,
    bookId,
    bookTitle,
    chapterIndex,
    chapterName,
    day,
    seconds,
    firstReadAt,
    lastReadAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelReadRecordRow &&
          other.deviceId == this.deviceId &&
          other.bookId == this.bookId &&
          other.bookTitle == this.bookTitle &&
          other.chapterIndex == this.chapterIndex &&
          other.chapterName == this.chapterName &&
          other.day == this.day &&
          other.seconds == this.seconds &&
          other.firstReadAt == this.firstReadAt &&
          other.lastReadAt == this.lastReadAt);
}

class NovelReadRecordsCompanion extends UpdateCompanion<NovelReadRecordRow> {
  final Value<String> deviceId;
  final Value<String> bookId;
  final Value<String> bookTitle;
  final Value<int> chapterIndex;
  final Value<String> chapterName;
  final Value<String> day;
  final Value<int> seconds;
  final Value<DateTime> firstReadAt;
  final Value<DateTime> lastReadAt;
  final Value<int> rowid;
  const NovelReadRecordsCompanion({
    this.deviceId = const Value.absent(),
    this.bookId = const Value.absent(),
    this.bookTitle = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.chapterName = const Value.absent(),
    this.day = const Value.absent(),
    this.seconds = const Value.absent(),
    this.firstReadAt = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NovelReadRecordsCompanion.insert({
    required String deviceId,
    required String bookId,
    this.bookTitle = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.chapterName = const Value.absent(),
    required String day,
    this.seconds = const Value.absent(),
    required DateTime firstReadAt,
    required DateTime lastReadAt,
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       bookId = Value(bookId),
       day = Value(day),
       firstReadAt = Value(firstReadAt),
       lastReadAt = Value(lastReadAt);
  static Insertable<NovelReadRecordRow> custom({
    Expression<String>? deviceId,
    Expression<String>? bookId,
    Expression<String>? bookTitle,
    Expression<int>? chapterIndex,
    Expression<String>? chapterName,
    Expression<String>? day,
    Expression<int>? seconds,
    Expression<DateTime>? firstReadAt,
    Expression<DateTime>? lastReadAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (bookId != null) 'book_id': bookId,
      if (bookTitle != null) 'book_title': bookTitle,
      if (chapterIndex != null) 'chapter_index': chapterIndex,
      if (chapterName != null) 'chapter_name': chapterName,
      if (day != null) 'day': day,
      if (seconds != null) 'seconds': seconds,
      if (firstReadAt != null) 'first_read_at': firstReadAt,
      if (lastReadAt != null) 'last_read_at': lastReadAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NovelReadRecordsCompanion copyWith({
    Value<String>? deviceId,
    Value<String>? bookId,
    Value<String>? bookTitle,
    Value<int>? chapterIndex,
    Value<String>? chapterName,
    Value<String>? day,
    Value<int>? seconds,
    Value<DateTime>? firstReadAt,
    Value<DateTime>? lastReadAt,
    Value<int>? rowid,
  }) {
    return NovelReadRecordsCompanion(
      deviceId: deviceId ?? this.deviceId,
      bookId: bookId ?? this.bookId,
      bookTitle: bookTitle ?? this.bookTitle,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      chapterName: chapterName ?? this.chapterName,
      day: day ?? this.day,
      seconds: seconds ?? this.seconds,
      firstReadAt: firstReadAt ?? this.firstReadAt,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (bookTitle.present) {
      map['book_title'] = Variable<String>(bookTitle.value);
    }
    if (chapterIndex.present) {
      map['chapter_index'] = Variable<int>(chapterIndex.value);
    }
    if (chapterName.present) {
      map['chapter_name'] = Variable<String>(chapterName.value);
    }
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (seconds.present) {
      map['seconds'] = Variable<int>(seconds.value);
    }
    if (firstReadAt.present) {
      map['first_read_at'] = Variable<DateTime>(firstReadAt.value);
    }
    if (lastReadAt.present) {
      map['last_read_at'] = Variable<DateTime>(lastReadAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NovelReadRecordsCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('bookId: $bookId, ')
          ..write('bookTitle: $bookTitle, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('chapterName: $chapterName, ')
          ..write('day: $day, ')
          ..write('seconds: $seconds, ')
          ..write('firstReadAt: $firstReadAt, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NovelBookmarkEntriesTable extends NovelBookmarkEntries
    with TableInfo<$NovelBookmarkEntriesTable, NovelBookmarkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NovelBookmarkEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceKeyMeta = const VerificationMeta(
    'sourceKey',
  );
  @override
  late final GeneratedColumn<String> sourceKey = GeneratedColumn<String>(
    'source_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _bookTitleMeta = const VerificationMeta(
    'bookTitle',
  );
  @override
  late final GeneratedColumn<String> bookTitle = GeneratedColumn<String>(
    'book_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _bookAuthorMeta = const VerificationMeta(
    'bookAuthor',
  );
  @override
  late final GeneratedColumn<String> bookAuthor = GeneratedColumn<String>(
    'book_author',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _bookUrlMeta = const VerificationMeta(
    'bookUrl',
  );
  @override
  late final GeneratedColumn<String> bookUrl = GeneratedColumn<String>(
    'book_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paragraphMeta = const VerificationMeta(
    'paragraph',
  );
  @override
  late final GeneratedColumn<int> paragraph = GeneratedColumn<int>(
    'paragraph',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _charOffsetMeta = const VerificationMeta(
    'charOffset',
  );
  @override
  late final GeneratedColumn<int> charOffset = GeneratedColumn<int>(
    'char_offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _chapterNameMeta = const VerificationMeta(
    'chapterName',
  );
  @override
  late final GeneratedColumn<String> chapterName = GeneratedColumn<String>(
    'chapter_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _excerptMeta = const VerificationMeta(
    'excerpt',
  );
  @override
  late final GeneratedColumn<String> excerpt = GeneratedColumn<String>(
    'excerpt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _unresolvedMeta = const VerificationMeta(
    'unresolved',
  );
  @override
  late final GeneratedColumn<bool> unresolved = GeneratedColumn<bool>(
    'unresolved',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("unresolved" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    sourceKey,
    bookTitle,
    bookAuthor,
    bookUrl,
    chapterIndex,
    paragraph,
    charOffset,
    chapterName,
    excerpt,
    unresolved,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bookmark';
  @override
  VerificationContext validateIntegrity(
    Insertable<NovelBookmarkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('source_key')) {
      context.handle(
        _sourceKeyMeta,
        sourceKey.isAcceptableOrUnknown(data['source_key']!, _sourceKeyMeta),
      );
    }
    if (data.containsKey('book_title')) {
      context.handle(
        _bookTitleMeta,
        bookTitle.isAcceptableOrUnknown(data['book_title']!, _bookTitleMeta),
      );
    }
    if (data.containsKey('book_author')) {
      context.handle(
        _bookAuthorMeta,
        bookAuthor.isAcceptableOrUnknown(data['book_author']!, _bookAuthorMeta),
      );
    }
    if (data.containsKey('book_url')) {
      context.handle(
        _bookUrlMeta,
        bookUrl.isAcceptableOrUnknown(data['book_url']!, _bookUrlMeta),
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
    } else if (isInserting) {
      context.missing(_chapterIndexMeta);
    }
    if (data.containsKey('paragraph')) {
      context.handle(
        _paragraphMeta,
        paragraph.isAcceptableOrUnknown(data['paragraph']!, _paragraphMeta),
      );
    }
    if (data.containsKey('char_offset')) {
      context.handle(
        _charOffsetMeta,
        charOffset.isAcceptableOrUnknown(data['char_offset']!, _charOffsetMeta),
      );
    }
    if (data.containsKey('chapter_name')) {
      context.handle(
        _chapterNameMeta,
        chapterName.isAcceptableOrUnknown(
          data['chapter_name']!,
          _chapterNameMeta,
        ),
      );
    }
    if (data.containsKey('excerpt')) {
      context.handle(
        _excerptMeta,
        excerpt.isAcceptableOrUnknown(data['excerpt']!, _excerptMeta),
      );
    }
    if (data.containsKey('unresolved')) {
      context.handle(
        _unresolvedMeta,
        unresolved.isAcceptableOrUnknown(data['unresolved']!, _unresolvedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NovelBookmarkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NovelBookmarkRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      sourceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_key'],
      )!,
      bookTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_title'],
      )!,
      bookAuthor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_author'],
      )!,
      bookUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_url'],
      )!,
      chapterIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_index'],
      )!,
      paragraph: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}paragraph'],
      )!,
      charOffset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}char_offset'],
      )!,
      chapterName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_name'],
      )!,
      excerpt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}excerpt'],
      )!,
      unresolved: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}unresolved'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $NovelBookmarkEntriesTable createAlias(String alias) {
    return $NovelBookmarkEntriesTable(attachedDatabase, alias);
  }
}

class NovelBookmarkRow extends DataClass
    implements Insertable<NovelBookmarkRow> {
  final int id;
  final String bookId;
  final String sourceKey;

  /// 书名列（参考上游 bookName）：全书书签列表按书分组时不必回查收藏表。
  final String bookTitle;
  final String bookAuthor;

  /// 书源详情页地址：从书签列表重新打开阅读器时重建 NovelRef 用
  /// （跨会话没有内存里的 detail 可依）。
  final String bookUrl;

  /// 0 起章下标（引擎口径，与 [NovelLocator.chapterIndex] 一致）。
  final int chapterIndex;

  /// 0 起段落下标；-1 表示章标题。
  final int paragraph;

  /// 段内字符偏移（不含段首缩进）。
  final int charOffset;
  final String chapterName;
  final String excerpt;

  /// 换源后按章标题/段落尽力重定位；失败置 true，列表里标「无法定位」，
  /// 不删行（上游同样保留书签，跳转前再问用户）。
  final bool unresolved;
  final DateTime createdAt;
  const NovelBookmarkRow({
    required this.id,
    required this.bookId,
    required this.sourceKey,
    required this.bookTitle,
    required this.bookAuthor,
    required this.bookUrl,
    required this.chapterIndex,
    required this.paragraph,
    required this.charOffset,
    required this.chapterName,
    required this.excerpt,
    required this.unresolved,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['book_id'] = Variable<String>(bookId);
    map['source_key'] = Variable<String>(sourceKey);
    map['book_title'] = Variable<String>(bookTitle);
    map['book_author'] = Variable<String>(bookAuthor);
    map['book_url'] = Variable<String>(bookUrl);
    map['chapter_index'] = Variable<int>(chapterIndex);
    map['paragraph'] = Variable<int>(paragraph);
    map['char_offset'] = Variable<int>(charOffset);
    map['chapter_name'] = Variable<String>(chapterName);
    map['excerpt'] = Variable<String>(excerpt);
    map['unresolved'] = Variable<bool>(unresolved);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  NovelBookmarkEntriesCompanion toCompanion(bool nullToAbsent) {
    return NovelBookmarkEntriesCompanion(
      id: Value(id),
      bookId: Value(bookId),
      sourceKey: Value(sourceKey),
      bookTitle: Value(bookTitle),
      bookAuthor: Value(bookAuthor),
      bookUrl: Value(bookUrl),
      chapterIndex: Value(chapterIndex),
      paragraph: Value(paragraph),
      charOffset: Value(charOffset),
      chapterName: Value(chapterName),
      excerpt: Value(excerpt),
      unresolved: Value(unresolved),
      createdAt: Value(createdAt),
    );
  }

  factory NovelBookmarkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NovelBookmarkRow(
      id: serializer.fromJson<int>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      sourceKey: serializer.fromJson<String>(json['sourceKey']),
      bookTitle: serializer.fromJson<String>(json['bookTitle']),
      bookAuthor: serializer.fromJson<String>(json['bookAuthor']),
      bookUrl: serializer.fromJson<String>(json['bookUrl']),
      chapterIndex: serializer.fromJson<int>(json['chapterIndex']),
      paragraph: serializer.fromJson<int>(json['paragraph']),
      charOffset: serializer.fromJson<int>(json['charOffset']),
      chapterName: serializer.fromJson<String>(json['chapterName']),
      excerpt: serializer.fromJson<String>(json['excerpt']),
      unresolved: serializer.fromJson<bool>(json['unresolved']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bookId': serializer.toJson<String>(bookId),
      'sourceKey': serializer.toJson<String>(sourceKey),
      'bookTitle': serializer.toJson<String>(bookTitle),
      'bookAuthor': serializer.toJson<String>(bookAuthor),
      'bookUrl': serializer.toJson<String>(bookUrl),
      'chapterIndex': serializer.toJson<int>(chapterIndex),
      'paragraph': serializer.toJson<int>(paragraph),
      'charOffset': serializer.toJson<int>(charOffset),
      'chapterName': serializer.toJson<String>(chapterName),
      'excerpt': serializer.toJson<String>(excerpt),
      'unresolved': serializer.toJson<bool>(unresolved),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  NovelBookmarkRow copyWith({
    int? id,
    String? bookId,
    String? sourceKey,
    String? bookTitle,
    String? bookAuthor,
    String? bookUrl,
    int? chapterIndex,
    int? paragraph,
    int? charOffset,
    String? chapterName,
    String? excerpt,
    bool? unresolved,
    DateTime? createdAt,
  }) => NovelBookmarkRow(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    sourceKey: sourceKey ?? this.sourceKey,
    bookTitle: bookTitle ?? this.bookTitle,
    bookAuthor: bookAuthor ?? this.bookAuthor,
    bookUrl: bookUrl ?? this.bookUrl,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    paragraph: paragraph ?? this.paragraph,
    charOffset: charOffset ?? this.charOffset,
    chapterName: chapterName ?? this.chapterName,
    excerpt: excerpt ?? this.excerpt,
    unresolved: unresolved ?? this.unresolved,
    createdAt: createdAt ?? this.createdAt,
  );
  NovelBookmarkRow copyWithCompanion(NovelBookmarkEntriesCompanion data) {
    return NovelBookmarkRow(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      sourceKey: data.sourceKey.present ? data.sourceKey.value : this.sourceKey,
      bookTitle: data.bookTitle.present ? data.bookTitle.value : this.bookTitle,
      bookAuthor: data.bookAuthor.present
          ? data.bookAuthor.value
          : this.bookAuthor,
      bookUrl: data.bookUrl.present ? data.bookUrl.value : this.bookUrl,
      chapterIndex: data.chapterIndex.present
          ? data.chapterIndex.value
          : this.chapterIndex,
      paragraph: data.paragraph.present ? data.paragraph.value : this.paragraph,
      charOffset: data.charOffset.present
          ? data.charOffset.value
          : this.charOffset,
      chapterName: data.chapterName.present
          ? data.chapterName.value
          : this.chapterName,
      excerpt: data.excerpt.present ? data.excerpt.value : this.excerpt,
      unresolved: data.unresolved.present
          ? data.unresolved.value
          : this.unresolved,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NovelBookmarkRow(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('sourceKey: $sourceKey, ')
          ..write('bookTitle: $bookTitle, ')
          ..write('bookAuthor: $bookAuthor, ')
          ..write('bookUrl: $bookUrl, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('paragraph: $paragraph, ')
          ..write('charOffset: $charOffset, ')
          ..write('chapterName: $chapterName, ')
          ..write('excerpt: $excerpt, ')
          ..write('unresolved: $unresolved, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    sourceKey,
    bookTitle,
    bookAuthor,
    bookUrl,
    chapterIndex,
    paragraph,
    charOffset,
    chapterName,
    excerpt,
    unresolved,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelBookmarkRow &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.sourceKey == this.sourceKey &&
          other.bookTitle == this.bookTitle &&
          other.bookAuthor == this.bookAuthor &&
          other.bookUrl == this.bookUrl &&
          other.chapterIndex == this.chapterIndex &&
          other.paragraph == this.paragraph &&
          other.charOffset == this.charOffset &&
          other.chapterName == this.chapterName &&
          other.excerpt == this.excerpt &&
          other.unresolved == this.unresolved &&
          other.createdAt == this.createdAt);
}

class NovelBookmarkEntriesCompanion extends UpdateCompanion<NovelBookmarkRow> {
  final Value<int> id;
  final Value<String> bookId;
  final Value<String> sourceKey;
  final Value<String> bookTitle;
  final Value<String> bookAuthor;
  final Value<String> bookUrl;
  final Value<int> chapterIndex;
  final Value<int> paragraph;
  final Value<int> charOffset;
  final Value<String> chapterName;
  final Value<String> excerpt;
  final Value<bool> unresolved;
  final Value<DateTime> createdAt;
  const NovelBookmarkEntriesCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.sourceKey = const Value.absent(),
    this.bookTitle = const Value.absent(),
    this.bookAuthor = const Value.absent(),
    this.bookUrl = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.paragraph = const Value.absent(),
    this.charOffset = const Value.absent(),
    this.chapterName = const Value.absent(),
    this.excerpt = const Value.absent(),
    this.unresolved = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  NovelBookmarkEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String bookId,
    this.sourceKey = const Value.absent(),
    this.bookTitle = const Value.absent(),
    this.bookAuthor = const Value.absent(),
    this.bookUrl = const Value.absent(),
    required int chapterIndex,
    this.paragraph = const Value.absent(),
    this.charOffset = const Value.absent(),
    this.chapterName = const Value.absent(),
    this.excerpt = const Value.absent(),
    this.unresolved = const Value.absent(),
    required DateTime createdAt,
  }) : bookId = Value(bookId),
       chapterIndex = Value(chapterIndex),
       createdAt = Value(createdAt);
  static Insertable<NovelBookmarkRow> custom({
    Expression<int>? id,
    Expression<String>? bookId,
    Expression<String>? sourceKey,
    Expression<String>? bookTitle,
    Expression<String>? bookAuthor,
    Expression<String>? bookUrl,
    Expression<int>? chapterIndex,
    Expression<int>? paragraph,
    Expression<int>? charOffset,
    Expression<String>? chapterName,
    Expression<String>? excerpt,
    Expression<bool>? unresolved,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (sourceKey != null) 'source_key': sourceKey,
      if (bookTitle != null) 'book_title': bookTitle,
      if (bookAuthor != null) 'book_author': bookAuthor,
      if (bookUrl != null) 'book_url': bookUrl,
      if (chapterIndex != null) 'chapter_index': chapterIndex,
      if (paragraph != null) 'paragraph': paragraph,
      if (charOffset != null) 'char_offset': charOffset,
      if (chapterName != null) 'chapter_name': chapterName,
      if (excerpt != null) 'excerpt': excerpt,
      if (unresolved != null) 'unresolved': unresolved,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  NovelBookmarkEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? bookId,
    Value<String>? sourceKey,
    Value<String>? bookTitle,
    Value<String>? bookAuthor,
    Value<String>? bookUrl,
    Value<int>? chapterIndex,
    Value<int>? paragraph,
    Value<int>? charOffset,
    Value<String>? chapterName,
    Value<String>? excerpt,
    Value<bool>? unresolved,
    Value<DateTime>? createdAt,
  }) {
    return NovelBookmarkEntriesCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      sourceKey: sourceKey ?? this.sourceKey,
      bookTitle: bookTitle ?? this.bookTitle,
      bookAuthor: bookAuthor ?? this.bookAuthor,
      bookUrl: bookUrl ?? this.bookUrl,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      paragraph: paragraph ?? this.paragraph,
      charOffset: charOffset ?? this.charOffset,
      chapterName: chapterName ?? this.chapterName,
      excerpt: excerpt ?? this.excerpt,
      unresolved: unresolved ?? this.unresolved,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (sourceKey.present) {
      map['source_key'] = Variable<String>(sourceKey.value);
    }
    if (bookTitle.present) {
      map['book_title'] = Variable<String>(bookTitle.value);
    }
    if (bookAuthor.present) {
      map['book_author'] = Variable<String>(bookAuthor.value);
    }
    if (bookUrl.present) {
      map['book_url'] = Variable<String>(bookUrl.value);
    }
    if (chapterIndex.present) {
      map['chapter_index'] = Variable<int>(chapterIndex.value);
    }
    if (paragraph.present) {
      map['paragraph'] = Variable<int>(paragraph.value);
    }
    if (charOffset.present) {
      map['char_offset'] = Variable<int>(charOffset.value);
    }
    if (chapterName.present) {
      map['chapter_name'] = Variable<String>(chapterName.value);
    }
    if (excerpt.present) {
      map['excerpt'] = Variable<String>(excerpt.value);
    }
    if (unresolved.present) {
      map['unresolved'] = Variable<bool>(unresolved.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NovelBookmarkEntriesCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('sourceKey: $sourceKey, ')
          ..write('bookTitle: $bookTitle, ')
          ..write('bookAuthor: $bookAuthor, ')
          ..write('bookUrl: $bookUrl, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('paragraph: $paragraph, ')
          ..write('charOffset: $charOffset, ')
          ..write('chapterName: $chapterName, ')
          ..write('excerpt: $excerpt, ')
          ..write('unresolved: $unresolved, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $NovelMarkingEntriesTable extends NovelMarkingEntries
    with TableInfo<$NovelMarkingEntriesTable, NovelMarkingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NovelMarkingEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceKeyMeta = const VerificationMeta(
    'sourceKey',
  );
  @override
  late final GeneratedColumn<String> sourceKey = GeneratedColumn<String>(
    'source_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _bookTitleMeta = const VerificationMeta(
    'bookTitle',
  );
  @override
  late final GeneratedColumn<String> bookTitle = GeneratedColumn<String>(
    'book_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _bookAuthorMeta = const VerificationMeta(
    'bookAuthor',
  );
  @override
  late final GeneratedColumn<String> bookAuthor = GeneratedColumn<String>(
    'book_author',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _bookUrlMeta = const VerificationMeta(
    'bookUrl',
  );
  @override
  late final GeneratedColumn<String> bookUrl = GeneratedColumn<String>(
    'book_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paragraphMeta = const VerificationMeta(
    'paragraph',
  );
  @override
  late final GeneratedColumn<int> paragraph = GeneratedColumn<int>(
    'paragraph',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _startOffsetMeta = const VerificationMeta(
    'startOffset',
  );
  @override
  late final GeneratedColumn<int> startOffset = GeneratedColumn<int>(
    'start_offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _endOffsetMeta = const VerificationMeta(
    'endOffset',
  );
  @override
  late final GeneratedColumn<int> endOffset = GeneratedColumn<int>(
    'end_offset',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _chapterNameMeta = const VerificationMeta(
    'chapterName',
  );
  @override
  late final GeneratedColumn<String> chapterName = GeneratedColumn<String>(
    'chapter_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _styleJsonMeta = const VerificationMeta(
    'styleJson',
  );
  @override
  late final GeneratedColumn<String> styleJson = GeneratedColumn<String>(
    'style_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _unresolvedMeta = const VerificationMeta(
    'unresolved',
  );
  @override
  late final GeneratedColumn<bool> unresolved = GeneratedColumn<bool>(
    'unresolved',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("unresolved" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
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
    id,
    bookId,
    sourceKey,
    bookTitle,
    bookAuthor,
    bookUrl,
    chapterIndex,
    paragraph,
    startOffset,
    endOffset,
    chapterName,
    styleJson,
    note,
    unresolved,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'marking';
  @override
  VerificationContext validateIntegrity(
    Insertable<NovelMarkingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('source_key')) {
      context.handle(
        _sourceKeyMeta,
        sourceKey.isAcceptableOrUnknown(data['source_key']!, _sourceKeyMeta),
      );
    }
    if (data.containsKey('book_title')) {
      context.handle(
        _bookTitleMeta,
        bookTitle.isAcceptableOrUnknown(data['book_title']!, _bookTitleMeta),
      );
    }
    if (data.containsKey('book_author')) {
      context.handle(
        _bookAuthorMeta,
        bookAuthor.isAcceptableOrUnknown(data['book_author']!, _bookAuthorMeta),
      );
    }
    if (data.containsKey('book_url')) {
      context.handle(
        _bookUrlMeta,
        bookUrl.isAcceptableOrUnknown(data['book_url']!, _bookUrlMeta),
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
    } else if (isInserting) {
      context.missing(_chapterIndexMeta);
    }
    if (data.containsKey('paragraph')) {
      context.handle(
        _paragraphMeta,
        paragraph.isAcceptableOrUnknown(data['paragraph']!, _paragraphMeta),
      );
    }
    if (data.containsKey('start_offset')) {
      context.handle(
        _startOffsetMeta,
        startOffset.isAcceptableOrUnknown(
          data['start_offset']!,
          _startOffsetMeta,
        ),
      );
    }
    if (data.containsKey('end_offset')) {
      context.handle(
        _endOffsetMeta,
        endOffset.isAcceptableOrUnknown(data['end_offset']!, _endOffsetMeta),
      );
    }
    if (data.containsKey('chapter_name')) {
      context.handle(
        _chapterNameMeta,
        chapterName.isAcceptableOrUnknown(
          data['chapter_name']!,
          _chapterNameMeta,
        ),
      );
    }
    if (data.containsKey('style_json')) {
      context.handle(
        _styleJsonMeta,
        styleJson.isAcceptableOrUnknown(data['style_json']!, _styleJsonMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('unresolved')) {
      context.handle(
        _unresolvedMeta,
        unresolved.isAcceptableOrUnknown(data['unresolved']!, _unresolvedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NovelMarkingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NovelMarkingRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      sourceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_key'],
      )!,
      bookTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_title'],
      )!,
      bookAuthor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_author'],
      )!,
      bookUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_url'],
      )!,
      chapterIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_index'],
      )!,
      paragraph: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}paragraph'],
      )!,
      startOffset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_offset'],
      )!,
      endOffset: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_offset'],
      )!,
      chapterName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_name'],
      )!,
      styleJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}style_json'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      unresolved: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}unresolved'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $NovelMarkingEntriesTable createAlias(String alias) {
    return $NovelMarkingEntriesTable(attachedDatabase, alias);
  }
}

class NovelMarkingRow extends DataClass implements Insertable<NovelMarkingRow> {
  final int id;
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

  /// `{"color": <argb>, "decoration": "background|underline|wavy"}`。
  final String styleJson;
  final String note;
  final bool unresolved;
  final DateTime createdAt;
  final DateTime updatedAt;
  const NovelMarkingRow({
    required this.id,
    required this.bookId,
    required this.sourceKey,
    required this.bookTitle,
    required this.bookAuthor,
    required this.bookUrl,
    required this.chapterIndex,
    required this.paragraph,
    required this.startOffset,
    required this.endOffset,
    required this.chapterName,
    required this.styleJson,
    required this.note,
    required this.unresolved,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['book_id'] = Variable<String>(bookId);
    map['source_key'] = Variable<String>(sourceKey);
    map['book_title'] = Variable<String>(bookTitle);
    map['book_author'] = Variable<String>(bookAuthor);
    map['book_url'] = Variable<String>(bookUrl);
    map['chapter_index'] = Variable<int>(chapterIndex);
    map['paragraph'] = Variable<int>(paragraph);
    map['start_offset'] = Variable<int>(startOffset);
    map['end_offset'] = Variable<int>(endOffset);
    map['chapter_name'] = Variable<String>(chapterName);
    map['style_json'] = Variable<String>(styleJson);
    map['note'] = Variable<String>(note);
    map['unresolved'] = Variable<bool>(unresolved);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  NovelMarkingEntriesCompanion toCompanion(bool nullToAbsent) {
    return NovelMarkingEntriesCompanion(
      id: Value(id),
      bookId: Value(bookId),
      sourceKey: Value(sourceKey),
      bookTitle: Value(bookTitle),
      bookAuthor: Value(bookAuthor),
      bookUrl: Value(bookUrl),
      chapterIndex: Value(chapterIndex),
      paragraph: Value(paragraph),
      startOffset: Value(startOffset),
      endOffset: Value(endOffset),
      chapterName: Value(chapterName),
      styleJson: Value(styleJson),
      note: Value(note),
      unresolved: Value(unresolved),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory NovelMarkingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NovelMarkingRow(
      id: serializer.fromJson<int>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      sourceKey: serializer.fromJson<String>(json['sourceKey']),
      bookTitle: serializer.fromJson<String>(json['bookTitle']),
      bookAuthor: serializer.fromJson<String>(json['bookAuthor']),
      bookUrl: serializer.fromJson<String>(json['bookUrl']),
      chapterIndex: serializer.fromJson<int>(json['chapterIndex']),
      paragraph: serializer.fromJson<int>(json['paragraph']),
      startOffset: serializer.fromJson<int>(json['startOffset']),
      endOffset: serializer.fromJson<int>(json['endOffset']),
      chapterName: serializer.fromJson<String>(json['chapterName']),
      styleJson: serializer.fromJson<String>(json['styleJson']),
      note: serializer.fromJson<String>(json['note']),
      unresolved: serializer.fromJson<bool>(json['unresolved']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bookId': serializer.toJson<String>(bookId),
      'sourceKey': serializer.toJson<String>(sourceKey),
      'bookTitle': serializer.toJson<String>(bookTitle),
      'bookAuthor': serializer.toJson<String>(bookAuthor),
      'bookUrl': serializer.toJson<String>(bookUrl),
      'chapterIndex': serializer.toJson<int>(chapterIndex),
      'paragraph': serializer.toJson<int>(paragraph),
      'startOffset': serializer.toJson<int>(startOffset),
      'endOffset': serializer.toJson<int>(endOffset),
      'chapterName': serializer.toJson<String>(chapterName),
      'styleJson': serializer.toJson<String>(styleJson),
      'note': serializer.toJson<String>(note),
      'unresolved': serializer.toJson<bool>(unresolved),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  NovelMarkingRow copyWith({
    int? id,
    String? bookId,
    String? sourceKey,
    String? bookTitle,
    String? bookAuthor,
    String? bookUrl,
    int? chapterIndex,
    int? paragraph,
    int? startOffset,
    int? endOffset,
    String? chapterName,
    String? styleJson,
    String? note,
    bool? unresolved,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => NovelMarkingRow(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    sourceKey: sourceKey ?? this.sourceKey,
    bookTitle: bookTitle ?? this.bookTitle,
    bookAuthor: bookAuthor ?? this.bookAuthor,
    bookUrl: bookUrl ?? this.bookUrl,
    chapterIndex: chapterIndex ?? this.chapterIndex,
    paragraph: paragraph ?? this.paragraph,
    startOffset: startOffset ?? this.startOffset,
    endOffset: endOffset ?? this.endOffset,
    chapterName: chapterName ?? this.chapterName,
    styleJson: styleJson ?? this.styleJson,
    note: note ?? this.note,
    unresolved: unresolved ?? this.unresolved,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  NovelMarkingRow copyWithCompanion(NovelMarkingEntriesCompanion data) {
    return NovelMarkingRow(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      sourceKey: data.sourceKey.present ? data.sourceKey.value : this.sourceKey,
      bookTitle: data.bookTitle.present ? data.bookTitle.value : this.bookTitle,
      bookAuthor: data.bookAuthor.present
          ? data.bookAuthor.value
          : this.bookAuthor,
      bookUrl: data.bookUrl.present ? data.bookUrl.value : this.bookUrl,
      chapterIndex: data.chapterIndex.present
          ? data.chapterIndex.value
          : this.chapterIndex,
      paragraph: data.paragraph.present ? data.paragraph.value : this.paragraph,
      startOffset: data.startOffset.present
          ? data.startOffset.value
          : this.startOffset,
      endOffset: data.endOffset.present ? data.endOffset.value : this.endOffset,
      chapterName: data.chapterName.present
          ? data.chapterName.value
          : this.chapterName,
      styleJson: data.styleJson.present ? data.styleJson.value : this.styleJson,
      note: data.note.present ? data.note.value : this.note,
      unresolved: data.unresolved.present
          ? data.unresolved.value
          : this.unresolved,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NovelMarkingRow(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('sourceKey: $sourceKey, ')
          ..write('bookTitle: $bookTitle, ')
          ..write('bookAuthor: $bookAuthor, ')
          ..write('bookUrl: $bookUrl, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('paragraph: $paragraph, ')
          ..write('startOffset: $startOffset, ')
          ..write('endOffset: $endOffset, ')
          ..write('chapterName: $chapterName, ')
          ..write('styleJson: $styleJson, ')
          ..write('note: $note, ')
          ..write('unresolved: $unresolved, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    sourceKey,
    bookTitle,
    bookAuthor,
    bookUrl,
    chapterIndex,
    paragraph,
    startOffset,
    endOffset,
    chapterName,
    styleJson,
    note,
    unresolved,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelMarkingRow &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.sourceKey == this.sourceKey &&
          other.bookTitle == this.bookTitle &&
          other.bookAuthor == this.bookAuthor &&
          other.bookUrl == this.bookUrl &&
          other.chapterIndex == this.chapterIndex &&
          other.paragraph == this.paragraph &&
          other.startOffset == this.startOffset &&
          other.endOffset == this.endOffset &&
          other.chapterName == this.chapterName &&
          other.styleJson == this.styleJson &&
          other.note == this.note &&
          other.unresolved == this.unresolved &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class NovelMarkingEntriesCompanion extends UpdateCompanion<NovelMarkingRow> {
  final Value<int> id;
  final Value<String> bookId;
  final Value<String> sourceKey;
  final Value<String> bookTitle;
  final Value<String> bookAuthor;
  final Value<String> bookUrl;
  final Value<int> chapterIndex;
  final Value<int> paragraph;
  final Value<int> startOffset;
  final Value<int> endOffset;
  final Value<String> chapterName;
  final Value<String> styleJson;
  final Value<String> note;
  final Value<bool> unresolved;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const NovelMarkingEntriesCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.sourceKey = const Value.absent(),
    this.bookTitle = const Value.absent(),
    this.bookAuthor = const Value.absent(),
    this.bookUrl = const Value.absent(),
    this.chapterIndex = const Value.absent(),
    this.paragraph = const Value.absent(),
    this.startOffset = const Value.absent(),
    this.endOffset = const Value.absent(),
    this.chapterName = const Value.absent(),
    this.styleJson = const Value.absent(),
    this.note = const Value.absent(),
    this.unresolved = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  NovelMarkingEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String bookId,
    this.sourceKey = const Value.absent(),
    this.bookTitle = const Value.absent(),
    this.bookAuthor = const Value.absent(),
    this.bookUrl = const Value.absent(),
    required int chapterIndex,
    this.paragraph = const Value.absent(),
    this.startOffset = const Value.absent(),
    this.endOffset = const Value.absent(),
    this.chapterName = const Value.absent(),
    this.styleJson = const Value.absent(),
    this.note = const Value.absent(),
    this.unresolved = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : bookId = Value(bookId),
       chapterIndex = Value(chapterIndex),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<NovelMarkingRow> custom({
    Expression<int>? id,
    Expression<String>? bookId,
    Expression<String>? sourceKey,
    Expression<String>? bookTitle,
    Expression<String>? bookAuthor,
    Expression<String>? bookUrl,
    Expression<int>? chapterIndex,
    Expression<int>? paragraph,
    Expression<int>? startOffset,
    Expression<int>? endOffset,
    Expression<String>? chapterName,
    Expression<String>? styleJson,
    Expression<String>? note,
    Expression<bool>? unresolved,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (sourceKey != null) 'source_key': sourceKey,
      if (bookTitle != null) 'book_title': bookTitle,
      if (bookAuthor != null) 'book_author': bookAuthor,
      if (bookUrl != null) 'book_url': bookUrl,
      if (chapterIndex != null) 'chapter_index': chapterIndex,
      if (paragraph != null) 'paragraph': paragraph,
      if (startOffset != null) 'start_offset': startOffset,
      if (endOffset != null) 'end_offset': endOffset,
      if (chapterName != null) 'chapter_name': chapterName,
      if (styleJson != null) 'style_json': styleJson,
      if (note != null) 'note': note,
      if (unresolved != null) 'unresolved': unresolved,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  NovelMarkingEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? bookId,
    Value<String>? sourceKey,
    Value<String>? bookTitle,
    Value<String>? bookAuthor,
    Value<String>? bookUrl,
    Value<int>? chapterIndex,
    Value<int>? paragraph,
    Value<int>? startOffset,
    Value<int>? endOffset,
    Value<String>? chapterName,
    Value<String>? styleJson,
    Value<String>? note,
    Value<bool>? unresolved,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return NovelMarkingEntriesCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      sourceKey: sourceKey ?? this.sourceKey,
      bookTitle: bookTitle ?? this.bookTitle,
      bookAuthor: bookAuthor ?? this.bookAuthor,
      bookUrl: bookUrl ?? this.bookUrl,
      chapterIndex: chapterIndex ?? this.chapterIndex,
      paragraph: paragraph ?? this.paragraph,
      startOffset: startOffset ?? this.startOffset,
      endOffset: endOffset ?? this.endOffset,
      chapterName: chapterName ?? this.chapterName,
      styleJson: styleJson ?? this.styleJson,
      note: note ?? this.note,
      unresolved: unresolved ?? this.unresolved,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (sourceKey.present) {
      map['source_key'] = Variable<String>(sourceKey.value);
    }
    if (bookTitle.present) {
      map['book_title'] = Variable<String>(bookTitle.value);
    }
    if (bookAuthor.present) {
      map['book_author'] = Variable<String>(bookAuthor.value);
    }
    if (bookUrl.present) {
      map['book_url'] = Variable<String>(bookUrl.value);
    }
    if (chapterIndex.present) {
      map['chapter_index'] = Variable<int>(chapterIndex.value);
    }
    if (paragraph.present) {
      map['paragraph'] = Variable<int>(paragraph.value);
    }
    if (startOffset.present) {
      map['start_offset'] = Variable<int>(startOffset.value);
    }
    if (endOffset.present) {
      map['end_offset'] = Variable<int>(endOffset.value);
    }
    if (chapterName.present) {
      map['chapter_name'] = Variable<String>(chapterName.value);
    }
    if (styleJson.present) {
      map['style_json'] = Variable<String>(styleJson.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (unresolved.present) {
      map['unresolved'] = Variable<bool>(unresolved.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NovelMarkingEntriesCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('sourceKey: $sourceKey, ')
          ..write('bookTitle: $bookTitle, ')
          ..write('bookAuthor: $bookAuthor, ')
          ..write('bookUrl: $bookUrl, ')
          ..write('chapterIndex: $chapterIndex, ')
          ..write('paragraph: $paragraph, ')
          ..write('startOffset: $startOffset, ')
          ..write('endOffset: $endOffset, ')
          ..write('chapterName: $chapterName, ')
          ..write('styleJson: $styleJson, ')
          ..write('note: $note, ')
          ..write('unresolved: $unresolved, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $NovelHighlightRulesTable extends NovelHighlightRules
    with TableInfo<$NovelHighlightRulesTable, NovelHighlightRuleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NovelHighlightRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _patternMeta = const VerificationMeta(
    'pattern',
  );
  @override
  late final GeneratedColumn<String> pattern = GeneratedColumn<String>(
    'pattern',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _foregroundLightMeta = const VerificationMeta(
    'foregroundLight',
  );
  @override
  late final GeneratedColumn<int> foregroundLight = GeneratedColumn<int>(
    'foreground_light',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _backgroundLightMeta = const VerificationMeta(
    'backgroundLight',
  );
  @override
  late final GeneratedColumn<int> backgroundLight = GeneratedColumn<int>(
    'background_light',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _foregroundDarkMeta = const VerificationMeta(
    'foregroundDark',
  );
  @override
  late final GeneratedColumn<int> foregroundDark = GeneratedColumn<int>(
    'foreground_dark',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _backgroundDarkMeta = const VerificationMeta(
    'backgroundDark',
  );
  @override
  late final GeneratedColumn<int> backgroundDark = GeneratedColumn<int>(
    'background_dark',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _underlineMeta = const VerificationMeta(
    'underline',
  );
  @override
  late final GeneratedColumn<bool> underline = GeneratedColumn<bool>(
    'underline',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("underline" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _boldMeta = const VerificationMeta('bold');
  @override
  late final GeneratedColumn<bool> bold = GeneratedColumn<bool>(
    'bold',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("bold" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _rawMeta = const VerificationMeta('raw');
  @override
  late final GeneratedColumn<String> raw = GeneratedColumn<String>(
    'raw',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
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
    id,
    bookId,
    name,
    pattern,
    foregroundLight,
    backgroundLight,
    foregroundDark,
    backgroundDark,
    underline,
    bold,
    enabled,
    raw,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'novel_highlight_rule';
  @override
  VerificationContext validateIntegrity(
    Insertable<NovelHighlightRuleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    }
    if (data.containsKey('pattern')) {
      context.handle(
        _patternMeta,
        pattern.isAcceptableOrUnknown(data['pattern']!, _patternMeta),
      );
    } else if (isInserting) {
      context.missing(_patternMeta);
    }
    if (data.containsKey('foreground_light')) {
      context.handle(
        _foregroundLightMeta,
        foregroundLight.isAcceptableOrUnknown(
          data['foreground_light']!,
          _foregroundLightMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_foregroundLightMeta);
    }
    if (data.containsKey('background_light')) {
      context.handle(
        _backgroundLightMeta,
        backgroundLight.isAcceptableOrUnknown(
          data['background_light']!,
          _backgroundLightMeta,
        ),
      );
    }
    if (data.containsKey('foreground_dark')) {
      context.handle(
        _foregroundDarkMeta,
        foregroundDark.isAcceptableOrUnknown(
          data['foreground_dark']!,
          _foregroundDarkMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_foregroundDarkMeta);
    }
    if (data.containsKey('background_dark')) {
      context.handle(
        _backgroundDarkMeta,
        backgroundDark.isAcceptableOrUnknown(
          data['background_dark']!,
          _backgroundDarkMeta,
        ),
      );
    }
    if (data.containsKey('underline')) {
      context.handle(
        _underlineMeta,
        underline.isAcceptableOrUnknown(data['underline']!, _underlineMeta),
      );
    }
    if (data.containsKey('bold')) {
      context.handle(
        _boldMeta,
        bold.isAcceptableOrUnknown(data['bold']!, _boldMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('raw')) {
      context.handle(
        _rawMeta,
        raw.isAcceptableOrUnknown(data['raw']!, _rawMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NovelHighlightRuleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NovelHighlightRuleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      pattern: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pattern'],
      )!,
      foregroundLight: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}foreground_light'],
      )!,
      backgroundLight: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}background_light'],
      ),
      foregroundDark: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}foreground_dark'],
      )!,
      backgroundDark: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}background_dark'],
      ),
      underline: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}underline'],
      )!,
      bold: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}bold'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      raw: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $NovelHighlightRulesTable createAlias(String alias) {
    return $NovelHighlightRulesTable(attachedDatabase, alias);
  }
}

class NovelHighlightRuleRow extends DataClass
    implements Insertable<NovelHighlightRuleRow> {
  final int id;

  /// 空串 = 全局；非空只对该 bookId 生效。
  final String bookId;
  final String name;

  /// 正则表达式（高亮只支持正则）。
  final String pattern;
  final int foregroundLight;
  final int? backgroundLight;
  final int foregroundDark;
  final int? backgroundDark;
  final bool underline;
  final bool bold;
  final bool enabled;

  /// 导入时的原始 JSON（手工新建为 `{}`）。
  final String raw;
  final DateTime createdAt;
  final DateTime updatedAt;
  const NovelHighlightRuleRow({
    required this.id,
    required this.bookId,
    required this.name,
    required this.pattern,
    required this.foregroundLight,
    this.backgroundLight,
    required this.foregroundDark,
    this.backgroundDark,
    required this.underline,
    required this.bold,
    required this.enabled,
    required this.raw,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['book_id'] = Variable<String>(bookId);
    map['name'] = Variable<String>(name);
    map['pattern'] = Variable<String>(pattern);
    map['foreground_light'] = Variable<int>(foregroundLight);
    if (!nullToAbsent || backgroundLight != null) {
      map['background_light'] = Variable<int>(backgroundLight);
    }
    map['foreground_dark'] = Variable<int>(foregroundDark);
    if (!nullToAbsent || backgroundDark != null) {
      map['background_dark'] = Variable<int>(backgroundDark);
    }
    map['underline'] = Variable<bool>(underline);
    map['bold'] = Variable<bool>(bold);
    map['enabled'] = Variable<bool>(enabled);
    map['raw'] = Variable<String>(raw);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  NovelHighlightRulesCompanion toCompanion(bool nullToAbsent) {
    return NovelHighlightRulesCompanion(
      id: Value(id),
      bookId: Value(bookId),
      name: Value(name),
      pattern: Value(pattern),
      foregroundLight: Value(foregroundLight),
      backgroundLight: backgroundLight == null && nullToAbsent
          ? const Value.absent()
          : Value(backgroundLight),
      foregroundDark: Value(foregroundDark),
      backgroundDark: backgroundDark == null && nullToAbsent
          ? const Value.absent()
          : Value(backgroundDark),
      underline: Value(underline),
      bold: Value(bold),
      enabled: Value(enabled),
      raw: Value(raw),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory NovelHighlightRuleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NovelHighlightRuleRow(
      id: serializer.fromJson<int>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      name: serializer.fromJson<String>(json['name']),
      pattern: serializer.fromJson<String>(json['pattern']),
      foregroundLight: serializer.fromJson<int>(json['foregroundLight']),
      backgroundLight: serializer.fromJson<int?>(json['backgroundLight']),
      foregroundDark: serializer.fromJson<int>(json['foregroundDark']),
      backgroundDark: serializer.fromJson<int?>(json['backgroundDark']),
      underline: serializer.fromJson<bool>(json['underline']),
      bold: serializer.fromJson<bool>(json['bold']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      raw: serializer.fromJson<String>(json['raw']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'bookId': serializer.toJson<String>(bookId),
      'name': serializer.toJson<String>(name),
      'pattern': serializer.toJson<String>(pattern),
      'foregroundLight': serializer.toJson<int>(foregroundLight),
      'backgroundLight': serializer.toJson<int?>(backgroundLight),
      'foregroundDark': serializer.toJson<int>(foregroundDark),
      'backgroundDark': serializer.toJson<int?>(backgroundDark),
      'underline': serializer.toJson<bool>(underline),
      'bold': serializer.toJson<bool>(bold),
      'enabled': serializer.toJson<bool>(enabled),
      'raw': serializer.toJson<String>(raw),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  NovelHighlightRuleRow copyWith({
    int? id,
    String? bookId,
    String? name,
    String? pattern,
    int? foregroundLight,
    Value<int?> backgroundLight = const Value.absent(),
    int? foregroundDark,
    Value<int?> backgroundDark = const Value.absent(),
    bool? underline,
    bool? bold,
    bool? enabled,
    String? raw,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => NovelHighlightRuleRow(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    name: name ?? this.name,
    pattern: pattern ?? this.pattern,
    foregroundLight: foregroundLight ?? this.foregroundLight,
    backgroundLight: backgroundLight.present
        ? backgroundLight.value
        : this.backgroundLight,
    foregroundDark: foregroundDark ?? this.foregroundDark,
    backgroundDark: backgroundDark.present
        ? backgroundDark.value
        : this.backgroundDark,
    underline: underline ?? this.underline,
    bold: bold ?? this.bold,
    enabled: enabled ?? this.enabled,
    raw: raw ?? this.raw,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  NovelHighlightRuleRow copyWithCompanion(NovelHighlightRulesCompanion data) {
    return NovelHighlightRuleRow(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      name: data.name.present ? data.name.value : this.name,
      pattern: data.pattern.present ? data.pattern.value : this.pattern,
      foregroundLight: data.foregroundLight.present
          ? data.foregroundLight.value
          : this.foregroundLight,
      backgroundLight: data.backgroundLight.present
          ? data.backgroundLight.value
          : this.backgroundLight,
      foregroundDark: data.foregroundDark.present
          ? data.foregroundDark.value
          : this.foregroundDark,
      backgroundDark: data.backgroundDark.present
          ? data.backgroundDark.value
          : this.backgroundDark,
      underline: data.underline.present ? data.underline.value : this.underline,
      bold: data.bold.present ? data.bold.value : this.bold,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      raw: data.raw.present ? data.raw.value : this.raw,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NovelHighlightRuleRow(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('name: $name, ')
          ..write('pattern: $pattern, ')
          ..write('foregroundLight: $foregroundLight, ')
          ..write('backgroundLight: $backgroundLight, ')
          ..write('foregroundDark: $foregroundDark, ')
          ..write('backgroundDark: $backgroundDark, ')
          ..write('underline: $underline, ')
          ..write('bold: $bold, ')
          ..write('enabled: $enabled, ')
          ..write('raw: $raw, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    name,
    pattern,
    foregroundLight,
    backgroundLight,
    foregroundDark,
    backgroundDark,
    underline,
    bold,
    enabled,
    raw,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelHighlightRuleRow &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.name == this.name &&
          other.pattern == this.pattern &&
          other.foregroundLight == this.foregroundLight &&
          other.backgroundLight == this.backgroundLight &&
          other.foregroundDark == this.foregroundDark &&
          other.backgroundDark == this.backgroundDark &&
          other.underline == this.underline &&
          other.bold == this.bold &&
          other.enabled == this.enabled &&
          other.raw == this.raw &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class NovelHighlightRulesCompanion
    extends UpdateCompanion<NovelHighlightRuleRow> {
  final Value<int> id;
  final Value<String> bookId;
  final Value<String> name;
  final Value<String> pattern;
  final Value<int> foregroundLight;
  final Value<int?> backgroundLight;
  final Value<int> foregroundDark;
  final Value<int?> backgroundDark;
  final Value<bool> underline;
  final Value<bool> bold;
  final Value<bool> enabled;
  final Value<String> raw;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const NovelHighlightRulesCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.name = const Value.absent(),
    this.pattern = const Value.absent(),
    this.foregroundLight = const Value.absent(),
    this.backgroundLight = const Value.absent(),
    this.foregroundDark = const Value.absent(),
    this.backgroundDark = const Value.absent(),
    this.underline = const Value.absent(),
    this.bold = const Value.absent(),
    this.enabled = const Value.absent(),
    this.raw = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  NovelHighlightRulesCompanion.insert({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.name = const Value.absent(),
    required String pattern,
    required int foregroundLight,
    this.backgroundLight = const Value.absent(),
    required int foregroundDark,
    this.backgroundDark = const Value.absent(),
    this.underline = const Value.absent(),
    this.bold = const Value.absent(),
    this.enabled = const Value.absent(),
    this.raw = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : pattern = Value(pattern),
       foregroundLight = Value(foregroundLight),
       foregroundDark = Value(foregroundDark),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<NovelHighlightRuleRow> custom({
    Expression<int>? id,
    Expression<String>? bookId,
    Expression<String>? name,
    Expression<String>? pattern,
    Expression<int>? foregroundLight,
    Expression<int>? backgroundLight,
    Expression<int>? foregroundDark,
    Expression<int>? backgroundDark,
    Expression<bool>? underline,
    Expression<bool>? bold,
    Expression<bool>? enabled,
    Expression<String>? raw,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (name != null) 'name': name,
      if (pattern != null) 'pattern': pattern,
      if (foregroundLight != null) 'foreground_light': foregroundLight,
      if (backgroundLight != null) 'background_light': backgroundLight,
      if (foregroundDark != null) 'foreground_dark': foregroundDark,
      if (backgroundDark != null) 'background_dark': backgroundDark,
      if (underline != null) 'underline': underline,
      if (bold != null) 'bold': bold,
      if (enabled != null) 'enabled': enabled,
      if (raw != null) 'raw': raw,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  NovelHighlightRulesCompanion copyWith({
    Value<int>? id,
    Value<String>? bookId,
    Value<String>? name,
    Value<String>? pattern,
    Value<int>? foregroundLight,
    Value<int?>? backgroundLight,
    Value<int>? foregroundDark,
    Value<int?>? backgroundDark,
    Value<bool>? underline,
    Value<bool>? bold,
    Value<bool>? enabled,
    Value<String>? raw,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return NovelHighlightRulesCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      name: name ?? this.name,
      pattern: pattern ?? this.pattern,
      foregroundLight: foregroundLight ?? this.foregroundLight,
      backgroundLight: backgroundLight ?? this.backgroundLight,
      foregroundDark: foregroundDark ?? this.foregroundDark,
      backgroundDark: backgroundDark ?? this.backgroundDark,
      underline: underline ?? this.underline,
      bold: bold ?? this.bold,
      enabled: enabled ?? this.enabled,
      raw: raw ?? this.raw,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (pattern.present) {
      map['pattern'] = Variable<String>(pattern.value);
    }
    if (foregroundLight.present) {
      map['foreground_light'] = Variable<int>(foregroundLight.value);
    }
    if (backgroundLight.present) {
      map['background_light'] = Variable<int>(backgroundLight.value);
    }
    if (foregroundDark.present) {
      map['foreground_dark'] = Variable<int>(foregroundDark.value);
    }
    if (backgroundDark.present) {
      map['background_dark'] = Variable<int>(backgroundDark.value);
    }
    if (underline.present) {
      map['underline'] = Variable<bool>(underline.value);
    }
    if (bold.present) {
      map['bold'] = Variable<bool>(bold.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (raw.present) {
      map['raw'] = Variable<String>(raw.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NovelHighlightRulesCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('name: $name, ')
          ..write('pattern: $pattern, ')
          ..write('foregroundLight: $foregroundLight, ')
          ..write('backgroundLight: $backgroundLight, ')
          ..write('foregroundDark: $foregroundDark, ')
          ..write('backgroundDark: $backgroundDark, ')
          ..write('underline: $underline, ')
          ..write('bold: $bold, ')
          ..write('enabled: $enabled, ')
          ..write('raw: $raw, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $NovelContentOverridesTable extends NovelContentOverrides
    with TableInfo<$NovelContentOverridesTable, NovelContentOverrideRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NovelContentOverridesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceKeyMeta = const VerificationMeta(
    'sourceKey',
  );
  @override
  late final GeneratedColumn<String> sourceKey = GeneratedColumn<String>(
    'source_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _chapterKeyMeta = const VerificationMeta(
    'chapterKey',
  );
  @override
  late final GeneratedColumn<String> chapterKey = GeneratedColumn<String>(
    'chapter_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chapterTitleMeta = const VerificationMeta(
    'chapterTitle',
  );
  @override
  late final GeneratedColumn<String> chapterTitle = GeneratedColumn<String>(
    'chapter_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _paragraphsJsonMeta = const VerificationMeta(
    'paragraphsJson',
  );
  @override
  late final GeneratedColumn<String> paragraphsJson = GeneratedColumn<String>(
    'paragraphs_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paragraphCountMeta = const VerificationMeta(
    'paragraphCount',
  );
  @override
  late final GeneratedColumn<int> paragraphCount = GeneratedColumn<int>(
    'paragraph_count',
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
  List<GeneratedColumn> get $columns => [
    bookId,
    sourceKey,
    chapterKey,
    chapterTitle,
    title,
    paragraphsJson,
    paragraphCount,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'novel_content_override';
  @override
  VerificationContext validateIntegrity(
    Insertable<NovelContentOverrideRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('source_key')) {
      context.handle(
        _sourceKeyMeta,
        sourceKey.isAcceptableOrUnknown(data['source_key']!, _sourceKeyMeta),
      );
    }
    if (data.containsKey('chapter_key')) {
      context.handle(
        _chapterKeyMeta,
        chapterKey.isAcceptableOrUnknown(data['chapter_key']!, _chapterKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_chapterKeyMeta);
    }
    if (data.containsKey('chapter_title')) {
      context.handle(
        _chapterTitleMeta,
        chapterTitle.isAcceptableOrUnknown(
          data['chapter_title']!,
          _chapterTitleMeta,
        ),
      );
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('paragraphs_json')) {
      context.handle(
        _paragraphsJsonMeta,
        paragraphsJson.isAcceptableOrUnknown(
          data['paragraphs_json']!,
          _paragraphsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_paragraphsJsonMeta);
    }
    if (data.containsKey('paragraph_count')) {
      context.handle(
        _paragraphCountMeta,
        paragraphCount.isAcceptableOrUnknown(
          data['paragraph_count']!,
          _paragraphCountMeta,
        ),
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
  Set<GeneratedColumn> get $primaryKey => {bookId, sourceKey, chapterKey};
  @override
  NovelContentOverrideRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NovelContentOverrideRow(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      sourceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_key'],
      )!,
      chapterKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_key'],
      )!,
      chapterTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}chapter_title'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      paragraphsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}paragraphs_json'],
      )!,
      paragraphCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}paragraph_count'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $NovelContentOverridesTable createAlias(String alias) {
    return $NovelContentOverridesTable(attachedDatabase, alias);
  }
}

class NovelContentOverrideRow extends DataClass
    implements Insertable<NovelContentOverrideRow> {
  final String bookId;
  final String sourceKey;
  final String chapterKey;
  final String chapterTitle;

  /// 编辑后的章节标题；空串表示沿用原章节标题。
  final String title;

  /// 正文段落 JSON 数组（`["第一段", "第二段"]`）。
  final String paragraphsJson;
  final int paragraphCount;
  final DateTime updatedAt;
  const NovelContentOverrideRow({
    required this.bookId,
    required this.sourceKey,
    required this.chapterKey,
    required this.chapterTitle,
    required this.title,
    required this.paragraphsJson,
    required this.paragraphCount,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['source_key'] = Variable<String>(sourceKey);
    map['chapter_key'] = Variable<String>(chapterKey);
    map['chapter_title'] = Variable<String>(chapterTitle);
    map['title'] = Variable<String>(title);
    map['paragraphs_json'] = Variable<String>(paragraphsJson);
    map['paragraph_count'] = Variable<int>(paragraphCount);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  NovelContentOverridesCompanion toCompanion(bool nullToAbsent) {
    return NovelContentOverridesCompanion(
      bookId: Value(bookId),
      sourceKey: Value(sourceKey),
      chapterKey: Value(chapterKey),
      chapterTitle: Value(chapterTitle),
      title: Value(title),
      paragraphsJson: Value(paragraphsJson),
      paragraphCount: Value(paragraphCount),
      updatedAt: Value(updatedAt),
    );
  }

  factory NovelContentOverrideRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NovelContentOverrideRow(
      bookId: serializer.fromJson<String>(json['bookId']),
      sourceKey: serializer.fromJson<String>(json['sourceKey']),
      chapterKey: serializer.fromJson<String>(json['chapterKey']),
      chapterTitle: serializer.fromJson<String>(json['chapterTitle']),
      title: serializer.fromJson<String>(json['title']),
      paragraphsJson: serializer.fromJson<String>(json['paragraphsJson']),
      paragraphCount: serializer.fromJson<int>(json['paragraphCount']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'sourceKey': serializer.toJson<String>(sourceKey),
      'chapterKey': serializer.toJson<String>(chapterKey),
      'chapterTitle': serializer.toJson<String>(chapterTitle),
      'title': serializer.toJson<String>(title),
      'paragraphsJson': serializer.toJson<String>(paragraphsJson),
      'paragraphCount': serializer.toJson<int>(paragraphCount),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  NovelContentOverrideRow copyWith({
    String? bookId,
    String? sourceKey,
    String? chapterKey,
    String? chapterTitle,
    String? title,
    String? paragraphsJson,
    int? paragraphCount,
    DateTime? updatedAt,
  }) => NovelContentOverrideRow(
    bookId: bookId ?? this.bookId,
    sourceKey: sourceKey ?? this.sourceKey,
    chapterKey: chapterKey ?? this.chapterKey,
    chapterTitle: chapterTitle ?? this.chapterTitle,
    title: title ?? this.title,
    paragraphsJson: paragraphsJson ?? this.paragraphsJson,
    paragraphCount: paragraphCount ?? this.paragraphCount,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  NovelContentOverrideRow copyWithCompanion(
    NovelContentOverridesCompanion data,
  ) {
    return NovelContentOverrideRow(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      sourceKey: data.sourceKey.present ? data.sourceKey.value : this.sourceKey,
      chapterKey: data.chapterKey.present
          ? data.chapterKey.value
          : this.chapterKey,
      chapterTitle: data.chapterTitle.present
          ? data.chapterTitle.value
          : this.chapterTitle,
      title: data.title.present ? data.title.value : this.title,
      paragraphsJson: data.paragraphsJson.present
          ? data.paragraphsJson.value
          : this.paragraphsJson,
      paragraphCount: data.paragraphCount.present
          ? data.paragraphCount.value
          : this.paragraphCount,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NovelContentOverrideRow(')
          ..write('bookId: $bookId, ')
          ..write('sourceKey: $sourceKey, ')
          ..write('chapterKey: $chapterKey, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('title: $title, ')
          ..write('paragraphsJson: $paragraphsJson, ')
          ..write('paragraphCount: $paragraphCount, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    bookId,
    sourceKey,
    chapterKey,
    chapterTitle,
    title,
    paragraphsJson,
    paragraphCount,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelContentOverrideRow &&
          other.bookId == this.bookId &&
          other.sourceKey == this.sourceKey &&
          other.chapterKey == this.chapterKey &&
          other.chapterTitle == this.chapterTitle &&
          other.title == this.title &&
          other.paragraphsJson == this.paragraphsJson &&
          other.paragraphCount == this.paragraphCount &&
          other.updatedAt == this.updatedAt);
}

class NovelContentOverridesCompanion
    extends UpdateCompanion<NovelContentOverrideRow> {
  final Value<String> bookId;
  final Value<String> sourceKey;
  final Value<String> chapterKey;
  final Value<String> chapterTitle;
  final Value<String> title;
  final Value<String> paragraphsJson;
  final Value<int> paragraphCount;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const NovelContentOverridesCompanion({
    this.bookId = const Value.absent(),
    this.sourceKey = const Value.absent(),
    this.chapterKey = const Value.absent(),
    this.chapterTitle = const Value.absent(),
    this.title = const Value.absent(),
    this.paragraphsJson = const Value.absent(),
    this.paragraphCount = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NovelContentOverridesCompanion.insert({
    required String bookId,
    this.sourceKey = const Value.absent(),
    required String chapterKey,
    this.chapterTitle = const Value.absent(),
    this.title = const Value.absent(),
    required String paragraphsJson,
    this.paragraphCount = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       chapterKey = Value(chapterKey),
       paragraphsJson = Value(paragraphsJson),
       updatedAt = Value(updatedAt);
  static Insertable<NovelContentOverrideRow> custom({
    Expression<String>? bookId,
    Expression<String>? sourceKey,
    Expression<String>? chapterKey,
    Expression<String>? chapterTitle,
    Expression<String>? title,
    Expression<String>? paragraphsJson,
    Expression<int>? paragraphCount,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (sourceKey != null) 'source_key': sourceKey,
      if (chapterKey != null) 'chapter_key': chapterKey,
      if (chapterTitle != null) 'chapter_title': chapterTitle,
      if (title != null) 'title': title,
      if (paragraphsJson != null) 'paragraphs_json': paragraphsJson,
      if (paragraphCount != null) 'paragraph_count': paragraphCount,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NovelContentOverridesCompanion copyWith({
    Value<String>? bookId,
    Value<String>? sourceKey,
    Value<String>? chapterKey,
    Value<String>? chapterTitle,
    Value<String>? title,
    Value<String>? paragraphsJson,
    Value<int>? paragraphCount,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return NovelContentOverridesCompanion(
      bookId: bookId ?? this.bookId,
      sourceKey: sourceKey ?? this.sourceKey,
      chapterKey: chapterKey ?? this.chapterKey,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      title: title ?? this.title,
      paragraphsJson: paragraphsJson ?? this.paragraphsJson,
      paragraphCount: paragraphCount ?? this.paragraphCount,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (sourceKey.present) {
      map['source_key'] = Variable<String>(sourceKey.value);
    }
    if (chapterKey.present) {
      map['chapter_key'] = Variable<String>(chapterKey.value);
    }
    if (chapterTitle.present) {
      map['chapter_title'] = Variable<String>(chapterTitle.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (paragraphsJson.present) {
      map['paragraphs_json'] = Variable<String>(paragraphsJson.value);
    }
    if (paragraphCount.present) {
      map['paragraph_count'] = Variable<int>(paragraphCount.value);
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
    return (StringBuffer('NovelContentOverridesCompanion(')
          ..write('bookId: $bookId, ')
          ..write('sourceKey: $sourceKey, ')
          ..write('chapterKey: $chapterKey, ')
          ..write('chapterTitle: $chapterTitle, ')
          ..write('title: $title, ')
          ..write('paragraphsJson: $paragraphsJson, ')
          ..write('paragraphCount: $paragraphCount, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NovelTtsCacheEntriesTable extends NovelTtsCacheEntries
    with TableInfo<$NovelTtsCacheEntriesTable, NovelTtsCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NovelTtsCacheEntriesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<int> bytes = GeneratedColumn<int>(
    'bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
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
  List<GeneratedColumn> get $columns => [
    cacheKey,
    path,
    bytes,
    createdAt,
    lastUsedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'novel_tts_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<NovelTtsCacheRow> instance, {
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
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
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
  Set<GeneratedColumn> get $primaryKey => {cacheKey};
  @override
  NovelTtsCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NovelTtsCacheRow(
      cacheKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cache_key'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bytes'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used_at'],
      )!,
    );
  }

  @override
  $NovelTtsCacheEntriesTable createAlias(String alias) {
    return $NovelTtsCacheEntriesTable(attachedDatabase, alias);
  }
}

class NovelTtsCacheRow extends DataClass
    implements Insertable<NovelTtsCacheRow> {
  /// sha256(bookId|chapterKey|paragraph|voice|rate)。
  final String cacheKey;
  final String path;

  /// 文件字节数，用于容量统计。
  final int bytes;
  final DateTime createdAt;
  final DateTime lastUsedAt;
  const NovelTtsCacheRow({
    required this.cacheKey,
    required this.path,
    required this.bytes,
    required this.createdAt,
    required this.lastUsedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['cache_key'] = Variable<String>(cacheKey);
    map['path'] = Variable<String>(path);
    map['bytes'] = Variable<int>(bytes);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    return map;
  }

  NovelTtsCacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return NovelTtsCacheEntriesCompanion(
      cacheKey: Value(cacheKey),
      path: Value(path),
      bytes: Value(bytes),
      createdAt: Value(createdAt),
      lastUsedAt: Value(lastUsedAt),
    );
  }

  factory NovelTtsCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NovelTtsCacheRow(
      cacheKey: serializer.fromJson<String>(json['cacheKey']),
      path: serializer.fromJson<String>(json['path']),
      bytes: serializer.fromJson<int>(json['bytes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastUsedAt: serializer.fromJson<DateTime>(json['lastUsedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'cacheKey': serializer.toJson<String>(cacheKey),
      'path': serializer.toJson<String>(path),
      'bytes': serializer.toJson<int>(bytes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastUsedAt': serializer.toJson<DateTime>(lastUsedAt),
    };
  }

  NovelTtsCacheRow copyWith({
    String? cacheKey,
    String? path,
    int? bytes,
    DateTime? createdAt,
    DateTime? lastUsedAt,
  }) => NovelTtsCacheRow(
    cacheKey: cacheKey ?? this.cacheKey,
    path: path ?? this.path,
    bytes: bytes ?? this.bytes,
    createdAt: createdAt ?? this.createdAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );
  NovelTtsCacheRow copyWithCompanion(NovelTtsCacheEntriesCompanion data) {
    return NovelTtsCacheRow(
      cacheKey: data.cacheKey.present ? data.cacheKey.value : this.cacheKey,
      path: data.path.present ? data.path.value : this.path,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NovelTtsCacheRow(')
          ..write('cacheKey: $cacheKey, ')
          ..write('path: $path, ')
          ..write('bytes: $bytes, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastUsedAt: $lastUsedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(cacheKey, path, bytes, createdAt, lastUsedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelTtsCacheRow &&
          other.cacheKey == this.cacheKey &&
          other.path == this.path &&
          other.bytes == this.bytes &&
          other.createdAt == this.createdAt &&
          other.lastUsedAt == this.lastUsedAt);
}

class NovelTtsCacheEntriesCompanion extends UpdateCompanion<NovelTtsCacheRow> {
  final Value<String> cacheKey;
  final Value<String> path;
  final Value<int> bytes;
  final Value<DateTime> createdAt;
  final Value<DateTime> lastUsedAt;
  final Value<int> rowid;
  const NovelTtsCacheEntriesCompanion({
    this.cacheKey = const Value.absent(),
    this.path = const Value.absent(),
    this.bytes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NovelTtsCacheEntriesCompanion.insert({
    required String cacheKey,
    required String path,
    this.bytes = const Value.absent(),
    required DateTime createdAt,
    required DateTime lastUsedAt,
    this.rowid = const Value.absent(),
  }) : cacheKey = Value(cacheKey),
       path = Value(path),
       createdAt = Value(createdAt),
       lastUsedAt = Value(lastUsedAt);
  static Insertable<NovelTtsCacheRow> custom({
    Expression<String>? cacheKey,
    Expression<String>? path,
    Expression<int>? bytes,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastUsedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (cacheKey != null) 'cache_key': cacheKey,
      if (path != null) 'path': path,
      if (bytes != null) 'bytes': bytes,
      if (createdAt != null) 'created_at': createdAt,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NovelTtsCacheEntriesCompanion copyWith({
    Value<String>? cacheKey,
    Value<String>? path,
    Value<int>? bytes,
    Value<DateTime>? createdAt,
    Value<DateTime>? lastUsedAt,
    Value<int>? rowid,
  }) {
    return NovelTtsCacheEntriesCompanion(
      cacheKey: cacheKey ?? this.cacheKey,
      path: path ?? this.path,
      bytes: bytes ?? this.bytes,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (cacheKey.present) {
      map['cache_key'] = Variable<String>(cacheKey.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<int>(bytes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
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
    return (StringBuffer('NovelTtsCacheEntriesCompanion(')
          ..write('cacheKey: $cacheKey, ')
          ..write('path: $path, ')
          ..write('bytes: $bytes, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NovelLocalBooksTable extends NovelLocalBooks
    with TableInfo<$NovelLocalBooksTable, NovelLocalBookRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NovelLocalBooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
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
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
    'author',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _encodingMeta = const VerificationMeta(
    'encoding',
  );
  @override
  late final GeneratedColumn<String> encoding = GeneratedColumn<String>(
    'encoding',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _byteSizeMeta = const VerificationMeta(
    'byteSize',
  );
  @override
  late final GeneratedColumn<int> byteSize = GeneratedColumn<int>(
    'byte_size',
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
  static const VerificationMeta _tocJsonMeta = const VerificationMeta(
    'tocJson',
  );
  @override
  late final GeneratedColumn<String> tocJson = GeneratedColumn<String>(
    'toc_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    path,
    title,
    author,
    format,
    encoding,
    byteSize,
    chapterCount,
    tocJson,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'novel_local_book';
  @override
  VerificationContext validateIntegrity(
    Insertable<NovelLocalBookRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('author')) {
      context.handle(
        _authorMeta,
        author.isAcceptableOrUnknown(data['author']!, _authorMeta),
      );
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    } else if (isInserting) {
      context.missing(_formatMeta);
    }
    if (data.containsKey('encoding')) {
      context.handle(
        _encodingMeta,
        encoding.isAcceptableOrUnknown(data['encoding']!, _encodingMeta),
      );
    }
    if (data.containsKey('byte_size')) {
      context.handle(
        _byteSizeMeta,
        byteSize.isAcceptableOrUnknown(data['byte_size']!, _byteSizeMeta),
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
    if (data.containsKey('toc_json')) {
      context.handle(
        _tocJsonMeta,
        tocJson.isAcceptableOrUnknown(data['toc_json']!, _tocJsonMeta),
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NovelLocalBookRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NovelLocalBookRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      author: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author'],
      )!,
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      )!,
      encoding: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encoding'],
      ),
      byteSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}byte_size'],
      )!,
      chapterCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter_count'],
      )!,
      tocJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}toc_json'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $NovelLocalBooksTable createAlias(String alias) {
    return $NovelLocalBooksTable(attachedDatabase, alias);
  }
}

class NovelLocalBookRow extends DataClass
    implements Insertable<NovelLocalBookRow> {
  final String id;

  /// 导入时的绝对路径（重新定位后改写这里）。
  final String path;
  final String title;
  final String author;

  /// `txt` / `epub` / `md`。
  final String format;

  /// 嗅探到的编码名（utf-8 / utf-16le / gbk / gb18030 / big5）；EPUB 为空。
  final String? encoding;
  final int byteSize;
  final int chapterCount;

  /// 目录 JSON：`[{"t": 标题, "s": 起始字节, "e": 结束字节, "h": href}]`。
  final String tocJson;
  final DateTime addedAt;
  const NovelLocalBookRow({
    required this.id,
    required this.path,
    required this.title,
    required this.author,
    required this.format,
    this.encoding,
    required this.byteSize,
    required this.chapterCount,
    required this.tocJson,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['path'] = Variable<String>(path);
    map['title'] = Variable<String>(title);
    map['author'] = Variable<String>(author);
    map['format'] = Variable<String>(format);
    if (!nullToAbsent || encoding != null) {
      map['encoding'] = Variable<String>(encoding);
    }
    map['byte_size'] = Variable<int>(byteSize);
    map['chapter_count'] = Variable<int>(chapterCount);
    map['toc_json'] = Variable<String>(tocJson);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  NovelLocalBooksCompanion toCompanion(bool nullToAbsent) {
    return NovelLocalBooksCompanion(
      id: Value(id),
      path: Value(path),
      title: Value(title),
      author: Value(author),
      format: Value(format),
      encoding: encoding == null && nullToAbsent
          ? const Value.absent()
          : Value(encoding),
      byteSize: Value(byteSize),
      chapterCount: Value(chapterCount),
      tocJson: Value(tocJson),
      addedAt: Value(addedAt),
    );
  }

  factory NovelLocalBookRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NovelLocalBookRow(
      id: serializer.fromJson<String>(json['id']),
      path: serializer.fromJson<String>(json['path']),
      title: serializer.fromJson<String>(json['title']),
      author: serializer.fromJson<String>(json['author']),
      format: serializer.fromJson<String>(json['format']),
      encoding: serializer.fromJson<String?>(json['encoding']),
      byteSize: serializer.fromJson<int>(json['byteSize']),
      chapterCount: serializer.fromJson<int>(json['chapterCount']),
      tocJson: serializer.fromJson<String>(json['tocJson']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'path': serializer.toJson<String>(path),
      'title': serializer.toJson<String>(title),
      'author': serializer.toJson<String>(author),
      'format': serializer.toJson<String>(format),
      'encoding': serializer.toJson<String?>(encoding),
      'byteSize': serializer.toJson<int>(byteSize),
      'chapterCount': serializer.toJson<int>(chapterCount),
      'tocJson': serializer.toJson<String>(tocJson),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  NovelLocalBookRow copyWith({
    String? id,
    String? path,
    String? title,
    String? author,
    String? format,
    Value<String?> encoding = const Value.absent(),
    int? byteSize,
    int? chapterCount,
    String? tocJson,
    DateTime? addedAt,
  }) => NovelLocalBookRow(
    id: id ?? this.id,
    path: path ?? this.path,
    title: title ?? this.title,
    author: author ?? this.author,
    format: format ?? this.format,
    encoding: encoding.present ? encoding.value : this.encoding,
    byteSize: byteSize ?? this.byteSize,
    chapterCount: chapterCount ?? this.chapterCount,
    tocJson: tocJson ?? this.tocJson,
    addedAt: addedAt ?? this.addedAt,
  );
  NovelLocalBookRow copyWithCompanion(NovelLocalBooksCompanion data) {
    return NovelLocalBookRow(
      id: data.id.present ? data.id.value : this.id,
      path: data.path.present ? data.path.value : this.path,
      title: data.title.present ? data.title.value : this.title,
      author: data.author.present ? data.author.value : this.author,
      format: data.format.present ? data.format.value : this.format,
      encoding: data.encoding.present ? data.encoding.value : this.encoding,
      byteSize: data.byteSize.present ? data.byteSize.value : this.byteSize,
      chapterCount: data.chapterCount.present
          ? data.chapterCount.value
          : this.chapterCount,
      tocJson: data.tocJson.present ? data.tocJson.value : this.tocJson,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NovelLocalBookRow(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('format: $format, ')
          ..write('encoding: $encoding, ')
          ..write('byteSize: $byteSize, ')
          ..write('chapterCount: $chapterCount, ')
          ..write('tocJson: $tocJson, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    path,
    title,
    author,
    format,
    encoding,
    byteSize,
    chapterCount,
    tocJson,
    addedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelLocalBookRow &&
          other.id == this.id &&
          other.path == this.path &&
          other.title == this.title &&
          other.author == this.author &&
          other.format == this.format &&
          other.encoding == this.encoding &&
          other.byteSize == this.byteSize &&
          other.chapterCount == this.chapterCount &&
          other.tocJson == this.tocJson &&
          other.addedAt == this.addedAt);
}

class NovelLocalBooksCompanion extends UpdateCompanion<NovelLocalBookRow> {
  final Value<String> id;
  final Value<String> path;
  final Value<String> title;
  final Value<String> author;
  final Value<String> format;
  final Value<String?> encoding;
  final Value<int> byteSize;
  final Value<int> chapterCount;
  final Value<String> tocJson;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const NovelLocalBooksCompanion({
    this.id = const Value.absent(),
    this.path = const Value.absent(),
    this.title = const Value.absent(),
    this.author = const Value.absent(),
    this.format = const Value.absent(),
    this.encoding = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.chapterCount = const Value.absent(),
    this.tocJson = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NovelLocalBooksCompanion.insert({
    required String id,
    required String path,
    required String title,
    this.author = const Value.absent(),
    required String format,
    this.encoding = const Value.absent(),
    this.byteSize = const Value.absent(),
    this.chapterCount = const Value.absent(),
    this.tocJson = const Value.absent(),
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       path = Value(path),
       title = Value(title),
       format = Value(format),
       addedAt = Value(addedAt);
  static Insertable<NovelLocalBookRow> custom({
    Expression<String>? id,
    Expression<String>? path,
    Expression<String>? title,
    Expression<String>? author,
    Expression<String>? format,
    Expression<String>? encoding,
    Expression<int>? byteSize,
    Expression<int>? chapterCount,
    Expression<String>? tocJson,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (path != null) 'path': path,
      if (title != null) 'title': title,
      if (author != null) 'author': author,
      if (format != null) 'format': format,
      if (encoding != null) 'encoding': encoding,
      if (byteSize != null) 'byte_size': byteSize,
      if (chapterCount != null) 'chapter_count': chapterCount,
      if (tocJson != null) 'toc_json': tocJson,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NovelLocalBooksCompanion copyWith({
    Value<String>? id,
    Value<String>? path,
    Value<String>? title,
    Value<String>? author,
    Value<String>? format,
    Value<String?>? encoding,
    Value<int>? byteSize,
    Value<int>? chapterCount,
    Value<String>? tocJson,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return NovelLocalBooksCompanion(
      id: id ?? this.id,
      path: path ?? this.path,
      title: title ?? this.title,
      author: author ?? this.author,
      format: format ?? this.format,
      encoding: encoding ?? this.encoding,
      byteSize: byteSize ?? this.byteSize,
      chapterCount: chapterCount ?? this.chapterCount,
      tocJson: tocJson ?? this.tocJson,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (encoding.present) {
      map['encoding'] = Variable<String>(encoding.value);
    }
    if (byteSize.present) {
      map['byte_size'] = Variable<int>(byteSize.value);
    }
    if (chapterCount.present) {
      map['chapter_count'] = Variable<int>(chapterCount.value);
    }
    if (tocJson.present) {
      map['toc_json'] = Variable<String>(tocJson.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NovelLocalBooksCompanion(')
          ..write('id: $id, ')
          ..write('path: $path, ')
          ..write('title: $title, ')
          ..write('author: $author, ')
          ..write('format: $format, ')
          ..write('encoding: $encoding, ')
          ..write('byteSize: $byteSize, ')
          ..write('chapterCount: $chapterCount, ')
          ..write('tocJson: $tocJson, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NovelTxtTocRulesTable extends NovelTxtTocRules
    with TableInfo<$NovelTxtTocRulesTable, NovelTxtTocRuleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NovelTxtTocRulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _patternMeta = const VerificationMeta(
    'pattern',
  );
  @override
  late final GeneratedColumn<String> pattern = GeneratedColumn<String>(
    'pattern',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _builtinMeta = const VerificationMeta(
    'builtin',
  );
  @override
  late final GeneratedColumn<bool> builtin = GeneratedColumn<bool>(
    'builtin',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("builtin" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
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
  List<GeneratedColumn> get $columns => [
    id,
    name,
    pattern,
    enabled,
    builtin,
    sortOrder,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'novel_txt_toc_rule';
  @override
  VerificationContext validateIntegrity(
    Insertable<NovelTxtTocRuleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('pattern')) {
      context.handle(
        _patternMeta,
        pattern.isAcceptableOrUnknown(data['pattern']!, _patternMeta),
      );
    } else if (isInserting) {
      context.missing(_patternMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('builtin')) {
      context.handle(
        _builtinMeta,
        builtin.isAcceptableOrUnknown(data['builtin']!, _builtinMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NovelTxtTocRuleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NovelTxtTocRuleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      pattern: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pattern'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      builtin: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}builtin'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $NovelTxtTocRulesTable createAlias(String alias) {
    return $NovelTxtTocRulesTable(attachedDatabase, alias);
  }
}

class NovelTxtTocRuleRow extends DataClass
    implements Insertable<NovelTxtTocRuleRow> {
  final int id;
  final String name;

  /// 正则表达式（对每一行整行匹配）。
  final String pattern;
  final bool enabled;

  /// 内置规则：可停用、可改，删除后可用「恢复默认」找回。
  final bool builtin;
  final int sortOrder;
  final DateTime updatedAt;
  const NovelTxtTocRuleRow({
    required this.id,
    required this.name,
    required this.pattern,
    required this.enabled,
    required this.builtin,
    required this.sortOrder,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['pattern'] = Variable<String>(pattern);
    map['enabled'] = Variable<bool>(enabled);
    map['builtin'] = Variable<bool>(builtin);
    map['sort_order'] = Variable<int>(sortOrder);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  NovelTxtTocRulesCompanion toCompanion(bool nullToAbsent) {
    return NovelTxtTocRulesCompanion(
      id: Value(id),
      name: Value(name),
      pattern: Value(pattern),
      enabled: Value(enabled),
      builtin: Value(builtin),
      sortOrder: Value(sortOrder),
      updatedAt: Value(updatedAt),
    );
  }

  factory NovelTxtTocRuleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NovelTxtTocRuleRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      pattern: serializer.fromJson<String>(json['pattern']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      builtin: serializer.fromJson<bool>(json['builtin']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'pattern': serializer.toJson<String>(pattern),
      'enabled': serializer.toJson<bool>(enabled),
      'builtin': serializer.toJson<bool>(builtin),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  NovelTxtTocRuleRow copyWith({
    int? id,
    String? name,
    String? pattern,
    bool? enabled,
    bool? builtin,
    int? sortOrder,
    DateTime? updatedAt,
  }) => NovelTxtTocRuleRow(
    id: id ?? this.id,
    name: name ?? this.name,
    pattern: pattern ?? this.pattern,
    enabled: enabled ?? this.enabled,
    builtin: builtin ?? this.builtin,
    sortOrder: sortOrder ?? this.sortOrder,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  NovelTxtTocRuleRow copyWithCompanion(NovelTxtTocRulesCompanion data) {
    return NovelTxtTocRuleRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      pattern: data.pattern.present ? data.pattern.value : this.pattern,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      builtin: data.builtin.present ? data.builtin.value : this.builtin,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NovelTxtTocRuleRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('pattern: $pattern, ')
          ..write('enabled: $enabled, ')
          ..write('builtin: $builtin, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, pattern, enabled, builtin, sortOrder, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelTxtTocRuleRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.pattern == this.pattern &&
          other.enabled == this.enabled &&
          other.builtin == this.builtin &&
          other.sortOrder == this.sortOrder &&
          other.updatedAt == this.updatedAt);
}

class NovelTxtTocRulesCompanion extends UpdateCompanion<NovelTxtTocRuleRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> pattern;
  final Value<bool> enabled;
  final Value<bool> builtin;
  final Value<int> sortOrder;
  final Value<DateTime> updatedAt;
  const NovelTxtTocRulesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.pattern = const Value.absent(),
    this.enabled = const Value.absent(),
    this.builtin = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  NovelTxtTocRulesCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String pattern,
    this.enabled = const Value.absent(),
    this.builtin = const Value.absent(),
    this.sortOrder = const Value.absent(),
    required DateTime updatedAt,
  }) : name = Value(name),
       pattern = Value(pattern),
       updatedAt = Value(updatedAt);
  static Insertable<NovelTxtTocRuleRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? pattern,
    Expression<bool>? enabled,
    Expression<bool>? builtin,
    Expression<int>? sortOrder,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (pattern != null) 'pattern': pattern,
      if (enabled != null) 'enabled': enabled,
      if (builtin != null) 'builtin': builtin,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  NovelTxtTocRulesCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? pattern,
    Value<bool>? enabled,
    Value<bool>? builtin,
    Value<int>? sortOrder,
    Value<DateTime>? updatedAt,
  }) {
    return NovelTxtTocRulesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      pattern: pattern ?? this.pattern,
      enabled: enabled ?? this.enabled,
      builtin: builtin ?? this.builtin,
      sortOrder: sortOrder ?? this.sortOrder,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (pattern.present) {
      map['pattern'] = Variable<String>(pattern.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (builtin.present) {
      map['builtin'] = Variable<bool>(builtin.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NovelTxtTocRulesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('pattern: $pattern, ')
          ..write('enabled: $enabled, ')
          ..write('builtin: $builtin, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $NovelTombstoneEntriesTable extends NovelTombstoneEntries
    with TableInfo<$NovelTombstoneEntriesTable, NovelTombstoneRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NovelTombstoneEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetKeyMeta = const VerificationMeta(
    'targetKey',
  );
  @override
  late final GeneratedColumn<String> targetKey = GeneratedColumn<String>(
    'target_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [kind, targetKey, deviceId, deletedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'novel_tombstone';
  @override
  VerificationContext validateIntegrity(
    Insertable<NovelTombstoneRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('target_key')) {
      context.handle(
        _targetKeyMeta,
        targetKey.isAcceptableOrUnknown(data['target_key']!, _targetKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_targetKeyMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_deletedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {kind, targetKey};
  @override
  NovelTombstoneRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NovelTombstoneRow(
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      targetKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_key'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      )!,
    );
  }

  @override
  $NovelTombstoneEntriesTable createAlias(String alias) {
    return $NovelTombstoneEntriesTable(attachedDatabase, alias);
  }
}

class NovelTombstoneRow extends DataClass
    implements Insertable<NovelTombstoneRow> {
  /// `bookmark` / `marking`。
  final String kind;

  /// 被删行的自然键（书 + 源 + 章 + 段 + 偏移）。
  final String targetKey;

  /// 哪台设备删的（诊断用）。
  final String deviceId;
  final DateTime deletedAt;
  const NovelTombstoneRow({
    required this.kind,
    required this.targetKey,
    required this.deviceId,
    required this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['kind'] = Variable<String>(kind);
    map['target_key'] = Variable<String>(targetKey);
    map['device_id'] = Variable<String>(deviceId);
    map['deleted_at'] = Variable<DateTime>(deletedAt);
    return map;
  }

  NovelTombstoneEntriesCompanion toCompanion(bool nullToAbsent) {
    return NovelTombstoneEntriesCompanion(
      kind: Value(kind),
      targetKey: Value(targetKey),
      deviceId: Value(deviceId),
      deletedAt: Value(deletedAt),
    );
  }

  factory NovelTombstoneRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NovelTombstoneRow(
      kind: serializer.fromJson<String>(json['kind']),
      targetKey: serializer.fromJson<String>(json['targetKey']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      deletedAt: serializer.fromJson<DateTime>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'kind': serializer.toJson<String>(kind),
      'targetKey': serializer.toJson<String>(targetKey),
      'deviceId': serializer.toJson<String>(deviceId),
      'deletedAt': serializer.toJson<DateTime>(deletedAt),
    };
  }

  NovelTombstoneRow copyWith({
    String? kind,
    String? targetKey,
    String? deviceId,
    DateTime? deletedAt,
  }) => NovelTombstoneRow(
    kind: kind ?? this.kind,
    targetKey: targetKey ?? this.targetKey,
    deviceId: deviceId ?? this.deviceId,
    deletedAt: deletedAt ?? this.deletedAt,
  );
  NovelTombstoneRow copyWithCompanion(NovelTombstoneEntriesCompanion data) {
    return NovelTombstoneRow(
      kind: data.kind.present ? data.kind.value : this.kind,
      targetKey: data.targetKey.present ? data.targetKey.value : this.targetKey,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NovelTombstoneRow(')
          ..write('kind: $kind, ')
          ..write('targetKey: $targetKey, ')
          ..write('deviceId: $deviceId, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(kind, targetKey, deviceId, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NovelTombstoneRow &&
          other.kind == this.kind &&
          other.targetKey == this.targetKey &&
          other.deviceId == this.deviceId &&
          other.deletedAt == this.deletedAt);
}

class NovelTombstoneEntriesCompanion
    extends UpdateCompanion<NovelTombstoneRow> {
  final Value<String> kind;
  final Value<String> targetKey;
  final Value<String> deviceId;
  final Value<DateTime> deletedAt;
  final Value<int> rowid;
  const NovelTombstoneEntriesCompanion({
    this.kind = const Value.absent(),
    this.targetKey = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NovelTombstoneEntriesCompanion.insert({
    required String kind,
    required String targetKey,
    this.deviceId = const Value.absent(),
    required DateTime deletedAt,
    this.rowid = const Value.absent(),
  }) : kind = Value(kind),
       targetKey = Value(targetKey),
       deletedAt = Value(deletedAt);
  static Insertable<NovelTombstoneRow> custom({
    Expression<String>? kind,
    Expression<String>? targetKey,
    Expression<String>? deviceId,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (kind != null) 'kind': kind,
      if (targetKey != null) 'target_key': targetKey,
      if (deviceId != null) 'device_id': deviceId,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NovelTombstoneEntriesCompanion copyWith({
    Value<String>? kind,
    Value<String>? targetKey,
    Value<String>? deviceId,
    Value<DateTime>? deletedAt,
    Value<int>? rowid,
  }) {
    return NovelTombstoneEntriesCompanion(
      kind: kind ?? this.kind,
      targetKey: targetKey ?? this.targetKey,
      deviceId: deviceId ?? this.deviceId,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (targetKey.present) {
      map['target_key'] = Variable<String>(targetKey.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NovelTombstoneEntriesCompanion(')
          ..write('kind: $kind, ')
          ..write('targetKey: $targetKey, ')
          ..write('deviceId: $deviceId, ')
          ..write('deletedAt: $deletedAt, ')
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
  late final $NovelSeriesEntriesTable novelSeriesEntries =
      $NovelSeriesEntriesTable(this);
  late final $NovelHistoryEntriesTable novelHistoryEntries =
      $NovelHistoryEntriesTable(this);
  late final $NovelSearchTermsTable novelSearchTerms = $NovelSearchTermsTable(
    this,
  );
  late final $NovelPrefsTable novelPrefs = $NovelPrefsTable(this);
  late final $NovelReadRecordsTable novelReadRecords = $NovelReadRecordsTable(
    this,
  );
  late final $NovelBookmarkEntriesTable novelBookmarkEntries =
      $NovelBookmarkEntriesTable(this);
  late final $NovelMarkingEntriesTable novelMarkingEntries =
      $NovelMarkingEntriesTable(this);
  late final $NovelHighlightRulesTable novelHighlightRules =
      $NovelHighlightRulesTable(this);
  late final $NovelContentOverridesTable novelContentOverrides =
      $NovelContentOverridesTable(this);
  late final $NovelTtsCacheEntriesTable novelTtsCacheEntries =
      $NovelTtsCacheEntriesTable(this);
  late final $NovelLocalBooksTable novelLocalBooks = $NovelLocalBooksTable(
    this,
  );
  late final $NovelTxtTocRulesTable novelTxtTocRules = $NovelTxtTocRulesTable(
    this,
  );
  late final $NovelTombstoneEntriesTable novelTombstoneEntries =
      $NovelTombstoneEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    novelCollectEntries,
    novelSeriesEntries,
    novelHistoryEntries,
    novelSearchTerms,
    novelPrefs,
    novelReadRecords,
    novelBookmarkEntries,
    novelMarkingEntries,
    novelHighlightRules,
    novelContentOverrides,
    novelTtsCacheEntries,
    novelLocalBooks,
    novelTxtTocRules,
    novelTombstoneEntries,
  ];
}

typedef $$NovelCollectEntriesTableCreateCompanionBuilder =
    NovelCollectEntriesCompanion Function({
      required String id,
      required String title,
      Value<String?> coverUrl,
      Value<String> payload,
      Value<String?> groupName,
      Value<String> note,
      Value<String?> customCoverPath,
      Value<int?> seriesId,
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
      Value<String> note,
      Value<String?> customCoverPath,
      Value<int?> seriesId,
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

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customCoverPath => $composableBuilder(
    column: $table.customCoverPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seriesId => $composableBuilder(
    column: $table.seriesId,
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

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customCoverPath => $composableBuilder(
    column: $table.customCoverPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seriesId => $composableBuilder(
    column: $table.seriesId,
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

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get customCoverPath => $composableBuilder(
    column: $table.customCoverPath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get seriesId =>
      $composableBuilder(column: $table.seriesId, builder: (column) => column);

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
                Value<String> note = const Value.absent(),
                Value<String?> customCoverPath = const Value.absent(),
                Value<int?> seriesId = const Value.absent(),
                Value<DateTime> collectedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NovelCollectEntriesCompanion(
                id: id,
                title: title,
                coverUrl: coverUrl,
                payload: payload,
                groupName: groupName,
                note: note,
                customCoverPath: customCoverPath,
                seriesId: seriesId,
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
                Value<String> note = const Value.absent(),
                Value<String?> customCoverPath = const Value.absent(),
                Value<int?> seriesId = const Value.absent(),
                required DateTime collectedAt,
                Value<int> rowid = const Value.absent(),
              }) => NovelCollectEntriesCompanion.insert(
                id: id,
                title: title,
                coverUrl: coverUrl,
                payload: payload,
                groupName: groupName,
                note: note,
                customCoverPath: customCoverPath,
                seriesId: seriesId,
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
typedef $$NovelSeriesEntriesTableCreateCompanionBuilder =
    NovelSeriesEntriesCompanion Function({
      Value<int> id,
      required String name,
      required DateTime createdAt,
    });
typedef $$NovelSeriesEntriesTableUpdateCompanionBuilder =
    NovelSeriesEntriesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<DateTime> createdAt,
    });

class $$NovelSeriesEntriesTableFilterComposer
    extends Composer<_$NovelDb, $NovelSeriesEntriesTable> {
  $$NovelSeriesEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NovelSeriesEntriesTableOrderingComposer
    extends Composer<_$NovelDb, $NovelSeriesEntriesTable> {
  $$NovelSeriesEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NovelSeriesEntriesTableAnnotationComposer
    extends Composer<_$NovelDb, $NovelSeriesEntriesTable> {
  $$NovelSeriesEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$NovelSeriesEntriesTableTableManager
    extends
        RootTableManager<
          _$NovelDb,
          $NovelSeriesEntriesTable,
          NovelSeriesRow,
          $$NovelSeriesEntriesTableFilterComposer,
          $$NovelSeriesEntriesTableOrderingComposer,
          $$NovelSeriesEntriesTableAnnotationComposer,
          $$NovelSeriesEntriesTableCreateCompanionBuilder,
          $$NovelSeriesEntriesTableUpdateCompanionBuilder,
          (
            NovelSeriesRow,
            BaseReferences<_$NovelDb, $NovelSeriesEntriesTable, NovelSeriesRow>,
          ),
          NovelSeriesRow,
          PrefetchHooks Function()
        > {
  $$NovelSeriesEntriesTableTableManager(
    _$NovelDb db,
    $NovelSeriesEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NovelSeriesEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NovelSeriesEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NovelSeriesEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => NovelSeriesEntriesCompanion(
                id: id,
                name: name,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required DateTime createdAt,
              }) => NovelSeriesEntriesCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NovelSeriesEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$NovelDb,
      $NovelSeriesEntriesTable,
      NovelSeriesRow,
      $$NovelSeriesEntriesTableFilterComposer,
      $$NovelSeriesEntriesTableOrderingComposer,
      $$NovelSeriesEntriesTableAnnotationComposer,
      $$NovelSeriesEntriesTableCreateCompanionBuilder,
      $$NovelSeriesEntriesTableUpdateCompanionBuilder,
      (
        NovelSeriesRow,
        BaseReferences<_$NovelDb, $NovelSeriesEntriesTable, NovelSeriesRow>,
      ),
      NovelSeriesRow,
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
typedef $$NovelReadRecordsTableCreateCompanionBuilder =
    NovelReadRecordsCompanion Function({
      required String deviceId,
      required String bookId,
      Value<String> bookTitle,
      Value<int> chapterIndex,
      Value<String> chapterName,
      required String day,
      Value<int> seconds,
      required DateTime firstReadAt,
      required DateTime lastReadAt,
      Value<int> rowid,
    });
typedef $$NovelReadRecordsTableUpdateCompanionBuilder =
    NovelReadRecordsCompanion Function({
      Value<String> deviceId,
      Value<String> bookId,
      Value<String> bookTitle,
      Value<int> chapterIndex,
      Value<String> chapterName,
      Value<String> day,
      Value<int> seconds,
      Value<DateTime> firstReadAt,
      Value<DateTime> lastReadAt,
      Value<int> rowid,
    });

class $$NovelReadRecordsTableFilterComposer
    extends Composer<_$NovelDb, $NovelReadRecordsTable> {
  $$NovelReadRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookTitle => $composableBuilder(
    column: $table.bookTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterName => $composableBuilder(
    column: $table.chapterName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seconds => $composableBuilder(
    column: $table.seconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get firstReadAt => $composableBuilder(
    column: $table.firstReadAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NovelReadRecordsTableOrderingComposer
    extends Composer<_$NovelDb, $NovelReadRecordsTable> {
  $$NovelReadRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookTitle => $composableBuilder(
    column: $table.bookTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterName => $composableBuilder(
    column: $table.chapterName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seconds => $composableBuilder(
    column: $table.seconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get firstReadAt => $composableBuilder(
    column: $table.firstReadAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NovelReadRecordsTableAnnotationComposer
    extends Composer<_$NovelDb, $NovelReadRecordsTable> {
  $$NovelReadRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get bookTitle =>
      $composableBuilder(column: $table.bookTitle, builder: (column) => column);

  GeneratedColumn<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<String> get chapterName => $composableBuilder(
    column: $table.chapterName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<int> get seconds =>
      $composableBuilder(column: $table.seconds, builder: (column) => column);

  GeneratedColumn<DateTime> get firstReadAt => $composableBuilder(
    column: $table.firstReadAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => column,
  );
}

class $$NovelReadRecordsTableTableManager
    extends
        RootTableManager<
          _$NovelDb,
          $NovelReadRecordsTable,
          NovelReadRecordRow,
          $$NovelReadRecordsTableFilterComposer,
          $$NovelReadRecordsTableOrderingComposer,
          $$NovelReadRecordsTableAnnotationComposer,
          $$NovelReadRecordsTableCreateCompanionBuilder,
          $$NovelReadRecordsTableUpdateCompanionBuilder,
          (
            NovelReadRecordRow,
            BaseReferences<
              _$NovelDb,
              $NovelReadRecordsTable,
              NovelReadRecordRow
            >,
          ),
          NovelReadRecordRow,
          PrefetchHooks Function()
        > {
  $$NovelReadRecordsTableTableManager(
    _$NovelDb db,
    $NovelReadRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NovelReadRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NovelReadRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NovelReadRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> deviceId = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> bookTitle = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<String> chapterName = const Value.absent(),
                Value<String> day = const Value.absent(),
                Value<int> seconds = const Value.absent(),
                Value<DateTime> firstReadAt = const Value.absent(),
                Value<DateTime> lastReadAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NovelReadRecordsCompanion(
                deviceId: deviceId,
                bookId: bookId,
                bookTitle: bookTitle,
                chapterIndex: chapterIndex,
                chapterName: chapterName,
                day: day,
                seconds: seconds,
                firstReadAt: firstReadAt,
                lastReadAt: lastReadAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String deviceId,
                required String bookId,
                Value<String> bookTitle = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<String> chapterName = const Value.absent(),
                required String day,
                Value<int> seconds = const Value.absent(),
                required DateTime firstReadAt,
                required DateTime lastReadAt,
                Value<int> rowid = const Value.absent(),
              }) => NovelReadRecordsCompanion.insert(
                deviceId: deviceId,
                bookId: bookId,
                bookTitle: bookTitle,
                chapterIndex: chapterIndex,
                chapterName: chapterName,
                day: day,
                seconds: seconds,
                firstReadAt: firstReadAt,
                lastReadAt: lastReadAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NovelReadRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$NovelDb,
      $NovelReadRecordsTable,
      NovelReadRecordRow,
      $$NovelReadRecordsTableFilterComposer,
      $$NovelReadRecordsTableOrderingComposer,
      $$NovelReadRecordsTableAnnotationComposer,
      $$NovelReadRecordsTableCreateCompanionBuilder,
      $$NovelReadRecordsTableUpdateCompanionBuilder,
      (
        NovelReadRecordRow,
        BaseReferences<_$NovelDb, $NovelReadRecordsTable, NovelReadRecordRow>,
      ),
      NovelReadRecordRow,
      PrefetchHooks Function()
    >;
typedef $$NovelBookmarkEntriesTableCreateCompanionBuilder =
    NovelBookmarkEntriesCompanion Function({
      Value<int> id,
      required String bookId,
      Value<String> sourceKey,
      Value<String> bookTitle,
      Value<String> bookAuthor,
      Value<String> bookUrl,
      required int chapterIndex,
      Value<int> paragraph,
      Value<int> charOffset,
      Value<String> chapterName,
      Value<String> excerpt,
      Value<bool> unresolved,
      required DateTime createdAt,
    });
typedef $$NovelBookmarkEntriesTableUpdateCompanionBuilder =
    NovelBookmarkEntriesCompanion Function({
      Value<int> id,
      Value<String> bookId,
      Value<String> sourceKey,
      Value<String> bookTitle,
      Value<String> bookAuthor,
      Value<String> bookUrl,
      Value<int> chapterIndex,
      Value<int> paragraph,
      Value<int> charOffset,
      Value<String> chapterName,
      Value<String> excerpt,
      Value<bool> unresolved,
      Value<DateTime> createdAt,
    });

class $$NovelBookmarkEntriesTableFilterComposer
    extends Composer<_$NovelDb, $NovelBookmarkEntriesTable> {
  $$NovelBookmarkEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceKey => $composableBuilder(
    column: $table.sourceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookTitle => $composableBuilder(
    column: $table.bookTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookAuthor => $composableBuilder(
    column: $table.bookAuthor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get paragraph => $composableBuilder(
    column: $table.paragraph,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterName => $composableBuilder(
    column: $table.chapterName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get excerpt => $composableBuilder(
    column: $table.excerpt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get unresolved => $composableBuilder(
    column: $table.unresolved,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NovelBookmarkEntriesTableOrderingComposer
    extends Composer<_$NovelDb, $NovelBookmarkEntriesTable> {
  $$NovelBookmarkEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKey => $composableBuilder(
    column: $table.sourceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookTitle => $composableBuilder(
    column: $table.bookTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookAuthor => $composableBuilder(
    column: $table.bookAuthor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get paragraph => $composableBuilder(
    column: $table.paragraph,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterName => $composableBuilder(
    column: $table.chapterName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get excerpt => $composableBuilder(
    column: $table.excerpt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get unresolved => $composableBuilder(
    column: $table.unresolved,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NovelBookmarkEntriesTableAnnotationComposer
    extends Composer<_$NovelDb, $NovelBookmarkEntriesTable> {
  $$NovelBookmarkEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get sourceKey =>
      $composableBuilder(column: $table.sourceKey, builder: (column) => column);

  GeneratedColumn<String> get bookTitle =>
      $composableBuilder(column: $table.bookTitle, builder: (column) => column);

  GeneratedColumn<String> get bookAuthor => $composableBuilder(
    column: $table.bookAuthor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bookUrl =>
      $composableBuilder(column: $table.bookUrl, builder: (column) => column);

  GeneratedColumn<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get paragraph =>
      $composableBuilder(column: $table.paragraph, builder: (column) => column);

  GeneratedColumn<int> get charOffset => $composableBuilder(
    column: $table.charOffset,
    builder: (column) => column,
  );

  GeneratedColumn<String> get chapterName => $composableBuilder(
    column: $table.chapterName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get excerpt =>
      $composableBuilder(column: $table.excerpt, builder: (column) => column);

  GeneratedColumn<bool> get unresolved => $composableBuilder(
    column: $table.unresolved,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$NovelBookmarkEntriesTableTableManager
    extends
        RootTableManager<
          _$NovelDb,
          $NovelBookmarkEntriesTable,
          NovelBookmarkRow,
          $$NovelBookmarkEntriesTableFilterComposer,
          $$NovelBookmarkEntriesTableOrderingComposer,
          $$NovelBookmarkEntriesTableAnnotationComposer,
          $$NovelBookmarkEntriesTableCreateCompanionBuilder,
          $$NovelBookmarkEntriesTableUpdateCompanionBuilder,
          (
            NovelBookmarkRow,
            BaseReferences<
              _$NovelDb,
              $NovelBookmarkEntriesTable,
              NovelBookmarkRow
            >,
          ),
          NovelBookmarkRow,
          PrefetchHooks Function()
        > {
  $$NovelBookmarkEntriesTableTableManager(
    _$NovelDb db,
    $NovelBookmarkEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NovelBookmarkEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NovelBookmarkEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$NovelBookmarkEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> sourceKey = const Value.absent(),
                Value<String> bookTitle = const Value.absent(),
                Value<String> bookAuthor = const Value.absent(),
                Value<String> bookUrl = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<int> paragraph = const Value.absent(),
                Value<int> charOffset = const Value.absent(),
                Value<String> chapterName = const Value.absent(),
                Value<String> excerpt = const Value.absent(),
                Value<bool> unresolved = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => NovelBookmarkEntriesCompanion(
                id: id,
                bookId: bookId,
                sourceKey: sourceKey,
                bookTitle: bookTitle,
                bookAuthor: bookAuthor,
                bookUrl: bookUrl,
                chapterIndex: chapterIndex,
                paragraph: paragraph,
                charOffset: charOffset,
                chapterName: chapterName,
                excerpt: excerpt,
                unresolved: unresolved,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String bookId,
                Value<String> sourceKey = const Value.absent(),
                Value<String> bookTitle = const Value.absent(),
                Value<String> bookAuthor = const Value.absent(),
                Value<String> bookUrl = const Value.absent(),
                required int chapterIndex,
                Value<int> paragraph = const Value.absent(),
                Value<int> charOffset = const Value.absent(),
                Value<String> chapterName = const Value.absent(),
                Value<String> excerpt = const Value.absent(),
                Value<bool> unresolved = const Value.absent(),
                required DateTime createdAt,
              }) => NovelBookmarkEntriesCompanion.insert(
                id: id,
                bookId: bookId,
                sourceKey: sourceKey,
                bookTitle: bookTitle,
                bookAuthor: bookAuthor,
                bookUrl: bookUrl,
                chapterIndex: chapterIndex,
                paragraph: paragraph,
                charOffset: charOffset,
                chapterName: chapterName,
                excerpt: excerpt,
                unresolved: unresolved,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NovelBookmarkEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$NovelDb,
      $NovelBookmarkEntriesTable,
      NovelBookmarkRow,
      $$NovelBookmarkEntriesTableFilterComposer,
      $$NovelBookmarkEntriesTableOrderingComposer,
      $$NovelBookmarkEntriesTableAnnotationComposer,
      $$NovelBookmarkEntriesTableCreateCompanionBuilder,
      $$NovelBookmarkEntriesTableUpdateCompanionBuilder,
      (
        NovelBookmarkRow,
        BaseReferences<_$NovelDb, $NovelBookmarkEntriesTable, NovelBookmarkRow>,
      ),
      NovelBookmarkRow,
      PrefetchHooks Function()
    >;
typedef $$NovelMarkingEntriesTableCreateCompanionBuilder =
    NovelMarkingEntriesCompanion Function({
      Value<int> id,
      required String bookId,
      Value<String> sourceKey,
      Value<String> bookTitle,
      Value<String> bookAuthor,
      Value<String> bookUrl,
      required int chapterIndex,
      Value<int> paragraph,
      Value<int> startOffset,
      Value<int> endOffset,
      Value<String> chapterName,
      Value<String> styleJson,
      Value<String> note,
      Value<bool> unresolved,
      required DateTime createdAt,
      required DateTime updatedAt,
    });
typedef $$NovelMarkingEntriesTableUpdateCompanionBuilder =
    NovelMarkingEntriesCompanion Function({
      Value<int> id,
      Value<String> bookId,
      Value<String> sourceKey,
      Value<String> bookTitle,
      Value<String> bookAuthor,
      Value<String> bookUrl,
      Value<int> chapterIndex,
      Value<int> paragraph,
      Value<int> startOffset,
      Value<int> endOffset,
      Value<String> chapterName,
      Value<String> styleJson,
      Value<String> note,
      Value<bool> unresolved,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$NovelMarkingEntriesTableFilterComposer
    extends Composer<_$NovelDb, $NovelMarkingEntriesTable> {
  $$NovelMarkingEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceKey => $composableBuilder(
    column: $table.sourceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookTitle => $composableBuilder(
    column: $table.bookTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookAuthor => $composableBuilder(
    column: $table.bookAuthor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get paragraph => $composableBuilder(
    column: $table.paragraph,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startOffset => $composableBuilder(
    column: $table.startOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endOffset => $composableBuilder(
    column: $table.endOffset,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterName => $composableBuilder(
    column: $table.chapterName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get styleJson => $composableBuilder(
    column: $table.styleJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get unresolved => $composableBuilder(
    column: $table.unresolved,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NovelMarkingEntriesTableOrderingComposer
    extends Composer<_$NovelDb, $NovelMarkingEntriesTable> {
  $$NovelMarkingEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKey => $composableBuilder(
    column: $table.sourceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookTitle => $composableBuilder(
    column: $table.bookTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookAuthor => $composableBuilder(
    column: $table.bookAuthor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookUrl => $composableBuilder(
    column: $table.bookUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get paragraph => $composableBuilder(
    column: $table.paragraph,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startOffset => $composableBuilder(
    column: $table.startOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endOffset => $composableBuilder(
    column: $table.endOffset,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterName => $composableBuilder(
    column: $table.chapterName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get styleJson => $composableBuilder(
    column: $table.styleJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get unresolved => $composableBuilder(
    column: $table.unresolved,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NovelMarkingEntriesTableAnnotationComposer
    extends Composer<_$NovelDb, $NovelMarkingEntriesTable> {
  $$NovelMarkingEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get sourceKey =>
      $composableBuilder(column: $table.sourceKey, builder: (column) => column);

  GeneratedColumn<String> get bookTitle =>
      $composableBuilder(column: $table.bookTitle, builder: (column) => column);

  GeneratedColumn<String> get bookAuthor => $composableBuilder(
    column: $table.bookAuthor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get bookUrl =>
      $composableBuilder(column: $table.bookUrl, builder: (column) => column);

  GeneratedColumn<int> get chapterIndex => $composableBuilder(
    column: $table.chapterIndex,
    builder: (column) => column,
  );

  GeneratedColumn<int> get paragraph =>
      $composableBuilder(column: $table.paragraph, builder: (column) => column);

  GeneratedColumn<int> get startOffset => $composableBuilder(
    column: $table.startOffset,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endOffset =>
      $composableBuilder(column: $table.endOffset, builder: (column) => column);

  GeneratedColumn<String> get chapterName => $composableBuilder(
    column: $table.chapterName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get styleJson =>
      $composableBuilder(column: $table.styleJson, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<bool> get unresolved => $composableBuilder(
    column: $table.unresolved,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$NovelMarkingEntriesTableTableManager
    extends
        RootTableManager<
          _$NovelDb,
          $NovelMarkingEntriesTable,
          NovelMarkingRow,
          $$NovelMarkingEntriesTableFilterComposer,
          $$NovelMarkingEntriesTableOrderingComposer,
          $$NovelMarkingEntriesTableAnnotationComposer,
          $$NovelMarkingEntriesTableCreateCompanionBuilder,
          $$NovelMarkingEntriesTableUpdateCompanionBuilder,
          (
            NovelMarkingRow,
            BaseReferences<
              _$NovelDb,
              $NovelMarkingEntriesTable,
              NovelMarkingRow
            >,
          ),
          NovelMarkingRow,
          PrefetchHooks Function()
        > {
  $$NovelMarkingEntriesTableTableManager(
    _$NovelDb db,
    $NovelMarkingEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NovelMarkingEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NovelMarkingEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$NovelMarkingEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> sourceKey = const Value.absent(),
                Value<String> bookTitle = const Value.absent(),
                Value<String> bookAuthor = const Value.absent(),
                Value<String> bookUrl = const Value.absent(),
                Value<int> chapterIndex = const Value.absent(),
                Value<int> paragraph = const Value.absent(),
                Value<int> startOffset = const Value.absent(),
                Value<int> endOffset = const Value.absent(),
                Value<String> chapterName = const Value.absent(),
                Value<String> styleJson = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<bool> unresolved = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => NovelMarkingEntriesCompanion(
                id: id,
                bookId: bookId,
                sourceKey: sourceKey,
                bookTitle: bookTitle,
                bookAuthor: bookAuthor,
                bookUrl: bookUrl,
                chapterIndex: chapterIndex,
                paragraph: paragraph,
                startOffset: startOffset,
                endOffset: endOffset,
                chapterName: chapterName,
                styleJson: styleJson,
                note: note,
                unresolved: unresolved,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String bookId,
                Value<String> sourceKey = const Value.absent(),
                Value<String> bookTitle = const Value.absent(),
                Value<String> bookAuthor = const Value.absent(),
                Value<String> bookUrl = const Value.absent(),
                required int chapterIndex,
                Value<int> paragraph = const Value.absent(),
                Value<int> startOffset = const Value.absent(),
                Value<int> endOffset = const Value.absent(),
                Value<String> chapterName = const Value.absent(),
                Value<String> styleJson = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<bool> unresolved = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => NovelMarkingEntriesCompanion.insert(
                id: id,
                bookId: bookId,
                sourceKey: sourceKey,
                bookTitle: bookTitle,
                bookAuthor: bookAuthor,
                bookUrl: bookUrl,
                chapterIndex: chapterIndex,
                paragraph: paragraph,
                startOffset: startOffset,
                endOffset: endOffset,
                chapterName: chapterName,
                styleJson: styleJson,
                note: note,
                unresolved: unresolved,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NovelMarkingEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$NovelDb,
      $NovelMarkingEntriesTable,
      NovelMarkingRow,
      $$NovelMarkingEntriesTableFilterComposer,
      $$NovelMarkingEntriesTableOrderingComposer,
      $$NovelMarkingEntriesTableAnnotationComposer,
      $$NovelMarkingEntriesTableCreateCompanionBuilder,
      $$NovelMarkingEntriesTableUpdateCompanionBuilder,
      (
        NovelMarkingRow,
        BaseReferences<_$NovelDb, $NovelMarkingEntriesTable, NovelMarkingRow>,
      ),
      NovelMarkingRow,
      PrefetchHooks Function()
    >;
typedef $$NovelHighlightRulesTableCreateCompanionBuilder =
    NovelHighlightRulesCompanion Function({
      Value<int> id,
      Value<String> bookId,
      Value<String> name,
      required String pattern,
      required int foregroundLight,
      Value<int?> backgroundLight,
      required int foregroundDark,
      Value<int?> backgroundDark,
      Value<bool> underline,
      Value<bool> bold,
      Value<bool> enabled,
      Value<String> raw,
      required DateTime createdAt,
      required DateTime updatedAt,
    });
typedef $$NovelHighlightRulesTableUpdateCompanionBuilder =
    NovelHighlightRulesCompanion Function({
      Value<int> id,
      Value<String> bookId,
      Value<String> name,
      Value<String> pattern,
      Value<int> foregroundLight,
      Value<int?> backgroundLight,
      Value<int> foregroundDark,
      Value<int?> backgroundDark,
      Value<bool> underline,
      Value<bool> bold,
      Value<bool> enabled,
      Value<String> raw,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

class $$NovelHighlightRulesTableFilterComposer
    extends Composer<_$NovelDb, $NovelHighlightRulesTable> {
  $$NovelHighlightRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pattern => $composableBuilder(
    column: $table.pattern,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get foregroundLight => $composableBuilder(
    column: $table.foregroundLight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get backgroundLight => $composableBuilder(
    column: $table.backgroundLight,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get foregroundDark => $composableBuilder(
    column: $table.foregroundDark,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get backgroundDark => $composableBuilder(
    column: $table.backgroundDark,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get underline => $composableBuilder(
    column: $table.underline,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get bold => $composableBuilder(
    column: $table.bold,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get raw => $composableBuilder(
    column: $table.raw,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NovelHighlightRulesTableOrderingComposer
    extends Composer<_$NovelDb, $NovelHighlightRulesTable> {
  $$NovelHighlightRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pattern => $composableBuilder(
    column: $table.pattern,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get foregroundLight => $composableBuilder(
    column: $table.foregroundLight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get backgroundLight => $composableBuilder(
    column: $table.backgroundLight,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get foregroundDark => $composableBuilder(
    column: $table.foregroundDark,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get backgroundDark => $composableBuilder(
    column: $table.backgroundDark,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get underline => $composableBuilder(
    column: $table.underline,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get bold => $composableBuilder(
    column: $table.bold,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get raw => $composableBuilder(
    column: $table.raw,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NovelHighlightRulesTableAnnotationComposer
    extends Composer<_$NovelDb, $NovelHighlightRulesTable> {
  $$NovelHighlightRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get pattern =>
      $composableBuilder(column: $table.pattern, builder: (column) => column);

  GeneratedColumn<int> get foregroundLight => $composableBuilder(
    column: $table.foregroundLight,
    builder: (column) => column,
  );

  GeneratedColumn<int> get backgroundLight => $composableBuilder(
    column: $table.backgroundLight,
    builder: (column) => column,
  );

  GeneratedColumn<int> get foregroundDark => $composableBuilder(
    column: $table.foregroundDark,
    builder: (column) => column,
  );

  GeneratedColumn<int> get backgroundDark => $composableBuilder(
    column: $table.backgroundDark,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get underline =>
      $composableBuilder(column: $table.underline, builder: (column) => column);

  GeneratedColumn<bool> get bold =>
      $composableBuilder(column: $table.bold, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<String> get raw =>
      $composableBuilder(column: $table.raw, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$NovelHighlightRulesTableTableManager
    extends
        RootTableManager<
          _$NovelDb,
          $NovelHighlightRulesTable,
          NovelHighlightRuleRow,
          $$NovelHighlightRulesTableFilterComposer,
          $$NovelHighlightRulesTableOrderingComposer,
          $$NovelHighlightRulesTableAnnotationComposer,
          $$NovelHighlightRulesTableCreateCompanionBuilder,
          $$NovelHighlightRulesTableUpdateCompanionBuilder,
          (
            NovelHighlightRuleRow,
            BaseReferences<
              _$NovelDb,
              $NovelHighlightRulesTable,
              NovelHighlightRuleRow
            >,
          ),
          NovelHighlightRuleRow,
          PrefetchHooks Function()
        > {
  $$NovelHighlightRulesTableTableManager(
    _$NovelDb db,
    $NovelHighlightRulesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NovelHighlightRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NovelHighlightRulesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$NovelHighlightRulesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> pattern = const Value.absent(),
                Value<int> foregroundLight = const Value.absent(),
                Value<int?> backgroundLight = const Value.absent(),
                Value<int> foregroundDark = const Value.absent(),
                Value<int?> backgroundDark = const Value.absent(),
                Value<bool> underline = const Value.absent(),
                Value<bool> bold = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String> raw = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => NovelHighlightRulesCompanion(
                id: id,
                bookId: bookId,
                name: name,
                pattern: pattern,
                foregroundLight: foregroundLight,
                backgroundLight: backgroundLight,
                foregroundDark: foregroundDark,
                backgroundDark: backgroundDark,
                underline: underline,
                bold: bold,
                enabled: enabled,
                raw: raw,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> name = const Value.absent(),
                required String pattern,
                required int foregroundLight,
                Value<int?> backgroundLight = const Value.absent(),
                required int foregroundDark,
                Value<int?> backgroundDark = const Value.absent(),
                Value<bool> underline = const Value.absent(),
                Value<bool> bold = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<String> raw = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => NovelHighlightRulesCompanion.insert(
                id: id,
                bookId: bookId,
                name: name,
                pattern: pattern,
                foregroundLight: foregroundLight,
                backgroundLight: backgroundLight,
                foregroundDark: foregroundDark,
                backgroundDark: backgroundDark,
                underline: underline,
                bold: bold,
                enabled: enabled,
                raw: raw,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NovelHighlightRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$NovelDb,
      $NovelHighlightRulesTable,
      NovelHighlightRuleRow,
      $$NovelHighlightRulesTableFilterComposer,
      $$NovelHighlightRulesTableOrderingComposer,
      $$NovelHighlightRulesTableAnnotationComposer,
      $$NovelHighlightRulesTableCreateCompanionBuilder,
      $$NovelHighlightRulesTableUpdateCompanionBuilder,
      (
        NovelHighlightRuleRow,
        BaseReferences<
          _$NovelDb,
          $NovelHighlightRulesTable,
          NovelHighlightRuleRow
        >,
      ),
      NovelHighlightRuleRow,
      PrefetchHooks Function()
    >;
typedef $$NovelContentOverridesTableCreateCompanionBuilder =
    NovelContentOverridesCompanion Function({
      required String bookId,
      Value<String> sourceKey,
      required String chapterKey,
      Value<String> chapterTitle,
      Value<String> title,
      required String paragraphsJson,
      Value<int> paragraphCount,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$NovelContentOverridesTableUpdateCompanionBuilder =
    NovelContentOverridesCompanion Function({
      Value<String> bookId,
      Value<String> sourceKey,
      Value<String> chapterKey,
      Value<String> chapterTitle,
      Value<String> title,
      Value<String> paragraphsJson,
      Value<int> paragraphCount,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$NovelContentOverridesTableFilterComposer
    extends Composer<_$NovelDb, $NovelContentOverridesTable> {
  $$NovelContentOverridesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceKey => $composableBuilder(
    column: $table.sourceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterKey => $composableBuilder(
    column: $table.chapterKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paragraphsJson => $composableBuilder(
    column: $table.paragraphsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get paragraphCount => $composableBuilder(
    column: $table.paragraphCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NovelContentOverridesTableOrderingComposer
    extends Composer<_$NovelDb, $NovelContentOverridesTable> {
  $$NovelContentOverridesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKey => $composableBuilder(
    column: $table.sourceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterKey => $composableBuilder(
    column: $table.chapterKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paragraphsJson => $composableBuilder(
    column: $table.paragraphsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get paragraphCount => $composableBuilder(
    column: $table.paragraphCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NovelContentOverridesTableAnnotationComposer
    extends Composer<_$NovelDb, $NovelContentOverridesTable> {
  $$NovelContentOverridesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get sourceKey =>
      $composableBuilder(column: $table.sourceKey, builder: (column) => column);

  GeneratedColumn<String> get chapterKey => $composableBuilder(
    column: $table.chapterKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get chapterTitle => $composableBuilder(
    column: $table.chapterTitle,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get paragraphsJson => $composableBuilder(
    column: $table.paragraphsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get paragraphCount => $composableBuilder(
    column: $table.paragraphCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$NovelContentOverridesTableTableManager
    extends
        RootTableManager<
          _$NovelDb,
          $NovelContentOverridesTable,
          NovelContentOverrideRow,
          $$NovelContentOverridesTableFilterComposer,
          $$NovelContentOverridesTableOrderingComposer,
          $$NovelContentOverridesTableAnnotationComposer,
          $$NovelContentOverridesTableCreateCompanionBuilder,
          $$NovelContentOverridesTableUpdateCompanionBuilder,
          (
            NovelContentOverrideRow,
            BaseReferences<
              _$NovelDb,
              $NovelContentOverridesTable,
              NovelContentOverrideRow
            >,
          ),
          NovelContentOverrideRow,
          PrefetchHooks Function()
        > {
  $$NovelContentOverridesTableTableManager(
    _$NovelDb db,
    $NovelContentOverridesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NovelContentOverridesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$NovelContentOverridesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$NovelContentOverridesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<String> sourceKey = const Value.absent(),
                Value<String> chapterKey = const Value.absent(),
                Value<String> chapterTitle = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> paragraphsJson = const Value.absent(),
                Value<int> paragraphCount = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NovelContentOverridesCompanion(
                bookId: bookId,
                sourceKey: sourceKey,
                chapterKey: chapterKey,
                chapterTitle: chapterTitle,
                title: title,
                paragraphsJson: paragraphsJson,
                paragraphCount: paragraphCount,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                Value<String> sourceKey = const Value.absent(),
                required String chapterKey,
                Value<String> chapterTitle = const Value.absent(),
                Value<String> title = const Value.absent(),
                required String paragraphsJson,
                Value<int> paragraphCount = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => NovelContentOverridesCompanion.insert(
                bookId: bookId,
                sourceKey: sourceKey,
                chapterKey: chapterKey,
                chapterTitle: chapterTitle,
                title: title,
                paragraphsJson: paragraphsJson,
                paragraphCount: paragraphCount,
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

typedef $$NovelContentOverridesTableProcessedTableManager =
    ProcessedTableManager<
      _$NovelDb,
      $NovelContentOverridesTable,
      NovelContentOverrideRow,
      $$NovelContentOverridesTableFilterComposer,
      $$NovelContentOverridesTableOrderingComposer,
      $$NovelContentOverridesTableAnnotationComposer,
      $$NovelContentOverridesTableCreateCompanionBuilder,
      $$NovelContentOverridesTableUpdateCompanionBuilder,
      (
        NovelContentOverrideRow,
        BaseReferences<
          _$NovelDb,
          $NovelContentOverridesTable,
          NovelContentOverrideRow
        >,
      ),
      NovelContentOverrideRow,
      PrefetchHooks Function()
    >;
typedef $$NovelTtsCacheEntriesTableCreateCompanionBuilder =
    NovelTtsCacheEntriesCompanion Function({
      required String cacheKey,
      required String path,
      Value<int> bytes,
      required DateTime createdAt,
      required DateTime lastUsedAt,
      Value<int> rowid,
    });
typedef $$NovelTtsCacheEntriesTableUpdateCompanionBuilder =
    NovelTtsCacheEntriesCompanion Function({
      Value<String> cacheKey,
      Value<String> path,
      Value<int> bytes,
      Value<DateTime> createdAt,
      Value<DateTime> lastUsedAt,
      Value<int> rowid,
    });

class $$NovelTtsCacheEntriesTableFilterComposer
    extends Composer<_$NovelDb, $NovelTtsCacheEntriesTable> {
  $$NovelTtsCacheEntriesTableFilterComposer({
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

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NovelTtsCacheEntriesTableOrderingComposer
    extends Composer<_$NovelDb, $NovelTtsCacheEntriesTable> {
  $$NovelTtsCacheEntriesTableOrderingComposer({
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

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NovelTtsCacheEntriesTableAnnotationComposer
    extends Composer<_$NovelDb, $NovelTtsCacheEntriesTable> {
  $$NovelTtsCacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get cacheKey =>
      $composableBuilder(column: $table.cacheKey, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );
}

class $$NovelTtsCacheEntriesTableTableManager
    extends
        RootTableManager<
          _$NovelDb,
          $NovelTtsCacheEntriesTable,
          NovelTtsCacheRow,
          $$NovelTtsCacheEntriesTableFilterComposer,
          $$NovelTtsCacheEntriesTableOrderingComposer,
          $$NovelTtsCacheEntriesTableAnnotationComposer,
          $$NovelTtsCacheEntriesTableCreateCompanionBuilder,
          $$NovelTtsCacheEntriesTableUpdateCompanionBuilder,
          (
            NovelTtsCacheRow,
            BaseReferences<
              _$NovelDb,
              $NovelTtsCacheEntriesTable,
              NovelTtsCacheRow
            >,
          ),
          NovelTtsCacheRow,
          PrefetchHooks Function()
        > {
  $$NovelTtsCacheEntriesTableTableManager(
    _$NovelDb db,
    $NovelTtsCacheEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NovelTtsCacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NovelTtsCacheEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$NovelTtsCacheEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> cacheKey = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<int> bytes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> lastUsedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NovelTtsCacheEntriesCompanion(
                cacheKey: cacheKey,
                path: path,
                bytes: bytes,
                createdAt: createdAt,
                lastUsedAt: lastUsedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String cacheKey,
                required String path,
                Value<int> bytes = const Value.absent(),
                required DateTime createdAt,
                required DateTime lastUsedAt,
                Value<int> rowid = const Value.absent(),
              }) => NovelTtsCacheEntriesCompanion.insert(
                cacheKey: cacheKey,
                path: path,
                bytes: bytes,
                createdAt: createdAt,
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

typedef $$NovelTtsCacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$NovelDb,
      $NovelTtsCacheEntriesTable,
      NovelTtsCacheRow,
      $$NovelTtsCacheEntriesTableFilterComposer,
      $$NovelTtsCacheEntriesTableOrderingComposer,
      $$NovelTtsCacheEntriesTableAnnotationComposer,
      $$NovelTtsCacheEntriesTableCreateCompanionBuilder,
      $$NovelTtsCacheEntriesTableUpdateCompanionBuilder,
      (
        NovelTtsCacheRow,
        BaseReferences<_$NovelDb, $NovelTtsCacheEntriesTable, NovelTtsCacheRow>,
      ),
      NovelTtsCacheRow,
      PrefetchHooks Function()
    >;
typedef $$NovelLocalBooksTableCreateCompanionBuilder =
    NovelLocalBooksCompanion Function({
      required String id,
      required String path,
      required String title,
      Value<String> author,
      required String format,
      Value<String?> encoding,
      Value<int> byteSize,
      Value<int> chapterCount,
      Value<String> tocJson,
      required DateTime addedAt,
      Value<int> rowid,
    });
typedef $$NovelLocalBooksTableUpdateCompanionBuilder =
    NovelLocalBooksCompanion Function({
      Value<String> id,
      Value<String> path,
      Value<String> title,
      Value<String> author,
      Value<String> format,
      Value<String?> encoding,
      Value<int> byteSize,
      Value<int> chapterCount,
      Value<String> tocJson,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

class $$NovelLocalBooksTableFilterComposer
    extends Composer<_$NovelDb, $NovelLocalBooksTable> {
  $$NovelLocalBooksTableFilterComposer({
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

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encoding => $composableBuilder(
    column: $table.encoding,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapterCount => $composableBuilder(
    column: $table.chapterCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tocJson => $composableBuilder(
    column: $table.tocJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NovelLocalBooksTableOrderingComposer
    extends Composer<_$NovelDb, $NovelLocalBooksTable> {
  $$NovelLocalBooksTableOrderingComposer({
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

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get author => $composableBuilder(
    column: $table.author,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encoding => $composableBuilder(
    column: $table.encoding,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get byteSize => $composableBuilder(
    column: $table.byteSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapterCount => $composableBuilder(
    column: $table.chapterCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tocJson => $composableBuilder(
    column: $table.tocJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NovelLocalBooksTableAnnotationComposer
    extends Composer<_$NovelDb, $NovelLocalBooksTable> {
  $$NovelLocalBooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<String> get encoding =>
      $composableBuilder(column: $table.encoding, builder: (column) => column);

  GeneratedColumn<int> get byteSize =>
      $composableBuilder(column: $table.byteSize, builder: (column) => column);

  GeneratedColumn<int> get chapterCount => $composableBuilder(
    column: $table.chapterCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tocJson =>
      $composableBuilder(column: $table.tocJson, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$NovelLocalBooksTableTableManager
    extends
        RootTableManager<
          _$NovelDb,
          $NovelLocalBooksTable,
          NovelLocalBookRow,
          $$NovelLocalBooksTableFilterComposer,
          $$NovelLocalBooksTableOrderingComposer,
          $$NovelLocalBooksTableAnnotationComposer,
          $$NovelLocalBooksTableCreateCompanionBuilder,
          $$NovelLocalBooksTableUpdateCompanionBuilder,
          (
            NovelLocalBookRow,
            BaseReferences<_$NovelDb, $NovelLocalBooksTable, NovelLocalBookRow>,
          ),
          NovelLocalBookRow,
          PrefetchHooks Function()
        > {
  $$NovelLocalBooksTableTableManager(_$NovelDb db, $NovelLocalBooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NovelLocalBooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NovelLocalBooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NovelLocalBooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> author = const Value.absent(),
                Value<String> format = const Value.absent(),
                Value<String?> encoding = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<int> chapterCount = const Value.absent(),
                Value<String> tocJson = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NovelLocalBooksCompanion(
                id: id,
                path: path,
                title: title,
                author: author,
                format: format,
                encoding: encoding,
                byteSize: byteSize,
                chapterCount: chapterCount,
                tocJson: tocJson,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String path,
                required String title,
                Value<String> author = const Value.absent(),
                required String format,
                Value<String?> encoding = const Value.absent(),
                Value<int> byteSize = const Value.absent(),
                Value<int> chapterCount = const Value.absent(),
                Value<String> tocJson = const Value.absent(),
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => NovelLocalBooksCompanion.insert(
                id: id,
                path: path,
                title: title,
                author: author,
                format: format,
                encoding: encoding,
                byteSize: byteSize,
                chapterCount: chapterCount,
                tocJson: tocJson,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NovelLocalBooksTableProcessedTableManager =
    ProcessedTableManager<
      _$NovelDb,
      $NovelLocalBooksTable,
      NovelLocalBookRow,
      $$NovelLocalBooksTableFilterComposer,
      $$NovelLocalBooksTableOrderingComposer,
      $$NovelLocalBooksTableAnnotationComposer,
      $$NovelLocalBooksTableCreateCompanionBuilder,
      $$NovelLocalBooksTableUpdateCompanionBuilder,
      (
        NovelLocalBookRow,
        BaseReferences<_$NovelDb, $NovelLocalBooksTable, NovelLocalBookRow>,
      ),
      NovelLocalBookRow,
      PrefetchHooks Function()
    >;
typedef $$NovelTxtTocRulesTableCreateCompanionBuilder =
    NovelTxtTocRulesCompanion Function({
      Value<int> id,
      required String name,
      required String pattern,
      Value<bool> enabled,
      Value<bool> builtin,
      Value<int> sortOrder,
      required DateTime updatedAt,
    });
typedef $$NovelTxtTocRulesTableUpdateCompanionBuilder =
    NovelTxtTocRulesCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> pattern,
      Value<bool> enabled,
      Value<bool> builtin,
      Value<int> sortOrder,
      Value<DateTime> updatedAt,
    });

class $$NovelTxtTocRulesTableFilterComposer
    extends Composer<_$NovelDb, $NovelTxtTocRulesTable> {
  $$NovelTxtTocRulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pattern => $composableBuilder(
    column: $table.pattern,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get builtin => $composableBuilder(
    column: $table.builtin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NovelTxtTocRulesTableOrderingComposer
    extends Composer<_$NovelDb, $NovelTxtTocRulesTable> {
  $$NovelTxtTocRulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pattern => $composableBuilder(
    column: $table.pattern,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get builtin => $composableBuilder(
    column: $table.builtin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NovelTxtTocRulesTableAnnotationComposer
    extends Composer<_$NovelDb, $NovelTxtTocRulesTable> {
  $$NovelTxtTocRulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get pattern =>
      $composableBuilder(column: $table.pattern, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<bool> get builtin =>
      $composableBuilder(column: $table.builtin, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$NovelTxtTocRulesTableTableManager
    extends
        RootTableManager<
          _$NovelDb,
          $NovelTxtTocRulesTable,
          NovelTxtTocRuleRow,
          $$NovelTxtTocRulesTableFilterComposer,
          $$NovelTxtTocRulesTableOrderingComposer,
          $$NovelTxtTocRulesTableAnnotationComposer,
          $$NovelTxtTocRulesTableCreateCompanionBuilder,
          $$NovelTxtTocRulesTableUpdateCompanionBuilder,
          (
            NovelTxtTocRuleRow,
            BaseReferences<
              _$NovelDb,
              $NovelTxtTocRulesTable,
              NovelTxtTocRuleRow
            >,
          ),
          NovelTxtTocRuleRow,
          PrefetchHooks Function()
        > {
  $$NovelTxtTocRulesTableTableManager(
    _$NovelDb db,
    $NovelTxtTocRulesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NovelTxtTocRulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NovelTxtTocRulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NovelTxtTocRulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> pattern = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<bool> builtin = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => NovelTxtTocRulesCompanion(
                id: id,
                name: name,
                pattern: pattern,
                enabled: enabled,
                builtin: builtin,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String pattern,
                Value<bool> enabled = const Value.absent(),
                Value<bool> builtin = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                required DateTime updatedAt,
              }) => NovelTxtTocRulesCompanion.insert(
                id: id,
                name: name,
                pattern: pattern,
                enabled: enabled,
                builtin: builtin,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NovelTxtTocRulesTableProcessedTableManager =
    ProcessedTableManager<
      _$NovelDb,
      $NovelTxtTocRulesTable,
      NovelTxtTocRuleRow,
      $$NovelTxtTocRulesTableFilterComposer,
      $$NovelTxtTocRulesTableOrderingComposer,
      $$NovelTxtTocRulesTableAnnotationComposer,
      $$NovelTxtTocRulesTableCreateCompanionBuilder,
      $$NovelTxtTocRulesTableUpdateCompanionBuilder,
      (
        NovelTxtTocRuleRow,
        BaseReferences<_$NovelDb, $NovelTxtTocRulesTable, NovelTxtTocRuleRow>,
      ),
      NovelTxtTocRuleRow,
      PrefetchHooks Function()
    >;
typedef $$NovelTombstoneEntriesTableCreateCompanionBuilder =
    NovelTombstoneEntriesCompanion Function({
      required String kind,
      required String targetKey,
      Value<String> deviceId,
      required DateTime deletedAt,
      Value<int> rowid,
    });
typedef $$NovelTombstoneEntriesTableUpdateCompanionBuilder =
    NovelTombstoneEntriesCompanion Function({
      Value<String> kind,
      Value<String> targetKey,
      Value<String> deviceId,
      Value<DateTime> deletedAt,
      Value<int> rowid,
    });

class $$NovelTombstoneEntriesTableFilterComposer
    extends Composer<_$NovelDb, $NovelTombstoneEntriesTable> {
  $$NovelTombstoneEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetKey => $composableBuilder(
    column: $table.targetKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NovelTombstoneEntriesTableOrderingComposer
    extends Composer<_$NovelDb, $NovelTombstoneEntriesTable> {
  $$NovelTombstoneEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetKey => $composableBuilder(
    column: $table.targetKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NovelTombstoneEntriesTableAnnotationComposer
    extends Composer<_$NovelDb, $NovelTombstoneEntriesTable> {
  $$NovelTombstoneEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get targetKey =>
      $composableBuilder(column: $table.targetKey, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$NovelTombstoneEntriesTableTableManager
    extends
        RootTableManager<
          _$NovelDb,
          $NovelTombstoneEntriesTable,
          NovelTombstoneRow,
          $$NovelTombstoneEntriesTableFilterComposer,
          $$NovelTombstoneEntriesTableOrderingComposer,
          $$NovelTombstoneEntriesTableAnnotationComposer,
          $$NovelTombstoneEntriesTableCreateCompanionBuilder,
          $$NovelTombstoneEntriesTableUpdateCompanionBuilder,
          (
            NovelTombstoneRow,
            BaseReferences<
              _$NovelDb,
              $NovelTombstoneEntriesTable,
              NovelTombstoneRow
            >,
          ),
          NovelTombstoneRow,
          PrefetchHooks Function()
        > {
  $$NovelTombstoneEntriesTableTableManager(
    _$NovelDb db,
    $NovelTombstoneEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NovelTombstoneEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$NovelTombstoneEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$NovelTombstoneEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> kind = const Value.absent(),
                Value<String> targetKey = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<DateTime> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NovelTombstoneEntriesCompanion(
                kind: kind,
                targetKey: targetKey,
                deviceId: deviceId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String kind,
                required String targetKey,
                Value<String> deviceId = const Value.absent(),
                required DateTime deletedAt,
                Value<int> rowid = const Value.absent(),
              }) => NovelTombstoneEntriesCompanion.insert(
                kind: kind,
                targetKey: targetKey,
                deviceId: deviceId,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NovelTombstoneEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$NovelDb,
      $NovelTombstoneEntriesTable,
      NovelTombstoneRow,
      $$NovelTombstoneEntriesTableFilterComposer,
      $$NovelTombstoneEntriesTableOrderingComposer,
      $$NovelTombstoneEntriesTableAnnotationComposer,
      $$NovelTombstoneEntriesTableCreateCompanionBuilder,
      $$NovelTombstoneEntriesTableUpdateCompanionBuilder,
      (
        NovelTombstoneRow,
        BaseReferences<
          _$NovelDb,
          $NovelTombstoneEntriesTable,
          NovelTombstoneRow
        >,
      ),
      NovelTombstoneRow,
      PrefetchHooks Function()
    >;

class $NovelDbManager {
  final _$NovelDb _db;
  $NovelDbManager(this._db);
  $$NovelCollectEntriesTableTableManager get novelCollectEntries =>
      $$NovelCollectEntriesTableTableManager(_db, _db.novelCollectEntries);
  $$NovelSeriesEntriesTableTableManager get novelSeriesEntries =>
      $$NovelSeriesEntriesTableTableManager(_db, _db.novelSeriesEntries);
  $$NovelHistoryEntriesTableTableManager get novelHistoryEntries =>
      $$NovelHistoryEntriesTableTableManager(_db, _db.novelHistoryEntries);
  $$NovelSearchTermsTableTableManager get novelSearchTerms =>
      $$NovelSearchTermsTableTableManager(_db, _db.novelSearchTerms);
  $$NovelPrefsTableTableManager get novelPrefs =>
      $$NovelPrefsTableTableManager(_db, _db.novelPrefs);
  $$NovelReadRecordsTableTableManager get novelReadRecords =>
      $$NovelReadRecordsTableTableManager(_db, _db.novelReadRecords);
  $$NovelBookmarkEntriesTableTableManager get novelBookmarkEntries =>
      $$NovelBookmarkEntriesTableTableManager(_db, _db.novelBookmarkEntries);
  $$NovelMarkingEntriesTableTableManager get novelMarkingEntries =>
      $$NovelMarkingEntriesTableTableManager(_db, _db.novelMarkingEntries);
  $$NovelHighlightRulesTableTableManager get novelHighlightRules =>
      $$NovelHighlightRulesTableTableManager(_db, _db.novelHighlightRules);
  $$NovelContentOverridesTableTableManager get novelContentOverrides =>
      $$NovelContentOverridesTableTableManager(_db, _db.novelContentOverrides);
  $$NovelTtsCacheEntriesTableTableManager get novelTtsCacheEntries =>
      $$NovelTtsCacheEntriesTableTableManager(_db, _db.novelTtsCacheEntries);
  $$NovelLocalBooksTableTableManager get novelLocalBooks =>
      $$NovelLocalBooksTableTableManager(_db, _db.novelLocalBooks);
  $$NovelTxtTocRulesTableTableManager get novelTxtTocRules =>
      $$NovelTxtTocRulesTableTableManager(_db, _db.novelTxtTocRules);
  $$NovelTombstoneEntriesTableTableManager get novelTombstoneEntries =>
      $$NovelTombstoneEntriesTableTableManager(_db, _db.novelTombstoneEntries);
}
