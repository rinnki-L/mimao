/// 网络代理设置：默认直连、自定义规则拼装、落库后重启读回。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mimao/core/db.dart';
import 'package:mimao/core/settings.dart';
import 'package:mimao/shell/network_settings.dart';

void main() {
  late AppDb db;
  late SettingsRepository repository;

  setUp(() {
    db = AppDb.forTesting(NativeDatabase.memory());
    repository = SettingsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('默认直连', () async {
    final settings = NetworkSettings();
    addTearDown(settings.dispose);
    await settings.load(repository);
    expect(settings.proxyMode, NetworkProxyMode.direct);
    expect(settings.findProxy(Uri.parse('https://site.test/')), 'DIRECT');
  });

  test('自定义代理规则拼装并落库，新实例能读回', () async {
    final settings = NetworkSettings();
    addTearDown(settings.dispose);
    await settings.load(repository);
    await settings.setProxyMode(NetworkProxyMode.custom);
    settings.setCustomProxy(host: ' 127.0.0.1 ', port: 7897);
    expect(
      settings.findProxy(Uri.parse('https://site.test/')),
      'PROXY 127.0.0.1:7897',
    );
    // 等防抖落库。
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final reloaded = NetworkSettings();
    addTearDown(reloaded.dispose);
    await reloaded.load(repository);
    expect(reloaded.proxyMode, NetworkProxyMode.custom);
    expect(reloaded.proxyHost, ' 127.0.0.1 ');
    expect(reloaded.proxyPort, 7897);
    expect(
      reloaded.findProxy(Uri.parse('https://site.test/')),
      'PROXY 127.0.0.1:7897',
    );
  });

  test('自定义地址为空/端口非法时回退直连', () async {
    final settings = NetworkSettings();
    addTearDown(settings.dispose);
    await settings.load(repository);
    await settings.setProxyMode(NetworkProxyMode.custom);
    settings.setCustomProxy(host: '   ', port: 7890);
    expect(settings.findProxy(Uri.parse('https://site.test/')), 'DIRECT');
    settings.setCustomProxy(host: '127.0.0.1', port: 0);
    expect(settings.findProxy(Uri.parse('https://site.test/')), 'DIRECT');
  });

  test('环境变量模式返回 findProxyFromEnvironment 的结果', () async {
    final settings = NetworkSettings();
    addTearDown(settings.dispose);
    await settings.load(repository);
    await settings.setProxyMode(NetworkProxyMode.environment);
    // 本机/CI 通常没有代理变量；有的话也不强断言具体值，只保证不崩。
    expect(settings.findProxy(Uri.parse('https://site.test/')), isNotEmpty);
  });
}
