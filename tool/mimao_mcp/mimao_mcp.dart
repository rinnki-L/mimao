// mimao-driver MCP Server —— 手写 stdio JSON-RPC 2.0，零依赖（仅 dart:io/dart:convert）。
//
// ZCode ──stdio 行分隔 JSON──> 本进程 ──HTTP 127.0.0.1+token──> lib/dev 驱动端点。
// 薄翻译层：不 import 任何 package:，不用 dart_mcp（零新依赖铁律）。
//
// 协议要点（否则 ZCode 连不上）：
//   - 行分隔：每条消息一行紧凑 JSON；读 stdin 按行切，写 stdout 每行一条。
//   - initialize 回显支持的 protocolVersion，否则回落 2025-06-18。
//   - notification（无 id）静默不响应。
//   - tools/call 结果必须在 content 数组里，不能直接返回 data。
//
// 启动：预编译成 exe 后由 ZCode 以 stdio 方式拉起（见 docs/driver-mcp.md）。

import 'dart:async' show Completer, StreamSubscription;
import 'dart:convert' show LineSplitter, jsonDecode, jsonEncode, utf8;
import 'dart:io'
    show
        File,
        HttpException,
        HttpClient,
        Platform,
        Process,
        stderr,
        stdin,
        stdout;

/// 支持的 MCP 协议版本（回显客户端请求的版本，否则回落到最后一个）。
const List<String> protocolVersions = <String>[
  '2026-07-28',
  '2025-06-18',
  '2025-03-26',
  '2024-11-05',
];
const String fallbackProtocolVersion = '2025-06-18';
const Duration requestTimeout = Duration(seconds: 10);

/// 一次驱动调用的结果：从 driver.json 读到链接信息 + HTTP 往返。
class DriverLink {
  final int port;
  final String token;
  final int pid;

  const DriverLink({
    required this.port,
    required this.token,
    required this.pid,
  });
}

/// driver.json 默认路径（可用 MIMAO_DRIVER_FILE 覆盖）。
String driverFilePath() {
  final override = Platform.environment['MIMAO_DRIVER_FILE'];
  if (override != null && override.isNotEmpty) return override;
  final base =
      Platform.environment['APPDATA'] ?? Platform.environment['HOME'] ?? '.';
  // 与 lib/dev/driver_server.dart 同款：/ 与 \ 混用由 Dart 的文件 API 接受。
  return '$base/com.rinnki.mimao/mimao/driver.json';
}

/// 把 driver.json 解析成 DriverLink；文件缺失/坏 JSON/字段不全返回 null。
DriverLink? parseDriverInfo(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) return null;
    final port = decoded['port'];
    final token = decoded['token'];
    final pid = decoded['pid'];
    if (port is! int || token is! String || token.isEmpty || pid is! int) {
      return null;
    }
    return DriverLink(port: port, token: token, pid: pid);
  } catch (_) {
    return null;
  }
}

/// 进程是否存活（pid 不存活视为驱动已停）。
///
/// 用无副作用的系统查询命令探活，而非 Process.killPid——后者只能发真实信号，
/// 没有 kill(pid, 0) 那种"只探测不杀"的语义，误用会把 app 干掉。
Future<bool> isPidAlive(int pid) async {
  try {
    final result = Platform.isWindows
        ? await Process.run('tasklist', <String>['/FI', 'PID eq $pid', '/NH'])
        : await Process.run('kill', <String>['-0', '$pid']);
    if (result.exitCode != 0) return false;
    return Platform.isWindows
        ? (result.stdout as String).contains(' $pid ')
        : true;
  } catch (_) {
    return false;
  }
}

/// 读 driver.json 并检查 pid；返回 null 或带可读错误的原因。
Future<DriverLink?> readDriverLink() async {
  final path = driverFilePath();
  final file = File(path);
  if (!await file.exists()) return null;
  DriverLink? link;
  try {
    link = parseDriverInfo(await file.readAsString());
  } catch (_) {
    return null;
  }
  if (link == null) return null;
  if (!await isPidAlive(link.pid)) return null;
  return link;
}

/// 一次 HTTP 调用；返回解码后的 JSON 字符串（直接透传给 content.text）。
Future<String> callDriverEndpoint(
  DriverLink link,
  String method,
  String path, {
  Map<String, Object?>? body,
}) async {
  final client = HttpClient();
  try {
    final uri = Uri.parse('http://127.0.0.1:${link.port}$path');
    final request = await client.openUrl(method, uri).timeout(requestTimeout);
    request.headers.set('authorization', 'Bearer ${link.token}');
    request.headers.set('content-type', 'application/json');
    if (body != null) {
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(requestTimeout);
    final raw = await utf8.decoder.bind(response).join();
    return raw;
  } on HttpException catch (error) {
    return jsonEncode(<String, Object?>{
      'ok': false,
      'error': '连接驱动失败：${error.message}',
    });
  } catch (error) {
    return jsonEncode(<String, Object?>{'ok': false, 'error': '连接驱动失败：$error'});
  } finally {
    client.close();
  }
}

/// 未启动时的统一中文指引。
String get notRunningMessage =>
    'mimao 未以驱动模式运行/未发现 driver.json，'
    '请先 flutter run -d windows --dart-define=MIMAO_DRIVER=1 '
    '（driver.json 路径：${driverFilePath()}）';

/// MCP 工具定义（name/description/inputSchema）。
final List<Map<String, Object?>> toolDefinitions = <Map<String, Object?>>[
  <String, Object?>{
    'name': 'mimao_health',
    'description': '驱动健康检查，返回 uptimeMs；用于确认 app 以驱动模式在跑。',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
    },
  },
  <String, Object?>{
    'name': 'mimao_state',
    'description':
        '读取壳导航态（activeModule/showLibrary/settingsOpen/themeSeed）、driver 信息与已注册 controller/db 查询名。',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
    },
  },
  <String, Object?>{
    'name': 'mimao_tree',
    'description': 'widget 树 JSON（type/key/text/rect/children），用于定位控件与断言渲染结果。',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{},
    },
  },
  <String, Object?>{
    'name': 'mimao_tap',
    'description': '按 key/tooltip/text 定位并合成真实点击。多命中用 index 消歧。',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'key': <String, Object?>{
          'type': 'string',
          'description': 'ValueKey 值，优先级最高',
        },
        'tooltip': <String, Object?>{'type': 'string'},
        'text': <String, Object?>{'type': 'string', 'description': '精确或包含匹配'},
        'index': <String, Object?>{
          'type': 'integer',
          'description': '多命中时选第几个（0 基）',
        },
      },
    },
  },
  <String, Object?>{
    'name': 'mimao_text',
    'description': '向文本框注入文本。给 field 走命名 controller；不给 field 时要求屏上唯一可编辑框。',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'field': <String, Object?>{
          'type': 'string',
          'description': '注册的 controller 名，如 animeSearch',
        },
        'value': <String, Object?>{'type': 'string', 'description': '要写入的文本'},
      },
      'required': <Object?>['value'],
    },
  },
  <String, Object?>{
    'name': 'mimao_navigate',
    'description': '切换壳导航态：entry/library/anime/comic/novel/music。',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'to': <String, Object?>{
          'type': 'string',
          'enum': <Object?>[
            'entry',
            'library',
            'anime',
            'comic',
            'novel',
            'music',
          ],
        },
      },
      'required': <Object?>['to'],
    },
  },
  <String, Object?>{
    'name': 'mimao_wait',
    'description': '轮询等待条件成立：text（树含该文案）/key（树有该 Key）/state（field=value）。',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'text': <String, Object?>{'type': 'string'},
        'key': <String, Object?>{'type': 'string'},
        'state': <String, Object?>{
          'type': 'string',
          'description': '如 activeModule=anime',
        },
        'timeoutMs': <String, Object?>{'type': 'integer'},
        'pollMs': <String, Object?>{'type': 'integer'},
      },
    },
  },
  <String, Object?>{
    'name': 'mimao_db',
    'description': '只读查询 DB：name 为 core/anime/comic/comicCollect，返回最近 20 行+总数。',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'name': <String, Object?>{
          'type': 'string',
          'description': 'core/anime/comic/comicCollect',
        },
      },
      'required': <Object?>['name'],
    },
  },
];

/// 把 tools/call 的 name+arguments 映射到 HTTP 端点。
class MappedCall {
  final String method;
  final String path;
  final Map<String, Object?>? body;

  const MappedCall(this.method, this.path, this.body);
}

MappedCall? mapToolCall(String name, Map<String, Object?> args) {
  switch (name) {
    case 'mimao_health':
      return const MappedCall('GET', '/health', null);
    case 'mimao_state':
      return const MappedCall('GET', '/state', null);
    case 'mimao_tree':
      return const MappedCall('GET', '/tree', null);
    case 'mimao_tap':
      return MappedCall('POST', '/tap', args);
    case 'mimao_text':
      return MappedCall('POST', '/text', args);
    case 'mimao_navigate':
      return MappedCall('POST', '/navigate', args);
    case 'mimao_wait':
      return MappedCall('POST', '/wait', args);
    case 'mimao_db':
      final dbName = args['name'];
      return MappedCall(
        'GET',
        '/db/${dbName is String ? Uri.encodeComponent(dbName) : ''}',
        null,
      );
    default:
      return null;
  }
}

/// 构造一条 JSON-RPC 响应行。
String encodeLine(Map<String, Object?> message) => jsonEncode(message);

Map<String, Object?> resultMessage(Object id, Object? result) =>
    <String, Object?>{'jsonrpc': '2.0', 'id': id, 'result': result};

Map<String, Object?> errorMessage(Object id, int code, String message) =>
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'error': <String, Object?>{'code': code, 'message': message},
    };

/// 唯一可测的业务入口：处理一条请求行，返回若干响应行（notification 返回空）。
/// 抽成纯函数（除 IO 桥在 callDriver 注入）便于 selftest 直接喂消息断言。
Future<List<String>> handleMessage(
  String line, {
  Future<String> Function(MappedCall call)? driver,
}) async {
  Object? decoded;
  try {
    decoded = jsonDecode(line);
  } catch (_) {
    return <String>[encodeLine(errorMessage(0, -32700, 'Parse error'))];
  }
  if (decoded is! Map<String, Object?>) {
    return <String>[encodeLine(errorMessage(0, -32600, 'Invalid Request'))];
  }

  final id = decoded['id'];
  final method = decoded['method'];
  if (method is! String) {
    if (id == null) return const <String>[];
    return <String>[encodeLine(errorMessage(id, -32600, 'Invalid Request'))];
  }
  final params = decoded['params'];
  final args = params is Map<String, Object?> ? params : <String, Object?>{};

  // notification：无 id，静默不响应（包括 initialized 与未知 notification）。
  if (id == null) return const <String>[];

  switch (method) {
    case 'initialize':
      final requested = args['protocolVersion'];
      final version =
          requested is String && protocolVersions.contains(requested)
          ? requested
          : fallbackProtocolVersion;
      return <String>[
        encodeLine(
          resultMessage(id, <String, Object?>{
            'protocolVersion': version,
            'capabilities': <String, Object?>{'tools': <String, Object?>{}},
            'serverInfo': <String, Object?>{
              'name': 'mimao-driver',
              'version': '1.0.0',
            },
          }),
        ),
      ];

    case 'tools/list':
      return <String>[
        encodeLine(
          resultMessage(id, <String, Object?>{'tools': toolDefinitions}),
        ),
      ];

    case 'tools/call':
      final name = args['name'];
      final callArgs = args['arguments'];
      final callArgMap = callArgs is Map<String, Object?>
          ? callArgs
          : <String, Object?>{};
      if (name is! String) {
        return <String>[
          encodeLine(
            resultMessage(id, <String, Object?>{
              'content': <Object?>[
                <String, Object?>{'type': 'text', 'text': '缺少工具名'},
              ],
              'isError': true,
            }),
          ),
        ];
      }
      final mapped = mapToolCall(name, callArgMap);
      if (mapped == null) {
        return <String>[
          encodeLine(
            resultMessage(id, <String, Object?>{
              'content': <Object?>[
                <String, Object?>{'type': 'text', 'text': '未知工具：$name'},
              ],
              'isError': true,
            }),
          ),
        ];
      }

      final link = await readDriverLink();
      if (link == null) {
        return <String>[
          encodeLine(
            resultMessage(id, <String, Object?>{
              'content': <Object?>[
                <String, Object?>{'type': 'text', 'text': notRunningMessage},
              ],
              'isError': true,
            }),
          ),
        ];
      }
      final raw = driver != null
          ? await driver(mapped)
          : await callDriverEndpoint(
              link,
              mapped.method,
              mapped.path,
              body: mapped.body,
            );

      // 判断 ok：驱动端点统一 {ok:true/false,...}。
      var isError = false;
      try {
        final decodedRaw = jsonDecode(raw);
        if (decodedRaw is Map<String, Object?> && decodedRaw['ok'] == false) {
          isError = true;
        }
      } catch (_) {
        isError = true;
      }
      final result = <String, Object?>{
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': raw},
        ],
      };
      if (isError) result['isError'] = true;
      return <String>[encodeLine(resultMessage(id, result))];

    default:
      return <String>[
        encodeLine(errorMessage(id, -32601, 'Method not found: $method')),
      ];
  }
}

Future<void> main(List<String> argv) async {
  // selftest 子进程模式：不进 stdio 循环，由 selftest.dart 直接调用 handleMessage。
  if (argv.isNotEmpty && argv.first == '--selftest-daemon') {
    await _selftestDaemon();
    return;
  }

  final lines = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .where((line) => line.trim().isNotEmpty);

  StreamSubscription<String>? subscription;
  final done = Completer<void>();
  subscription = lines.listen(
    (line) async {
      try {
        final responses = await handleMessage(line);
        for (final response in responses) {
          stdout.writeln(response);
        }
      } catch (error) {
        stderr.writeln('mimao_mcp 处理消息出错：$error');
      }
    },
    onDone: () {
      if (!done.isCompleted) done.complete();
    },
    onError: (Object error) {
      stderr.writeln('mimao_mcp stdin 错误：$error');
      if (!done.isCompleted) done.complete();
    },
  );
  await done.future;
  await subscription.cancel();
}

/// 极简 selftest 守护：读 stdin 行逐条 handleMessage（复用同一协议栈），
/// 让 selftest.dart 能在子进程里跑真实协议而不复制逻辑。
Future<void> _selftestDaemon() async {
  final lines = stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .where((line) => line.trim().isNotEmpty);
  await for (final line in lines) {
    final responses = await handleMessage(line);
    for (final response in responses) {
      stdout.writeln(response);
    }
  }
}
