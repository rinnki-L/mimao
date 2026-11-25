// 书架展示配置、手动顺序、文件夹/系列归组的纯函数测试（无 Flutter 绑定）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/shelf/shelf_view_config.dart';

class _Book {
  const _Book(this.id, {this.folder, this.series});

  final String id;
  final String? folder;
  final int? series;
}

void main() {
  group('NovelShelfViewConfig 序列化', () {
    test('默认值等于改造前的观感', () {
      const config = NovelShelfViewConfig();
      expect(config.mode, NovelShelfMode.grid);
      expect(config.columns, 0);
      expect(config.coverShadow, isFalse);
      expect(config.showTags, isFalse);
      expect(config.showLatestChapter, isTrue);
      expect(config.showIntro, isFalse);
      expect(config.showUpdateTime, isFalse);
      expect(config.groupBySeries, isFalse);
    });

    test('五种布局与全部展示项往返一致', () {
      for (final mode in NovelShelfMode.values) {
        final config = NovelShelfViewConfig(
          mode: mode,
          columns: 5,
          coverWidth: 168,
          coverRadius: 20,
          coverShadow: true,
          showTags: true,
          showLatestChapter: false,
          showIntro: true,
          showUpdateTime: true,
          groupBySeries: true,
        );
        final decoded = NovelShelfViewConfig.decode(config.encode());
        expect(decoded.mode, mode);
        expect(decoded.columns, 5);
        expect(decoded.coverWidth, 168);
        expect(decoded.coverRadius, 20);
        expect(decoded.coverShadow, isTrue);
        expect(decoded.showTags, isTrue);
        expect(decoded.showLatestChapter, isFalse);
        expect(decoded.showIntro, isTrue);
        expect(decoded.showUpdateTime, isTrue);
        expect(decoded.groupBySeries, isTrue);
      }
    });

    test('旧 kv（grid/list 裸字符串）迁移到新模式', () {
      expect(NovelShelfViewConfig.decode('list').mode, NovelShelfMode.list);
      expect(NovelShelfViewConfig.decode('grid').mode, NovelShelfMode.grid);
      expect(NovelShelfViewConfig.decode(null).mode, NovelShelfMode.grid);
      expect(NovelShelfViewConfig.decode('').mode, NovelShelfMode.grid);
    });

    test('坏 JSON / 越界值收敛到可用配置', () {
      expect(
        NovelShelfViewConfig.decode('{not json').mode,
        NovelShelfMode.grid,
      );
      final decoded = NovelShelfViewConfig.decode(
        jsonEncode(<String, Object?>{
          'mode': 'waterfall',
          'columns': 99,
          'coverWidth': 9999,
          'coverRadius': -5,
        }),
      );
      expect(decoded.mode, NovelShelfMode.waterfall);
      expect(decoded.columns, 10);
      expect(decoded.coverWidth, NovelShelfViewConfig.maxCoverWidth);
      expect(decoded.coverRadius, NovelShelfViewConfig.minCoverRadius);
    });

    test('未知 mode 回落网格', () {
      expect(
        NovelShelfViewConfig.decode('{"mode":"mosaic"}').mode,
        NovelShelfMode.grid,
      );
    });
  });

  group('手动顺序', () {
    test('编码/解码往返，坏数据当空', () {
      const ids = <String>['b3', 'b1', 'b2'];
      expect(decodeShelfOrder(encodeShelfOrder(ids)), ids);
      expect(decodeShelfOrder('not-json'), isEmpty);
      expect(decodeShelfOrder('{"a":1}'), isEmpty);
      expect(decodeShelfOrder(null), isEmpty);
      expect(decodeShelfOrder('["a","","b"]'), <String>['a', 'b']);
    });

    test('applyShelfOrder 按手动顺序，未知项按原序追加', () {
      final books = <_Book>[
        const _Book('a'),
        const _Book('b'),
        const _Book('c'),
        const _Book('d'),
      ];
      final ordered = applyShelfOrder<_Book>(books, <String>[
        'c',
        'a',
        'gone',
      ], (book) => book.id);
      expect(ordered.map((book) => book.id).toList(), <String>[
        'c',
        'a',
        'b',
        'd',
      ]);
    });

    test('空顺序保持原序，不丢书', () {
      final books = <_Book>[const _Book('a'), const _Book('b')];
      expect(
        applyShelfOrder<_Book>(books, const <String>[], (book) => book.id),
        books,
      );
    });
  });

  group('文件夹分组', () {
    test('按组名排序、未分组排最后', () {
      final books = <_Book>[
        const _Book('a', folder: '科幻'),
        const _Book('b'),
        const _Book('c', folder: '武侠'),
        const _Book('d', folder: '  '),
      ];
      final sections = groupShelfByFolder<_Book>(
        books: books,
        folderOf: (book) => book.folder,
      );
      expect(sections.map((s) => s.title).toList(), <String>[
        '武侠',
        '科幻',
        '未分组',
      ]);
      expect(sections.last.books.map((b) => b.id).toList(), <String>['b', 'd']);
    });

    test('全部分组时不出未分组节', () {
      final sections = groupShelfByFolder<_Book>(
        books: <_Book>[const _Book('a', folder: '科幻')],
        folderOf: (book) => book.folder,
      );
      expect(sections, hasLength(1));
      expect(sections.single.folder, '科幻');
    });
  });

  group('系列归组', () {
    test('同系列聚成节，散书单列，系列名排序', () {
      final books = <_Book>[
        const _Book('a', series: 2),
        const _Book('b', series: 1),
        const _Book('c'),
        const _Book('d', series: 1),
      ];
      final grouping = groupShelfBySeries<_Book>(
        books: books,
        seriesOf: (book) => book.series,
        seriesNames: <int, String>{1: '基地', 2: '沙丘'},
      );
      expect(grouping.hasSeries, isTrue);
      expect(grouping.series.map((s) => s.title).toList(), <String>[
        '基地',
        '沙丘',
      ]);
      expect(grouping.series.first.books.map((b) => b.id).toList(), <String>[
        'b',
        'd',
      ]);
      expect(grouping.singles.map((b) => b.id).toList(), <String>['c']);
    });

    test('系列 id 已失效（名字缺失）按散书处理，不造假标题', () {
      final grouping = groupShelfBySeries<_Book>(
        books: <_Book>[const _Book('a', series: 9)],
        seriesOf: (book) => book.series,
        seriesNames: const <int, String>{},
      );
      expect(grouping.series, isEmpty);
      expect(grouping.singles.map((b) => b.id).toList(), <String>['a']);
    });
  });

  test('自动列数按封面宽度算并夹在 3..10', () {
    expect(autoShelfColumns(1200, 142), 8);
    expect(autoShelfColumns(200, 142), 3);
    expect(autoShelfColumns(4000, 142), 10);
    expect(
      autoShelfColumns(1200, 0),
      autoShelfColumns(1200, NovelShelfViewConfig.defaultCoverWidth),
    );
  });
}
