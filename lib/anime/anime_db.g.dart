// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'anime_db.dart';

// ignore_for_file: type=lint
class $AnimeCollectEntriesTable extends AnimeCollectEntries
    with TableInfo<$AnimeCollectEntriesTable, AnimeCollectRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnimeCollectEntriesTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'anime_collect';
  @override
  VerificationContext validateIntegrity(
    Insertable<AnimeCollectRow> instance, {
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
  AnimeCollectRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AnimeCollectRow(
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
  $AnimeCollectEntriesTable createAlias(String alias) {
    return $AnimeCollectEntriesTable(attachedDatabase, alias);
  }
}

class AnimeCollectRow extends DataClass implements Insertable<AnimeCollectRow> {
  final String id;
  final String sourceName;
  final String title;
  final String? coverUrl;

  /// 模块私有 JSON；投影里的 payload 是投影函数另写的摘要，不是这一列。
  final String payload;
  final DateTime collectedAt;
  const AnimeCollectRow({
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

  AnimeCollectEntriesCompanion toCompanion(bool nullToAbsent) {
    return AnimeCollectEntriesCompanion(
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

  factory AnimeCollectRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AnimeCollectRow(
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

  AnimeCollectRow copyWith({
    String? id,
    String? sourceName,
    String? title,
    Value<String?> coverUrl = const Value.absent(),
    String? payload,
    DateTime? collectedAt,
  }) => AnimeCollectRow(
    id: id ?? this.id,
    sourceName: sourceName ?? this.sourceName,
    title: title ?? this.title,
    coverUrl: coverUrl.present ? coverUrl.value : this.coverUrl,
    payload: payload ?? this.payload,
    collectedAt: collectedAt ?? this.collectedAt,
  );
  AnimeCollectRow copyWithCompanion(AnimeCollectEntriesCompanion data) {
    return AnimeCollectRow(
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
    return (StringBuffer('AnimeCollectRow(')
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
      (other is AnimeCollectRow &&
          other.id == this.id &&
          other.sourceName == this.sourceName &&
          other.title == this.title &&
          other.coverUrl == this.coverUrl &&
          other.payload == this.payload &&
          other.collectedAt == this.collectedAt);
}

class AnimeCollectEntriesCompanion extends UpdateCompanion<AnimeCollectRow> {
  final Value<String> id;
  final Value<String> sourceName;
  final Value<String> title;
  final Value<String?> coverUrl;
  final Value<String> payload;
  final Value<DateTime> collectedAt;
  final Value<int> rowid;
  const AnimeCollectEntriesCompanion({
    this.id = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.title = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.payload = const Value.absent(),
    this.collectedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AnimeCollectEntriesCompanion.insert({
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
  static Insertable<AnimeCollectRow> custom({
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

  AnimeCollectEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? sourceName,
    Value<String>? title,
    Value<String?>? coverUrl,
    Value<String>? payload,
    Value<DateTime>? collectedAt,
    Value<int>? rowid,
  }) {
    return AnimeCollectEntriesCompanion(
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
    return (StringBuffer('AnimeCollectEntriesCompanion(')
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

class $AnimeHistoryEntriesTable extends AnimeHistoryEntries
    with TableInfo<$AnimeHistoryEntriesTable, AnimeHistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnimeHistoryEntriesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _episodeMeta = const VerificationMeta(
    'episode',
  );
  @override
  late final GeneratedColumn<int> episode = GeneratedColumn<int>(
    'episode',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _positionSecMeta = const VerificationMeta(
    'positionSec',
  );
  @override
  late final GeneratedColumn<int> positionSec = GeneratedColumn<int>(
    'position_sec',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationSecMeta = const VerificationMeta(
    'durationSec',
  );
  @override
  late final GeneratedColumn<int> durationSec = GeneratedColumn<int>(
    'duration_sec',
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
    episode,
    positionSec,
    durationSec,
    openedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'anime_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<AnimeHistoryRow> instance, {
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
    if (data.containsKey('episode')) {
      context.handle(
        _episodeMeta,
        episode.isAcceptableOrUnknown(data['episode']!, _episodeMeta),
      );
    }
    if (data.containsKey('position_sec')) {
      context.handle(
        _positionSecMeta,
        positionSec.isAcceptableOrUnknown(
          data['position_sec']!,
          _positionSecMeta,
        ),
      );
    }
    if (data.containsKey('duration_sec')) {
      context.handle(
        _durationSecMeta,
        durationSec.isAcceptableOrUnknown(
          data['duration_sec']!,
          _durationSecMeta,
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
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, sourceName};
  @override
  AnimeHistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AnimeHistoryRow(
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
      episode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode'],
      )!,
      positionSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_sec'],
      )!,
      durationSec: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_sec'],
      )!,
      openedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}opened_at'],
      )!,
    );
  }

  @override
  $AnimeHistoryEntriesTable createAlias(String alias) {
    return $AnimeHistoryEntriesTable(attachedDatabase, alias);
  }
}

class AnimeHistoryRow extends DataClass implements Insertable<AnimeHistoryRow> {
  final String id;
  final String sourceName;

  /// 打开历史时来源可能已下线，标题/封面随历史一起留底。
  final String title;
  final String? coverUrl;
  final int episode;
  final int positionSec;
  final int durationSec;
  final DateTime openedAt;
  const AnimeHistoryRow({
    required this.id,
    required this.sourceName,
    required this.title,
    this.coverUrl,
    required this.episode,
    required this.positionSec,
    required this.durationSec,
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
    map['episode'] = Variable<int>(episode);
    map['position_sec'] = Variable<int>(positionSec);
    map['duration_sec'] = Variable<int>(durationSec);
    map['opened_at'] = Variable<DateTime>(openedAt);
    return map;
  }

  AnimeHistoryEntriesCompanion toCompanion(bool nullToAbsent) {
    return AnimeHistoryEntriesCompanion(
      id: Value(id),
      sourceName: Value(sourceName),
      title: Value(title),
      coverUrl: coverUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(coverUrl),
      episode: Value(episode),
      positionSec: Value(positionSec),
      durationSec: Value(durationSec),
      openedAt: Value(openedAt),
    );
  }

  factory AnimeHistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AnimeHistoryRow(
      id: serializer.fromJson<String>(json['id']),
      sourceName: serializer.fromJson<String>(json['sourceName']),
      title: serializer.fromJson<String>(json['title']),
      coverUrl: serializer.fromJson<String?>(json['coverUrl']),
      episode: serializer.fromJson<int>(json['episode']),
      positionSec: serializer.fromJson<int>(json['positionSec']),
      durationSec: serializer.fromJson<int>(json['durationSec']),
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
      'episode': serializer.toJson<int>(episode),
      'positionSec': serializer.toJson<int>(positionSec),
      'durationSec': serializer.toJson<int>(durationSec),
      'openedAt': serializer.toJson<DateTime>(openedAt),
    };
  }

  AnimeHistoryRow copyWith({
    String? id,
    String? sourceName,
    String? title,
    Value<String?> coverUrl = const Value.absent(),
    int? episode,
    int? positionSec,
    int? durationSec,
    DateTime? openedAt,
  }) => AnimeHistoryRow(
    id: id ?? this.id,
    sourceName: sourceName ?? this.sourceName,
    title: title ?? this.title,
    coverUrl: coverUrl.present ? coverUrl.value : this.coverUrl,
    episode: episode ?? this.episode,
    positionSec: positionSec ?? this.positionSec,
    durationSec: durationSec ?? this.durationSec,
    openedAt: openedAt ?? this.openedAt,
  );
  AnimeHistoryRow copyWithCompanion(AnimeHistoryEntriesCompanion data) {
    return AnimeHistoryRow(
      id: data.id.present ? data.id.value : this.id,
      sourceName: data.sourceName.present
          ? data.sourceName.value
          : this.sourceName,
      title: data.title.present ? data.title.value : this.title,
      coverUrl: data.coverUrl.present ? data.coverUrl.value : this.coverUrl,
      episode: data.episode.present ? data.episode.value : this.episode,
      positionSec: data.positionSec.present
          ? data.positionSec.value
          : this.positionSec,
      durationSec: data.durationSec.present
          ? data.durationSec.value
          : this.durationSec,
      openedAt: data.openedAt.present ? data.openedAt.value : this.openedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AnimeHistoryRow(')
          ..write('id: $id, ')
          ..write('sourceName: $sourceName, ')
          ..write('title: $title, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('episode: $episode, ')
          ..write('positionSec: $positionSec, ')
          ..write('durationSec: $durationSec, ')
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
    episode,
    positionSec,
    durationSec,
    openedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AnimeHistoryRow &&
          other.id == this.id &&
          other.sourceName == this.sourceName &&
          other.title == this.title &&
          other.coverUrl == this.coverUrl &&
          other.episode == this.episode &&
          other.positionSec == this.positionSec &&
          other.durationSec == this.durationSec &&
          other.openedAt == this.openedAt);
}

class AnimeHistoryEntriesCompanion extends UpdateCompanion<AnimeHistoryRow> {
  final Value<String> id;
  final Value<String> sourceName;
  final Value<String> title;
  final Value<String?> coverUrl;
  final Value<int> episode;
  final Value<int> positionSec;
  final Value<int> durationSec;
  final Value<DateTime> openedAt;
  final Value<int> rowid;
  const AnimeHistoryEntriesCompanion({
    this.id = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.title = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.episode = const Value.absent(),
    this.positionSec = const Value.absent(),
    this.durationSec = const Value.absent(),
    this.openedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AnimeHistoryEntriesCompanion.insert({
    required String id,
    required String sourceName,
    required String title,
    this.coverUrl = const Value.absent(),
    this.episode = const Value.absent(),
    this.positionSec = const Value.absent(),
    this.durationSec = const Value.absent(),
    required DateTime openedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sourceName = Value(sourceName),
       title = Value(title),
       openedAt = Value(openedAt);
  static Insertable<AnimeHistoryRow> custom({
    Expression<String>? id,
    Expression<String>? sourceName,
    Expression<String>? title,
    Expression<String>? coverUrl,
    Expression<int>? episode,
    Expression<int>? positionSec,
    Expression<int>? durationSec,
    Expression<DateTime>? openedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceName != null) 'source_name': sourceName,
      if (title != null) 'title': title,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (episode != null) 'episode': episode,
      if (positionSec != null) 'position_sec': positionSec,
      if (durationSec != null) 'duration_sec': durationSec,
      if (openedAt != null) 'opened_at': openedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AnimeHistoryEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? sourceName,
    Value<String>? title,
    Value<String?>? coverUrl,
    Value<int>? episode,
    Value<int>? positionSec,
    Value<int>? durationSec,
    Value<DateTime>? openedAt,
    Value<int>? rowid,
  }) {
    return AnimeHistoryEntriesCompanion(
      id: id ?? this.id,
      sourceName: sourceName ?? this.sourceName,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      episode: episode ?? this.episode,
      positionSec: positionSec ?? this.positionSec,
      durationSec: durationSec ?? this.durationSec,
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
    if (episode.present) {
      map['episode'] = Variable<int>(episode.value);
    }
    if (positionSec.present) {
      map['position_sec'] = Variable<int>(positionSec.value);
    }
    if (durationSec.present) {
      map['duration_sec'] = Variable<int>(durationSec.value);
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
    return (StringBuffer('AnimeHistoryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('sourceName: $sourceName, ')
          ..write('title: $title, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('episode: $episode, ')
          ..write('positionSec: $positionSec, ')
          ..write('durationSec: $durationSec, ')
          ..write('openedAt: $openedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AnimeSearchTermsTable extends AnimeSearchTerms
    with TableInfo<$AnimeSearchTermsTable, AnimeSearchTermRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnimeSearchTermsTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'anime_search_term';
  @override
  VerificationContext validateIntegrity(
    Insertable<AnimeSearchTermRow> instance, {
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
  AnimeSearchTermRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AnimeSearchTermRow(
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
  $AnimeSearchTermsTable createAlias(String alias) {
    return $AnimeSearchTermsTable(attachedDatabase, alias);
  }
}

class AnimeSearchTermRow extends DataClass
    implements Insertable<AnimeSearchTermRow> {
  final String term;
  final DateTime lastUsedAt;
  const AnimeSearchTermRow({required this.term, required this.lastUsedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['term'] = Variable<String>(term);
    map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    return map;
  }

  AnimeSearchTermsCompanion toCompanion(bool nullToAbsent) {
    return AnimeSearchTermsCompanion(
      term: Value(term),
      lastUsedAt: Value(lastUsedAt),
    );
  }

  factory AnimeSearchTermRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AnimeSearchTermRow(
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

  AnimeSearchTermRow copyWith({String? term, DateTime? lastUsedAt}) =>
      AnimeSearchTermRow(
        term: term ?? this.term,
        lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      );
  AnimeSearchTermRow copyWithCompanion(AnimeSearchTermsCompanion data) {
    return AnimeSearchTermRow(
      term: data.term.present ? data.term.value : this.term,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AnimeSearchTermRow(')
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
      (other is AnimeSearchTermRow &&
          other.term == this.term &&
          other.lastUsedAt == this.lastUsedAt);
}

class AnimeSearchTermsCompanion extends UpdateCompanion<AnimeSearchTermRow> {
  final Value<String> term;
  final Value<DateTime> lastUsedAt;
  final Value<int> rowid;
  const AnimeSearchTermsCompanion({
    this.term = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AnimeSearchTermsCompanion.insert({
    required String term,
    required DateTime lastUsedAt,
    this.rowid = const Value.absent(),
  }) : term = Value(term),
       lastUsedAt = Value(lastUsedAt);
  static Insertable<AnimeSearchTermRow> custom({
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

  AnimeSearchTermsCompanion copyWith({
    Value<String>? term,
    Value<DateTime>? lastUsedAt,
    Value<int>? rowid,
  }) {
    return AnimeSearchTermsCompanion(
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
    return (StringBuffer('AnimeSearchTermsCompanion(')
          ..write('term: $term, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AnimeDanmakuCacheEntriesTable extends AnimeDanmakuCacheEntries
    with TableInfo<$AnimeDanmakuCacheEntriesTable, AnimeDanmakuCacheRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnimeDanmakuCacheEntriesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _episodeMeta = const VerificationMeta(
    'episode',
  );
  @override
  late final GeneratedColumn<int> episode = GeneratedColumn<int>(
    'episode',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _commentsJsonMeta = const VerificationMeta(
    'commentsJson',
  );
  @override
  late final GeneratedColumn<String> commentsJson = GeneratedColumn<String>(
    'comments_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourceName,
    episode,
    commentsJson,
    fetchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'anime_danmaku_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<AnimeDanmakuCacheRow> instance, {
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
    if (data.containsKey('episode')) {
      context.handle(
        _episodeMeta,
        episode.isAcceptableOrUnknown(data['episode']!, _episodeMeta),
      );
    } else if (isInserting) {
      context.missing(_episodeMeta);
    }
    if (data.containsKey('comments_json')) {
      context.handle(
        _commentsJsonMeta,
        commentsJson.isAcceptableOrUnknown(
          data['comments_json']!,
          _commentsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_commentsJsonMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id, sourceName, episode};
  @override
  AnimeDanmakuCacheRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AnimeDanmakuCacheRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sourceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_name'],
      )!,
      episode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode'],
      )!,
      commentsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}comments_json'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $AnimeDanmakuCacheEntriesTable createAlias(String alias) {
    return $AnimeDanmakuCacheEntriesTable(attachedDatabase, alias);
  }
}

class AnimeDanmakuCacheRow extends DataClass
    implements Insertable<AnimeDanmakuCacheRow> {
  final String id;
  final String sourceName;
  final int episode;

  /// `List<DanmakuComment>` 的 JSON 串；缓存的唯一格式由 danmaku.dart 定义。
  final String commentsJson;
  final DateTime fetchedAt;
  const AnimeDanmakuCacheRow({
    required this.id,
    required this.sourceName,
    required this.episode,
    required this.commentsJson,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['source_name'] = Variable<String>(sourceName);
    map['episode'] = Variable<int>(episode);
    map['comments_json'] = Variable<String>(commentsJson);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  AnimeDanmakuCacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return AnimeDanmakuCacheEntriesCompanion(
      id: Value(id),
      sourceName: Value(sourceName),
      episode: Value(episode),
      commentsJson: Value(commentsJson),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory AnimeDanmakuCacheRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AnimeDanmakuCacheRow(
      id: serializer.fromJson<String>(json['id']),
      sourceName: serializer.fromJson<String>(json['sourceName']),
      episode: serializer.fromJson<int>(json['episode']),
      commentsJson: serializer.fromJson<String>(json['commentsJson']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sourceName': serializer.toJson<String>(sourceName),
      'episode': serializer.toJson<int>(episode),
      'commentsJson': serializer.toJson<String>(commentsJson),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  AnimeDanmakuCacheRow copyWith({
    String? id,
    String? sourceName,
    int? episode,
    String? commentsJson,
    DateTime? fetchedAt,
  }) => AnimeDanmakuCacheRow(
    id: id ?? this.id,
    sourceName: sourceName ?? this.sourceName,
    episode: episode ?? this.episode,
    commentsJson: commentsJson ?? this.commentsJson,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  AnimeDanmakuCacheRow copyWithCompanion(
    AnimeDanmakuCacheEntriesCompanion data,
  ) {
    return AnimeDanmakuCacheRow(
      id: data.id.present ? data.id.value : this.id,
      sourceName: data.sourceName.present
          ? data.sourceName.value
          : this.sourceName,
      episode: data.episode.present ? data.episode.value : this.episode,
      commentsJson: data.commentsJson.present
          ? data.commentsJson.value
          : this.commentsJson,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AnimeDanmakuCacheRow(')
          ..write('id: $id, ')
          ..write('sourceName: $sourceName, ')
          ..write('episode: $episode, ')
          ..write('commentsJson: $commentsJson, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, sourceName, episode, commentsJson, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AnimeDanmakuCacheRow &&
          other.id == this.id &&
          other.sourceName == this.sourceName &&
          other.episode == this.episode &&
          other.commentsJson == this.commentsJson &&
          other.fetchedAt == this.fetchedAt);
}

class AnimeDanmakuCacheEntriesCompanion
    extends UpdateCompanion<AnimeDanmakuCacheRow> {
  final Value<String> id;
  final Value<String> sourceName;
  final Value<int> episode;
  final Value<String> commentsJson;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const AnimeDanmakuCacheEntriesCompanion({
    this.id = const Value.absent(),
    this.sourceName = const Value.absent(),
    this.episode = const Value.absent(),
    this.commentsJson = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AnimeDanmakuCacheEntriesCompanion.insert({
    required String id,
    required String sourceName,
    required int episode,
    required String commentsJson,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sourceName = Value(sourceName),
       episode = Value(episode),
       commentsJson = Value(commentsJson),
       fetchedAt = Value(fetchedAt);
  static Insertable<AnimeDanmakuCacheRow> custom({
    Expression<String>? id,
    Expression<String>? sourceName,
    Expression<int>? episode,
    Expression<String>? commentsJson,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceName != null) 'source_name': sourceName,
      if (episode != null) 'episode': episode,
      if (commentsJson != null) 'comments_json': commentsJson,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AnimeDanmakuCacheEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? sourceName,
    Value<int>? episode,
    Value<String>? commentsJson,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return AnimeDanmakuCacheEntriesCompanion(
      id: id ?? this.id,
      sourceName: sourceName ?? this.sourceName,
      episode: episode ?? this.episode,
      commentsJson: commentsJson ?? this.commentsJson,
      fetchedAt: fetchedAt ?? this.fetchedAt,
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
    if (episode.present) {
      map['episode'] = Variable<int>(episode.value);
    }
    if (commentsJson.present) {
      map['comments_json'] = Variable<String>(commentsJson.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AnimeDanmakuCacheEntriesCompanion(')
          ..write('id: $id, ')
          ..write('sourceName: $sourceName, ')
          ..write('episode: $episode, ')
          ..write('commentsJson: $commentsJson, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AnimeDb extends GeneratedDatabase {
  _$AnimeDb(QueryExecutor e) : super(e);
  $AnimeDbManager get managers => $AnimeDbManager(this);
  late final $AnimeCollectEntriesTable animeCollectEntries =
      $AnimeCollectEntriesTable(this);
  late final $AnimeHistoryEntriesTable animeHistoryEntries =
      $AnimeHistoryEntriesTable(this);
  late final $AnimeSearchTermsTable animeSearchTerms = $AnimeSearchTermsTable(
    this,
  );
  late final $AnimeDanmakuCacheEntriesTable animeDanmakuCacheEntries =
      $AnimeDanmakuCacheEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    animeCollectEntries,
    animeHistoryEntries,
    animeSearchTerms,
    animeDanmakuCacheEntries,
  ];
}

typedef $$AnimeCollectEntriesTableCreateCompanionBuilder =
    AnimeCollectEntriesCompanion Function({
      required String id,
      required String sourceName,
      required String title,
      Value<String?> coverUrl,
      Value<String> payload,
      required DateTime collectedAt,
      Value<int> rowid,
    });
typedef $$AnimeCollectEntriesTableUpdateCompanionBuilder =
    AnimeCollectEntriesCompanion Function({
      Value<String> id,
      Value<String> sourceName,
      Value<String> title,
      Value<String?> coverUrl,
      Value<String> payload,
      Value<DateTime> collectedAt,
      Value<int> rowid,
    });

class $$AnimeCollectEntriesTableFilterComposer
    extends Composer<_$AnimeDb, $AnimeCollectEntriesTable> {
  $$AnimeCollectEntriesTableFilterComposer({
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

class $$AnimeCollectEntriesTableOrderingComposer
    extends Composer<_$AnimeDb, $AnimeCollectEntriesTable> {
  $$AnimeCollectEntriesTableOrderingComposer({
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

class $$AnimeCollectEntriesTableAnnotationComposer
    extends Composer<_$AnimeDb, $AnimeCollectEntriesTable> {
  $$AnimeCollectEntriesTableAnnotationComposer({
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

class $$AnimeCollectEntriesTableTableManager
    extends
        RootTableManager<
          _$AnimeDb,
          $AnimeCollectEntriesTable,
          AnimeCollectRow,
          $$AnimeCollectEntriesTableFilterComposer,
          $$AnimeCollectEntriesTableOrderingComposer,
          $$AnimeCollectEntriesTableAnnotationComposer,
          $$AnimeCollectEntriesTableCreateCompanionBuilder,
          $$AnimeCollectEntriesTableUpdateCompanionBuilder,
          (
            AnimeCollectRow,
            BaseReferences<
              _$AnimeDb,
              $AnimeCollectEntriesTable,
              AnimeCollectRow
            >,
          ),
          AnimeCollectRow,
          PrefetchHooks Function()
        > {
  $$AnimeCollectEntriesTableTableManager(
    _$AnimeDb db,
    $AnimeCollectEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AnimeCollectEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AnimeCollectEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AnimeCollectEntriesTableAnnotationComposer(
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
              }) => AnimeCollectEntriesCompanion(
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
              }) => AnimeCollectEntriesCompanion.insert(
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

typedef $$AnimeCollectEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AnimeDb,
      $AnimeCollectEntriesTable,
      AnimeCollectRow,
      $$AnimeCollectEntriesTableFilterComposer,
      $$AnimeCollectEntriesTableOrderingComposer,
      $$AnimeCollectEntriesTableAnnotationComposer,
      $$AnimeCollectEntriesTableCreateCompanionBuilder,
      $$AnimeCollectEntriesTableUpdateCompanionBuilder,
      (
        AnimeCollectRow,
        BaseReferences<_$AnimeDb, $AnimeCollectEntriesTable, AnimeCollectRow>,
      ),
      AnimeCollectRow,
      PrefetchHooks Function()
    >;
typedef $$AnimeHistoryEntriesTableCreateCompanionBuilder =
    AnimeHistoryEntriesCompanion Function({
      required String id,
      required String sourceName,
      required String title,
      Value<String?> coverUrl,
      Value<int> episode,
      Value<int> positionSec,
      Value<int> durationSec,
      required DateTime openedAt,
      Value<int> rowid,
    });
typedef $$AnimeHistoryEntriesTableUpdateCompanionBuilder =
    AnimeHistoryEntriesCompanion Function({
      Value<String> id,
      Value<String> sourceName,
      Value<String> title,
      Value<String?> coverUrl,
      Value<int> episode,
      Value<int> positionSec,
      Value<int> durationSec,
      Value<DateTime> openedAt,
      Value<int> rowid,
    });

class $$AnimeHistoryEntriesTableFilterComposer
    extends Composer<_$AnimeDb, $AnimeHistoryEntriesTable> {
  $$AnimeHistoryEntriesTableFilterComposer({
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

  ColumnFilters<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionSec => $composableBuilder(
    column: $table.positionSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AnimeHistoryEntriesTableOrderingComposer
    extends Composer<_$AnimeDb, $AnimeHistoryEntriesTable> {
  $$AnimeHistoryEntriesTableOrderingComposer({
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

  ColumnOrderings<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionSec => $composableBuilder(
    column: $table.positionSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AnimeHistoryEntriesTableAnnotationComposer
    extends Composer<_$AnimeDb, $AnimeHistoryEntriesTable> {
  $$AnimeHistoryEntriesTableAnnotationComposer({
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

  GeneratedColumn<int> get episode =>
      $composableBuilder(column: $table.episode, builder: (column) => column);

  GeneratedColumn<int> get positionSec => $composableBuilder(
    column: $table.positionSec,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationSec => $composableBuilder(
    column: $table.durationSec,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get openedAt =>
      $composableBuilder(column: $table.openedAt, builder: (column) => column);
}

class $$AnimeHistoryEntriesTableTableManager
    extends
        RootTableManager<
          _$AnimeDb,
          $AnimeHistoryEntriesTable,
          AnimeHistoryRow,
          $$AnimeHistoryEntriesTableFilterComposer,
          $$AnimeHistoryEntriesTableOrderingComposer,
          $$AnimeHistoryEntriesTableAnnotationComposer,
          $$AnimeHistoryEntriesTableCreateCompanionBuilder,
          $$AnimeHistoryEntriesTableUpdateCompanionBuilder,
          (
            AnimeHistoryRow,
            BaseReferences<
              _$AnimeDb,
              $AnimeHistoryEntriesTable,
              AnimeHistoryRow
            >,
          ),
          AnimeHistoryRow,
          PrefetchHooks Function()
        > {
  $$AnimeHistoryEntriesTableTableManager(
    _$AnimeDb db,
    $AnimeHistoryEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AnimeHistoryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AnimeHistoryEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AnimeHistoryEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sourceName = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> coverUrl = const Value.absent(),
                Value<int> episode = const Value.absent(),
                Value<int> positionSec = const Value.absent(),
                Value<int> durationSec = const Value.absent(),
                Value<DateTime> openedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AnimeHistoryEntriesCompanion(
                id: id,
                sourceName: sourceName,
                title: title,
                coverUrl: coverUrl,
                episode: episode,
                positionSec: positionSec,
                durationSec: durationSec,
                openedAt: openedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sourceName,
                required String title,
                Value<String?> coverUrl = const Value.absent(),
                Value<int> episode = const Value.absent(),
                Value<int> positionSec = const Value.absent(),
                Value<int> durationSec = const Value.absent(),
                required DateTime openedAt,
                Value<int> rowid = const Value.absent(),
              }) => AnimeHistoryEntriesCompanion.insert(
                id: id,
                sourceName: sourceName,
                title: title,
                coverUrl: coverUrl,
                episode: episode,
                positionSec: positionSec,
                durationSec: durationSec,
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

typedef $$AnimeHistoryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AnimeDb,
      $AnimeHistoryEntriesTable,
      AnimeHistoryRow,
      $$AnimeHistoryEntriesTableFilterComposer,
      $$AnimeHistoryEntriesTableOrderingComposer,
      $$AnimeHistoryEntriesTableAnnotationComposer,
      $$AnimeHistoryEntriesTableCreateCompanionBuilder,
      $$AnimeHistoryEntriesTableUpdateCompanionBuilder,
      (
        AnimeHistoryRow,
        BaseReferences<_$AnimeDb, $AnimeHistoryEntriesTable, AnimeHistoryRow>,
      ),
      AnimeHistoryRow,
      PrefetchHooks Function()
    >;
typedef $$AnimeSearchTermsTableCreateCompanionBuilder =
    AnimeSearchTermsCompanion Function({
      required String term,
      required DateTime lastUsedAt,
      Value<int> rowid,
    });
typedef $$AnimeSearchTermsTableUpdateCompanionBuilder =
    AnimeSearchTermsCompanion Function({
      Value<String> term,
      Value<DateTime> lastUsedAt,
      Value<int> rowid,
    });

class $$AnimeSearchTermsTableFilterComposer
    extends Composer<_$AnimeDb, $AnimeSearchTermsTable> {
  $$AnimeSearchTermsTableFilterComposer({
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

class $$AnimeSearchTermsTableOrderingComposer
    extends Composer<_$AnimeDb, $AnimeSearchTermsTable> {
  $$AnimeSearchTermsTableOrderingComposer({
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

class $$AnimeSearchTermsTableAnnotationComposer
    extends Composer<_$AnimeDb, $AnimeSearchTermsTable> {
  $$AnimeSearchTermsTableAnnotationComposer({
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

class $$AnimeSearchTermsTableTableManager
    extends
        RootTableManager<
          _$AnimeDb,
          $AnimeSearchTermsTable,
          AnimeSearchTermRow,
          $$AnimeSearchTermsTableFilterComposer,
          $$AnimeSearchTermsTableOrderingComposer,
          $$AnimeSearchTermsTableAnnotationComposer,
          $$AnimeSearchTermsTableCreateCompanionBuilder,
          $$AnimeSearchTermsTableUpdateCompanionBuilder,
          (
            AnimeSearchTermRow,
            BaseReferences<
              _$AnimeDb,
              $AnimeSearchTermsTable,
              AnimeSearchTermRow
            >,
          ),
          AnimeSearchTermRow,
          PrefetchHooks Function()
        > {
  $$AnimeSearchTermsTableTableManager(
    _$AnimeDb db,
    $AnimeSearchTermsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AnimeSearchTermsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AnimeSearchTermsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AnimeSearchTermsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> term = const Value.absent(),
                Value<DateTime> lastUsedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AnimeSearchTermsCompanion(
                term: term,
                lastUsedAt: lastUsedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String term,
                required DateTime lastUsedAt,
                Value<int> rowid = const Value.absent(),
              }) => AnimeSearchTermsCompanion.insert(
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

typedef $$AnimeSearchTermsTableProcessedTableManager =
    ProcessedTableManager<
      _$AnimeDb,
      $AnimeSearchTermsTable,
      AnimeSearchTermRow,
      $$AnimeSearchTermsTableFilterComposer,
      $$AnimeSearchTermsTableOrderingComposer,
      $$AnimeSearchTermsTableAnnotationComposer,
      $$AnimeSearchTermsTableCreateCompanionBuilder,
      $$AnimeSearchTermsTableUpdateCompanionBuilder,
      (
        AnimeSearchTermRow,
        BaseReferences<_$AnimeDb, $AnimeSearchTermsTable, AnimeSearchTermRow>,
      ),
      AnimeSearchTermRow,
      PrefetchHooks Function()
    >;
typedef $$AnimeDanmakuCacheEntriesTableCreateCompanionBuilder =
    AnimeDanmakuCacheEntriesCompanion Function({
      required String id,
      required String sourceName,
      required int episode,
      required String commentsJson,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$AnimeDanmakuCacheEntriesTableUpdateCompanionBuilder =
    AnimeDanmakuCacheEntriesCompanion Function({
      Value<String> id,
      Value<String> sourceName,
      Value<int> episode,
      Value<String> commentsJson,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$AnimeDanmakuCacheEntriesTableFilterComposer
    extends Composer<_$AnimeDb, $AnimeDanmakuCacheEntriesTable> {
  $$AnimeDanmakuCacheEntriesTableFilterComposer({
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

  ColumnFilters<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get commentsJson => $composableBuilder(
    column: $table.commentsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AnimeDanmakuCacheEntriesTableOrderingComposer
    extends Composer<_$AnimeDb, $AnimeDanmakuCacheEntriesTable> {
  $$AnimeDanmakuCacheEntriesTableOrderingComposer({
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

  ColumnOrderings<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get commentsJson => $composableBuilder(
    column: $table.commentsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AnimeDanmakuCacheEntriesTableAnnotationComposer
    extends Composer<_$AnimeDb, $AnimeDanmakuCacheEntriesTable> {
  $$AnimeDanmakuCacheEntriesTableAnnotationComposer({
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

  GeneratedColumn<int> get episode =>
      $composableBuilder(column: $table.episode, builder: (column) => column);

  GeneratedColumn<String> get commentsJson => $composableBuilder(
    column: $table.commentsJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$AnimeDanmakuCacheEntriesTableTableManager
    extends
        RootTableManager<
          _$AnimeDb,
          $AnimeDanmakuCacheEntriesTable,
          AnimeDanmakuCacheRow,
          $$AnimeDanmakuCacheEntriesTableFilterComposer,
          $$AnimeDanmakuCacheEntriesTableOrderingComposer,
          $$AnimeDanmakuCacheEntriesTableAnnotationComposer,
          $$AnimeDanmakuCacheEntriesTableCreateCompanionBuilder,
          $$AnimeDanmakuCacheEntriesTableUpdateCompanionBuilder,
          (
            AnimeDanmakuCacheRow,
            BaseReferences<
              _$AnimeDb,
              $AnimeDanmakuCacheEntriesTable,
              AnimeDanmakuCacheRow
            >,
          ),
          AnimeDanmakuCacheRow,
          PrefetchHooks Function()
        > {
  $$AnimeDanmakuCacheEntriesTableTableManager(
    _$AnimeDb db,
    $AnimeDanmakuCacheEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AnimeDanmakuCacheEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$AnimeDanmakuCacheEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AnimeDanmakuCacheEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sourceName = const Value.absent(),
                Value<int> episode = const Value.absent(),
                Value<String> commentsJson = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AnimeDanmakuCacheEntriesCompanion(
                id: id,
                sourceName: sourceName,
                episode: episode,
                commentsJson: commentsJson,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sourceName,
                required int episode,
                required String commentsJson,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => AnimeDanmakuCacheEntriesCompanion.insert(
                id: id,
                sourceName: sourceName,
                episode: episode,
                commentsJson: commentsJson,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AnimeDanmakuCacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AnimeDb,
      $AnimeDanmakuCacheEntriesTable,
      AnimeDanmakuCacheRow,
      $$AnimeDanmakuCacheEntriesTableFilterComposer,
      $$AnimeDanmakuCacheEntriesTableOrderingComposer,
      $$AnimeDanmakuCacheEntriesTableAnnotationComposer,
      $$AnimeDanmakuCacheEntriesTableCreateCompanionBuilder,
      $$AnimeDanmakuCacheEntriesTableUpdateCompanionBuilder,
      (
        AnimeDanmakuCacheRow,
        BaseReferences<
          _$AnimeDb,
          $AnimeDanmakuCacheEntriesTable,
          AnimeDanmakuCacheRow
        >,
      ),
      AnimeDanmakuCacheRow,
      PrefetchHooks Function()
    >;

class $AnimeDbManager {
  final _$AnimeDb _db;
  $AnimeDbManager(this._db);
  $$AnimeCollectEntriesTableTableManager get animeCollectEntries =>
      $$AnimeCollectEntriesTableTableManager(_db, _db.animeCollectEntries);
  $$AnimeHistoryEntriesTableTableManager get animeHistoryEntries =>
      $$AnimeHistoryEntriesTableTableManager(_db, _db.animeHistoryEntries);
  $$AnimeSearchTermsTableTableManager get animeSearchTerms =>
      $$AnimeSearchTermsTableTableManager(_db, _db.animeSearchTerms);
  $$AnimeDanmakuCacheEntriesTableTableManager get animeDanmakuCacheEntries =>
      $$AnimeDanmakuCacheEntriesTableTableManager(
        _db,
        _db.animeDanmakuCacheEntries,
      );
}
