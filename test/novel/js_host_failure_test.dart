// 网络回归单测：java.post 的 body 正确落进请求、失败不永久缓存。
//
// 无 native 库的环境自动 skip（与 test/novel/legado_js_host_test.dart 同款）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/analyzer/legado_rule_analyzer.dart';
import 'package:mimao/novel/engine/novel_http_client.dart';
import 'package:mimao/novel/js/legado_js_host.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

bool get _hasNativeJs => File('flutter_qjs_plugin.dll').existsSync();

/// 记录每次请求的 body / method，并可让前 N 次请求失败。
class _RecordingTransport implements NovelHttpTransport {
  _RecordingTransport({this.failFirst = 0});

  final int failFirst;
  final List<NovelHttpRequest> requests = <NovelHttpRequest>[];

  @override
  Future<NovelHttpResponse> send(NovelHttpRequest request) async {
    requests.add(request);
    if (requests.length <= failFirst) {
      throw StateError('模拟网络抖动');
    }
    return NovelHttpResponse(
      url: request.url,
      statusCode: 200,
      body: '成功正文-${request.method}',
    );
  }

  @override
  void close() {}
}

NovelBookSource _source() => NovelBookSource(
  key: 'k1',
  name: '测试源',
  url: 'https://example.com',
  type: 0,
  enabled: true,
  raw: <String, dynamic>{'bookSourceUrl': 'https://example.com'},
);

RuleJsContext _context(LegadoJsHost host) {
  final analyzer = LegadoRuleAnalyzer(
    content: '<div></div>',
    baseUrl: 'https://example.com',
    jsRunner: host.evaluate,
  );
  return RuleJsContext(
    callbacks: analyzer,
    result: 'https://example.com',
    baseUrl: 'https://example.com',
  );
}

void main() {
  if (!_hasNativeJs) {
    test('skip：缺少 flutter_qjs_plugin.dll', () {}, skip: '无 native QuickJS');
    return;
  }

  late _RecordingTransport transport;
  late LegadoJsHost host;
  late RuleJsContext context;

  setUp(() {
    transport = _RecordingTransport();
    host = LegadoJsHost(transport: transport, source: _source());
    context = _context(host);
  });

  tearDown(() => host.dispose());

  test('java.post 的 body 不被当 timeout，正确进入请求', () async {
    final value = await host.evaluate(
      'java.post("http://x/kw", "kw=abc", "{}").body',
      context,
    );
    expect(value, '成功正文-POST');
    expect(transport.requests, hasLength(1));
    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(request.body, 'kw=abc');
  });

  test('java.post 的错误串不再被当超时参数，超时是 args[3]', () async {
    // 第四个参数是 timeout；即使传了它也不该影响 body。
    await host.evaluate(
      'java.post("http://x/kw", "kw=abc", "{}", 123).body',
      context,
    );
    expect(transport.requests.single.body, 'kw=abc');
  });

  test('首次失败不缓存，第二次重放拿到成功正文', () async {
    transport = _RecordingTransport(failFirst: 1);
    host.dispose();
    host = LegadoJsHost(transport: transport, source: _source());
    context = _context(host);

    final first = await host.evaluate('java.ajax("http://x/flaky")', context);
    // 预取失败不入缓存 → 这一轮仍只有 sentinel，JS 抛 __MIMAO_FETCH__。
    // evaluate 重放时再抓一次即成功。
    expect(first, '成功正文-GET');
    expect(transport.requests, hasLength(2));
    expect(host.logs.any((line) => line.contains('请求失败')), isTrue);
    expect(host.logs.any((line) => line.contains('不缓存')), isTrue);
  });
}
