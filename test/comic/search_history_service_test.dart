// 搜索历史单测：去重、上限淘汰、空白输入、清除；不写 core 书架投影。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/search_history_service.dart';

import 'comic_test_env.dart';

void main() {
  late ComicTestEnv env;
  late ComicSearchHistoryService searchHistory;

  setUp(() {
    env = ComicTestEnv.create();
    searchHistory = ComicSearchHistoryService(env.comicDb, maxEntries: 3);
  });

  tearDown(() => env.close());

  test('按最近使用排序，重复关键词去重并刷新时间', () async {
    await searchHistory.record('  芙莉莲  ', now: DateTime(2026, 11, 1));
    await searchHistory.record('迷宫饭', now: DateTime(2026, 11, 2));
    await searchHistory.record('芙莉莲', now: DateTime(2026, 11, 3));

    final recent = await searchHistory.recent();
    expect(recent, ['芙莉莲', '迷宫饭']);
    expect(await searchHistory.recent(limit: 1), ['芙莉莲']);
  });

  test('超过上限淘汰最久未用的关键词', () async {
    for (var day = 1; day <= 5; day++) {
      await searchHistory.record('关键词$day', now: DateTime(2026, 11, day));
    }

    final recent = await searchHistory.recent();
    expect(recent, ['关键词5', '关键词4', '关键词3']);
    expect(await searchHistory.recent(limit: 10), hasLength(3));
  });

  test('空白关键词被忽略', () async {
    await searchHistory.record('   ', now: DateTime(2026, 11, 1));
    await searchHistory.record('', now: DateTime(2026, 11, 2));

    expect(await searchHistory.recent(), isEmpty);
  });

  test('remove/clear 生效，且搜索历史不产生 core 书架投影', () async {
    await searchHistory.record('芙莉莲', now: DateTime(2026, 11, 1));
    await searchHistory.record('迷宫饭', now: DateTime(2026, 11, 2));
    expect(await env.library.timeline(), isEmpty);

    await searchHistory.remove('芙莉莲');
    expect(await searchHistory.recent(), ['迷宫饭']);

    await searchHistory.clear();
    expect(await searchHistory.recent(), isEmpty);
  });
}
