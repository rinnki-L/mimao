// 正文分页回归：每页只给出指向下一页的链接，验证逐页重新求值规则。
//
// 用假传输返回固定页面，完全离线；与 legado_engine_test 的夹具风格一致。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/cache/novel_cache.dart';
import 'package:mimao/novel/engine/legado_engine.dart';
import 'package:mimao/novel/engine/novel_http_client.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

class _ChainTransport implements NovelHttpTransport {
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
    // 每页的 nextContentUrl 只指向紧随其后的那一页；第三页没有下一页。
    final page = RegExp(r'/page/(\d+)').firstMatch(url)?.group(1);
    switch (page) {
      case '1':
        return '''
<html><body><h2>标题</h2>
<div id="content"><p>第一页正文。</p></div>
<a class="next" href="/book/1/page/2">下一页</a>
</body></html>
''';
      case '2':
        return '''
<html><body><h2>标题</h2>
<div id="content"><p>第二页正文。</p></div>
<a class="next" href="/book/1/page/3">下一页</a>
</body></html>
''';
      case '3':
        return '''
<html><body><h2>标题</h2>
<div id="content"><p>第三页正文。</p></div>
</body></html>
''';
      default:
        return '<html><body>not found</body></html>';
    }
  }

  @override
  void close() {}
}

class _NullCache implements NovelCache {
  @override
  Future<NovelContent?> read(NovelRef ref, NovelChapter chapter) async => null;

  @override
  Future<void> write(
    NovelRef ref,
    NovelChapter chapter,
    NovelContent content,
  ) async {}

  @override
  Future<void> clear(NovelRef ref) async {}
}

NovelBookSource _source() => NovelBookSource(
  key: 'chain',
  name: '分页测试源',
  url: 'https://site.test',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{
    'bookSourceUrl': 'https://site.test',
    'ruleContent': <String, dynamic>{
      'content': '#content@html',
      'title': 'h2@text',
      'nextContentUrl': 'a.next@href',
    },
  },
);

void main() {
  final ref = NovelRef(
    id: 'chain::https://site.test/book/1',
    sourceKey: 'chain',
    bookUrl: 'https://site.test/book/1',
  );
  const chapter = NovelChapter(
    id: 'https://site.test/book/1/page/1',
    title: '第一章',
    index: 0,
    url: 'https://site.test/book/1/page/1',
  );

  test('逐页求值 nextContentUrl：三页正文全部拼接', () async {
    final transport = _ChainTransport();
    final engine = LegadoNovelEngine(transport: transport, cache: _NullCache());
    addTearDown(engine.close);

    final content = await engine.contentFor(_source(), ref, chapter);

    expect(content.paragraphs, <String>['第一页正文。', '第二页正文。', '第三页正文。']);
    expect(transport.requested, <String>[
      'https://site.test/book/1/page/1',
      'https://site.test/book/1/page/2',
      'https://site.test/book/1/page/3',
    ]);
  });
}
