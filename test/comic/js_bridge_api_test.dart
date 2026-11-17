/// js_bridge API 对齐性测试（纯 Dart，无 native 依赖，CI 可跑）。
///
/// 用真实 Venera 社区源的 API 调用形状直接喂 ComicJsBridge：验证
/// html/convert/cookie/log/uuid/random/http 各 method 都能解析出结果。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';

import 'package:mimao/comic/engine/engine.dart';

import 'fixtures.dart';

/// 记录请求头/URL 的假 HTTP 客户端。
class _RecordingClient implements ComicHttpClient {
  @override
  Future<ComicHttpResponse> fetch(
    String url, {
    ComicFetchOptions options = const ComicFetchOptions(),
  }) async {
    seenUrls.add(url);
    seenHeaders.add(Map<String, String>.from(options.headers));
    final body = url.contains('search')
        ? fixtureSearchHtml
        : url.contains('/comic/') && url.contains('ch-')
        ? fixtureImagesHtml
        : url.contains('/comic/')
        ? fixtureDetailHtml
        : '{"ok":true}';
    return ComicHttpResponse(
      statusCode: 200,
      body: body,
      bodyBytes: utf8.encode(body),
      url: url,
    );
  }

  final List<String> seenUrls = <String>[];
  final List<Map<String, String>> seenHeaders = <Map<String, String>>[];

  final Map<String, String> _cookieStore = <String, String>{};

  @override
  Future<void> setCookies(String url, Map<String, String> cookies) async {
    _cookieStore.addAll(cookies);
  }

  @override
  List<Map<String, String>> getCookies(String url) => _cookieStore.entries
      .map((e) => <String, String>{'name': e.key, 'value': e.value})
      .toList();

  @override
  Future<void> deleteCookies(String url) async {
    _cookieStore.clear();
  }
}

void main() {
  group('真实 Venera 源 API 形状 → js_bridge 对齐', () {
    test('HtmlDocument.querySelectorAll / text / attributes 解析搜索页', () async {
      final bridge = ComicJsBridge(client: _RecordingClient());
      final docKey = bridge._sync(<dynamic, dynamic>{
        'method': 'html',
        'function': 'parse',
        'data': fixtureSearchHtml,
      });
      final nodes =
          bridge._sync(<dynamic, dynamic>{
                'method': 'html',
                'function': 'querySelectorAll',
                'key': docKey,
                'query': '.result-item',
              })
              as List;
      expect(nodes.length, 2);

      final titles = <String>[];
      for (final nodeKey in nodes) {
        final anchor = bridge._sync(<dynamic, dynamic>{
          'method': 'html',
          'function': 'dom_querySelector',
          'key': nodeKey,
          'query': 'a.title',
          'doc': docKey,
        });
        titles.add(
          bridge._sync(<dynamic, dynamic>{
                'method': 'html',
                'function': 'getText',
                'key': anchor,
                'doc': docKey,
              })
              as String,
        );
      }
      expect(titles, <String>['海贼王', '咒术回战']);
    });

    test('Convert.encodeUtf8 / md5 / base64 与 dart:convert 结果一致', () async {
      final bridge = ComicJsBridge(client: _RecordingClient());
      final utf8Bytes =
          bridge._sync(<dynamic, dynamic>{
                'method': 'convert',
                'type': 'utf8',
                'value': 'abc',
                'isEncode': true,
              })
              as List<int>;
      expect(utf8Bytes, utf8.encode('abc'));

      final md5Bytes =
          bridge._sync(<dynamic, dynamic>{
                'method': 'convert',
                'type': 'md5',
                'value': 'abc',
                'isEncode': true,
              })
              as List<int>;
      expect(md5Bytes, crypto.md5.convert(utf8.encode('abc')).bytes);

      // 对齐 Venera：encodeBase64 返回字符串，decodeBase64 返回字节。
      final b64 =
          bridge._sync(<dynamic, dynamic>{
                'method': 'convert',
                'type': 'base64',
                'value': utf8Bytes,
                'isEncode': true,
              })
              as String;
      expect(b64, base64.encode(utf8.encode('abc')));
    });

    test('Network.get → method:http 返回 status/body，带自定义头', () async {
      final client = _RecordingClient();
      final bridge = ComicJsBridge(client: client);
      final result = await bridge.dispatch(<dynamic, dynamic>{
        'method': 'http',
        'http_method': 'GET',
        'url': 'https://fixture.test/search?q=x',
        'headers': <dynamic, dynamic>{'User-Agent': 'fixture-UA'},
        'data': null,
      });
      expect(result, isA<Map>());
      final map = result as Map;
      expect(map['status'], 200);
      expect(map['body'], fixtureSearchHtml);
      expect(client.seenHeaders.first['User-Agent'], 'fixture-UA');
    });

    test('Network.get → bytes:true 返回字节体', () async {
      final bridge = ComicJsBridge(client: _RecordingClient());
      final result = await bridge.dispatch(<dynamic, dynamic>{
        'method': 'http',
        'http_method': 'GET',
        'bytes': true,
        'url': 'https://fixture.test/search',
        'headers': <dynamic, dynamic>{},
      });
      final map = result as Map;
      expect(map['body'], isA<List<int>>());
      expect((map['body'] as List<int>).isNotEmpty, isTrue);
    });

    test('Network.setCookies / getCookies / deleteCookies', () async {
      final bridge = ComicJsBridge(client: _RecordingClient());
      bridge._sync(<dynamic, dynamic>{
        'method': 'cookie',
        'function': 'set',
        'url': 'https://fixture.test',
        'cookies': [
          <dynamic, dynamic>{'name': 'sid', 'value': 'abc', 'domain': ''},
        ],
      });
      await Future<void>.delayed(Duration.zero);
      final cookies =
          bridge._sync(<dynamic, dynamic>{
                'method': 'cookie',
                'function': 'get',
                'url': 'https://fixture.test',
              })
              as List;
      expect(cookies, hasLength(1));
      expect((cookies.first as Map)['name'], 'sid');
    });

    test('console.log → method:log 落日志；uuid/random 形状正确', () async {
      final bridge = ComicJsBridge(client: _RecordingClient());
      bridge._sync(<dynamic, dynamic>{
        'method': 'log',
        'level': 'info',
        'title': 'JS Console',
        'content': 'hello',
      });
      expect(bridge.logs.single.content, 'hello');

      final uuid = bridge._sync(<dynamic, dynamic>{'method': 'uuid'}) as String;
      expect(uuid, matches(RegExp(r'^[0-9a-f-]{36}$')));

      final n = bridge._sync(<dynamic, dynamic>{
        'method': 'random',
        'type': 'int',
        'min': 5,
        'max': 5,
      });
      expect(n, 5);
    });

    test('loadData/saveData/deleteData/loadSetting/isLogged 回调可注入', () async {
      final bridge = ComicJsBridge(client: _RecordingClient());
      final store = <String, Object?>{'token': 't1'};
      bridge.loadData = (key, dataKey) => store[dataKey];
      bridge.saveData = (key, dataKey, data) => store[dataKey] = data;
      bridge.deleteData = (key, dataKey) => store.remove(dataKey);
      bridge.loadSetting = (key, settingKey) => 'default-setting';
      bridge.isLogged = (key) => true;

      expect(
        bridge._sync(<dynamic, dynamic>{
          'method': 'load_data',
          'key': 'fixture',
          'data_key': 'token',
        }),
        't1',
      );
      bridge._sync(<dynamic, dynamic>{
        'method': 'save_data',
        'key': 'fixture',
        'data_key': 'token',
        'data': 't2',
      });
      expect(store['token'], 't2');
      expect(
        bridge._sync(<dynamic, dynamic>{
          'method': 'load_setting',
          'key': 'fixture',
          'setting_key': 'x',
        }),
        'default-setting',
      );
      expect(
        bridge._sync(<dynamic, dynamic>{
          'method': 'isLogged',
          'key': 'fixture',
        }),
        isTrue,
      );
    });
  });
}

/// 测试便捷封装：拿同步分派的值（http 不会走到这里）。
extension _SyncDispatch on ComicJsBridge {
  Object? _sync(Map<dynamic, dynamic> message) {
    final (value, needsAsync) = dispatchSync(message);
    assert(!needsAsync, '同步测试不应触发 http/delay');
    return value;
  }
}
