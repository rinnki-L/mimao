// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'music_db.dart';

// ignore_for_file: type=lint
class $MusicCollectEntriesTable extends MusicCollectEntries
    with TableInfo<$MusicCollectEntriesTable, MusicCollectRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MusicCollectEntriesTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'music_collect';
  @override
  VerificationContext validateIntegrity(
    Insertable<MusicCollectRow> instance, {
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
  MusicCollectRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MusicCollectRow(
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
  $MusicCollectEntriesTable createAlias(String alias) {
    return $MusicCollectEntriesTable(attachedDatabase, alias);
  }
}

class MusicCollectRow extends DataClass implements Insertable<MusicCollectRow> {
  /// `MusicSong.id`（缺省时由 `musicRefOf` 回退到 hash）。
  final String id;
  final String title;
  final String? coverUrl;

  /// 歌曲 JSON（完整 `MusicSong.toJson`）；投影里的 payload 是进度摘要，
  /// 不是这一列。
  final String payload;
  final DateTime collectedAt;
  const MusicCollectRow({
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

  MusicCollectEntriesCompanion toCompanion(bool nullToAbsent) {
    return MusicCollectEntriesCompanion(
      id: Value(id),
      title: Value(title),
      coverUrl: coverUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(coverUrl),
      payload: Value(payload),
      collectedAt: Value(collectedAt),
    );
  }

  factory MusicCollectRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MusicCollectRow(
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

  MusicCollectRow copyWith({
    String? id,
    String? title,
    Value<String?> coverUrl = const Value.absent(),
    String? payload,
    DateTime? collectedAt,
  }) => MusicCollectRow(
    id: id ?? this.id,
    title: title ?? this.title,
    coverUrl: coverUrl.present ? coverUrl.value : this.coverUrl,
    payload: payload ?? this.payload,
    collectedAt: collectedAt ?? this.collectedAt,
  );
  MusicCollectRow copyWithCompanion(MusicCollectEntriesCompanion data) {
    return MusicCollectRow(
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
    return (StringBuffer('MusicCollectRow(')
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
      (other is MusicCollectRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.coverUrl == this.coverUrl &&
          other.payload == this.payload &&
          other.collectedAt == this.collectedAt);
}

class MusicCollectEntriesCompanion extends UpdateCompanion<MusicCollectRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> coverUrl;
  final Value<String> payload;
  final Value<DateTime> collectedAt;
  final Value<int> rowid;
  const MusicCollectEntriesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.payload = const Value.absent(),
    this.collectedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MusicCollectEntriesCompanion.insert({
    required String id,
    required String title,
    this.coverUrl = const Value.absent(),
    this.payload = const Value.absent(),
    required DateTime collectedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       collectedAt = Value(collectedAt);
  static Insertable<MusicCollectRow> custom({
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

  MusicCollectEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? coverUrl,
    Value<String>? payload,
    Value<DateTime>? collectedAt,
    Value<int>? rowid,
  }) {
    return MusicCollectEntriesCompanion(
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
    return (StringBuffer('MusicCollectEntriesCompanion(')
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

class $MusicHistoryEntriesTable extends MusicHistoryEntries
    with TableInfo<$MusicHistoryEntriesTable, MusicHistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MusicHistoryEntriesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _positionMsMeta = const VerificationMeta(
    'positionMs',
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
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
  static const VerificationMeta _playCountMeta = const VerificationMeta(
    'playCount',
  );
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
    'play_count',
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
    positionMs,
    durationMs,
    openedAt,
    playCount,
    payload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'music_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<MusicHistoryRow> instance, {
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
    if (data.containsKey('position_ms')) {
      context.handle(
        _positionMsMeta,
        positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
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
    if (data.containsKey('play_count')) {
      context.handle(
        _playCountMeta,
        playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta),
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
  MusicHistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MusicHistoryRow(
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
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      openedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}opened_at'],
      )!,
      playCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}play_count'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $MusicHistoryEntriesTable createAlias(String alias) {
    return $MusicHistoryEntriesTable(attachedDatabase, alias);
  }
}

class MusicHistoryRow extends DataClass implements Insertable<MusicHistoryRow> {
  final String id;
  final String title;
  final String? coverUrl;
  final int positionMs;
  final int durationMs;
  final DateTime openedAt;
  final int playCount;

  /// 歌曲 JSON，历史续播据此重建 [MusicSong]。
  final String payload;
  const MusicHistoryRow({
    required this.id,
    required this.title,
    this.coverUrl,
    required this.positionMs,
    required this.durationMs,
    required this.openedAt,
    required this.playCount,
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
    map['position_ms'] = Variable<int>(positionMs);
    map['duration_ms'] = Variable<int>(durationMs);
    map['opened_at'] = Variable<DateTime>(openedAt);
    map['play_count'] = Variable<int>(playCount);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  MusicHistoryEntriesCompanion toCompanion(bool nullToAbsent) {
    return MusicHistoryEntriesCompanion(
      id: Value(id),
      title: Value(title),
      coverUrl: coverUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(coverUrl),
      positionMs: Value(positionMs),
      durationMs: Value(durationMs),
      openedAt: Value(openedAt),
      playCount: Value(playCount),
      payload: Value(payload),
    );
  }

  factory MusicHistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MusicHistoryRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      coverUrl: serializer.fromJson<String?>(json['coverUrl']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      openedAt: serializer.fromJson<DateTime>(json['openedAt']),
      playCount: serializer.fromJson<int>(json['playCount']),
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
      'positionMs': serializer.toJson<int>(positionMs),
      'durationMs': serializer.toJson<int>(durationMs),
      'openedAt': serializer.toJson<DateTime>(openedAt),
      'playCount': serializer.toJson<int>(playCount),
      'payload': serializer.toJson<String>(payload),
    };
  }

  MusicHistoryRow copyWith({
    String? id,
    String? title,
    Value<String?> coverUrl = const Value.absent(),
    int? positionMs,
    int? durationMs,
    DateTime? openedAt,
    int? playCount,
    String? payload,
  }) => MusicHistoryRow(
    id: id ?? this.id,
    title: title ?? this.title,
    coverUrl: coverUrl.present ? coverUrl.value : this.coverUrl,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs ?? this.durationMs,
    openedAt: openedAt ?? this.openedAt,
    playCount: playCount ?? this.playCount,
    payload: payload ?? this.payload,
  );
  MusicHistoryRow copyWithCompanion(MusicHistoryEntriesCompanion data) {
    return MusicHistoryRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      coverUrl: data.coverUrl.present ? data.coverUrl.value : this.coverUrl,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      openedAt: data.openedAt.present ? data.openedAt.value : this.openedAt,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MusicHistoryRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('openedAt: $openedAt, ')
          ..write('playCount: $playCount, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    coverUrl,
    positionMs,
    durationMs,
    openedAt,
    playCount,
    payload,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MusicHistoryRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.coverUrl == this.coverUrl &&
          other.positionMs == this.positionMs &&
          other.durationMs == this.durationMs &&
          other.openedAt == this.openedAt &&
          other.playCount == this.playCount &&
          other.payload == this.payload);
}

class MusicHistoryEntriesCompanion extends UpdateCompanion<MusicHistoryRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> coverUrl;
  final Value<int> positionMs;
  final Value<int> durationMs;
  final Value<DateTime> openedAt;
  final Value<int> playCount;
  final Value<String> payload;
  final Value<int> rowid;
  const MusicHistoryEntriesCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.coverUrl = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.openedAt = const Value.absent(),
    this.playCount = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MusicHistoryEntriesCompanion.insert({
    required String id,
    required String title,
    this.coverUrl = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    required DateTime openedAt,
    this.playCount = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       openedAt = Value(openedAt);
  static Insertable<MusicHistoryRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? coverUrl,
    Expression<int>? positionMs,
    Expression<int>? durationMs,
    Expression<DateTime>? openedAt,
    Expression<int>? playCount,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (coverUrl != null) 'cover_url': coverUrl,
      if (positionMs != null) 'position_ms': positionMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (openedAt != null) 'opened_at': openedAt,
      if (playCount != null) 'play_count': playCount,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MusicHistoryEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? coverUrl,
    Value<int>? positionMs,
    Value<int>? durationMs,
    Value<DateTime>? openedAt,
    Value<int>? playCount,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return MusicHistoryEntriesCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      openedAt: openedAt ?? this.openedAt,
      playCount: playCount ?? this.playCount,
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
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (openedAt.present) {
      map['opened_at'] = Variable<DateTime>(openedAt.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
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
    return (StringBuffer('MusicHistoryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('coverUrl: $coverUrl, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('openedAt: $openedAt, ')
          ..write('playCount: $playCount, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MusicSearchTermsTable extends MusicSearchTerms
    with TableInfo<$MusicSearchTermsTable, MusicSearchTermRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MusicSearchTermsTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'music_search_term';
  @override
  VerificationContext validateIntegrity(
    Insertable<MusicSearchTermRow> instance, {
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
  MusicSearchTermRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MusicSearchTermRow(
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
  $MusicSearchTermsTable createAlias(String alias) {
    return $MusicSearchTermsTable(attachedDatabase, alias);
  }
}

class MusicSearchTermRow extends DataClass
    implements Insertable<MusicSearchTermRow> {
  final String keyword;
  final DateTime searchedAt;
  final int hits;
  const MusicSearchTermRow({
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

  MusicSearchTermsCompanion toCompanion(bool nullToAbsent) {
    return MusicSearchTermsCompanion(
      keyword: Value(keyword),
      searchedAt: Value(searchedAt),
      hits: Value(hits),
    );
  }

  factory MusicSearchTermRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MusicSearchTermRow(
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

  MusicSearchTermRow copyWith({
    String? keyword,
    DateTime? searchedAt,
    int? hits,
  }) => MusicSearchTermRow(
    keyword: keyword ?? this.keyword,
    searchedAt: searchedAt ?? this.searchedAt,
    hits: hits ?? this.hits,
  );
  MusicSearchTermRow copyWithCompanion(MusicSearchTermsCompanion data) {
    return MusicSearchTermRow(
      keyword: data.keyword.present ? data.keyword.value : this.keyword,
      searchedAt: data.searchedAt.present
          ? data.searchedAt.value
          : this.searchedAt,
      hits: data.hits.present ? data.hits.value : this.hits,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MusicSearchTermRow(')
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
      (other is MusicSearchTermRow &&
          other.keyword == this.keyword &&
          other.searchedAt == this.searchedAt &&
          other.hits == this.hits);
}

class MusicSearchTermsCompanion extends UpdateCompanion<MusicSearchTermRow> {
  final Value<String> keyword;
  final Value<DateTime> searchedAt;
  final Value<int> hits;
  final Value<int> rowid;
  const MusicSearchTermsCompanion({
    this.keyword = const Value.absent(),
    this.searchedAt = const Value.absent(),
    this.hits = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MusicSearchTermsCompanion.insert({
    required String keyword,
    required DateTime searchedAt,
    this.hits = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : keyword = Value(keyword),
       searchedAt = Value(searchedAt);
  static Insertable<MusicSearchTermRow> custom({
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

  MusicSearchTermsCompanion copyWith({
    Value<String>? keyword,
    Value<DateTime>? searchedAt,
    Value<int>? hits,
    Value<int>? rowid,
  }) {
    return MusicSearchTermsCompanion(
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
    return (StringBuffer('MusicSearchTermsCompanion(')
          ..write('keyword: $keyword, ')
          ..write('searchedAt: $searchedAt, ')
          ..write('hits: $hits, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$MusicDb extends GeneratedDatabase {
  _$MusicDb(QueryExecutor e) : super(e);
  $MusicDbManager get managers => $MusicDbManager(this);
  late final $MusicCollectEntriesTable musicCollectEntries =
      $MusicCollectEntriesTable(this);
  late final $MusicHistoryEntriesTable musicHistoryEntries =
      $MusicHistoryEntriesTable(this);
  late final $MusicSearchTermsTable musicSearchTerms = $MusicSearchTermsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    musicCollectEntries,
    musicHistoryEntries,
    musicSearchTerms,
  ];
}

typedef $$MusicCollectEntriesTableCreateCompanionBuilder =
    MusicCollectEntriesCompanion Function({
      required String id,
      required String title,
      Value<String?> coverUrl,
      Value<String> payload,
      required DateTime collectedAt,
      Value<int> rowid,
    });
typedef $$MusicCollectEntriesTableUpdateCompanionBuilder =
    MusicCollectEntriesCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> coverUrl,
      Value<String> payload,
      Value<DateTime> collectedAt,
      Value<int> rowid,
    });

class $$MusicCollectEntriesTableFilterComposer
    extends Composer<_$MusicDb, $MusicCollectEntriesTable> {
  $$MusicCollectEntriesTableFilterComposer({
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

class $$MusicCollectEntriesTableOrderingComposer
    extends Composer<_$MusicDb, $MusicCollectEntriesTable> {
  $$MusicCollectEntriesTableOrderingComposer({
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

class $$MusicCollectEntriesTableAnnotationComposer
    extends Composer<_$MusicDb, $MusicCollectEntriesTable> {
  $$MusicCollectEntriesTableAnnotationComposer({
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

class $$MusicCollectEntriesTableTableManager
    extends
        RootTableManager<
          _$MusicDb,
          $MusicCollectEntriesTable,
          MusicCollectRow,
          $$MusicCollectEntriesTableFilterComposer,
          $$MusicCollectEntriesTableOrderingComposer,
          $$MusicCollectEntriesTableAnnotationComposer,
          $$MusicCollectEntriesTableCreateCompanionBuilder,
          $$MusicCollectEntriesTableUpdateCompanionBuilder,
          (
            MusicCollectRow,
            BaseReferences<
              _$MusicDb,
              $MusicCollectEntriesTable,
              MusicCollectRow
            >,
          ),
          MusicCollectRow,
          PrefetchHooks Function()
        > {
  $$MusicCollectEntriesTableTableManager(
    _$MusicDb db,
    $MusicCollectEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MusicCollectEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MusicCollectEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$MusicCollectEntriesTableAnnotationComposer(
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
              }) => MusicCollectEntriesCompanion(
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
              }) => MusicCollectEntriesCompanion.insert(
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

typedef $$MusicCollectEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$MusicDb,
      $MusicCollectEntriesTable,
      MusicCollectRow,
      $$MusicCollectEntriesTableFilterComposer,
      $$MusicCollectEntriesTableOrderingComposer,
      $$MusicCollectEntriesTableAnnotationComposer,
      $$MusicCollectEntriesTableCreateCompanionBuilder,
      $$MusicCollectEntriesTableUpdateCompanionBuilder,
      (
        MusicCollectRow,
        BaseReferences<_$MusicDb, $MusicCollectEntriesTable, MusicCollectRow>,
      ),
      MusicCollectRow,
      PrefetchHooks Function()
    >;
typedef $$MusicHistoryEntriesTableCreateCompanionBuilder =
    MusicHistoryEntriesCompanion Function({
      required String id,
      required String title,
      Value<String?> coverUrl,
      Value<int> positionMs,
      Value<int> durationMs,
      required DateTime openedAt,
      Value<int> playCount,
      Value<String> payload,
      Value<int> rowid,
    });
typedef $$MusicHistoryEntriesTableUpdateCompanionBuilder =
    MusicHistoryEntriesCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> coverUrl,
      Value<int> positionMs,
      Value<int> durationMs,
      Value<DateTime> openedAt,
      Value<int> playCount,
      Value<String> payload,
      Value<int> rowid,
    });

class $$MusicHistoryEntriesTableFilterComposer
    extends Composer<_$MusicDb, $MusicHistoryEntriesTable> {
  $$MusicHistoryEntriesTableFilterComposer({
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

  ColumnFilters<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MusicHistoryEntriesTableOrderingComposer
    extends Composer<_$MusicDb, $MusicHistoryEntriesTable> {
  $$MusicHistoryEntriesTableOrderingComposer({
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

  ColumnOrderings<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MusicHistoryEntriesTableAnnotationComposer
    extends Composer<_$MusicDb, $MusicHistoryEntriesTable> {
  $$MusicHistoryEntriesTableAnnotationComposer({
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

  GeneratedColumn<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get openedAt =>
      $composableBuilder(column: $table.openedAt, builder: (column) => column);

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$MusicHistoryEntriesTableTableManager
    extends
        RootTableManager<
          _$MusicDb,
          $MusicHistoryEntriesTable,
          MusicHistoryRow,
          $$MusicHistoryEntriesTableFilterComposer,
          $$MusicHistoryEntriesTableOrderingComposer,
          $$MusicHistoryEntriesTableAnnotationComposer,
          $$MusicHistoryEntriesTableCreateCompanionBuilder,
          $$MusicHistoryEntriesTableUpdateCompanionBuilder,
          (
            MusicHistoryRow,
            BaseReferences<
              _$MusicDb,
              $MusicHistoryEntriesTable,
              MusicHistoryRow
            >,
          ),
          MusicHistoryRow,
          PrefetchHooks Function()
        > {
  $$MusicHistoryEntriesTableTableManager(
    _$MusicDb db,
    $MusicHistoryEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MusicHistoryEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MusicHistoryEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$MusicHistoryEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> coverUrl = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<DateTime> openedAt = const Value.absent(),
                Value<int> playCount = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MusicHistoryEntriesCompanion(
                id: id,
                title: title,
                coverUrl: coverUrl,
                positionMs: positionMs,
                durationMs: durationMs,
                openedAt: openedAt,
                playCount: playCount,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> coverUrl = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                required DateTime openedAt,
                Value<int> playCount = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MusicHistoryEntriesCompanion.insert(
                id: id,
                title: title,
                coverUrl: coverUrl,
                positionMs: positionMs,
                durationMs: durationMs,
                openedAt: openedAt,
                playCount: playCount,
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

typedef $$MusicHistoryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$MusicDb,
      $MusicHistoryEntriesTable,
      MusicHistoryRow,
      $$MusicHistoryEntriesTableFilterComposer,
      $$MusicHistoryEntriesTableOrderingComposer,
      $$MusicHistoryEntriesTableAnnotationComposer,
      $$MusicHistoryEntriesTableCreateCompanionBuilder,
      $$MusicHistoryEntriesTableUpdateCompanionBuilder,
      (
        MusicHistoryRow,
        BaseReferences<_$MusicDb, $MusicHistoryEntriesTable, MusicHistoryRow>,
      ),
      MusicHistoryRow,
      PrefetchHooks Function()
    >;
typedef $$MusicSearchTermsTableCreateCompanionBuilder =
    MusicSearchTermsCompanion Function({
      required String keyword,
      required DateTime searchedAt,
      Value<int> hits,
      Value<int> rowid,
    });
typedef $$MusicSearchTermsTableUpdateCompanionBuilder =
    MusicSearchTermsCompanion Function({
      Value<String> keyword,
      Value<DateTime> searchedAt,
      Value<int> hits,
      Value<int> rowid,
    });

class $$MusicSearchTermsTableFilterComposer
    extends Composer<_$MusicDb, $MusicSearchTermsTable> {
  $$MusicSearchTermsTableFilterComposer({
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

class $$MusicSearchTermsTableOrderingComposer
    extends Composer<_$MusicDb, $MusicSearchTermsTable> {
  $$MusicSearchTermsTableOrderingComposer({
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

class $$MusicSearchTermsTableAnnotationComposer
    extends Composer<_$MusicDb, $MusicSearchTermsTable> {
  $$MusicSearchTermsTableAnnotationComposer({
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

class $$MusicSearchTermsTableTableManager
    extends
        RootTableManager<
          _$MusicDb,
          $MusicSearchTermsTable,
          MusicSearchTermRow,
          $$MusicSearchTermsTableFilterComposer,
          $$MusicSearchTermsTableOrderingComposer,
          $$MusicSearchTermsTableAnnotationComposer,
          $$MusicSearchTermsTableCreateCompanionBuilder,
          $$MusicSearchTermsTableUpdateCompanionBuilder,
          (
            MusicSearchTermRow,
            BaseReferences<
              _$MusicDb,
              $MusicSearchTermsTable,
              MusicSearchTermRow
            >,
          ),
          MusicSearchTermRow,
          PrefetchHooks Function()
        > {
  $$MusicSearchTermsTableTableManager(
    _$MusicDb db,
    $MusicSearchTermsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MusicSearchTermsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MusicSearchTermsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MusicSearchTermsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> keyword = const Value.absent(),
                Value<DateTime> searchedAt = const Value.absent(),
                Value<int> hits = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MusicSearchTermsCompanion(
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
              }) => MusicSearchTermsCompanion.insert(
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

typedef $$MusicSearchTermsTableProcessedTableManager =
    ProcessedTableManager<
      _$MusicDb,
      $MusicSearchTermsTable,
      MusicSearchTermRow,
      $$MusicSearchTermsTableFilterComposer,
      $$MusicSearchTermsTableOrderingComposer,
      $$MusicSearchTermsTableAnnotationComposer,
      $$MusicSearchTermsTableCreateCompanionBuilder,
      $$MusicSearchTermsTableUpdateCompanionBuilder,
      (
        MusicSearchTermRow,
        BaseReferences<_$MusicDb, $MusicSearchTermsTable, MusicSearchTermRow>,
      ),
      MusicSearchTermRow,
      PrefetchHooks Function()
    >;

class $MusicDbManager {
  final _$MusicDb _db;
  $MusicDbManager(this._db);
  $$MusicCollectEntriesTableTableManager get musicCollectEntries =>
      $$MusicCollectEntriesTableTableManager(_db, _db.musicCollectEntries);
  $$MusicHistoryEntriesTableTableManager get musicHistoryEntries =>
      $$MusicHistoryEntriesTableTableManager(_db, _db.musicHistoryEntries);
  $$MusicSearchTermsTableTableManager get musicSearchTerms =>
      $$MusicSearchTermsTableTableManager(_db, _db.musicSearchTerms);
}
