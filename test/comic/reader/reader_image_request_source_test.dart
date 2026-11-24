// 章节图片请求头贯通：源实现 ReaderImageRequestSource 时，ImageRequest
// 原样进入章节流与 LazyChapterSource，不再被拍平成纯地址。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_chapter_source.dart';
import 'package:mimao/comic/reader/reader_integration.dart';
import 'package:mimao/comic/reader/reader_models.dart';
import 'package:mimao/comic/reader/reader_waterfall_controller.dart';

class _RequestSource implements ReaderChapterSource, ReaderImageRequestSource {
  int loadCalls = 0;

  @override
  int get chapterCount => 2;

  @override
  String chapterId(int chapter) => 'ep-$chapter';

  @override
  Future<List<String>> load(int chapter, ReaderLoadScope scope) async => [
    for (final request in await loadRequests(chapter, scope)) request.url,
  ];

  @override
  Future<List<ImageRequest>> loadRequests(
    int chapter,
    ReaderLoadScope scope,
  ) async {
    loadCalls++;
    return <ImageRequest>[
      ImageRequest(
        url: 'https://img/$chapter-1.jpg',
        headers: const <String, String>{'Referer': 'https://site/'},
      ),
      ImageRequest(url: 'https://img/$chapter-2.jpg'),
    ];
  }
}

void main() {
  test('瀑布流保存源注入的图片请求头', () async {
    final source = _RequestSource();
    final waterfall = ReaderWaterfallController(
      source: source,
      initialChapter: 1,
      initialChapterId: 'ep-1',
    );
    await waterfall.start();

    final first = waterfall.flow.imageAt(1)!;
    expect(first.url, 'https://img/1-1.jpg');
    expect(first.request.headers['Referer'], 'https://site/');
    final second = waterfall.flow.imageAt(2)!;
    expect(second.request.headers, isEmpty);
  });

  test('LazyChapterSource 优先走 loadRequests 并缓存结果', () async {
    var calls = 0;
    final source = LazyChapterSource(
      episodeIds: const <String>['ep-1'],
      titles: const <String>['第 1 章'],
      loadRequests: (chapter) async {
        calls++;
        return <ImageRequest>[
          const ImageRequest(
            url: 'https://img/1.jpg',
            headers: <String, String>{'Cookie': 'a=b'},
          ),
        ];
      },
    );

    final scope = ReaderLoadScope();
    final first = await source.loadRequests(1, scope);
    final again = await source.loadRequests(1, ReaderLoadScope());
    expect(first.single.headers['Cookie'], 'a=b');
    expect(again.single, same(first.single));
    expect(calls, 1, reason: '同一章第二次读取走缓存');
    expect(await source.load(1, ReaderLoadScope()), <String>[
      'https://img/1.jpg',
    ]);
  });

  test('只有纯地址时自动包成无头 ImageRequest', () async {
    final source = LazyChapterSource(
      episodeIds: const <String>['ep-1'],
      titles: const <String>['第 1 章'],
      loadImages: (_) async => <String>['a.jpg'],
    );
    final requests = await source.loadRequests(1, ReaderLoadScope());
    expect(requests.single.url, 'a.jpg');
    expect(requests.single.headers, isEmpty);
  });
}
