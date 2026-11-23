// 页内位置存储：往返、章节匹配、清空、容量淘汰。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/library_api.dart';
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
}
