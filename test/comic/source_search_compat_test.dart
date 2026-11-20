/// 搜索兼容性测试：默认 options（Venera optionList/defaultValue 语义）与
/// `search.load` 缺失时回退 `search.loadNext`。
///
/// 用 fake [JsHost] 记录引擎发出的表达式并回放预置结果，不启动 QuickJS——
/// 这些测试只验证表达式形状与结果解析，真实 JS 语义由 source_execution_test
/// 的 native 用例兜底。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:mimao/comic/engine/engine.dart';

/// 记录表达式、按前缀回放搜索结果的假宿主。
class _RecordingHost implements JsHost {
  _RecordingHost({required this.searchResult});

  /// `source.search.*` 表达式的返回值（模拟源脚本执行结果）。
  final Object? searchResult;

  /// 引擎发来的全部表达式（注册探针 + 搜索调用）。
  final List<String> expressions = <String>[];

  bool closed = false;

  @override
  Future<void> loadScript(String script) async {}

  @override
  Future<Object?> evaluate(String expression) async {
    expressions.add(expression);
    // 注册期的实例化/settings 快照/init 探针不是搜索，回 null 即可。
    if (expression.startsWith('source.search.load')) return searchResult;
    return null;
  }

  @override
  void close() => closed = true;

  /// 最近一次搜索表达式。
  String get searchExpression =>
      expressions.lastWhere((e) => e.startsWith('source.search.load'));
}

const String _fakeSourceScript = r'''
class FakeSource extends ComicSource {
  var key = "fake";
  var name = "Fake";
}
''';

/// 注册一个假源并返回 (host, engine)。
Future<(_RecordingHost, ComicSourceEngine)> _setup({
  Object? searchResult,
}) async {
  final host = _RecordingHost(searchResult: searchResult);
  final pool = SourceExecutionPool(hostFactory: () => host);
  await pool.register('fake', _fakeSourceScript);
  addTearDown(pool.disposeAll);
  return (host, ComicSourceEngine(pool: pool));
}

void main() {
  group('默认 options（optionList defaultValue）', () {
    test('表达式包含 default 优先逻辑与 loadNext 回退', () async {
      final (host, engine) = await _setup(
        searchResult: <String, Object?>{
          'comics': <Object?>[
            <String, Object?>{'id': 'c1', 'title': '默认选项漫画'},
          ],
        },
      );

      final result = await engine.search('fake', '海贼');

      final expression = host.searchExpression;
      // optionList + default 优先（Venera：defaultVal ?? 第一个合法 value）。
      expect(expression, contains('source.search.optionList'));
      expect(
        expression,
        contains("Object.prototype.hasOwnProperty.call(item, 'default')"),
      );
      expect(expression, contains('JSON.stringify(item.default)'));
      // "value-显示名" 取第一个合法 value。
      expect(expression, contains('entry.indexOf("-")'));
      // 没有 load 时必须回退到 loadNext，且首屏 next token 为 null。
      expect(expression, contains('source.search.loadNext'));
      expect(expression, contains(', null)'));

      expect(result.diagnostics, isEmpty);
      expect(result.items.single.title, '默认选项漫画');
    });

    test('没有 optionList 时走空数组守卫，不抛错', () async {
      final (host, engine) = await _setup(
        searchResult: <String, Object?>{'comics': <Object?>[]},
      );

      final result = await engine.search('fake', 'x');

      // 缺 optionList / 非数组 → `[]`（Venera 默认选项为空）。
      expect(
        host.searchExpression,
        contains('if (!Array.isArray(list)) return [];'),
      );
      expect(result.items, isEmpty);
      expect(result.diagnostics, isEmpty);
    });

    test('关键词仍用 _q 转义，不引入注入面', () async {
      final (host, engine) = await _setup(
        searchResult: <String, Object?>{'comics': <Object?>[]},
      );

      await engine.search('fake', '海"贼\\1');

      expect(host.searchExpression, contains(r'"海\"贼\\1"'));
    });
  });

  group('显式 options', () {
    test('使用调用方传入的值，不再计算 optionList 默认值', () async {
      final (host, engine) = await _setup(
        searchResult: <String, Object?>{'comics': <Object?>[]},
      );

      await engine.search('fake', '海贼', options: <String>['st0', '0']);

      final expression = host.searchExpression;
      expect(expression, contains('["st0","0"]'));
      expect(expression, isNot(contains('optionList')));
      // 显式 options 同样有 loadNext 回退。
      expect(expression, contains('source.search.loadNext'));
    });
  });

  group('loadNext 结果解析', () {
    test('{comics: [...]} 能解析出条目，maxPage 为 null', () async {
      final (_, engine) = await _setup(
        searchResult: <String, Object?>{
          'comics': <Object?>[
            <String, Object?>{
              'id': 'e1',
              'title': 'E-Hentai 条目',
              'cover': 'https://img.test/e1.jpg',
              'tags': <String>['tag'],
            },
          ],
        },
      );

      final result = await engine.search('fake', 'keyword');

      expect(result.diagnostics, isEmpty);
      expect(result.items, hasLength(1));
      expect(result.items.single.id, 'e1');
      expect(result.items.single.title, 'E-Hentai 条目');
      expect(result.maxPage, isNull);
    });
  });
}
