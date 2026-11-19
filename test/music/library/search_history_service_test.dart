// 验收 A5：搜索历史去重 + hits 递增 + 空串忽略 + clear。
import 'package:flutter_test/flutter_test.dart';

import 'music_test_env.dart';

void main() {
  late MusicTestEnv env;

  setUp(() {
    env = MusicTestEnv.create();
  });

  tearDown(() => env.close());

  test('A5 record 去重并 hits 递增，空串/纯空白忽略', () async {
    await env.searchHistory.record('  稻香  ');
    await env.searchHistory.record('稻香');
    await env.searchHistory.record('   ');
    await env.searchHistory.record('');

    final rows = await env.musicDb.select(env.musicDb.musicSearchTerms).get();
    expect(rows, hasLength(1));
    expect(rows.single.keyword, '稻香');
    expect(rows.single.hits, 2);
    expect(await env.searchHistory.recent(), <String>['稻香']);
  });

  test('A5 recent 按最近搜索倒序并遵守 limit；clear 清空', () async {
    await env.searchHistory.record('一', at: DateTime(2026, 11, 1));
    await env.searchHistory.record('二', at: DateTime(2026, 11, 2));
    await env.searchHistory.record('三', at: DateTime(2026, 11, 3));

    final recent = await env.searchHistory.recent();
    expect(recent, hasLength(3));
    expect(recent.first, '三');
    expect((await env.searchHistory.recent(limit: 1)), <String>['三']);

    await env.searchHistory.clear();
    expect(await env.searchHistory.recent(), isEmpty);
    expect(
      await env.musicDb.select(env.musicDb.musicSearchTerms).get(),
      isEmpty,
    );
  });
}
