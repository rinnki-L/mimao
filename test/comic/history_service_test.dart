// 阅读历史（history）单测：进度持久化、文案、打开校正入口、复合主键。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/comic_models.dart';
import 'package:mimao/comic/history_service.dart';

import 'comic_test_env.dart';

void main() {
  late ComicTestEnv env;
  late ComicHistoryService history;

  const ref = ComicRef(id: 'venera:1001', sourceName: '漫画源');

  setUp(() {
    env = ComicTestEnv.create();
    history = ComicHistoryService(env.comicDb, env.library);
  });

  tearDown(() => env.close());

  test('saveProgress：先写内部库，同函数内投影 progressText 与时间', () async {
    final saved = await history.saveProgress(
      ref,
      title: '葬送的芙莉莲',
      coverUrl: 'https://example.test/frieren.jpg',
      chapterId: 'ch1',
      page: 10,
      pageCount: 20,
      openedAt: DateTime(2026, 11, 17, 20, 30),
    );

    expect(saved.page, 10);
    final latest = await history.latest(ref);
    expect(latest, isNotNull);
    expect(latest!.page, 10);
    expect(latest.title, '葬送的芙莉莲');

    final view = (await env.library.timeline()).single;
    expect(view.progressText, 'ch1 · 第 10 页 · 50%');
    expect(view.lastOpenedAt, DateTime(2026, 11, 17, 20, 30));
    expect(view.coverUrl, 'https://example.test/frieren.jpg');
  });

  test('有总页数时带百分比并四舍五入；无总页数只报页码', () async {
    await history.saveProgress(
      ref,
      title: '葬送的芙莉莲',
      chapterId: 'ch2',
      page: 3,
      pageCount: 7,
    );
    expect(
      (await env.library.timeline()).single.progressText,
      'ch2 · 第 3 页 · 43%',
    );

    await history.saveProgress(ref, title: '葬送的芙莉莲', page: 5, pageCount: 0);
    expect((await env.library.timeline()).single.progressText, '看到第 5 页');
  });

  test('open 只在内部库有历史时校正投影（无记录不凭空造条目）', () async {
    await history.open(ref);
    expect(await env.library.timeline(), isEmpty);

    await history.saveProgress(
      ref,
      title: '葬送的芙莉莲',
      page: 2,
      openedAt: DateTime(2026, 11, 1),
    );
    await history.open(ref);
    expect((await env.library.timeline()).single.progressText, '看到第 2 页');
  });

  test('负数进度被拒绝', () async {
    expect(
      () => history.saveProgress(ref, title: '葬送的芙莉莲', page: -1),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('复合主键：同 id 不同源各一行历史、投影也各一行', () async {
    const sourceA = ComicRef(id: 'same-id', sourceName: '源A');
    const sourceB = ComicRef(id: 'same-id', sourceName: '源B');

    await history.saveProgress(
      sourceA,
      title: 'A 版',
      page: 10,
      openedAt: DateTime(2026, 11, 17),
    );
    await history.saveProgress(
      sourceB,
      title: 'B 版',
      page: 2,
      openedAt: DateTime(2026, 11, 16),
    );

    final recent = await history.recent();
    expect(recent, hasLength(2));
    expect(recent.first.ref.sourceName, '源A');
    expect(recent.first.title, 'A 版');
    expect(recent.last.title, 'B 版');

    final rows = await env.library.timeline();
    expect(rows, hasLength(2));
    expect(rows.map((row) => row.title), containsAll(<String>['A 版', 'B 版']));
  });
}
