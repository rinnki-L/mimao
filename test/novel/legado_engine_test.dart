// 书源引擎四阶段单测：搜索 → 发现 → 详情/目录 → 正文（含目录/正文分页、缓存）。
//
// 用假传输返回固定页面，完全离线；JS 路径由 legado_js_host_test 覆盖。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/cache/novel_cache.dart';
import 'package:mimao/novel/engine/legado_engine.dart';
import 'package:mimao/novel/engine/novel_http_client.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

class _FixtureTransport implements NovelHttpTransport {
  final List<String> requested = <String>[];

  @override
  Future<NovelHttpResponse> send(NovelHttpRequest request) async {
    requested.add(request.url);
    return NovelHttpResponse(
      url: request.url,
      statusCode: 200,
      body: _bodyFor(request.url),
    );
  }

  String _bodyFor(String url) {
    if (url.contains('/search')) return _searchHtml;
    if (url.contains('/list/')) return _exploreHtml;
    if (url.endsWith('/toc')) return _tocHtml;
    if (url.endsWith('/toc2')) return _toc2Html;
    if (url.contains('page=2')) return _content2Html;
    if (url.endsWith('/book/1/1')) return _content1Html;
    if (url.endsWith('/book/1/2')) return _content2Html;
    if (url.contains('/book/1')) return _detailHtml;
    return '<html><body>not found</body></html>';
  }

  @override
  void close() {}
}

class _MemoryCache implements NovelCache {
  final Map<String, NovelContent> _store = <String, NovelContent>{};

  @override
  Future<NovelContent?> read(NovelRef ref, NovelChapter chapter) async =>
      _store['${ref.id}:${chapter.id}'];

  @override
  Future<void> write(
    NovelRef ref,
    NovelChapter chapter,
    NovelContent content,
  ) async {
    _store['${ref.id}:${chapter.id}'] = content;
  }

  @override
  Future<void> clear(NovelRef ref) async =>
      _store.removeWhere((key, _) => key.startsWith('${ref.id}:'));
}

NovelBookSource _source() => NovelBookSource(
  key: 'src1',
  name: '测试源',
  url: 'https://site.test',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{
    'bookSourceUrl': 'https://site.test',
    'searchUrl': '/search?kw={{key}}&page={{page}}',
    'exploreUrl': '玄幻::/list/1/{{page}}.html\n都市::/list/2/{{page}}.html',
    'ruleSearch': <String, dynamic>{
      'bookList': 'class.result@li',
      'name': 'a.0@text',
      'author': 'class.author@text',
      'bookUrl': 'a.0@href',
      'coverUrl': 'img@src',
      'intro': 'class.intro@text',
      'kind': 'class.kind@text',
    },
    'ruleExplore': <String, dynamic>{
      'bookList': 'class.result@li',
      'name': 'a.0@text',
      'author': 'class.author@text',
      'bookUrl': 'a.0@href',
    },
    'ruleBookInfo': <String, dynamic>{
      'name': 'h1@text',
      'author': 'class.author@text',
      'intro': 'class.intro@text',
      'coverUrl': 'img@src',
      'tocUrl': 'a.toc@href',
    },
    'ruleToc': <String, dynamic>{
      'chapterList': 'class.chapters@li',
      'chapterName': 'a@text',
      'chapterUrl': 'a@href',
      'nextTocUrl': 'a.nextToc@href',
    },
    'ruleContent': <String, dynamic>{
      'content': '#content@html',
      'title': 'h2@text',
      'nextContentUrl': 'a.next@href',
    },
  },
);

const String _searchHtml = '''
<html><body>
<ul class="result">
  <li><a href="/book/1">书名一</a><span class="author">作者一</span>
      <img src="/cover/1.jpg"><span class="intro">简介一</span>
      <span class="kind">玄幻</span></li>
  <li><a href="/book/2">书名二</a><span class="author">作者二</span></li>
</ul>
</body></html>
''';

const String _exploreHtml = '''
<html><body><ul class="result">
<li><a href="/book/1">书名一</a><span class="author">作者一</span></li>
</ul></body></html>
''';

const String _detailHtml = '''
<html><body>
<h1>书名一</h1>
<span class="author">作者一</span>
<div class="intro">这是简介。</div>
<img src="/cover/1.jpg">
<a class="toc" href="/book/1/toc">目录</a>
</body></html>
''';

const String _tocHtml = '''
<html><body><ul class="chapters">
<li><a href="/book/1/4">第四章</a></li>
<li><a href="/book/1/3">第三章</a></li>
</ul>
<a class="nextToc" href="/book/1/toc2">下一页</a>
</body></html>
''';

const String _toc2Html = '''
<html><body><ul class="chapters">
<li><a href="/book/1/2">第二章</a></li>
<li><a href="/book/1/1">第一章</a></li>
</ul></body></html>
''';

const String _content1Html = '''
<html><body>
<h2>第一章 标题</h2>
<div id="content"><p>第一页第一段。</p><p>第一页第二段。</p></div>
<a class="next" href="/book/1/1?page=2">下一页</a>
</body></html>
''';

const String _content2Html = '''
<html><body>
<h2>第一章 标题</h2>
<div id="content"><p>第二页第一段。</p></div>
</body></html>
''';

void main() {
  late _FixtureTransport transport;
  late LegadoNovelEngine engine;
  late NovelBookSource source;

  setUp(() {
    transport = _FixtureTransport();
    engine = LegadoNovelEngine(transport: transport, cache: _MemoryCache());
    source = _source();
  });

  tearDown(() => engine.close());

  test('搜索：URL 插值、列表规则、相对链接补全', () async {
    final books = await engine.searchSource(source, '关键词', page: 2);
    expect(books.length, 2);
    final book = books.first;
    expect(book.title, '书名一');
    expect(book.author, '作者一');
    expect(book.bookUrl, 'https://site.test/book/1');
    expect(book.coverUrl, 'https://site.test/cover/1.jpg');
    expect(book.intro, '简介一');
    expect(book.kind, '玄幻');
    expect(book.sourceKey, 'src1');
    expect(
      transport.requested.single,
      contains('kw=%E5%85%B3%E9%94%AE%E8%AF%8D&page=2'),
    );
  });

  test('发现：分类目录解析 + 列表抓取', () async {
    final kinds = await engine.exploreKinds(source);
    expect(kinds.map((kind) => kind.name), <String>['玄幻', '都市']);
    final books = await engine.exploreSource(source, kinds.first, page: 1);
    expect(books.single.title, '书名一');
  });

  test('详情 + 目录：分页、去重、阅读顺序、索引重排', () async {
    final detail = await engine.bookDetail(
      source,
      NovelRef(
        id: 'src1::https://site.test/book/1',
        sourceKey: 'src1',
        bookUrl: 'https://site.test/book/1',
      ),
    );
    expect(detail.title, '书名一');
    expect(detail.author, '作者一');
    expect(detail.intro, '这是简介。');
    expect(detail.coverUrl, 'https://site.test/cover/1.jpg');
    expect(detail.chapters.map((chapter) => chapter.title), <String>[
      '第一章',
      '第二章',
      '第三章',
      '第四章',
    ]);
    expect(detail.chapters.map((chapter) => chapter.index), <int>[0, 1, 2, 3]);
    expect(detail.chapters.first.url, 'https://site.test/book/1/1');
  });

  test('正文：分页拼接、标题覆盖、HTML 转段落、缓存命中', () async {
    final ref = NovelRef(
      id: 'src1::https://site.test/book/1',
      sourceKey: 'src1',
      bookUrl: 'https://site.test/book/1',
    );
    const chapter = NovelChapter(
      id: 'https://site.test/book/1/1',
      title: '第一章',
      index: 0,
      url: 'https://site.test/book/1/1',
    );
    final content = await engine.contentFor(source, ref, chapter);
    expect(content.title, '第一章 标题');
    expect(content.paragraphs, contains('第一页第一段。'));
    expect(content.paragraphs, contains('第二页第一段。'));

    final before = transport.requested.length;
    final cached = await engine.contentFor(source, ref, chapter);
    expect(cached.paragraphs, content.paragraphs);
    expect(transport.requested.length, before, reason: '第二次应命中缓存');
  });

  test('源无搜索地址时给出可读错误', () async {
    final broken = NovelBookSource(
      key: 'bad',
      name: '坏源',
      url: 'https://bad.test',
      type: 0,
      enabled: true,
      raw: <String, dynamic>{'bookSourceUrl': 'https://bad.test'},
    );
    expect(
      () => engine.searchSource(broken, 'x'),
      throwsA(isA<NovelEngineException>()),
    );
  });
}
