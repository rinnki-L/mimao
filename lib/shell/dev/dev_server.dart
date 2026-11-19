import 'dart:async';
import 'dart:convert';
import 'dart:developer' show Service;
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart' show Element, WidgetsBinding;
import 'package:mimao/shell/dev/dev_databases.dart';
import 'package:mimao/shell/dev/dev_log.dart';
import 'package:mimao/shell/dev/dev_navigate.dart';
import 'package:mimao/shell/dev/dev_capability.dart';
import 'package:mimao/shell/dev/dev_route.dart';
import 'package:mimao/shell/dev/dev_shot.dart';
import 'package:mimao/shell/dev/dev_state.dart';
import 'package:mimao/shell/dev/dev_tap.dart';

/// dev harness 的本地 HTTP 服务。
///
/// 安全姿态（与「只服务本机 agent 调试」的定位匹配）：
///   - 只绑 127.0.0.1、端口随机（0）；随机 token 每次启动重生成
///   - 鉴权走 `Bearer` 头或 `?token=` 查询参数（后者为 curl 单行流取巧）
///   - 整个 server 由 startDevHarness 在 kDebugMode 下启动，release 零存在
///   - /db 只拒 ATTACH/DETACH/LOAD——防 SQL 触碰库外文件；其余不设白名单，
///     debug 本机库无生产数据，放宽换取 agent 的完整调试能力
///
/// 驱动信息（端口/token/pid/VM service 地址）写 driver.json，供 skill 侧发现。
final class DevServer {
  HttpServer? _server;
  String? _token;
  DateTime? _startedAt;
  String? _vmServiceUri;

  /// /shot 截图落盘目录（harness 计算后传入）。
  String? _shotsDir;

  bool get isRunning => _server != null;

  /// 监听端口；未启动为 0。
  int get port => _server?.port ?? 0;

  /// 当前 token（未启动为 null）。
  String? get token => _token;

  /// 启动并写 driver.json（幂等：已运行则只刷新 driver 文件）。
  ///
  /// [driverFilePath] 由调用方给出（生产走 path_provider，测试给临时路径）；
  /// 写文件失败只记 [DevLog]，不让 dev 设施拖垮 app。
  Future<void> start({
    required String driverFilePath,
    required String shotsDir,
  }) async {
    if (_server != null) {
      _shotsDir = shotsDir;
      await _writeDriverFile(driverFilePath);
      return;
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _token = _randomToken();
    _startedAt = DateTime.now();
    _shotsDir = shotsDir;
    server.listen(
      (HttpRequest request) => unawaited(_handle(request)),
      onError: (Object error) {
        DevLog.error('dev', 'dev server 监听异常：$error');
      },
      cancelOnError: false,
    );
    DevLog.info('dev', 'dev server 已启动，端口 ${server.port}');
    _vmServiceUri = await _probeVmServiceUri();
    await _writeDriverFile(driverFilePath);
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _token = null;
    _startedAt = null;
    _vmServiceUri = null;
    _shotsDir = null;
    await server?.close(force: true);
  }

  Future<void> _writeDriverFile(String driverFilePath) async {
    try {
      final file = File(driverFilePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'port': port,
          'token': _token,
          'pid': pid,
          'vmServiceUri': _vmServiceUri,
          'startedAt': _startedAt?.toIso8601String(),
        }),
        flush: true,
      );
    } catch (error) {
      DevLog.error('dev', 'driver.json 写入失败（$driverFilePath）：$error');
    }
  }

  /// VM service 地址（best-effort）。plain dart VM 下 DDS 包装可能给出与
  /// --observe 不一致的端口；热重载脚本以 flutter run 控制台输出为准，
  /// 这里只作参考值。
  Future<String?> _probeVmServiceUri() async {
    try {
      return (await Service.getInfo()).serverUri?.toString();
    } catch (_) {
      return null;
    }
  }

  static String _randomToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  // ── 请求分发 ──────────────────────────────────────────────────────────

  Future<void> _handle(HttpRequest request) async {
    try {
      // 先整体读 body（GET 为空串）：不读就响应会让部分客户端挂在发送上。
      final length = request.contentLength;
      if (length > 1024 * 1024) {
        _json(request, HttpStatus.requestEntityTooLarge, <String, Object?>{
          'error': '请求体超过 1MB 上限',
        });
        return;
      }
      final String body = await utf8.decoder.bind(request).join();

      if (!_authorized(request)) {
        _json(request, HttpStatus.unauthorized, <String, Object?>{
          'error': '无效 token（读 driver.json 里的 token 字段）',
        });
        return;
      }

      final path = request.uri.path;
      switch (path) {
        case '/health':
          if (request.method != 'GET') {
            _methodNotAllowed(request, path);
            return;
          }
          _json(request, HttpStatus.ok, _health());
        case '/logs':
          if (request.method != 'GET') {
            _methodNotAllowed(request, path);
            return;
          }
          _json(request, HttpStatus.ok, _logs(request.uri.queryParameters));
        case '/route':
          if (request.method != 'GET') {
            _methodNotAllowed(request, path);
            return;
          }
          _json(request, HttpStatus.ok, <String, Object?>{
            'depth': devRouteTracker.depth,
            'stack': devRouteTracker.snapshot(),
          });
        case '/state':
          if (request.method != 'GET') {
            _methodNotAllowed(request, path);
            return;
          }
          _json(request, HttpStatus.ok, devStateSnapshot());
        case '/tap':
          if (request.method != 'POST') {
            _methodNotAllowed(request, path);
            return;
          }
          final (tapStatus, tapPayload) = await _runTap(body);
          _json(request, tapStatus, tapPayload);
        case '/shot':
          if (request.method != 'GET') {
            _methodNotAllowed(request, path);
            return;
          }
          final shotsDir = _shotsDir;
          if (shotsDir == null) {
            _json(request, HttpStatus.conflict, <String, Object?>{
              'ok': false,
              'error': 'shots 目录未配置（start 未传 shotsDir？）',
            });
            return;
          }
          _json(
            request,
            HttpStatus.ok,
            await captureScreenshot(shotsDir: shotsDir),
          );
        case '/navigate':
          if (request.method != 'POST') {
            _methodNotAllowed(request, path);
            return;
          }
          final (navStatus, navPayload) = await _runNavigate(body);
          _json(request, navStatus, navPayload);
        case '/eval':
          if (request.method == 'GET') {
            _json(request, HttpStatus.ok, <String, Object?>{
              'capabilities': devCapabilityNames(),
            });
          } else if (request.method == 'POST') {
            final (evalStatus, evalPayload) = await _runEval(body);
            _json(request, evalStatus, evalPayload);
          } else {
            _methodNotAllowed(request, path);
          }
        case '/db':
          if (request.method == 'GET') {
            _json(request, HttpStatus.ok, <String, Object?>{
              'databases': devDatabaseNames(),
            });
          } else if (request.method == 'POST') {
            final (status, payload) = await _runSql(body);
            _json(request, status, payload);
          } else {
            _methodNotAllowed(request, path);
          }
        default:
          _json(request, HttpStatus.notFound, <String, Object?>{
            'error':
                '未知路径 $path'
                '（可用：/health /logs /route /state /navigate /tap /shot /db）',
          });
      }
    } catch (error, stack) {
      DevLog.error(
        'dev',
        '处理请求失败 ${request.method} ${request.uri.path}：$error',
        details: stack,
      );
      _json(request, HttpStatus.internalServerError, <String, Object?>{
        'error': '$error',
      });
    }
  }

  void _methodNotAllowed(HttpRequest request, String path) {
    _json(request, HttpStatus.methodNotAllowed, <String, Object?>{
      'error': '$path 只支持约定方法（/db：GET 列库名 + POST 跑 SQL，其余 GET）',
    });
  }

  Map<String, Object?> _health() => <String, Object?>{
    'ok': true,
    'app': 'mimao',
    'debug': true,
    'port': port,
    'pid': pid,
    'startedAt': _startedAt?.toIso8601String(),
    'uptimeSec': _startedAt == null
        ? null
        : DateTime.now().difference(_startedAt!).inSeconds,
    'vmServiceUri': _vmServiceUri,
    'endpoints': <String, Object?>{
      'GET':
          '/health /logs?level=&limit= /route /state /shot /db（列库名） '
          '/eval（列能力）',
      'POST':
          '/db（{db, sql, params?}） /navigate（{action, name?}） '
          '/tap（{key?, text?, index?, dryRun?}） /eval（{capability, args?}）',
    },
  };

  Map<String, Object?> _logs(Map<String, String> query) {
    final level = query['level'];
    final limit = int.tryParse(query['limit'] ?? '') ?? 200;
    return <String, Object?>{
      'entries': DevLog.snapshot(
        limit: limit.clamp(1, DevLog.capacity),
        level: level,
      ),
    };
  }

  /// /tap 的 body 解析壳：解析失败/根未就绪在这里收敛，语义在 performTap。
  Future<(int, Map<String, Object?>)> _runTap(String body) async {
    final Object? decoded;
    try {
      decoded = body.isEmpty ? null : jsonDecode(body);
    } on FormatException catch (error) {
      return (
        HttpStatus.badRequest,
        <String, Object?>{'ok': false, 'error': 'body 不是合法 JSON：$error'},
      );
    }
    if (decoded is! Map<String, Object?>) {
      return (
        HttpStatus.badRequest,
        <String, Object?>{
          'ok': false,
          'error': 'body 应为 {key?, text?, index?, dryRun?}',
        },
      );
    }
    final Element? root = WidgetsBinding.instance.rootElement;
    if (root == null) {
      return (
        HttpStatus.conflict,
        <String, Object?>{'ok': false, 'error': 'widget 树尚未构建'},
      );
    }
    try {
      return (
        HttpStatus.ok,
        await performTap(TapSelector.fromJson(decoded), root: root),
      );
    } catch (error) {
      return (
        HttpStatus.internalServerError,
        <String, Object?>{'ok': false, 'error': '$error'},
      );
    }
  }

  /// /eval 的 body 解析与执行：能力未注册 → 404；能力内部异常 → 500。
  Future<(int, Map<String, Object?>)> _runEval(String body) async {
    final Object? decoded;
    try {
      decoded = body.isEmpty ? null : jsonDecode(body);
    } on FormatException catch (error) {
      return (
        HttpStatus.badRequest,
        <String, Object?>{'ok': false, 'error': 'body 不是合法 JSON：$error'},
      );
    }
    if (decoded is! Map<String, Object?>) {
      return (
        HttpStatus.badRequest,
        <String, Object?>{'ok': false, 'error': 'body 应为 {capability, args?}'},
      );
    }
    final name = decoded['capability']?.toString() ?? '';
    final capability = devCapabilities[name];
    if (capability == null) {
      return (
        HttpStatus.notFound,
        <String, Object?>{
          'ok': false,
          'error': '未注册能力 "$name"；可用：${devCapabilityNames().join(', ')}',
        },
      );
    }
    final args =
        (decoded['args'] as Map<String, Object?>?) ?? const <String, Object?>{};
    try {
      final value = await capability(args);
      return (
        HttpStatus.ok,
        <String, Object?>{
          'ok': true,
          'result': jsonEncode(value, toEncodable: (Object? o) => o.toString()),
        },
      );
    } catch (error) {
      return (
        HttpStatus.internalServerError,
        <String, Object?>{'ok': false, 'error': '$error'},
      );
    }
  }

  /// /navigate 的 body 解析壳（JSON 层错误在这里收敛，语义层在 devNavigate）。
  Future<(int, Map<String, Object?>)> _runNavigate(String body) async {
    final Object? decoded;
    try {
      decoded = body.isEmpty ? null : jsonDecode(body);
    } on FormatException catch (error) {
      return (
        HttpStatus.badRequest,
        <String, Object?>{'ok': false, 'error': 'body 不是合法 JSON：$error'},
      );
    }
    if (decoded is! Map<String, Object?>) {
      return (
        HttpStatus.badRequest,
        <String, Object?>{'ok': false, 'error': 'body 应为 {action, name?}'},
      );
    }
    return devNavigate(decoded);
  }

  // ── /db SQL 执行 ─────────────────────────────────────────────────────

  /// 禁止的语句前缀：附加数据库/加载外部代码，防 SQL 触碰库外文件。
  static final RegExp _forbiddenPrefix = RegExp(
    r'^(ATTACH|DETACH|LOAD)\b',
    caseSensitive: false,
  );

  /// 读语句判定前缀（customSelect 才能换列名；其余走 customStatement）。
  static final RegExp _readPrefix = RegExp(
    r'^(SELECT|WITH)\b',
    caseSensitive: false,
  );

  /// 剥掉前导注释，让前缀判定不被 `-- xx` 或 `/* xx */` 迷惑。
  static String _stripLeadingComments(String sql) {
    var s = sql.trimLeft();
    while (true) {
      if (s.startsWith('--')) {
        final end = s.indexOf('\n');
        s = end < 0 ? '' : s.substring(end + 1).trimLeft();
      } else if (s.startsWith('/*')) {
        final end = s.indexOf('*/');
        s = end < 0 ? '' : s.substring(end + 2).trimLeft();
      } else {
        return s;
      }
    }
  }

  /// JSON 参数 → sqlite 绑定标量（bool→int；非标量拒绝）。
  static Object? _normalizeParam(Object? value) {
    if (value == null) return null;
    if (value is bool) return value ? 1 : 0;
    if (value is num || value is String) return value;
    throw FormatException('params 只支持 JSON 标量（null/bool/num/string）');
  }

  /// 返回（HTTP 状态码, 响应体）。SQL 语法错/约束冲突属调用方问题 → 400。
  Future<(int, Map<String, Object?>)> _runSql(String body) async {
    final Object? decoded;
    try {
      decoded = body.isEmpty ? null : jsonDecode(body);
    } on FormatException catch (error) {
      return _sqlError('body 不是合法 JSON：$error', status: HttpStatus.badRequest);
    }
    if (decoded is! Map<String, Object?>) {
      return _sqlError(
        'body 应为 {db, sql, params?}',
        status: HttpStatus.badRequest,
      );
    }
    final String dbName = (decoded['db'] as String?) ?? '';
    final String sql = ((decoded['sql'] as String?) ?? '').trim();
    final List<Object?> rawParams =
        (decoded['params'] as List?) ?? const <Object?>[];

    if (dbName.isEmpty) {
      return _sqlError(
        '缺少 db 字段；可用库名：${devDatabaseNames().join(', ')}',
        status: HttpStatus.badRequest,
      );
    }
    final GeneratedDatabase? db = devDatabases[dbName];
    if (db == null) {
      return _sqlError(
        '未注册的库名 "$dbName"；可用：${devDatabaseNames().join(', ')}',
        status: HttpStatus.notFound,
      );
    }
    if (sql.isEmpty) {
      return _sqlError('缺少 sql 字段', status: HttpStatus.badRequest);
    }

    final List<Object?> params;
    try {
      params = <Object?>[for (final Object? p in rawParams) _normalizeParam(p)];
    } on FormatException catch (error) {
      return _sqlError(error.message, status: HttpStatus.badRequest);
    }

    final stripped = _stripLeadingComments(sql);
    if (_forbiddenPrefix.hasMatch(stripped)) {
      return _sqlError(
        'dev harness 禁止 ATTACH/DETACH/LOAD 语句（防 SQL 触碰库外文件）',
        status: HttpStatus.forbidden,
      );
    }

    final stopwatch = Stopwatch()..start();
    try {
      if (_readPrefix.hasMatch(stripped)) {
        // 读走 customSelect 换列名；drift 对非 SELECT 抛 ArgumentError 时
        // （如 WITH 内含写语句）回退到 statement 通道。
        try {
          final rows = await db
              .customSelect(
                sql,
                variables: <Variable>[
                  for (final Object? p in params) Variable(p),
                ],
              )
              .get();
          return _sqlOk(<String, Object?>{
            'kind': 'select',
            'rowCount': rows.length,
            'rows': <Object?>[for (final QueryRow row in rows) row.data],
          }, stopwatch);
        } on ArgumentError {
          // 落到下方 statement 通道。
        }
      }
      // 写通道用 customWriteReturning（drift 2.31 的 customStatement 只执行
      // 不回结果集）：INSERT ... RETURNING 直接拿行；普通写返回空 rows；
      // PRAGMA 也从这条通道拿结果行。全 app 无 watch 流，直写不产生脏 UI。
      final rows = await db.customWriteReturning(
        sql,
        variables: <Variable>[for (final Object? p in params) Variable(p)],
      );
      return _sqlOk(<String, Object?>{
        'kind': 'statement',
        'rowCount': rows.length,
        'rows': <Object?>[for (final QueryRow row in rows) row.data],
        'hint': '写语句后可单独跑 SELECT last_insert_rowid() 或 SELECT changes()',
      }, stopwatch);
    } on Exception catch (error) {
      return _sqlError(error.toString(), status: HttpStatus.badRequest);
    }
  }

  (int, Map<String, Object?>) _sqlOk(
    Map<String, Object?> extra,
    Stopwatch stopwatch,
  ) => (
    HttpStatus.ok,
    <String, Object?>{
      'ok': true,
      ...extra,
      'durationMs': stopwatch.elapsedMilliseconds,
    },
  );

  (int, Map<String, Object?>) _sqlError(String message, {required int status}) {
    return (status, <String, Object?>{'ok': false, 'error': message});
  }

  // ── 鉴权与响应 ────────────────────────────────────────────────────────

  /// header `Bearer <token>` 或 `?token=` 任一命中即可。
  bool _authorized(HttpRequest request) {
    final token = _token;
    if (token == null) return false;
    final queryToken = request.uri.queryParameters['token'];
    if (queryToken != null && _safeEquals(queryToken, token)) return true;
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header != null && header.startsWith('Bearer ')) {
      return _safeEquals(header.substring('Bearer '.length), token);
    }
    return false;
  }

  /// 定长比较，避免时序侧信道（本地调试场景是纵深防御的一层，写法从简）。
  static bool _safeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  void _json(HttpRequest request, int status, Object? payload) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType(
      'application',
      'json',
      charset: 'utf-8',
    );
    request.response.write(jsonEncode(payload));
    request.response.close();
  }
}
