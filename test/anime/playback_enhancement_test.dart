// B 线 · 番剧播放增强验收测试：线路字段 / 详情封面回退 / UA·Referer 透传 /
// 播放页线路切换。全部离线：假 HTTP 客户端 / 假播放后端 / 占位视频槽。
// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用 material.dart。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/data/anime_models.dart';
import 'package:mimao/anime/data/rule_anime_mapper.dart';
import 'package:mimao/anime/engine/extractor.dart';
import 'package:mimao/anime/engine/result.dart';
import 'package:mimao/anime/engine/rule.dart';
import 'package:mimao/anime/player/player_controller.dart';
import 'package:mimao/anime/player/player_page.dart';

import 'fixtures.dart';
import 'player/fake_playback_engine.dart';

AnimeSummary _summary(String source) => AnimeSummary(
  id: 'https://a.test/anime/1',
  title: '某番',
  coverUrl: 'https://a.test/search.jpg',
  detailUrl: 'https://a.test/anime/1',
  sourceName: source,
);

void main() {
  // ── 1. AnimeEpisode 线路字段 ──
  group('AnimeEpisode 线路字段', () {
    test('JSON 往返：roadIndex/roadName/duration 都不丢', () {
      const episode = AnimeEpisode(
        number: 3,
        title: '第3集',
        url: 'https://a.test/3',
        duration: '24:00',
        roadIndex: 2,
        roadName: '备用线路',
      );
      final json = episode.toJson();
      expect(json['roadIndex'], 2);
      expect(json['roadName'], '备用线路');
      expect(AnimeEpisode.fromJson(json), episode);
    });

    test('默认值兼容旧构造：roadIndex=1 / roadName=空串', () {
      const episode = AnimeEpisode(number: 1, title: '第一集', url: 'u');
      expect(episode.roadIndex, 1);
      expect(episode.roadName, '');
      expect(episode.duration, isNull);
      // fromJson 缺省字段也回退到默认值。
      final restored = AnimeEpisode.fromJson(<String, dynamic>{
        'number': 1,
        'title': '第一集',
        'url': 'u',
      });
      expect(restored, episode);
    });

    test('==/hashCode 把线路字段纳入比较', () {
      const a = AnimeEpisode(number: 1, title: 't', url: 'u', roadIndex: 1);
      const b = AnimeEpisode(number: 1, title: 't', url: 'u', roadIndex: 2);
      expect(a, isNot(b));
      expect(a.hashCode, isNot(b.hashCode));
      const c = AnimeEpisode(number: 1, title: 't', url: 'u', roadIndex: 1);
      expect(a, c);
      expect(a.hashCode, c.hashCode);
    });
  });

  // ── 2. rule_anime_mapper ──
  group('rule_anime_mapper 线路透传 + 封面回退链', () {
    final rule = AnimeRule.fromJson(
      jsonDecode(demoRuleJson) as Map<String, dynamic>,
    );

    test('roadIndex/roadName 不再丢失，逐集透传', () {
      const episodes = <RuleEpisode>[
        RuleEpisode(
          title: '第1集',
          url: '/1',
          absoluteUrl: 'https://a.test/1',
          roadIndex: 1,
          roadName: '播放线路1',
        ),
        RuleEpisode(
          title: '第1集',
          url: '/b1',
          absoluteUrl: 'https://a.test/b1',
          roadIndex: 2,
          roadName: '播放线路2',
        ),
      ];
      final detail = detailFromRule(rule, _summary('demo03'), episodes);
      expect(detail.episodes[0].roadIndex, 1);
      expect(detail.episodes[0].roadName, '播放线路1');
      expect(detail.episodes[1].roadIndex, 2);
      expect(detail.episodes[1].roadName, '播放线路2');
    });

    test('封面回退：详情封面优先于搜索封面', () {
      final detail = detailFromRule(
        rule,
        _summary('demo03'),
        const <RuleEpisode>[],
        detailCoverUrl: 'https://a.test/detail.jpg',
      );
      expect(detail.coverUrl, 'https://a.test/detail.jpg');
    });

    test('封面回退：详情封面为空时用搜索封面', () {
      final detail = detailFromRule(
        rule,
        _summary('demo03'),
        const <RuleEpisode>[],
      );
      expect(detail.coverUrl, 'https://a.test/search.jpg');
    });

    test('封面回退：两者都空时为空串（Kazumi 原生行为不变）', () {
      final item = AnimeSummary(
        id: 'id',
        title: '无封面',
        coverUrl: '',
        detailUrl: 'https://a.test/1',
        sourceName: 'demo03',
      );
      final detail = detailFromRule(
        rule,
        item,
        const <RuleEpisode>[],
        detailCoverUrl: '   ',
      );
      expect(detail.coverUrl, '');
    });
  });

  // ── 3. extractor 详情封面 ──
  group('extractor 详情封面抽取', () {
    const extractor = RuleExtractor();

    test('带 detailCover 的规则抽出详情封面（原始 + 绝对）', () {
      const html = '''
<html><body>
<img class="poster" src="/cover/1001.jpg">
<div class="playlist"><a class="episode" href="/play/1">第1集</a></div>
</body></html>''';
      final rule = AnimeRule.fromJson(<String, dynamic>{
        ...jsonDecode(demoRuleJson) as Map<String, dynamic>,
        'detailCover': '//img[@class="poster"]',
      });
      final cover = extractor.parseDetailCover(html, rule);
      expect(cover.coverUrl, '/cover/1001.jpg');
      expect(cover.absoluteCoverUrl, 'https://example.com/cover/1001.jpg');

      // parseDetail 同一次解析也带上封面，避免二次抓取。
      final parsed = extractor.parseDetail(html, rule);
      expect(parsed.absoluteCoverUrl, 'https://example.com/cover/1001.jpg');
      expect(parsed.items, hasLength(1));
    });

    test('cover 别名同样被识别', () {
      final rule = AnimeRule.fromJson(<String, dynamic>{
        ...jsonDecode(demoRuleJson) as Map<String, dynamic>,
        'cover': '//img/@src',
      });
      expect(rule.detail.cover, '//img/@src');
      expect(rule.toJson()['detailCover'], '//img/@src');
    });

    test('Kazumi 原生规则无封面字段 → 空串，且 validate 不变', () {
      final kazumi = AnimeRule.fromJson(
        jsonDecode(kazumiMxdmRuleJson) as Map<String, dynamic>,
      );
      expect(kazumi.detail.cover, '');
      expect(kazumi.validate(), isEmpty);
      final cover = extractor.parseDetailCover(mxdmDetailHtml, kazumi);
      expect(cover.coverUrl, '');
      expect(cover.absoluteCoverUrl, '');
      final parsed = extractor.parseDetail(mxdmDetailHtml, kazumi);
      expect(parsed.absoluteCoverUrl, '');
      expect(parsed.items, hasLength(4));
    });

    test('非法封面 XPath 不使规则失效，只回退空串', () {
      final rule = AnimeRule.fromJson(<String, dynamic>{
        ...jsonDecode(demoRuleJson) as Map<String, dynamic>,
        'detailCover': 'img[@class=]',
      });
      expect(rule.validate(), isEmpty); // hasValidSelectors 没变严。
      final cover = extractor.parseDetailCover(demoDetailPageHtml, rule);
      expect(cover.coverUrl, '');
    });
  });

  // ── 4. fake playback engine 收到注入的 UA/Referer ──
  group('UA/Referer 透传到播放引擎', () {
    final headers = <String, String>{
      'User-Agent': 'custom-UA',
      'Referer': 'https://a.test/',
    };

    test('controller.start 把 Episode.headers 传给 engine.open', () async {
      final engine = FakePlaybackEngine();
      final controller = PlayerController(
        engine: engine,
        episodes: <Episode>[
          Episode(
            number: 1,
            title: '第1集',
            url: 'https://a.test/1',
            headers: headers,
          ),
        ],
      );
      addTearDown(controller.dispose);
      await controller.start();
      expect(engine.openedHeaders.single, headers);
    });

    test('controller.loadEpisode / switchRoad 同样透传各自集的 headers', () async {
      final engine = FakePlaybackEngine();
      final otherHeaders = <String, String>{
        'User-Agent': 'road2-UA',
        'Referer': 'https://b.test/',
      };
      final controller = PlayerController(
        engine: engine,
        episodes: <Episode>[
          Episode(
            number: 1,
            title: '1',
            url: 'https://a.test/1',
            headers: headers,
            roadIndex: 1,
          ),
          Episode(
            number: 1,
            title: '1备',
            url: 'https://a.test/b1',
            headers: otherHeaders,
            roadIndex: 2,
          ),
        ],
      );
      addTearDown(controller.dispose);
      await controller.start();
      await controller.switchRoad(2);
      expect(engine.openedUrls.last, 'https://a.test/b1');
      expect(engine.openedHeaders.last, otherHeaders);
    });

    test('默认空 headers 时 engine.open 收到 null（既有行为不变）', () async {
      final engine = FakePlaybackEngine();
      final controller = PlayerController(
        engine: engine,
        episodes: const <Episode>[
          Episode(number: 1, title: '1', url: 'https://a.test/1'),
        ],
      );
      addTearDown(controller.dispose);
      await controller.start();
      expect(engine.openedHeaders.single, isNull);
    });

    test('switchRoad 按当前集数选新线路同集，缺集回退该线路第 1 集', () async {
      final engine = FakePlaybackEngine();
      final controller = PlayerController(
        engine: engine,
        episodes: <Episode>[
          Episode(number: 1, title: '1', url: 'a1', roadIndex: 1),
          Episode(number: 2, title: '2', url: 'a2', roadIndex: 1),
          // 线路2 只有第 1 集。
          Episode(number: 1, title: '1备', url: 'b1', roadIndex: 2),
        ],
        initialIndex: 1,
      );
      addTearDown(controller.dispose);
      await controller.switchRoad(2);
      // 当前是第 2 集，线路2 没有 → 回退第 1 集。
      expect(engine.openedUrls.last, 'b1');
    });
  });

  // ── 5. 播放页线路选择器 widget ──
  group('播放页线路选择器', () {
    testWidgets('多线路显示选择器，切换触发新 URL 加载', (tester) async {
      final engine = FakePlaybackEngine();
      final controller = PlayerController(
        engine: engine,
        episodes: <Episode>[
          Episode(
            number: 1,
            title: '第1话',
            url: 'a1',
            roadIndex: 1,
            roadName: '主线路',
          ),
          Episode(
            number: 1,
            title: '第1话备',
            url: 'b1',
            roadIndex: 2,
            roadName: '备用线路',
          ),
        ],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: PlayerPage(controller: controller)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('player-road-selector')), findsOneWidget);
      expect(find.text('主线路'), findsWidgets);

      await tester.tap(find.byKey(const Key('player-road-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('player-road-2')));
      await tester.pump();
      await tester.pump();

      expect(controller.currentRoadIndex, 2);
      expect(engine.openedUrls.last, 'b1');
    });

    testWidgets('单线路时不显示选择器', (tester) async {
      final engine = FakePlaybackEngine();
      final controller = PlayerController(
        engine: engine,
        episodes: const <Episode>[
          Episode(
            number: 1,
            title: '1',
            url: 'a1',
            roadIndex: 1,
            roadName: '主线路',
          ),
          Episode(
            number: 2,
            title: '2',
            url: 'a2',
            roadIndex: 1,
            roadName: '主线路',
          ),
        ],
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(home: PlayerPage(controller: controller)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('player-road-selector')), findsNothing);
      // 既有 UI 未回归：剧集条与播放/暂停仍在。
      expect(find.byKey(const Key('episode-0')), findsOneWidget);
      expect(find.byKey(const Key('player-play-pause')), findsOneWidget);
    });
  });
}
