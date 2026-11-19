// 验收 A1–A3：MusicDb 三表可读写 + 收藏服务的幂等/倒序/取消语义。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/music_db.dart';

import 'music_test_env.dart';

void main() {
  late MusicTestEnv env;

  const ref = MusicRef(id: '7301');

  setUp(() {
    env = MusicTestEnv.create();
  });

  tearDown(() => env.close());

  test('A1 MusicDb.forTesting 三表可读写，collectRow/historyRow 无行返回 null', () async {
    expect(await env.musicDb.collectRow(ref), isNull);
    expect(await env.musicDb.historyRow(ref), isNull);

    await env.musicDb
        .into(env.musicDb.musicSearchTerms)
        .insert(
          MusicSearchTermsCompanion.insert(
            keyword: '稻香',
            searchedAt: DateTime(2026, 11, 19),
          ),
        );
    expect(
      (await env.musicDb.select(env.musicDb.musicSearchTerms).get())
          .single
          .keyword,
      '稻香',
    );

    await env.collect.collect(testSong());
    expect((await env.musicDb.collectRow(ref))!.title, '稻香');

    await env.history.saveProgress(
      testSong(),
      const Duration(seconds: 30),
      const Duration(seconds: 223),
    );
    expect((await env.musicDb.historyRow(ref))!.positionMs, 30 * 1000);
  });

  test('A2 收藏：isCollected/collectedIds/list 倒序；重复收藏不新增行且刷新时间', () async {
    await env.collect.collectRef(
      const MusicRef(id: 'a'),
      title: '第一首',
      song: testSong(id: 'a', title: '第一首'),
      collectedAt: DateTime(2026, 11, 1),
    );
    await env.collect.collectRef(
      const MusicRef(id: 'b'),
      title: '第二首',
      song: testSong(id: 'b', title: '第二首'),
      collectedAt: DateTime(2026, 11, 2),
    );

    expect(await env.collect.isCollected('a'), isTrue);
    expect(await env.collect.isCollected('missing'), isFalse);
    expect(await env.collect.collectedIds(), <String>{'a', 'b'});
    expect(
      (await env.collect.list()).map((item) => item.ref.id).toList(),
      <String>['b', 'a'],
    );

    await env.collect.collectRef(
      const MusicRef(id: 'a'),
      title: '第一首（再收藏）',
      song: testSong(id: 'a', title: '第一首（再收藏）'),
      collectedAt: DateTime(2026, 11, 3),
    );

    final rows = await env.musicDb
        .select(env.musicDb.musicCollectEntries)
        .get();
    expect(rows, hasLength(2), reason: '重复收藏只更新一行');
    final first = (await env.collect.list()).first;
    expect(first.ref.id, 'a');
    expect(first.title, '第一首（再收藏）');
    expect(first.collectedAt, DateTime(2026, 11, 3));
    expect(first.song!.artists.single.name, '周杰伦', reason: 'payload 可重建曲目');
  });

  test('A3 取消收藏：内部行删除、投影 starred=false 且标题保留；重复 remove 幂等', () async {
    await env.collect.collectRef(
      ref,
      title: '稻香',
      coverUrl: 'https://example.com/cover.jpg',
      song: testSong(),
      collectedAt: DateTime(2026, 11, 1, 10),
    );

    await env.collect.remove(ref.id);

    expect(await env.musicDb.collectRow(ref), isNull);
    expect(await env.collect.isCollected(ref.id), isFalse);
    final view = (await env.library.timeline()).single;
    expect(view.starred, isFalse);
    expect(view.title, '稻香');
    expect(view.coverUrl, 'https://example.com/cover.jpg');

    await env.collect.remove(ref.id);
    expect(await env.library.timeline(), hasLength(1));
  });
}
