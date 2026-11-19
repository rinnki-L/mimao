// 小说数据层测试（验收 8/9/10）：内部权威库 + core 投影库各一个内存实例。
//
// 用 NovelDb.forTesting(NativeDatabase.memory()) 与 AppDb.forTesting(...) 双注入，
// 对齐 test/music/library 的 MusicTestEnv 口径；全部离线、不碰 path_provider。
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/novel/collect_service.dart';
import 'package:mimao/novel/history_service.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/novel_projection.dart';
import 'package:mimao/novel/search_history_service.dart';

/// 测试环境：两个内存 drift 库 + 预组装三服务（对齐 MusicTestEnv）。
class NovelTestEnv {
  final AppDb appDb;
  final NovelDb novelDb;
  final LibraryRepository library;
  final NovelCollectService collect;
  final NovelHistoryService history;
  final NovelSearchHistoryService searchHistory;

  NovelTestEnv._(this.appDb, this.novelDb)
    : library = LibraryRepository(appDb),
      collect = NovelCollectService(novelDb, LibraryRepository(appDb)),
      history = NovelHistoryService(novelDb, LibraryRepository(appDb)),
      searchHistory = NovelSearchHistoryService(novelDb);

  factory NovelTestEnv.create() => NovelTestEnv._(
    AppDb.forTesting(NativeDatabase.memory()),
    NovelDb.forTesting(NativeDatabase.memory()),
  );

  Future<void> close() async {
    await appDb.close();
    await novelDb.close();
  }
}

NovelSummary testBook({
  String id = 'b1',
  String title = '书名',
  String coverUrl = 'https://example.com/c.jpg',
  String author = '作者',
}) => NovelSummary(id: id, title: title, coverUrl: coverUrl, author: author);

void main() {
  late NovelTestEnv env;

  const ref = NovelRef(id: 'b1');

  setUp(() {
    env = NovelTestEnv.create();
  });

  tearDown(() => env.close());

  Future<Map<String, Object?>> readPayload() async {
    final raw = await env.appDb.select(env.appDb.mediaEntries).getSingle();
    return jsonDecode(raw.payload) as Map<String, Object?>;
  }

  test(
    '8 NovelDb.forTesting 可打开，三表可读写，collectRow/historyRow 空返回 null',
    () async {
      expect(await env.novelDb.collectRow(ref), isNull);
      expect(await env.novelDb.historyRow(ref), isNull);

      // 搜索表可写可读。
      await env.novelDb
          .into(env.novelDb.novelSearchTerms)
          .insert(
            NovelSearchTermsCompanion.insert(
              keyword: '关键词',
              searchedAt: DateTime(2026, 11, 19),
            ),
          );
      expect(
        (await env.novelDb.select(env.novelDb.novelSearchTerms).get())
            .single
            .keyword,
        '关键词',
      );

      // 收藏表可写可读。
      await env.collect.collect(testBook());
      expect((await env.novelDb.collectRow(ref))!.title, '书名');

      // 历史表可写可读。
      await env.history.saveProgress(testBook(), 3, 10);
      expect((await env.novelDb.historyRow(ref))!.chapterIndex, 3);
    },
  );

  test('9 无收藏无历史且无 fallback → syncNovelProjection 不写投影行', () async {
    await syncNovelProjection(db: env.novelDb, library: env.library, ref: ref);
    expect(await env.appDb.select(env.appDb.mediaEntries).get(), isEmpty);
    expect(await env.library.timeline(), isEmpty);
  });

  test(
    '9 有收藏行 → starred=true，标题/封面取收藏行，progressText=novelUnreadText',
    () async {
      await env.collect.collect(
        testBook(title: '收藏标题', coverUrl: 'https://example.com/collect.jpg'),
      );

      final view = (await env.library.timeline()).single;
      expect(view.id, ref.id);
      expect(view.type, MediaType.novel);
      expect(view.sourceName, novelSourceName);
      expect(view.title, '收藏标题');
      expect(view.coverUrl, 'https://example.com/collect.jpg');
      expect(view.starred, isTrue);
      expect(view.progressText, novelUnreadText);
      // 无历史时 payload 进度为 0。
      expect(await readPayload(), <String, Object?>{
        'chapterIndex': 0,
        'chapterCount': 0,
      });
    },
  );

  test(
    '9 有历史行 → progressText 有进度，payload 含 chapterIndex/chapterCount',
    () async {
      await env.history.saveProgress(testBook(title: '历史标题'), 3, 10);

      final view = (await env.library.timeline()).single;
      expect(view.title, '历史标题');
      expect(view.starred, isFalse);
      expect(view.progressText, '看到第 3 章 · 30%');
      expect(await readPayload(), <String, Object?>{
        'chapterIndex': 3,
        'chapterCount': 10,
      });
    },
  );

  test('10 收藏服务注入：collect → 投影 starred=true（fake/真实库可替换注入）', () async {
    // 接口缝：可把真实服务当作 NovelCollectApi 注入调用方。
    final NovelCollectApi api = env.collect;
    await api.collect(testBook());
    expect(await api.isCollected(ref.id), isTrue);
    expect(await api.collectedIds(), <String>{ref.id});

    final view = (await env.library.timeline()).single;
    expect(view.starred, isTrue);
    expect(view.title, '书名');
  });

  test('10 历史服务注入：saveProgress → 历史行 + 投影（fake/真实库可替换注入）', () async {
    final NovelHistoryApi api = env.history;
    await api.saveProgress(testBook(), 5, 10);

    expect((await api.latest(ref.id))!.chapterIndex, 5);
    expect((await env.novelDb.historyRow(ref))!.chapterCount, 10);

    final view = (await env.library.timeline()).single;
    expect(view.progressText, '看到第 5 章 · 50%');
    expect(await readPayload(), <String, Object?>{
      'chapterIndex': 5,
      'chapterCount': 10,
    });
  });

  test('10 搜索历史服务注入：record/recent/clear 正常（只构造 NovelDb，不碰 core 投影）', () async {
    final NovelSearchHistoryApi api = env.searchHistory;
    await api.record('  小说  ');
    await api.record('小说');
    await api.record('   ');

    expect(await api.recent(), <String>['小说']);
    // 搜索词不进 core 书架投影。
    expect(await env.appDb.select(env.appDb.mediaEntries).get(), isEmpty);

    await api.clear();
    expect(await api.recent(), isEmpty);
  });
}
