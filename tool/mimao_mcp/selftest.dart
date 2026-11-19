// MCP server 协议自检：spawn 子进程喂 initialize/initialized/tools/list/tools/call，
// 断言响应结构。独立 CI step（dart run tool/mimao_mcp/selftest.dart），不挂 flutter test
// （flutter_tester 环境 spawn dart 不稳）。
//
// 通过 MIMAO_DRIVER_FILE 指向不存在的路径来稳定覆盖"app 未启动"分支。
// ignore_for_file: avoid_print — 独立 CLI 工具，print 即输出。

import 'dart:async' show Future;
import 'dart:convert' show LineSplitter, jsonDecode, jsonEncode, utf8;
import 'dart:io' show Directory, Platform, Process;

int _passed = 0;
final List<String> _failures = <String>[];

void check(bool condition, String label) {
  if (condition) {
    _passed++;
    print('  ✓ $label');
  } else {
    _failures.add(label);
    print('  ✗ $label');
  }
}

Future<void> main() async {
  // 用临时目录里的不存在路径，保证 tools/call 走"未启动"分支。
  final tmp = Directory.systemTemp.createTempSync('mimao_mcp_selftest_');
  final missingFile = '${tmp.path}${Platform.pathSeparator}missing_driver.json';
  const entry = 'tool/mimao_mcp/mimao_mcp.dart';

  print('== mimao_mcp selftest ==');
  final responses = await _runProtocol(
    entry,
    missingFile,
    <Map<String, Object?>>[
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': <String, Object?>{
          'protocolVersion': '2025-06-18',
          'capabilities': <String, Object?>{},
          'clientInfo': <String, Object?>{'name': 'selftest', 'version': '1'},
        },
      },
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      },
      <String, Object?>{'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
      <String, Object?>{
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': <String, Object?>{
          'name': 'mimao_state',
          'arguments': <String, Object?>{},
        },
      },
      <String, Object?>{'jsonrpc': '2.0', 'id': 4, 'method': 'no/such/method'},
    ],
  );

  // 响应按 id 归类（notification 无响应；应有 1/2/3/4 四条）。
  final byId = <Object, Map<String, Object?>>{};
  for (final line in responses) {
    final decoded = jsonDecode(line) as Map<String, Object?>;
    final id = decoded['id'];
    if (id != null) byId[id] = decoded;
  }

  final init = byId[1];
  check(init != null, 'initialize 有响应');
  if (init != null) {
    final result = init['result'] as Map<String, Object?>;
    check(
      result['protocolVersion'] == '2025-06-18',
      'initialize 回显 protocolVersion',
    );
    final caps = result['capabilities'] as Map<String, Object?>;
    check(caps.containsKey('tools'), 'capabilities 含 tools');
    final info = result['serverInfo'] as Map<String, Object?>;
    check(info['name'] == 'mimao-driver', 'serverInfo.name=mimao-driver');
  }

  final anyNullIdResponse = responses.any(
    (line) => (jsonDecode(line) as Map<String, Object?>)['id'] == null,
  );
  check(!anyNullIdResponse, 'notifications/initialized 无响应行');

  final list = byId[2];
  check(list != null, 'tools/list 有响应');
  if (list != null) {
    final tools =
        (list['result'] as Map<String, Object?>)['tools'] as List<Object?>;
    check(tools.length == 8, 'tools/list 恰好八个工具（实际 ${tools.length}）');
    final names = tools
        .map((t) => (t as Map<String, Object?>)['name'] as String)
        .toSet();
    check(
      names.containsAll(<String>{
        'mimao_health',
        'mimao_state',
        'mimao_tree',
        'mimao_tap',
        'mimao_text',
        'mimao_navigate',
        'mimao_wait',
        'mimao_db',
      }),
      '八个工具名齐全',
    );
  }

  final call = byId[3];
  check(call != null, 'tools/call 有响应');
  if (call != null) {
    final result = call['result'] as Map<String, Object?>;
    final content = result['content'] as List<Object?>;
    check(content.isNotEmpty, 'tools/call 结果在 content 数组');
    final text = (content.first as Map<String, Object?>)['text'] as String;
    check(
      text.contains('driver.json') && result['isError'] == true,
      'app 未启动时返回中文指引+isError',
    );
  }

  final unknown = byId[4];
  check(unknown != null, '未知方法有响应');
  if (unknown != null) {
    final error = unknown['error'] as Map<String, Object?>;
    check(error['code'] == -32601, '未知方法 code=-32601');
  }

  tmp.deleteSync(recursive: true);

  print('');
  print('结果：$_passed 通过，${_failures.length} 失败');
  if (_failures.isNotEmpty) {
    for (final failure in _failures) {
      print('  - $failure');
    }
    throw StateError('mimao_mcp selftest 失败');
  }
  print('mimao_mcp selftest 全部通过');
}

/// spawn 子进程喂所有消息（一次性写完关闭 stdin），收集 stdout 非空行。
Future<List<String>> _runProtocol(
  String entry,
  String driverFile,
  List<Map<String, Object?>> messages,
) async {
  final dart = Platform.resolvedExecutable;
  final process = await Process.start(
    dart,
    <String>[entry, '--selftest-daemon'],
    workingDirectory: Directory.current.path,
    environment: <String, String>{'MIMAO_DRIVER_FILE': driverFile},
  );
  for (final message in messages) {
    process.stdin.writeln(jsonEncode(message));
  }
  await process.stdin.close();
  final stdoutBuffer = StringBuffer();
  final stderrBuffer = StringBuffer();
  await Future.wait<Object?>(<Future<Object?>>[
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .join('\n')
        .then((v) => stdoutBuffer.write(v)),
    process.stderr
        .transform(utf8.decoder)
        .join()
        .then((v) => stderrBuffer.write(v)),
    process.exitCode,
  ]);
  if (stderrBuffer.isNotEmpty) {
    print('  [stderr] $stderrBuffer');
  }
  return stdoutBuffer
      .toString()
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .toList();
}
