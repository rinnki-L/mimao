/// 输出模型与编排解析测试：验证引擎输出纯数据、不依赖 UI，
/// 且能把 Venera 源脚本的原始结果收敛成稳定类型。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:mimao/comic/engine/engine.dart';

void main() {
  final engine = ComicSourceEngine();

  group('纯数据模型', () {
    test('ComicSummary 值相等与 hashCode', () {
      const a = ComicSummary(id: '1', title: 'Title', tags: <String>['x']);
      const b = ComicSummary(id: '1', title: 'Title', tags: <String>['x']);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('Title'));
    });

    test('ComicSourceResult 默认空列表、诊断可携带', () {
      const result = ComicSourceResult<int>(diagnostics: <String>['bad']);
      expect(result.isEmpty, isTrue);
      expect(result.diagnostics, <String>['bad']);
    });
  });

  group('编排解析（JS 原始结构 → 模型）', () {
    test('parseComic 接受 subTitle 别名与可选字段', () {
      final comic = engine.parseComic(<String, dynamic>{
        'id': 'c1',
        'title': '海贼王',
        'subTitle': '尾田',
        'cover': 'https://x/c.jpg',
        'tags': <String>['冒险', '热血'],
        'maxPage': 12,
        'stars': 4.5,
      });
      expect(comic, isNotNull);
      expect(comic!.subtitle, '尾田');
      expect(comic.tags, <String>['冒险', '热血']);
      expect(comic.maxPage, 12);
      expect(comic.stars, 4.5);
    });

    test('parseComicDetail 展开 chapters 映射、recommend 列表', () {
      final detail = engine.parseComicDetail(<String, dynamic>{
        'title': 'Title',
        'subTitle': 'Sub',
        'chapters': <String, dynamic>{'e1': '第1话', 'e2': '第2话'},
        'tags': <String, dynamic>{
          '作者': <String>['A'],
        },
        'recommend': <dynamic>[
          <String, dynamic>{'id': 'r1', 'title': 'Related'},
        ],
      });
      expect(detail, isNotNull);
      expect(detail!.subtitle, 'Sub');
      expect(detail.chapters.map((c) => c.id), <String>['e1', 'e2']);
      expect(detail.chapters.last.title, '第2话');
      expect(detail.recommend.single.title, 'Related');
      expect(detail.tags['作者'], <String>['A']);
    });

    test('parseComicList 缺 comics 数组返回诊断不抛异常', () {
      final result = engine.parseComicList(<String, dynamic>{}, 'maxPage');
      expect(result.isEmpty, isTrue);
      expect(result.diagnostics, isNotEmpty);
    });

    test('parseComicList 保留源返回的 maxPage 供翻页', () {
      final result = engine.parseComicList(<String, dynamic>{
        'comics': <dynamic>[
          <String, dynamic>{'id': 'c1', 'title': 'A'},
        ],
        'maxPage': 9,
      }, 'maxPage');
      expect(result.items, hasLength(1));
      expect(result.maxPage, 9);
    });

    test('maxPage/stars 非有限数（NaN/Infinity）收敛为 null，不抛异常', () {
      // 多个源在 total 缺失时算 `Math.ceil(undefined / 21)` → NaN；
      // 真实事故：一个源返回 NaN 就让整次聚合搜索报「搜索失败」。
      for (final bad in <num>[
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final result = engine.parseComicList(<String, dynamic>{
          'comics': <dynamic>[
            <String, dynamic>{'id': 'c1', 'title': 'A', 'maxPage': bad},
          ],
          'maxPage': bad,
        }, 'maxPage');
        expect(result.items, hasLength(1));
        expect(result.maxPage, isNull, reason: '$bad');
        expect(result.items.single.maxPage, isNull, reason: '$bad');
      }

      final comic = engine.parseComic(<String, dynamic>{
        'id': 'c1',
        'title': 'A',
        'stars': double.nan,
      });
      expect(comic!.stars, isNull);
    });

    test('parseImages 收拢图片地址并跳过空项', () {
      final result = engine.parseImages(<String, dynamic>{
        'images': <dynamic>['https://x/1.jpg', '', 'https://x/2.jpg'],
      });
      expect(result.items.map((e) => e.url), <String>[
        'https://x/1.jpg',
        'https://x/2.jpg',
      ]);
      expect(result.diagnostics, hasLength(1));
    });

    test('parseImages 读取 onImageLoad 注入的请求头', () {
      final result = engine.parseImages(<String, dynamic>{
        'images': <dynamic>['https://x/1.jpg', 'https://x/2.jpg'],
        'headers': <String, dynamic>{
          'https://x/1.jpg': <String, dynamic>{
            'Referer': 'https://x/',
            'Cookie': 'a=b',
            'callback': 1,
          },
        },
      });
      expect(result.items, hasLength(2));
      expect(result.items[0].headers, <String, String>{
        'Referer': 'https://x/',
        'Cookie': 'a=b',
      });
      expect(result.items[1].headers, isEmpty);
    });
  });
}
