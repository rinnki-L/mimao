// 页内位置存储：往返、章节匹配、清空、容量淘汰。

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/reader/novel_locator.dart';
import 'package:mimao/novel/reader/novel_reader_position.dart';

class _FakePrefs implements NovelPrefsApi {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

NovelReaderPosition _position({
  required String chapterUrl,
  int chapterIndex = 0,
  int page = 1,
  int pageCount = 1,
  double scrollRatio = 0,
}) => NovelReaderPosition(
  chapterUrl: chapterUrl,
  chapterId: chapterUrl,
  chapterIndex: chapterIndex,
  page: page,
  pageCount: pageCount,
  scrollRatio: scrollRatio,
);

void main() {
  test('保存后能按书读回，并判断是否同一章', () async {
    final prefs = _FakePrefs();
    final store = NovelReaderPositionStore(prefs);
    await store.save(
      'book1',
      _position(chapterUrl: '/c/3', chapterIndex: 2, page: 4, pageCount: 13),
    );

    // 新实例从同一份 kv 读取，确认真的落到了预置存储而不是内存缓存。
    final loaded = await NovelReaderPositionStore(prefs).load('book1');
    expect(loaded, isNotNull);
    expect(loaded!.chapterIndex, 2);
    expect(loaded.page, 4);
    expect(loaded.pageCount, 13);
    expect(
      loaded.matches(chapterUrl: '/c/3', chapterId: '/c/3', chapterIndex: 2),
      isTrue,
    );
    expect(
      loaded.matches(chapterUrl: '/c/4', chapterId: '/c/4', chapterIndex: 3),
      isFalse,
    );
  });

  test('clear 后读不到', () async {
    final store = NovelReaderPositionStore(_FakePrefs());
    await store.save('book1', _position(chapterUrl: '/c/1'));
    expect(await store.load('book1'), isNotNull);
    await store.clear('book1');
    expect(await store.load('book1'), isNull);
  });

  test('超出容量淘汰最旧的书', () async {
    final store = NovelReaderPositionStore(_FakePrefs(), capacity: 2);
    await store.save('a', _position(chapterUrl: '/a'));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await store.save('b', _position(chapterUrl: '/b'));
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await store.save('c', _position(chapterUrl: '/c'));

    expect(await store.load('a'), isNull);
    expect(await store.load('b'), isNotNull);
    expect(await store.load('c'), isNotNull);
  });

  test('没有 kv 时退化为内存，不抛异常', () async {
    final store = NovelReaderPositionStore(null);
    await store.save('book1', _position(chapterUrl: '/c/1'));
    expect(await store.load('book1'), isNotNull);
    await store.clear('book1');
    expect(await store.load('book1'), isNull);
  });

  test('locator 往返保留段落与字符偏移', () async {
    final prefs = _FakePrefs();
    final store = NovelReaderPositionStore(prefs);
    await store.save(
      'book1',
      NovelReaderPosition(
        chapterUrl: '/c/3',
        chapterId: 'c3',
        chapterIndex: 2,
        page: 4,
        pageCount: 13,
        scrollRatio: 0.4,
        locator: const NovelLocator(
          chapterIndex: 2,
          paragraph: 7,
          charOffset: 15,
          sourceKey: 's1',
        ),
      ),
    );

    final loaded = await NovelReaderPositionStore(prefs).load('book1');
    expect(loaded!.locator, isNotNull);
    expect(loaded.locator!.paragraph, 7);
    expect(loaded.locator!.charOffset, 15);
    expect(loaded.locator!.chapterIndex, 2);
  });

  test('按书源分键：换源不串位置，且保存后清掉旧键', () async {
    final prefs = _FakePrefs();
    final store = NovelReaderPositionStore(prefs);
    await store.save(
      'book1',
      _position(chapterUrl: '/s1/c1', chapterIndex: 1),
      sourceKey: 's1',
    );
    await store.save(
      'book1',
      _position(chapterUrl: '/s2/c9', chapterIndex: 9),
      sourceKey: 's2',
    );

    expect(
      (await NovelReaderPositionStore(
        prefs,
      ).load('book1', sourceKey: 's1'))!.chapterIndex,
      1,
    );
    expect(
      (await NovelReaderPositionStore(
        prefs,
      ).load('book1', sourceKey: 's2'))!.chapterIndex,
      9,
    );
    // 新键接管后不再保留无 sourceKey 的 legacy 键。
    final all = jsonDecode(prefs.values[NovelReaderPositionStore.key]!) as Map;
    expect(all.containsKey('book1'), isFalse);
    expect(all.containsKey('s1|book1'), isTrue);
    expect(all.containsKey('s2|book1'), isTrue);
  });

  test('旧 bookId 键可读，保存后迁移到 sourceKey 键', () async {
    final prefs = _FakePrefs();
    prefs.values[NovelReaderPositionStore.key] = jsonEncode(<String, Object?>{
      'book1': _position(chapterUrl: '/legacy/c4', chapterIndex: 3).toJson(),
    });
    final store = NovelReaderPositionStore(prefs);

    final legacy = await store.load('book1', sourceKey: 's1');
    expect(legacy!.chapterIndex, 3);

    await store.save(
      'book1',
      _position(chapterUrl: '/s1/c5', chapterIndex: 4),
      sourceKey: 's1',
    );
    final all = jsonDecode(prefs.values[NovelReaderPositionStore.key]!) as Map;
    expect(all.containsKey('book1'), isFalse);
    expect(all.containsKey('s1|book1'), isTrue);
  });
}
