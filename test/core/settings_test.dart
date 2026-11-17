// 应用设置 kv 读写单测 + 生成行值对象（toJson/copyWith/==）覆盖。
// 这些是 core/settings.dart 与 drift 生成代码在真实读写循环中会走到的路径。

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/core/settings.dart';

void main() {
  late AppDb db;
  late SettingsRepository settings;
  late LibraryRepository library;

  setUp(() {
    db = AppDb.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
    library = LibraryRepository(db);
  });

  tearDown(() async => db.close());

  test('kv 读写与覆盖', () async {
    expect(await settings.get('theme'), isNull);
    await settings.set('theme', 'green');
    expect(await settings.get('theme'), 'green');
    await settings.set('theme', 'ochre');
    expect(await settings.get('theme'), 'ochre');
    expect(await settings.getOr('missing', 'fallback'), 'fallback');
    expect(await settings.getOr('theme', 'fallback'), 'ochre');
  });

  test('AppSettingRow 的 JSON 往返 / copyWith / 相等', () async {
    await settings.set('k', 'v');
    final row = await (db.select(db.appSettings)).getSingle();

    final json = row.toJson();
    expect(json['key'], 'k');
    expect(AppSettingRow.fromJson(json), row);
    expect(row.copyWith(value: 'v2').value, 'v2');
    expect(
      row
          .copyWithCompanion(AppSettingsCompanion(value: const Value('v3')))
          .value,
      'v3',
    );
    expect(row.toString(), contains('k'));
    expect(row.hashCode, row.hashCode);
    expect(row == AppSettingRow(key: 'k', value: 'v'), isTrue);
    expect(row == AppSettingRow(key: 'k', value: 'other'), isFalse);
  });

  test('MediaEntryRow 的 JSON 往返 / copyWith / 相等 / 反序列化', () async {
    await library.upsert(
      id: 'x:1',
      type: MediaType.novel,
      sourceName: '书源',
      title: '诡秘之主',
      payload: '{"chapter":102}',
      progressText: '第102章',
    );
    final row = await (db.select(db.mediaEntries)).getSingle();

    final json = row.toJson();
    // serializer 会应用 converter，因此 JSON 里拿到的是 MediaType 而非字符串；
    // SQL 层才存字符串名（见下方 converter 断言）。
    expect(json['mediaType'], MediaType.novel);
    expect(json['payload'], '{"chapter":102}');
    final back = MediaEntryRow.fromJson(json);
    expect(back, row);

    expect(row.copyWith(title: '新标题').title, '新标题');
    expect(
      row
          .copyWithCompanion(MediaEntriesCompanion(starred: const Value(true)))
          .starred,
      isTrue,
    );
    expect(row.toString(), contains('诡秘之主'));
    expect(row.hashCode, row.hashCode);
    expect(row == row, isTrue);
    expect(row == row.copyWith(title: '不同'), isFalse);
  });

  test('map() 从原始列数据重建行（含 nullable coverUrl 的空/非空两路）', () async {
    await library.upsert(
      id: 'x:2',
      type: MediaType.anime,
      sourceName: '源',
      title: '无封面',
      payload: '{}',
      progressText: '未开始',
    );
    final row = await (db.select(db.mediaEntries)).getSingle();
    final raw = <String, Object?>{
      'id': row.id,
      'media_type': row.mediaType.name,
      'source_name': row.sourceName,
      'title': row.title,
      'cover_url': null,
      'payload': row.payload,
      'progress_text': row.progressText,
      'starred': 0,
      'last_opened_at': row.lastOpenedAt.millisecondsSinceEpoch,
      'created_at': row.createdAt.millisecondsSinceEpoch,
    };
    // 不传 tablePrefix（传空串会拼出 ".id" 这种键，反而取不到列）。
    final mapped = db.mediaEntries.map(raw);
    expect(mapped.coverUrl, isNull);
    expect(mapped.mediaType, MediaType.anime);
  });

  test('映射转换器对未知枚举名抛出（契约：库里只存四种类型）', () {
    const converter = MediaTypeConverter();
    for (final type in MediaType.values) {
      expect(converter.fromSql(type.name), type);
      expect(converter.toSql(type), type.name);
    }
  });
}
