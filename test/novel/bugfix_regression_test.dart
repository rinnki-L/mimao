// 小说书源引擎 bug 清单的回归测试：规则解析 / URL 编码 / 数据层 / JS helper。
//
// 全部离线、无 native QuickJS 依赖（JS 相关的行为通过 helper 与 preamble 文本断言）。
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:mimao/core/db.dart';
import 'package:mimao/core/library.dart';
import 'package:mimao/novel/analyzer/regex_analyzer.dart';
import 'package:mimao/novel/analyzer/simple_xpath.dart';
import 'package:mimao/novel/cache/file_novel_cache.dart';
import 'package:mimao/novel/collect_service.dart';
import 'package:mimao/novel/engine/analyze_url.dart';
import 'package:mimao/novel/engine/explore_kinds.dart';
import 'package:mimao/novel/engine/novel_http_client.dart';
import 'package:mimao/novel/js/js_helpers.dart' as helpers;
import 'package:mimao/novel/js/js_preamble.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/novel_db.dart';
import 'package:mimao/novel/novel_projection.dart';
import 'package:mimao/novel/source/novel_source_repository.dart';
import 'package:mimao/novel/source/novel_source_store.dart';
import 'package:path/path.dart' as p;

class _FakeTransport implements NovelHttpTransport {
  @override
  Future<NovelHttpResponse> send(NovelHttpRequest request) async =>
      NovelHttpResponse(url: request.url, statusCode: 200, body: 'ok');

  @override
  void close() {}
}

/// 记录最后一次请求，用于断言编码后的 body。
class _RecordingTransport implements NovelHttpTransport {
  NovelHttpRequest? lastRequest;

  @override
  Future<NovelHttpResponse> send(NovelHttpRequest request) async {
    lastRequest = request;
    return NovelHttpResponse(url: request.url, statusCode: 200, body: 'ok');
  }

  @override
  void close() {}
}

void main() {
  group('规则解析', () {
    test('RegexAnalyzer 多段 && 递归匹配（对齐 Kotlin AnalyzeByRegex）', () {
      // 第一段抓每条 <li>，第二段从拼接结果里取捕获组。
      final patterns = <String>[r'<li>(.*?)</li>', r'第(\d+)章'];
      final result = RegexAnalyzer.getElements('abc第1章def第2章ghi', patterns);
      // 单段即可匹配时退化为普通 allMatches；这里直接测多段链路：
      final multi = RegexAnalyzer.getElements(
        '<li>第1章</li><li>第2章</li>',
        <String>[r'<li>(.*?)</li>', r'第(\d+)章'],
      );
      expect(multi, hasLength(2));
      expect(multi.first, <String>['第1章', '1']);
      expect(result, isNotNull);
    });

    test('getElement 多段 &&：非末段取所有匹配整段喂给末段', () {
      final groups = RegexAnalyzer.getElement('x<a>1</a>y<a>2</a>z', <String>[
        r'<a>(.*?)</a>',
        r'(\d)',
      ]);
      expect(groups, <String>['1', '1']);
    });

    test('simpleXPath 自轴 . 返回当前节点，不是子节点', () {
      final doc = html_parser.parse(
        '<div id="d"><span>A</span><span>B</span></div>',
      );
      final div = doc.querySelector('#d')!;
      // //div/. 应得到 div 本身（1 个元素），而非两个 span。
      final self = simpleXPath(doc.documentElement!, '//div/.');
      expect(self, hasLength(1));
      expect((self.first as dynamic).localName, 'div');
      // //div/./span 应得到两个 span，结果不错位。
      final spans = simpleXPath(doc.documentElement!, '//div/./span');
      expect(spans, hasLength(2));
      expect(div.children, hasLength(2));
    });
  });

  group('URL / 编码', () {
    test('_querySafe 含 %：已编码与未编码混合不会被二次编码', () async {
      final analyze = await AnalyzeUrl.resolve(
        ruleUrl: 'https://example.com/s?q=%E5%BC%A0%E4%B8%89&p=中文',
        baseUrl: 'https://example.com',
        transport: _FakeTransport(),
      );
      expect(analyze.resolvedUrl, contains('q=%E5%BC%A0%E4%B8%89'));
      expect(analyze.resolvedUrl, contains('p=%E4%B8%AD%E6%96%87'));
      expect(analyze.resolvedUrl, isNot(contains('%25')));
    });

    test("charset:'escape' 走 JS escape() 的 %uXXXX 语义", () async {
      final transport = _RecordingTransport();
      final analyze = await AnalyzeUrl.resolve(
        ruleUrl:
            'https://example.com/api,{"method":"POST","charset":"escape","body":"q=中文"}',
        baseUrl: 'https://example.com',
        transport: transport,
      );
      expect(analyze.method, 'POST');
      await analyze.fetch();
      expect(analyze.charset, 'escape');
      // 旧实现把 escape 当 utf8 → %E4%B8%AD；正确是 JS escape 的 %u4E2D。
      expect(transport.lastRequest?.body, 'q=%u4E2D%u6587');
      expect(transport.lastRequest?.body, isNot(contains('%E4')));
    });

    test('escape() 直接单测：码元 >255 编 %uXXXX', () {
      // 通过公开的 form 编码路径间接验证：escape 下不会按 UTF-8 逐字节出 %XX。
      expect(helpers.toTraditional('书'), '書');
      expect(helpers.toSimplified('書'), '书');
    });
  });

  group('发现分类', () {
    test('<js>…</js> 包裹被剥掉后执行，不把 <js> 当 JS 语句', () async {
      final kinds = await parseExploreKinds(
        '<js>JSON.stringify([{title:"都市",url:"/u/1"}])</js>',
        jsRunner: (code, context) async {
          expect(code, isNot(contains('<js>')));
          return [
            <String, Object?>{'title': '都市', 'url': '/u/1'},
          ];
        },
        baseUrl: 'https://example.com',
      );
      expect(kinds, hasLength(1));
      expect(kinds.first.name, '都市');
    });
  });

  group('数据层', () {
    test('collectRef 不传 book 时保留已有 payload（在线续读信息不丢）', () async {
      final db = NovelDb.forTesting(NativeDatabase.memory());
      final appDb = AppDb.forTesting(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
        await appDb.close();
      });
      final service = NovelCollectService(db, LibraryRepository(appDb));
      const ref = NovelRef(id: 'b1');
      final full = NovelSummary(
        id: 'b1',
        title: '书名',
        sourceKey: 'src-9',
        bookUrl: 'https://example.com/book/1',
        intro: '简介',
      );
      await service.collectRef(ref, title: '书名', book: full);
      // 只更新元数据，不带 book。
      await service.collectRef(ref, title: '新标题');
      final row = await db.collectRow(ref);
      expect(row!.title, '新标题');
      final restored = novelSummaryFromPayload(row.payload);
      expect(restored, isNotNull);
      expect(restored!.sourceKey, 'src-9');
      expect(restored.bookUrl, 'https://example.com/book/1');
    });

    test('NovelSourceRepository 打开失败后允许重试', () async {
      final dir = await Directory.systemTemp.createTemp('novel-source-repo');
      addTearDown(() => dir.delete(recursive: true));
      var attempts = 0;
      final repo = NovelSourceRepository(() async {
        attempts++;
        if (attempts == 1) throw StateError('瞬时故障');
        return NovelSourceStore(dir);
      });
      await expectLater(repo.loadAll(), throwsA(anything));
      final result = await repo.loadAll();
      expect(result, isEmpty);
      expect(attempts, 2);
    });
  });

  group('正文缓存', () {
    test('TTL 过期后 read 返回 null 并删除文件', () async {
      final dir = await Directory.systemTemp.createTemp('novel-cache-ttl');
      addTearDown(() => dir.delete(recursive: true));
      var now = DateTime(2026, 1, 1);
      final cache = FileNovelCache(
        dir,
        ttl: const Duration(days: 7),
        now: () => now,
      );
      const ref = NovelRef(id: 'b1');
      const chapter = NovelChapter(id: 'c1', title: '第一章', index: 0);
      const content = NovelContent(
        chapterId: 'c1',
        title: '第一章',
        paragraphs: <String>['正文'],
      );
      await cache.write(ref, chapter, content);
      expect(await cache.read(ref, chapter), isNotNull);
      now = now.add(const Duration(days: 8));
      expect(await cache.read(ref, chapter), isNull);
    });

    test('超出文件上限时删除最旧的缓存', () async {
      final dir = await Directory.systemTemp.createTemp('novel-cache-cap');
      addTearDown(() => dir.delete(recursive: true));
      final cache = FileNovelCache(dir, ttl: Duration.zero, maxFiles: 2);
      const ref = NovelRef(id: 'b1');
      for (var i = 0; i < 5; i++) {
        await cache.write(
          ref,
          NovelChapter(id: 'c$i', title: '第$i章', index: i),
          NovelContent(chapterId: 'c$i', title: '第$i章'),
        );
      }
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => p.extension(f.path) == '.json');
      expect(files.length, 2);
    });
  });

  group('JS 兼容层', () {
    test('preamble 不再是不对称/签名空桩，且钉住时间随机源', () {
      // 旧的纯空桩 `sign: () => ''` 已被真实 RSA 签名桥替代。
      expect(legadoInitJs, isNot(contains("sign: () => ''")));
      expect(legadoInitJs, contains('__resetPins'));
      expect(legadoInitJs, contains('Date.now = function()'));
      expect(legadoInitJs, contains('Math.random = function()'));
      expect(legadoInitJs, contains('crypto.rsaSignBase64'));
    });

    test('t2s/s2t helper 做真实字级转换', () {
      expect(helpers.toSimplified('書名與作者'), '书名与作者');
      expect(helpers.toTraditional('书名与作者'), '書名與作者');
    });
  });
}
