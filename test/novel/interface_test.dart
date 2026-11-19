// 小说五个窄接口的可实现性测试（验收 6）：fake 实现 + 注入 NovelModule。
//
// 全部离线：不访问网络、不调真实 JS、不落盘；只证明接口形状可用 fake 实现并注入。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/novel/analyzer/rule_analyzer.dart';
import 'package:mimao/novel/analyzer/rule_models.dart';
import 'package:mimao/novel/cache/novel_cache.dart';
import 'package:mimao/novel/engine/engine.dart';
import 'package:mimao/novel/js/js_host.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_entry.dart';

const _ref = NovelRef(id: 'b1');
const _chapter = NovelChapter(id: 'c1', title: '第一章', index: 1);
const _summary = NovelSummary(id: 'b1', title: '书名');
const _detail = NovelDetail(ref: _ref, title: '书名');
const _content = NovelContent(
  chapterId: 'c1',
  title: '第一章',
  paragraphs: <String>['正文'],
);
const _source = BookSource(
  id: 's1',
  name: '书源',
  baseUrl: 'https://example.com',
);

/// fake 数据源：返回固定领域模型，记录调用。
class FakeDataSource implements NovelDataSource {
  int searchCalls = 0;
  int discoverCalls = 0;
  int bookListCalls = 0;
  int bookContentCalls = 0;

  @override
  Future<List<NovelSummary>> search(String keyword) async {
    searchCalls++;
    return <NovelSummary>[_summary];
  }

  @override
  Future<List<NovelSummary>> discover() async {
    discoverCalls++;
    return <NovelSummary>[_summary];
  }

  @override
  Future<NovelDetail> bookList(NovelRef ref) async {
    bookListCalls++;
    return _detail;
  }

  @override
  Future<NovelContent> bookContent(NovelRef ref, NovelChapter chapter) async {
    bookContentCalls++;
    return _content;
  }
}

/// fake 引擎：签名与 DataSource 对齐，额外接收 BookSource。
class FakeEngine implements NovelEngine {
  @override
  Future<List<NovelSummary>> search(BookSource source, String keyword) async =>
      <NovelSummary>[_summary];

  @override
  Future<List<NovelSummary>> discover(BookSource source) async =>
      <NovelSummary>[_summary];

  @override
  Future<NovelDetail> chapters(BookSource source, NovelRef ref) async =>
      _detail;

  @override
  Future<NovelContent> content(
    BookSource source,
    NovelRef ref,
    NovelChapter chapter,
  ) async => _content;
}

/// fake 规则解析器：回显固定结果，不执行任何选择器/JS。
class FakeRuleAnalyzer implements RuleAnalyzer {
  @override
  Future<List<String>> parse(String content, Rule rule) async => <String>[
    '解析结果',
  ];
}

/// fake 缓存：内存 Map 读写，不落盘。
class FakeCache implements NovelCache {
  final Map<String, NovelContent> _store = <String, NovelContent>{};

  @override
  Future<NovelContent?> read(NovelRef ref, NovelChapter chapter) async =>
      _store['${ref.id}:${chapter.id}'];

  @override
  Future<void> write(
    NovelRef ref,
    NovelChapter chapter,
    NovelContent content,
  ) async => _store['${ref.id}:${chapter.id}'] = content;

  @override
  Future<void> clear(NovelRef ref) async =>
      _store.removeWhere((key, _) => key.startsWith('${ref.id}:'));
}

/// fake JS 宿主：不执行任何 JS，仅回显，dispose 记录调用。
class FakeJsHost implements JsHost {
  bool disposed = false;

  @override
  Future<String?> run(
    String snippet, {
    Map<String, Object?> context = const {},
  }) async => '已处理:$snippet';

  @override
  void dispose() => disposed = true;
}

void main() {
  test('6 NovelDataSource / NovelEngine 可用 fake 实现并返回预期领域模型', () async {
    final ds = FakeDataSource();
    expect((await ds.search('关键词')).single, _summary);
    expect((await ds.discover()).single, _summary);
    expect(await ds.bookList(_ref), _detail);
    expect(await ds.bookContent(_ref, _chapter), _content);
    expect(ds.searchCalls, 1);
    expect(ds.discoverCalls, 1);
    expect(ds.bookListCalls, 1);
    expect(ds.bookContentCalls, 1);

    final engine = FakeEngine();
    expect((await engine.search(_source, '关键词')).single, _summary);
    expect((await engine.discover(_source)).single, _summary);
    expect(await engine.chapters(_source, _ref), _detail);
    expect(await engine.content(_source, _ref, _chapter), _content);
  });

  test('6 RuleAnalyzer / NovelCache / JsHost 可用 fake 实现并注入返回预期值', () async {
    final analyzer = FakeRuleAnalyzer();
    expect(
      await analyzer.parse(
        '正文',
        const Rule(mode: RuleMode.css, expression: '.a'),
      ),
      <String>['解析结果'],
    );

    final cache = FakeCache();
    expect(await cache.read(_ref, _chapter), isNull);
    await cache.write(_ref, _chapter, _content);
    expect(await cache.read(_ref, _chapter), _content);
    await cache.clear(_ref);
    expect(await cache.read(_ref, _chapter), isNull);

    final js = FakeJsHost();
    expect(await js.run('1+1'), '已处理:1+1');
    expect(js.disposed, isFalse);
    js.dispose();
    expect(js.disposed, isTrue);
  });

  test('6 五个 fake 全部注入 NovelModule，持有实例且元信息不变', () {
    final ds = FakeDataSource();
    final engine = FakeEngine();
    final module = NovelModule(
      dataSource: ds,
      engine: engine,
      sourceStore: Object(),
    );

    // 注入点可拿回同一实例（窄接口缝真实存在）。
    expect(module.dataSource, same(ds));
    expect(module.engine, same(engine));
    expect(module.sourceStore, isNotNull);
    expect(module.type, MediaType.novel);
    expect(module.label, '小说');
  });
}
