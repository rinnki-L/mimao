// B 线 · rule_anime_mapper 单测：线路透传 + 详情封面回退链。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/anime/data/anime_models.dart';
import 'package:mimao/anime/data/rule_anime_mapper.dart';
import 'package:mimao/anime/engine/engine.dart';

void main() {
  final rule = AnimeRule.fromJson(<String, dynamic>{
    'name': '甲站',
    'baseURL': 'https://a.test',
  });

  AnimeSummary item({String cover = ''}) => AnimeSummary(
    id: 'https://a.test/anime/1',
    title: '某番',
    coverUrl: cover,
    detailUrl: 'https://a.test/anime/1',
  );

  const episodes = <RuleEpisode>[
    RuleEpisode(
      title: '第1话',
      url: '/play/1',
      absoluteUrl: 'https://a.test/play/1',
      roadIndex: 1,
      roadName: '主线路',
    ),
    RuleEpisode(
      title: '第1话备',
      url: '/play/b1',
      absoluteUrl: 'https://a.test/play/b1',
      roadIndex: 2,
      roadName: '备用线路',
    ),
  ];

  group('detailFromRule 线路透传', () {
    test('roadIndex/roadName 不再丢失，逐集透传', () {
      final detail = detailFromRule(rule, item(), episodes);

      expect(detail.episodes, hasLength(2));
      expect(detail.episodes[0].roadIndex, 1);
      expect(detail.episodes[0].roadName, '主线路');
      expect(detail.episodes[1].roadIndex, 2);
      expect(detail.episodes[1].roadName, '备用线路');
    });

    test('number 仍按传入顺序从 1 生成，url 回退规则不变', () {
      final detail = detailFromRule(rule, item(), episodes);
      expect(detail.episodes.map((e) => e.number), [1, 2]);
      expect(detail.episodes[0].url, 'https://a.test/play/1');
    });
  });

  group('AnimeDetail.coverUrl 回退链：详情封面 → 搜索封面 → 空串', () {
    test('情况一：详情封面非空 → 用详情封面（覆盖搜索封面）', () {
      final detail = detailFromRule(
        rule,
        item(cover: 'https://a.test/search.jpg'),
        episodes,
        detailCover: 'https://a.test/detail.jpg',
      );
      expect(detail.coverUrl, 'https://a.test/detail.jpg');
    });

    test('情况二：详情封面空 → 回退搜索封面', () {
      final detail = detailFromRule(
        rule,
        item(cover: 'https://a.test/search.jpg'),
        episodes,
      );
      expect(detail.coverUrl, 'https://a.test/search.jpg');
    });

    test('情况三：两者都空 → 空串（Kazumi 原生规则行为不变）', () {
      final detail = detailFromRule(rule, item(), episodes);
      expect(detail.coverUrl, '');
    });

    test('详情封面为空白串时按空处理，回退搜索封面', () {
      final detail = detailFromRule(
        rule,
        item(cover: 'https://a.test/search.jpg'),
        episodes,
        detailCover: '   ',
      );
      expect(detail.coverUrl, 'https://a.test/search.jpg');
    });
  });
}
