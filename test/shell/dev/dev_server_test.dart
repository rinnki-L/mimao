import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart'
    show PageRouteBuilder, RouteSettings, SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/db.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/shell/dev/dev_capability.dart';
import 'package:mimao/shell/dev/dev_databases.dart';
import 'package:mimao/shell/dev/dev_log.dart';
import 'package:mimao/shell/dev/dev_route.dart';
import 'package:mimao/shell/dev/dev_server.dart';
import 'package:mimao/shell/shell_store.dart';

void main() {
  late DevServer server;
  late Directory tempDir;
  late String driverFile;
  late AppDb appDb;
  const dbName = '__srv_test__';

  /// 默认带合法 token；显式传空串 `token: ''` 表示不带鉴权（测 401 用）。
  Future<(int, Object?)> call(
    String method,
    String path, {
    String? token,
    Object? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:${server.port}$path'),
      );
      final effectiveToken = token ?? server.token;
      if (effectiveToken != null && effectiveToken.isNotEmpty) {
        // 用常量键拼 Bearer 头（避免字面量头名，见 write-tool 脱敏坑）。
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $effectiveToken',
        );
      }
      if (body != null) {
        final payload = body is String ? body : jsonEncode(body);
        request.headers.contentType = ContentType.json;
        request.add(utf8.encode(payload));
      }
      final response = await request.close();
      final raw = await utf8.decoder.bind(response).join();
      final decoded = raw.isEmpty ? null : jsonDecode(raw);
      return (response.statusCode, decoded);
    } finally {
      client.close(force: true);
    }
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mimao_dev_server_test');
    driverFile = '${tempDir.path}${Platform.pathSeparator}driver.json';
    server = DevServer();
    appDb = AppDb.forTesting(NativeDatabase.memory());
    devRegisterDatabase(dbName, appDb);
    await server.start(driverFilePath: driverFile, shotsDir: tempDir.path);
  });

  tearDown(() async {
    await server.stop();
    devUnregisterDatabase(dbName);
    await appDb.close();
    await tempDir.delete(recursive: true);
    shellStore.goHome();
    DevLog.clearForTest();
    devRouteTracker.reset();
  });

  group('driver.json', () {
    test('启动即写：port/token/pid/vmServiceUri/startedAt 齐全', () async {
      final decoded =
          jsonDecode(await File(driverFile).readAsString())
              as Map<String, Object?>;
      expect(decoded['port'], server.port);
      final token = decoded['token'] as String?;
      expect(token, isNotNull);
      expect(token!.length, 64, reason: '32 字节随机数 hex 64 字符');
      expect(decoded['pid'], pid);
      expect(decoded['startedAt'], isNotNull);
      expect(decoded.keys, contains('vmServiceUri'));
    });

    test('start 幂等：不换端口、token 稳定，driver 文件重写', () async {
      final before =
          jsonDecode(await File(driverFile).readAsString())
              as Map<String, Object?>;
      await server.start(driverFilePath: driverFile, shotsDir: tempDir.path);
      final after =
          jsonDecode(await File(driverFile).readAsString())
              as Map<String, Object?>;
      expect(server.port, before['port']);
      expect(after['token'], before['token']);
    });
  });

  group('鉴权', () {
    test('无 token / 错 token → 401', () async {
      final (noToken, _) = await call('GET', '/health', token: '');
      expect(noToken, HttpStatus.unauthorized);

      final (wrongToken, wrongBody) = await call(
        'GET',
        '/health?token=${'x' * 64}',
        token: '',
      );
      expect(wrongToken, HttpStatus.unauthorized);
      expect((wrongBody as Map<String, Object?>)['error'], contains('token'));
    });

    test('?token= 与 Bearer 头都能过', () async {
      final (viaQuery, _) = await call('GET', '/health?token=${server.token}');
      expect(viaQuery, HttpStatus.ok);

      final (viaHeader, _) = await call('GET', '/health', token: server.token);
      expect(viaHeader, HttpStatus.ok);
    });
  });

  group('内省端点', () {
    test('/health 结构齐全', () async {
      final (status, payload) = await call('GET', '/health');
      expect(status, HttpStatus.ok);
      final body = payload! as Map<String, Object?>;
      expect(body['ok'], true);
      expect(body['app'], 'mimao');
      expect(body['debug'], true);
      expect(body['port'], server.port);
      expect(body['pid'], pid);
      expect(body['uptimeSec'], isNotNull);
      expect(body['endpoints'], isNotNull);
    });

    test('/logs 反映 DevLog 记录；level/limit 过滤', () async {
      DevLog.warn('dev', '测试警告一条');
      final (status, payload) = await call('GET', '/logs?level=warn&limit=10');
      expect(status, HttpStatus.ok);
      final entries =
          (payload! as Map<String, Object?>)['entries'] as List<Object?>;
      expect(entries, hasLength(1));
      expect((entries.single as Map<String, Object?>)['message'], '测试警告一条');
    });

    test('/route 端点输出栈深', () async {
      devRouteTracker.didPush(
        PageRouteBuilder<void>(
          settings: const RouteSettings(name: 'p1'),
          pageBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
        null,
      );
      final (status, payload) = await call('GET', '/route');
      expect(status, HttpStatus.ok);
      final body = payload! as Map<String, Object?>;
      expect(body['depth'], 1);
      expect(
        (body['stack'] as List<Object?>).single,
        isA<Map<String, Object?>>(),
      );
    });

    test('/state 输出壳态 + 模块表 + 库名', () async {
      shellStore.openModule(MediaType.comic);
      final (status, payload) = await call('GET', '/state');
      expect(status, HttpStatus.ok);
      final body = payload! as Map<String, Object?>;

      final shell = body['shell']! as Map<String, Object?>;
      expect(shell['activeModule'], 'comic');
      expect(shell['showLibrary'], false);

      expect((body['modules']! as Map<String, Object?>).keys, [
        'anime',
        'comic',
        'novel',
        'music',
      ]);
      expect((body['databases']! as List<Object?>), contains(dbName));
    });

    test('/navigate 落位壳态；坏 body → 400', () async {
      final (status, payload) = await call(
        'POST',
        '/navigate',
        body: <String, Object?>{'action': 'module', 'name': 'music'},
      );
      expect(status, HttpStatus.ok);
      final state =
          (payload! as Map<String, Object?>)['state']! as Map<String, Object?>;
      expect(
        (state['shell']! as Map<String, Object?>)['activeModule'],
        'music',
      );

      final (badStatus, _) = await call('POST', '/navigate', body: 'not-json{');
      expect(badStatus, HttpStatus.badRequest);
    });

    test('未知路径 → 404；错误方法 → 405', () async {
      final (notFound, notFoundBody) = await call('GET', '/nope');
      expect(notFound, HttpStatus.notFound);
      expect(
        (notFoundBody! as Map<String, Object?>)['error'],
        contains('/nope'),
      );

      final (postHealth, _) = await call('POST', '/health', body: '{}');
      expect(postHealth, HttpStatus.methodNotAllowed);

      final (deleteDb, _) = await call('DELETE', '/db');
      expect(deleteDb, HttpStatus.methodNotAllowed);
    });
  });

  group('/db SQL', () {
    test('GET 列库名', () async {
      final (status, payload) = await call('GET', '/db');
      expect(status, HttpStatus.ok);
      expect((payload! as Map<String, Object?>)['databases'], contains(dbName));
    });

    test('/eval：能力执行、未注册 404、GET 列能力', () async {
      devRegisterCapability(
        '__test_cap__',
        (args) async => <String, Object?>{'echo': args['x']},
      );
      addTearDown(() => devUnregisterCapability('__test_cap__'));

      final (okStatus, okPayload) = await call(
        'POST',
        '/eval',
        body: {
          'capability': '__test_cap__',
          'args': {'x': 42},
        },
      );
      expect(okStatus, HttpStatus.ok);
      final body = okPayload! as Map<String, Object?>;
      expect(body['ok'], true);
      // result 经 jsonEncode 成字符串回传（能力返回值统一走编码兜底）。
      expect(body['result'], contains('"echo"'));

      final (listStatus, listPayload) = await call('GET', '/eval');
      expect(listStatus, HttpStatus.ok);
      expect(
        (listPayload! as Map<String, Object?>)['capabilities'],
        contains('__test_cap__'),
      );

      final (missingStatus, missingPayload) = await call(
        'POST',
        '/eval',
        body: {'capability': 'nope'},
      );
      expect(missingStatus, HttpStatus.notFound);
      expect(
        (missingPayload! as Map<String, Object?>)['error'],
        contains('nope'),
      );
    });

    test('SELECT 返回命名列行；参数绑定 ? 正常', () async {
      await appDb.customStatement(
        "INSERT INTO app_settings (key, value) VALUES ('k1', 'v1')",
      );

      final (status, payload) = await call(
        'POST',
        '/db',
        body: <String, Object?>{
          'db': dbName,
          'sql': 'SELECT value FROM app_settings WHERE key = ?',
          'params': <Object?>['k1'],
        },
      );
      expect(status, HttpStatus.ok);
      final body = payload! as Map<String, Object?>;
      expect(body['ok'], true);
      expect(body['kind'], 'select');
      expect(body['rowCount'], 1);
      final rows = body['rows']! as List<Object?>;
      expect((rows.single as Map<String, Object?>)['value'], 'v1');
      expect(body['durationMs'], isNotNull);
    });

    test('INSERT 走 statement 通道；last_insert_rowid 可单独查', () async {
      final (insertStatus, insertPayload) = await call(
        'POST',
        '/db',
        body: <String, Object?>{
          'db': dbName,
          'sql': "INSERT INTO app_settings (key, value) VALUES ('k2', 'v2')",
        },
      );
      expect(insertStatus, HttpStatus.ok);
      final insertBody = insertPayload! as Map<String, Object?>;
      expect(insertBody['ok'], true);
      expect(insertBody['kind'], 'statement');
      expect(insertBody['rowCount'], 0);

      final (selectStatus, selectPayload) = await call(
        'POST',
        '/db',
        body: <String, Object?>{
          'db': dbName,
          'sql': 'SELECT last_insert_rowid() AS rid',
        },
      );
      expect(selectStatus, HttpStatus.ok);
      final rows =
          (selectPayload! as Map<String, Object?>)['rows']! as List<Object?>;
      final rid = (rows.single as Map<String, Object?>)['rid'];
      expect(rid, greaterThan(0));

      final (valueStatus, valuePayload) = await call(
        'POST',
        '/db',
        body: <String, Object?>{
          'db': dbName,
          'sql': 'SELECT value FROM app_settings WHERE key = ?',
          'params': <Object?>['k2'],
        },
      );
      expect(valueStatus, HttpStatus.ok);
      final valueRows =
          (valuePayload! as Map<String, Object?>)['rows']! as List<Object?>;
      expect((valueRows.single as Map<String, Object?>)['value'], 'v2');
    });

    test('bool 参数归一为 int（true→1）', () async {
      final (status, payload) = await call(
        'POST',
        '/db',
        body: <String, Object?>{
          'db': dbName,
          'sql': 'SELECT ? AS flag',
          'params': <Object?>[true],
        },
      );
      expect(status, HttpStatus.ok);
      final rows = (payload! as Map<String, Object?>)['rows']! as List<Object?>;
      expect((rows.single as Map<String, Object?>)['flag'], 1);
    });

    test('INSERT ... RETURNING 拿到行', () async {
      final (status, payload) = await call(
        'POST',
        '/db',
        body: <String, Object?>{
          'db': dbName,
          'sql':
              "INSERT INTO app_settings (key, value) VALUES ('r1', 'rv') "
              'RETURNING key, value',
        },
      );
      expect(status, HttpStatus.ok);
      final body = payload! as Map<String, Object?>;
      expect(body['kind'], 'statement');
      expect(body['rowCount'], 1);
      final rows = body['rows']! as List<Object?>;
      final row = rows.single as Map<String, Object?>;
      expect(row['key'], 'r1');
      expect(row['value'], 'rv');
    });

    test('CTE 读语句（WITH）也走命名行通道', () async {
      final (status, payload) = await call(
        'POST',
        '/db',
        body: <String, Object?>{
          'db': dbName,
          'sql': 'WITH one(x) AS (SELECT 1) SELECT x FROM one',
        },
      );
      expect(status, HttpStatus.ok);
      final rows = (payload! as Map<String, Object?>)['rows']! as List<Object?>;
      expect((rows.single as Map<String, Object?>)['x'], 1);
    });

    test('ATTACH 被拒（403）', () async {
      final (status, payload) = await call(
        'POST',
        '/db',
        body: <String, Object?>{
          'db': dbName,
          'sql': "ATTACH DATABASE 'C:/evil.db' AS evil",
        },
      );
      expect(status, HttpStatus.forbidden);
      expect((payload! as Map<String, Object?>)['ok'], false);
    });

    test('坏 SQL → 400 且 ok=false（不是 500）', () async {
      final (status, payload) = await call(
        'POST',
        '/db',
        body: <String, Object?>{
          'db': dbName,
          'sql': 'SELECT * FROM no_such_table',
        },
      );
      expect(status, HttpStatus.badRequest);
      expect((payload! as Map<String, Object?>)['ok'], false);
    });

    test('未知库名 → 404；缺字段 → 400；body 非 JSON → 400', () async {
      final (badDb, badDbBody) = await call(
        'POST',
        '/db',
        body: <String, Object?>{'db': 'nope', 'sql': 'SELECT 1'},
      );
      expect(badDb, HttpStatus.notFound);
      expect((badDbBody! as Map<String, Object?>)['error'], contains('nope'));

      final (missing, _) = await call(
        'POST',
        '/db',
        body: <String, Object?>{'db': dbName},
      );
      expect(missing, HttpStatus.badRequest);

      final (notJson, _) = await call('POST', '/db', body: 'not-json{');
      expect(notJson, HttpStatus.badRequest);
    });

    test('非标量 params → 400', () async {
      final (status, payload) = await call(
        'POST',
        '/db',
        body: <String, Object?>{
          'db': dbName,
          'sql': 'SELECT ? AS x',
          'params': <Object?>[
            <String, String>{'no': 'map'},
          ],
        },
      );
      expect(status, HttpStatus.badRequest);
      expect((payload! as Map<String, Object?>)['error'], contains('标量'));
    });

    test('前导注释不迷惑读判定/禁令判定', () async {
      // 注释后的 SELECT 仍走命名行通道。
      final (selectStatus, selectPayload) = await call(
        'POST',
        '/db',
        body: <String, Object?>{'db': dbName, 'sql': '-- 查一下\nSELECT 2 AS two'},
      );
      expect(selectStatus, HttpStatus.ok);
      final rows =
          (selectPayload! as Map<String, Object?>)['rows']! as List<Object?>;
      expect((rows.single as Map<String, Object?>)['two'], 2);

      // 注释后的 ATTACH 仍被禁。
      final (attachStatus, _) = await call(
        'POST',
        '/db',
        body: <String, Object?>{
          'db': dbName,
          'sql': "-- 注释\nATTACH DATABASE 'x' AS y",
        },
      );
      expect(attachStatus, HttpStatus.forbidden);
    });
  });
}
