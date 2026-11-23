// 缓存写入失败回归：写盘异常不能把已成功解析的正文变成“抓取失败”。
//
// 用假传输返回固定页面，完全离线。
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/cache/novel_cache.dart';
import 'package:mimao/novel/engine/legado_engine.dart';
import 'package:mimao/novel/engine/novel_http_client.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

class _FixtureTransport implements NovelHttpTransport {
  @override
  Future<NovelHttpResponse> send(NovelHttpRequest request) async {
    return NovelHttpResponse(
      url: request.url,
      statusCode: 200,
      body: '''
<html><body><h2>标题</h2>
<div id="content"><p>正文第一段。</p><p>正文第二段。</p></div>
</body></html>
''',
    );
  }

  @override
  void close() {}
}

/// 写盘必失败的缓存，模拟磁盘满/权限不足等场景。
class _ThrowingCache implements NovelCache {
  @override
  Future<NovelContent?> read(NovelRef ref, NovelChapter chapter) async => null;

  @override
  Future<void> write(
    NovelRef ref,
    NovelChapter chapter,
    NovelContent content,
  ) async {
    throw StateError('磁盘写入失败');
  }

  @override
  Future<void> clear(NovelRef ref) async {}
}

NovelBookSource _source() => NovelBookSource(
  key: 'cachefail',
  name: '缓存失败测试源',
  url: 'https://site.test',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{
    'bookSourceUrl': 'https://site.test',
    'ruleContent': <String, dynamic>{
      'content': '#content@html',
      'title': 'h2@text',
    },
  },
);

void main() {
  test('缓存 write 抛错时仍返回正文并记录警告', () async {
    final engine = LegadoNovelEngine(
      transport: _FixtureTransport(),
      cache: _ThrowingCache(),
    );
    addTearDown(engine.close);

    final ref = NovelRef(
      id: 'cachefail::https://site.test/book/1',
      sourceKey: 'cachefail',
      bookUrl: 'https://site.test/book/1',
    );
    const chapter = NovelChapter(
      id: 'https://site.test/book/1/1',
      title: '第一章',
      index: 0,
      url: 'https://site.test/book/1/1',
    );

    final content = await engine.contentFor(_source(), ref, chapter);
    expect(content.paragraphs, <String>['正文第一段。', '正文第二段。']);
    expect(engine.warningFor('cachefail'), contains('正文缓存写入失败'));
  });
}
