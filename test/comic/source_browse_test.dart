/// 发现（explore）与分类（category）引擎能力测试。
///
/// 用假 [JsHost] 记录表达式并回放预置结果，验证：
/// - 表达式形状（load/loadNext 回退、逐分区 catch、参数转义）；
/// - 多种返回结构的收敛（multiPartPage / multiPageComicList / mixed / 数组）；
/// - 分类树解析（静态 categories + 平行 categoryParams）与缺失回退。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:mimao/comic/engine/engine.dart';

/// 记录表达式、按前缀回放结果的假宿主。
class _BrowseHost implements JsHost {
  _BrowseHost(this.handler);

  /// 表达式 → 返回值（返回 null 表示「没有处理」，回 null）。
  final Object? Function(String expression) handler;

  final List<String> expressions = <String>[];

  @override
  Future<void> loadScript(String script) async {}

  @override
  Future<Object?> evaluate(String expression) async {
    expressions.add(expression);
    return handler(expression);
  }

  @override
  void close() {}
}

const String _fakeScript = r'''
class BrowseSource extends ComicSource {
  key = "browse";
  name = "Browse";
}
''';

Future<(_BrowseHost, ComicSourceEngine)> _setup(
  Object? Function(String expression) handler,
) async {
  final host = _BrowseHost(handler);
  final pool = SourceExecutionPool(hostFactory: () => host);
  await pool.register('browse', _fakeScript);
  addTearDown(pool.disposeAll);
  return (host, ComicSourceEngine(pool: pool));
}

void main() {
  group('exploreGroups：表达式形状', () {
    test('逐分区 Promise.all + 单分区 catch + loadNext 回退', () async {
      final (host, engine) = await _setup((_) => null);

      await engine.exploreGroups('browse', page: 2);

      final expression = host.expressions.last;
      expect(expression, contains('Promise.all(list.map('));
      expect(expression, contains("typeof item.load === 'function'"));
      expect(expression, contains("typeof item.loadNext === 'function'"));
      // 单个分区 reject 收敛成 {error}，不拖垮整次调用。
      expect(
        expression,
        contains(
          '(error) => ({ index: i, title: title, error: String(error) })',
        ),
      );
      expect(expression, contains('item.load(2)'));
      // 只有 loadNext 的分区首参是 token，不是页码（首屏传 null）。
      expect(expression, contains('item.loadNext(null)'));
    });

    test('loadNext 分区首屏传 null 而不是页码（ehentai 绝对 URL 缺口）', () async {
      final (host, engine) = await _setup((expression) {
        if (expression.contains('Promise.all(list.map(')) {
          // 模拟源解析后返回空数据即可，重点断言表达式首参。
          return <Object?>[];
        }
        return null;
      });

      await engine.exploreGroups('browse', page: 7);

      final expression = host.expressions.last;
      expect(expression, contains('call = item.loadNext(null)'));
      expect(expression, isNot(contains('item.loadNext(7)')));
    });

    test('exploreSection 按下标取分区，并回传 data', () async {
      final (host, engine) = await _setup((expression) {
        if (expression.contains('source.explore[3]')) {
          return <String, Object?>{
            'index': 3,
            'title': '排行',
            'data': <String, Object?>{
              'comics': <Object?>[
                <String, Object?>{'id': 'c9', 'title': '排行第一'},
              ],
              'maxPage': 4,
            },
          };
        }
        return null;
      });

      final result = await engine.exploreSection('browse', 3, page: 1);

      expect(host.expressions.last, contains('source.explore[3]'));
      expect(result.items, hasLength(1));
      final group = result.items.single;
      expect(group.title, '排行');
      expect(group.comics.single.title, '排行第一');
      expect(group.maxPage, 4);
      expect(group.index, 3);
    });
  });

  group('exploreGroups：返回结构收敛', () {
    test('{标题: 漫画数组} 按多分区展开', () async {
      final (_, engine) = await _setup((expression) {
        if (!expression.contains('Promise.all')) return null;
        return <Object?>[
          <String, Object?>{
            'index': 0,
            'title': '哔哩哔哩漫画',
            'data': <String, Object?>{
              '推荐': <Object?>[
                <String, Object?>{'id': 'a', 'title': '推荐漫画'},
              ],
              '热门': <Object?>[
                <String, Object?>{'id': 'b', 'title': '热门漫画'},
              ],
            },
          },
        ];
      });

      final result = await engine.exploreGroups('browse');

      expect(result.diagnostics, isEmpty);
      expect(result.items.map((g) => g.title), <String>['推荐', '热门']);
      expect(result.items.first.comics.single.title, '推荐漫画');
    });

    test('{comics, maxPage} 单分区（multiPageComicList）', () async {
      final (_, engine) = await _setup((expression) {
        if (!expression.contains('Promise.all')) return null;
        return <Object?>[
          <String, Object?>{
            'index': 0,
            'title': '最新',
            'data': <String, Object?>{
              'comics': <Object?>[
                <String, Object?>{'id': 'n1', 'title': '新连载'},
              ],
              'maxPage': 7,
            },
          },
        ];
      });

      final result = await engine.exploreGroups('browse');

      final group = result.items.single;
      expect(group.title, '最新');
      expect(group.maxPage, 7);
      expect(group.hasMore, isTrue);
      expect(group.comics.single.id, 'n1');
    });

    test('纯漫画数组（singlePageWithMultiPart 的 data 是数组）', () async {
      final (_, engine) = await _setup((expression) {
        if (!expression.contains('Promise.all')) return null;
        return <Object?>[
          <String, Object?>{
            'index': 0,
            'title': '拷贝漫画',
            'data': <Object?>[
              <String, Object?>{'id': 'x', 'title': '数组条目'},
            ],
          },
        ];
      });

      final result = await engine.exploreGroups('browse');

      expect(result.items.single.title, '拷贝漫画');
      expect(result.items.single.comics.single.title, '数组条目');
    });

    test('mixed：{data: {...}, maxPage} 递归解析 data', () async {
      final (_, engine) = await _setup((expression) {
        if (!expression.contains('Promise.all')) return null;
        return <Object?>[
          <String, Object?>{
            'index': 0,
            'title': '混合',
            'data': <String, Object?>{
              'data': <String, Object?>{
                '分区A': <Object?>[
                  <String, Object?>{'id': 'm1', 'title': '混合条目'},
                ],
              },
              'maxPage': 2,
            },
          },
        ];
      });

      final result = await engine.exploreGroups('browse');

      expect(result.items.single.title, '分区A');
      expect(result.items.single.comics.single.title, '混合条目');
    });

    test('单分区失败保留为空分区 + 诊断，其它分区照常返回', () async {
      final (_, engine) = await _setup((expression) {
        if (!expression.contains('Promise.all')) return null;
        return <Object?>[
          <String, Object?>{
            'index': 0,
            'title': '坏分区',
            'error': 'network down',
          },
          <String, Object?>{
            'index': 1,
            'title': '好分区',
            'data': <String, Object?>{
              'comics': <Object?>[
                <String, Object?>{'id': 'ok', 'title': '正常漫画'},
              ],
            },
          },
        ];
      });

      final result = await engine.exploreGroups('browse');

      // 失败分区不凭空消失：保留空数据 + 诊断，页面据此显示真实原因。
      expect(result.items.map((g) => g.title), <String>['坏分区', '好分区']);
      expect(result.items.first.comics, isEmpty);
      expect(result.items.first.diagnostics.single, 'network down');
      expect(result.items.last.comics.single.title, '正常漫画');
      expect(result.diagnostics.single, contains('坏分区：network down'));
    });

    test('源没有 explore（返回非数组）→ 诊断而非抛错', () async {
      final (_, engine) = await _setup((_) => null);

      final result = await engine.exploreGroups('browse');

      expect(result.items, isEmpty);
      expect(result.diagnostics.single, contains('未提供 explore'));
    });

    test('畸形条目被跳过，不产生空分区', () async {
      final (_, engine) = await _setup((expression) {
        if (!expression.contains('Promise.all')) return null;
        return <Object?>['not-a-map', 42];
      });

      final result = await engine.exploreGroups('browse');

      expect(result.items, isEmpty);
      expect(result.diagnostics, isEmpty);
    });
  });

  group('category 树解析', () {
    test('静态 categories + 平行 categoryParams', () async {
      final (host, engine) = await _setup((expression) {
        if (expression.contains('source.category;')) {
          return <String, Object?>{
            'title': '拷贝漫画',
            'parts': <Object?>[
              <String, Object?>{
                'name': '主题',
                'categories': <Object?>['恋爱', '热血'],
                'categoryParams': <Object?>['love', 'hot'],
              },
            ],
          };
        }
        return null;
      });

      final tree = await engine.category('browse');

      expect(host.expressions.last, contains('source.category'));
      expect(tree, isNotNull);
      expect(tree!.title, '拷贝漫画');
      final part = tree.parts.single;
      expect(part.name, '主题');
      expect(part.items.map((i) => i.name), <String>['恋爱', '热血']);
      expect(part.items.map((i) => i.param), <String>['love', 'hot']);
    });

    test('categories 写成 {label, target} 对象时用 target 作 param', () async {
      final (_, engine) = await _setup((expression) {
        if (expression.contains('source.category;')) {
          return <String, Object?>{
            'parts': <Object?>[
              <String, Object?>{
                'name': '题材',
                'categories': <Object?>[
                  <String, Object?>{'label': '科幻', 'target': 'scifi'},
                ],
              },
            ],
          };
        }
        return null;
      });

      final tree = await engine.category('browse');

      expect(tree!.parts.single.items.single.name, '科幻');
      expect(tree.parts.single.items.single.param, 'scifi');
    });

    test('dynamic loader 分区现场生成标签（manga_dex/kavita 同形）', () async {
      final (host, engine) = await _setup((expression) {
        if (expression.contains('source.category;')) {
          // JS 侧已把 loader() 结果归一化成 items:[{name,param}]。
          return <String, Object?>{
            'title': 'MangaDex',
            'parts': <Object?>[
              <String, Object?>{
                'name': 'Tags',
                'categories': <Object?>[],
                'items': <Object?>[
                  <String, Object?>{'name': 'Oneshot', 'param': 'tag-uuid-1'},
                  <String, Object?>{'name': '全部', 'param': 'all'},
                ],
              },
            ],
          };
        }
        return null;
      });

      final tree = await engine.category('browse');

      expect(host.expressions.last, contains("part.type === 'dynamic'"));
      expect(host.expressions.last, contains('part.loader()'));
      expect(tree, isNotNull);
      expect(tree!.parts.single.items.map((i) => i.name), <String>[
        'Oneshot',
        '全部',
      ]);
      expect(tree.parts.single.items.map((i) => i.param), <String>[
        'tag-uuid-1',
        'all',
      ]);
    });

    test('没有 category 返回 null（UI 回退 explore）', () async {
      final (_, engine) = await _setup((_) => null);

      expect(await engine.category('browse'), isNull);
    });

    test('parts 存在但全部为空也返回 null（避免空分类页）', () async {
      final (_, engine) = await _setup((expression) {
        if (expression.contains('source.category;')) {
          return <String, Object?>{
            'parts': <Object?>[
              <String, Object?>{'name': '空组', 'categories': <Object?>[]},
            ],
          };
        }
        return null;
      });

      expect(await engine.category('browse'), isNull);
    });
  });

  group('categoryComics', () {
    test('表达式传 category/param/page 并带 loadNext 回退', () async {
      final (host, engine) = await _setup((expression) {
        if (expression.contains('source.categoryComics')) {
          return <String, Object?>{
            'comics': <Object?>[
              <String, Object?>{'id': 'cc1', 'title': '分类结果'},
            ],
            'maxPage': 3,
          };
        }
        return null;
      });

      final result = await engine.categoryComics(
        'browse',
        const ComicCategoryItem(name: '科幻', param: 'scifi'),
        page: 2,
      );

      final expression = host.expressions.last;
      expect(expression, contains('c.load("科幻", "scifi", __defaults, 2)'));
      expect(
        expression,
        contains('c.loadNext("科幻", "scifi", __defaults, null)'),
      );
      expect(result.items.single.comics.single.title, '分类结果');
      expect(result.items.single.maxPage, 3);
    });

    test('param 为 null 时传 null 字面量', () async {
      final (host, engine) = await _setup((_) => null);

      await engine.categoryComics(
        'browse',
        const ComicCategoryItem(name: '全部'),
      );

      expect(
        host.expressions.last,
        contains('c.load("全部", null, __defaults, 1)'),
      );
    });

    test('options 取 categoryComics.optionList 默认值（baozi/ykmh 同类缺口）', () async {
      final (host, engine) = await _setup((_) => null);

      await engine.categoryComics(
        'browse',
        const ComicCategoryItem(name: '全部', param: 'all'),
      );

      final expression = host.expressions.last;
      // 必须在 JS 侧从 c.optionList 计算默认值，而不是硬编码空数组。
      expect(expression, contains('const list = c.optionList'));
      expect(expression, contains('item.default'));
      expect(expression, contains('entry.slice(0, dash)'));
      expect(expression, contains('__defaults, 1'));
      expect(expression, isNot(contains(', [], 1)')));
    });

    test('分类名含引号时转义，不产生注入面', () async {
      final (host, engine) = await _setup((_) => null);

      await engine.categoryComics(
        'browse',
        const ComicCategoryItem(name: 'a"b\\c'),
      );

      expect(host.expressions.last, contains(r'"a\"b\\c"'));
    });

    test('源没有 categoryComics 时返回空结果而非抛错', () async {
      // 表达式在 JS 侧已守卫：没有 categoryComics 时返回空对象。
      final (_, engine) = await _setup((expression) {
        if (expression.contains('source.categoryComics')) {
          return <String, Object?>{'comics': <Object?>[], 'maxPage': null};
        }
        return null;
      });

      final result = await engine.categoryComics(
        'browse',
        const ComicCategoryItem(name: '任意'),
      );

      expect(result.items.single.comics, isEmpty);
      expect(result.diagnostics, isEmpty);
    });
  });
}
