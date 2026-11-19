import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/contract.dart';
import 'package:mimao/shell/dev/dev_navigate.dart';
import 'package:mimao/shell/shell_store.dart';

void main() {
  // 'back' 动作读 GlobalKey.currentState：binding 未初始化会直接抛异常，真实
  // app 里 binding 必然就绪——测试先对齐这个前提，再走「Navigator 未挂载」
  // 的 409 分支。
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(shellStore.goHome);

  /// devNavigate 的 body.state.shell 子层（agent 拿到的导航态就在这里）。
  Map<String, Object?> shellOf(Object? body) =>
      ((body! as Map<String, Object?>)['state']!
              as Map<String, Object?>)['shell']!
          as Map<String, Object?>;

  test('home / library / settings 动作落位 shellStore 并回带 state 快照', () async {
    // 先钻进一个模块，让 home 有东西可清。
    shellStore.openModule(MediaType.comic);
    final (homeStatus, homeBody) = await devNavigate(<String, Object?>{
      'action': 'home',
    });
    expect(homeStatus, HttpStatus.ok);
    expect(homeBody['ok'], true);
    expect(shellOf(homeBody)['onEntryPage'], true);
    expect(homeBody['routeDepth'], isA<int>());

    final (libStatus, libBody) = await devNavigate(<String, Object?>{
      'action': 'library',
    });
    expect(libStatus, HttpStatus.ok);
    expect(shellOf(libBody)['showLibrary'], true);

    final (setStatus, setBody) = await devNavigate(<String, Object?>{
      'action': 'settings',
    });
    expect(setStatus, HttpStatus.ok);
    expect(shellOf(setBody)['settingsOpen'], true);
    expect(
      shellOf(setBody)['showLibrary'],
      true,
      reason: 'openSettings 不动 library——上一步的打开态应保持',
    );

    await devNavigate(<String, Object?>{'action': 'closeSettings'});
    expect(shellStore.settingsOpen, false);
  });

  test('module：合法名落位 activeModule；非法名 400 并列可用名', () async {
    final (okStatus, okBody) = await devNavigate(<String, Object?>{
      'action': 'module',
      'name': 'comic',
    });
    expect(okStatus, HttpStatus.ok);
    expect(shellOf(okBody)['activeModule'], 'comic');

    final (badStatus, badBody) = await devNavigate(<String, Object?>{
      'action': 'module',
      'name': 'nope',
    });
    expect(badStatus, HttpStatus.badRequest);
    final error = (badBody['error']! as String);
    expect(error, contains('nope'));
    expect(error, contains('comic'), reason: '错误信息要列可用模块名');
  });

  test('未知 action → 400 并列可用动作', () async {
    final (status, body) = await devNavigate(<String, Object?>{
      'action': 'fly',
    });
    expect(status, HttpStatus.badRequest);
    expect(body['error']! as String, contains('fly'));
  });

  test('back：根 Navigator 未就绪时返回 409 不崩', () async {
    // 绑定已初始化但 MimaoApp 从未挂载：currentState 为 null。
    final (status, body) = await devNavigate(<String, Object?>{
      'action': 'back',
    });
    expect(status, HttpStatus.conflict);
    expect(body['ok'], false);
    expect(body['error'], contains('Navigator'));
  });

  test('缺 action → 400', () async {
    final (status, body) = await devNavigate(<String, Object?>{});
    expect(status, HttpStatus.badRequest);
    expect(body['error'], contains('action'));
  });
}
