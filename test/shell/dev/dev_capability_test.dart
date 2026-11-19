import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/shell/dev/dev_capability.dart';

void main() {
  tearDown(() {
    devUnregisterCapability('__test_cap__');
  });

  test('注册/覆盖/注销/列名', () async {
    expect(devCapabilityNames(), isNot(contains('__test_cap__')));

    devRegisterCapability('__test_cap__', (args) async => 'v1');
    expect(devCapabilityNames(), contains('__test_cap__'));

    devRegisterCapability('__test_cap__', (args) async => 'v2');
    final out = await devCapabilities['__test_cap__']!(<String, Object?>{});
    expect(out, 'v2', reason: '同名覆盖后注册者胜');

    devUnregisterCapability('__test_cap__');
    expect(devCapabilityNames(), isNot(contains('__test_cap__')));
  });

  test('能力收到解码后的 args Map', () async {
    String? seen;
    devRegisterCapability('__test_cap__', (args) async {
      seen = args['code']?.toString();
      return seen;
    });

    await devCapabilities['__test_cap__']!(<String, Object?>{'code': '1 + 1'});
    expect(seen, '1 + 1');
  });

  test('devCapabilityNames 字典序', () async {
    devRegisterCapability('z', (args) async => null);
    devRegisterCapability('a', (args) async => null);
    addTearDown(() {
      devUnregisterCapability('a');
      devUnregisterCapability('z');
    });

    final names = devCapabilityNames().where((n) => n == 'a' || n == 'z');
    expect(names.toList(), ['a', 'z']);
  });
}
