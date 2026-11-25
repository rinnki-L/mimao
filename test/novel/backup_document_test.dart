// 备份文档 v2：编解码往返、v1 归一化、版本与格式校验、进度专用包裁剪。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/backup/backup_crypto.dart';
import 'package:mimao/novel/backup/backup_document.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/reader/novel_locator.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

void main() {
  test('v2 往返：各段都能原样解回', () {
    final doc = NovelBackupDocument(
      collects: <NovelBackupCollect>[
        NovelBackupCollect(
          book: _book('b1', '三体'),
          groupName: '科幻',
          note: '很好',
          seriesName: '三部曲',
          chapterIndex: 12,
          chapterCount: 400,
          updatedAt: DateTime.utc(2026, 11, 1),
        ),
      ],
      histories: <NovelBackupHistory>[
        NovelBackupHistory(
          book: _book('b1', '三体'),
          chapterIndex: 12,
          chapterCount: 400,
          readCount: 7,
          openedAt: DateTime.utc(2026, 11, 2),
        ),
      ],
      searchKeywords: const <String>['三体'],
      sources: <NovelBookSource>[_source('k1', '源甲')],
      prefs: <String, String>{novelPrefReaderSettings: '{"font":22}'},
      exportedAt: DateTime.utc(2026, 11, 25),
      deviceId: 'device-a',
      deviceName: 'Windows-PC',
      progress: <NovelBackupProgress>[
        NovelBackupProgress(
          bookId: 'b1',
          chapterIndex: 12,
          chapterCount: 400,
          locator: const NovelLocator(
            chapterIndex: 11,
            paragraph: 3,
            charOffset: 40,
          ),
          updatedAt: DateTime.utc(2026, 11, 2),
        ),
      ],
      series: const <NovelBackupSeries>[NovelBackupSeries(name: '三部曲')],
      bookmarks: <NovelBackupBookmark>[
        NovelBackupBookmark(
          bookId: 'b1',
          chapterIndex: 3,
          paragraph: 1,
          charOffset: 10,
          excerpt: '摘录',
          createdAt: DateTime.utc(2026, 11, 3),
        ),
      ],
      markings: <NovelBackupMarking>[
        NovelBackupMarking(
          bookId: 'b1',
          chapterIndex: 3,
          paragraph: 1,
          startOffset: 2,
          endOffset: 8,
          note: '笔记',
          styleJson: '{"color":4294967295,"decoration":"background"}',
          createdAt: DateTime.utc(2026, 11, 3),
          updatedAt: DateTime.utc(2026, 11, 4),
        ),
      ],
      readRecords: <NovelBackupReadRecord>[
        NovelBackupReadRecord(
          deviceId: 'device-a',
          bookId: 'b1',
          chapterIndex: 12,
          day: '2026-11-25',
          seconds: 600,
          firstReadAt: DateTime.utc(2026, 11, 25, 8),
          lastReadAt: DateTime.utc(2026, 11, 25, 9),
        ),
      ],
      tombstones: <NovelBackupTombstone>[
        NovelBackupTombstone(
          kind: novelTombstoneBookmark,
          key: 'b1||3|1|10|10',
          deviceId: 'device-a',
          deletedAt: DateTime.utc(2026, 11, 5),
        ),
      ],
    );

    final decoded = NovelBackupDocument.decode(doc.encode());

    expect(decoded.legacyV1, isFalse);
    expect(decoded.deviceId, 'device-a');
    expect(decoded.deviceName, 'Windows-PC');
    expect(decoded.collects.single.groupName, '科幻');
    expect(decoded.collects.single.note, '很好');
    expect(decoded.collects.single.seriesName, '三部曲');
    expect(decoded.histories.single.readCount, 7);
    expect(decoded.progress.single.locator?.paragraph, 3);
    expect(decoded.series.single.name, '三部曲');
    expect(decoded.bookmarks.single.excerpt, '摘录');
    expect(decoded.markings.single.contentSignature, contains('笔记'));
    expect(decoded.readRecords.single.seconds, 600);
    expect(decoded.tombstones.single.kind, novelTombstoneBookmark);
    expect(decoded.sources.single.name, '源甲');
    expect(decoded.prefs[novelPrefReaderSettings], '{"font":22}');
  });

  test('v1 文档：归一化成 v2，进度由收藏/历史合成、按本机设备导入', () {
    final legacy = jsonEncode(<String, Object?>{
      'format': novelBackupFormat,
      'version': 1,
      'exportedAt': '2026-11-01T00:00:00.000Z',
      'collects': <Object?>[
        <String, Object?>{
          'book': _book('b1', '三体').toJson(),
          'groupName': '科幻',
          'chapterIndex': 3,
          'chapterCount': 400,
        },
      ],
      'histories': <Object?>[
        <String, Object?>{
          'book': _book('b1', '三体').toJson(),
          'chapterIndex': 12,
          'chapterCount': 400,
          'openedAt': '2026-11-20T00:00:00.000Z',
        },
      ],
      'searchKeywords': <String>['三体'],
      'sources': <Object?>[_source('k1', '源甲').toJson()],
      'prefs': <String, Object?>{novelPrefGoalMinutes: '45'},
    });

    final doc = NovelBackupDocument.decode(legacy);

    expect(doc.legacyV1, isTrue);
    expect(doc.deviceId, isNull, reason: 'v1 没有设备维度，恢复时按本机设备落库');
    expect(doc.collects.single.groupName, '科幻');
    expect(doc.histories.single.chapterIndex, 12);
    // 进度合成：收藏给 3 章，历史给 12 章 → 取更大的 12，时间用历史的打开时间。
    expect(doc.progress.single.bookId, 'b1');
    expect(doc.progress.single.chapterIndex, 12);
    expect(doc.progress.single.updatedAt, DateTime.utc(2026, 11, 20));
    // v1 没有的段一律留空。
    expect(doc.bookmarks, isEmpty);
    expect(doc.markings, isEmpty);
    expect(doc.readRecords, isEmpty);
    expect(doc.tombstones, isEmpty);
  });

  test('进度专用包：只带 progress 段', () {
    final full = NovelBackupDocument(
      collects: <NovelBackupCollect>[
        NovelBackupCollect(book: _book('b1', '三体')),
      ],
      histories: const <NovelBackupHistory>[],
      searchKeywords: const <String>['三体'],
      sources: const <NovelBookSource>[],
      prefs: const <String, String>{novelPrefGoalMinutes: '45'},
      exportedAt: DateTime.utc(2026, 11, 25),
      deviceId: 'device-a',
      progress: <NovelBackupProgress>[
        NovelBackupProgress(bookId: 'b1', chapterIndex: 12),
      ],
    );
    final progressOnly = full.progressOnly();
    final json = jsonDecode(progressOnly.encode()) as Map<String, Object?>;
    expect(json['kind'], 'progress');
    expect(json['progress'], isA<List<Object?>>());
    expect(json.containsKey('collects'), isFalse);
    expect(json.containsKey('sources'), isFalse);
    expect(json.containsKey('prefs'), isFalse);

    final decoded = NovelBackupDocument.decode(progressOnly.encode());
    expect(decoded.kind, NovelBackupKind.progress);
    expect(decoded.progress.single.chapterIndex, 12);
    expect(decoded.collects, isEmpty);
  });

  test('拒绝未来版本', () {
    final json = jsonEncode(<String, Object?>{
      'format': novelBackupFormat,
      'version': novelBackupVersion + 1,
    });
    expect(
      () => NovelBackupDocument.decode(json),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('版本'),
        ),
      ),
    );
  });

  test('拒绝非 mimao 备份', () {
    expect(
      () => NovelBackupDocument.decode('{"format":"other","version":2}'),
      throwsFormatException,
    );
  });

  test('加密包走 parseNovelBackupBundle，不直接 decode', () {
    final encrypted = encryptNovelBackupText(
      NovelBackupDocument(
        collects: const <NovelBackupCollect>[],
        histories: const <NovelBackupHistory>[],
        searchKeywords: const <String>[],
        sources: const <NovelBookSource>[],
        prefs: const <String, String>{},
        exportedAt: DateTime.utc(2026, 11, 25),
      ).encode(),
      'pw',
      iterations: 500,
    );
    expect(
      () => NovelBackupDocument.decode(encrypted.encode()),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('密码'),
        ),
      ),
    );
  });

  test('坏条目单条跳过，不拖垮整包', () {
    final json = jsonEncode(<String, Object?>{
      'format': novelBackupFormat,
      'version': 2,
      'exportedAt': '2026-11-25T00:00:00.000Z',
      'collects': <Object?>[
        <String, Object?>{'book': _book('b1', '三体').toJson()},
        <String, Object?>{
          'book': <String, Object?>{'id': ''},
        },
        'not-a-map',
      ],
      'bookmarks': <Object?>[
        <String, Object?>{'chapterIndex': 1},
        <String, Object?>{'bookId': 'b1', 'chapterIndex': 2},
      ],
    });
    final doc = NovelBackupDocument.decode(json);
    expect(doc.collects, hasLength(1));
    expect(doc.bookmarks, hasLength(1));
  });
}

NovelSummary _book(String id, String title) =>
    NovelSummary(id: id, title: title, coverUrl: '');

NovelBookSource _source(String key, String name) => NovelBookSource(
  key: key,
  name: name,
  url: 'https://a.example',
  type: 0,
  enabled: true,
  raw: const <String, dynamic>{},
);
