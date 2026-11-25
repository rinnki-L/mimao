// 小说数据层扩展测试：书架分组、阅读统计/目标、历史删除的投影收尾、
// 书单 JSON 编解码。全部离线（两个内存 drift 库），不碰 path_provider。
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/novel/booklist_io.dart';
import 'package:mimao/novel/collect_service.dart';
import 'package:mimao/novel/history_service.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/stats_service.dart';

void main() {
  late AppDb appDb;
  late NovelDb novelDb;
  late LibraryRepository library;
  late NovelCollectService collect;
  late NovelHistoryService history;
  late NovelStatsService stats;

  setUp(() {
    appDb = AppDb.forTesting(NativeDatabase.memory());
    novelDb = NovelDb.forTesting(NativeDatabase.memory());
    library = LibraryRepository(appDb);
    collect = NovelCollectService(novelDb, library);
    history = NovelHistoryService(novelDb, library);
    stats = NovelStatsService(novelDb);
  });

  tearDown(() async {
    await appDb.close();
    await novelDb.close();
  });

  NovelSummary book(String id, String title, {String author = '作者'}) =>
      NovelSummary(id: id, title: title, author: author);

  test('分组：单本设置/批量设置/重命名/删除，收藏行状态不变', () async {
    await collect.collect(book('b1', '三体'));
    await collect.collect(book('b2', '球状闪电'));
    await collect.collect(book('b3', '超新星纪元'));

    await collect.setGroup('b1', '科幻');
    await collect.setGroupFor(<String>['b2', 'b3'], '  科幻  ');
    expect(await collect.groups(), <String>['科幻']);

    final items = await collect.list();
    expect(items.every((item) => item.groupName == '科幻'), isTrue);

    await collect.renameGroup('科幻', '经典');
    expect(await collect.groups(), <String>['经典']);
    expect(
      (await collect.list()).every((item) => item.groupName == '经典'),
      isTrue,
    );

    // 批量移出分组。
    await collect.setGroupFor(<String>['b1', 'b2'], null);
    expect(
      (await collect.list()).where((item) => item.groupName == null).length,
      2,
    );

    // 删除分组只解除归属，书仍在书架。
    await collect.deleteGroup('经典');
    expect(await collect.groups(), isEmpty);
    expect(await collect.list(), hasLength(3));
  });

  test('备注 / 自定义封面：写入收藏行，空白归一成空串，未收藏行是空操作', () async {
    await collect.collect(book('b1', '三体'));
    await collect.setNote('b1', '  读到第二部再回来  ');
    await collect.setCustomCover('b1', 'C:/covers/b1.png');

    var item = (await collect.list()).single;
    expect(item.note, '读到第二部再回来');
    expect(item.customCoverPath, 'C:/covers/b1.png');
    expect(item.effectiveCoverUrl, 'C:/covers/b1.png');

    // 恢复书源封面 → 退回 book.coverUrl。
    await collect.setCustomCover('b1', '   ');
    item = (await collect.list()).single;
    expect(item.customCoverPath, isNull);
    expect(item.effectiveCoverUrl, item.book?.coverUrl ?? '');

    await collect.setNote('b1', '');
    expect((await collect.list()).single.note, '');

    // 不存在的书不凭空造行。
    await collect.setNote('ghost', '不该落库');
    await collect.setCustomCover('ghost', 'x.png');
    expect(await collect.list(), hasLength(1));
  });

  test('系列：新建去重复用、批量归属、删除只解绑、悬挂 id 不写入', () async {
    await collect.collect(book('b1', '三体'));
    await collect.collect(book('b2', '黑暗森林'));
    await collect.collect(book('b3', '死神永生'));

    final id = await collect.createSeries('地球往事');
    // 同名（含首尾空白）复用同一个系列。
    expect(await collect.createSeries('  地球往事 '), id);
    expect(await collect.series(), hasLength(1));

    await collect.setSeriesFor(<String>['b1', 'b2', 'b3'], id);
    final items = await collect.list();
    expect(items.every((item) => item.seriesId == id), isTrue);

    await collect.renameSeries(id, '三体三部曲');
    expect((await collect.series()).single.name, '三体三部曲');

    // 移出一本。
    await collect.setSeriesFor(<String>['b3'], null);
    expect(
      (await collect.list()).where((item) => item.seriesId == id),
      hasLength(2),
    );

    // 悬挂 id 不写进收藏行（系列可能刚被删掉）。
    await collect.setSeriesFor(<String>['b3'], 9999);
    expect(
      (await collect.list()).firstWhere((item) => item.ref.id == 'b3').seriesId,
      isNull,
    );

    // 删除系列：成员解绑，书都还在。
    await collect.deleteSeries(id);
    expect(await collect.series(), isEmpty);
    expect(await collect.list(), hasLength(3));
    expect(
      (await collect.list()).every((item) => item.seriesId == null),
      isTrue,
    );
  });

  test('系列名不能为空', () async {
    expect(() => collect.createSeries('   '), throwsArgumentError);
    final id = await collect.createSeries('系列');
    expect(() => collect.renameSeries(id, ''), throwsArgumentError);
  });

  test('统计：阅读时长按天累加、目标读写，书籍/收藏计数来自内部库', () async {
    var snapshot = await stats.snapshot();
    expect(snapshot.booksRead, 0);
    expect(snapshot.collected, 0);
    expect(snapshot.totalSeconds, 0);
    expect(snapshot.goalMinutes, novelDefaultGoalMinutes);

    await collect.collect(book('b1', '三体'));
    await history.saveProgress(book('b1', '三体'), 3, 10);
    await stats.addReadingTime(const Duration(minutes: 5));
    await stats.addReadingTime(
      const Duration(minutes: 2),
      at: DateTime(2020, 1, 1),
    );

    snapshot = await stats.snapshot();
    expect(snapshot.booksRead, 1);
    expect(snapshot.collected, 1);
    expect(snapshot.totalSeconds, 7 * 60);
    expect(snapshot.todaySeconds, 5 * 60);
    expect(snapshot.todayMinutes, 5);
    expect(snapshot.goalMinutes, 30);
    expect(snapshot.goalProgress, closeTo(5 / 30, 0.001));

    await stats.setGoalMinutes(45);
    snapshot = await stats.snapshot();
    expect(snapshot.goalMinutes, 45);

    // 0 分钟 = 关闭目标，进度按 0 处理。
    await stats.setGoalMinutes(0);
    snapshot = await stats.snapshot();
    expect(snapshot.goalMinutes, 0);
    expect(snapshot.goalProgress, 0);
  });

  test('历史删除的投影收尾：有收藏回未读，无收藏摘投影行', () async {
    await collect.collect(book('b1', '三体'));
    await history.saveProgress(book('b1', '三体'), 3, 10);
    expect((await library.timeline()).single.progressText, '看到第 3 章 · 30%');

    await history.remove('b1');
    final kept = (await library.timeline()).single;
    expect(kept.progressText, novelUnreadText);
    expect(kept.starred, isTrue);

    await collect.remove('b1');
    expect(await library.timeline(), isEmpty);

    // 仅有历史行：删掉历史后投影行也应消失。
    await history.saveProgress(book('b2', '球状闪电'), 1, 5);
    expect((await library.timeline()).single.id, 'b2');
    await history.clear();
    expect(await library.timeline(), isEmpty);
  });

  test('书单：导出→导入往返保留分组与进度，数组/单对象也能解析', () {
    const books = <NovelBooklistBook>[
      NovelBooklistBook(
        id: 'b1',
        title: '三体',
        author: '刘慈欣',
        coverUrl: 'https://example.com/1.jpg',
        groupName: '科幻',
        chapterIndex: 12,
        chapterCount: 400,
      ),
      NovelBooklistBook(id: 'b2', title: '球状闪电'),
    ];
    final text = encodeNovelBooklist(books, exportedAt: DateTime(2026, 11, 22));
    final parsed = decodeNovelBooklist(text);
    expect(parsed, hasLength(2));
    expect(parsed.first.id, 'b1');
    expect(parsed.first.author, '刘慈欣');
    expect(parsed.first.groupName, '科幻');
    expect(parsed.first.hasProgress, isTrue);
    expect(parsed.last.hasProgress, isFalse);

    // 纯数组 / 单条对象也接受；缺 id 或书名被跳过。
    final array = decodeNovelBooklist('[{"id":"x","title":"X"}]');
    expect(array.single.title, 'X');
    final single = decodeNovelBooklist('{"id":"y","title":"Y"}');
    expect(single.single.id, 'y');

    expect(
      () => decodeNovelBooklist('[{"title":""}]'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => decodeNovelBooklist('{"format":"other","books":[]}'),
      throwsA(isA<FormatException>()),
    );
  });
}
