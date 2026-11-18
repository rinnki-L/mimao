/// wire 解码辅助测试：宽容面与 Rust response.rs 对齐——该宽容的宽容
/// （数字/字符串互换），该拒绝的拒绝（bool 不当文本、非数组不吞成空表）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/wire.dart';

void main() {
  group('标量辅助', () {
    test('optionalInt：数字/数字字符串/null/非数字', () {
      expect(optionalInt(1), 1);
      expect(optionalInt('42'), 42);
      expect(optionalInt(null), isNull);
      expect(optionalInt('abc'), isNull);
      expect(optionalInt(true), isNull);
      expect(optionalInt(1.5), 1);
    });

    test('wireText：bool 不产生假文本（Rust text 语义）', () {
      expect(wireText('s'), 's');
      expect(wireText(123), '123');
      expect(wireText(1.5), '1.5');
      expect(wireText(null), '');
      expect(wireText(true), '', reason: 'bool 反序列化失败为空串，不是 "true"');
    });

    test('optionalText：数字转字符串、bool/null → null', () {
      expect(optionalText('s'), 's');
      expect(optionalText(123), '123');
      expect(optionalText(null), isNull);
      expect(optionalText(false), isNull);
    });

    test('requiredScalarInt：缺省/非标量 → decode 失败', () {
      expect(
        () => requiredScalarInt(null, 'status'),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
      expect(
        () => requiredScalarInt(true, 'status'),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
      expect(requiredScalarInt('1', 'status'), 1);
    });

    test('wireList：null → 空表；非数组 → decode 失败（不吞成空表）', () {
      expect(wireList(null, 'lists'), isEmpty);
      expect(wireList(<Object>[1, 2], 'lists'), <Object>[1, 2]);
      expect(
        () => wireList('nope', 'Singers'),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
      expect(
        () => wireList(true, 'lists'),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
    });
  });

  group('信封解码', () {
    Uint8List envelope(Object? json) =>
        Uint8List.fromList(utf8.encode(jsonEncode(json)));

    test('status/error_code 必填且标量', () {
      final ok = decodeEnvelope(
        envelope(<String, Object?>{
          'status': 1,
          'error_code': 0,
          'data': <Object?>[],
        }),
      );
      expect(ok.status, 1);
      expect(ok.errorCode, 0);
      // 字符串包裹的数字也接受（scalar 语义）。
      final wrapped = decodeEnvelope(
        envelope(<String, Object?>{
          'status': '1',
          'error_code': '0',
          'data': <Object?>[],
        }),
      );
      expect(wrapped.status, 1);
      // 缺 error_code / bool status → decode。
      expect(
        () => decodeEnvelope(envelope(<String, Object?>{'status': 1})),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
      expect(
        () => decodeEnvelope(
          envelope(<String, Object?>{'status': true, 'error_code': 0}),
        ),
        throwsA(predicate((Object e) => '$e'.contains('decode'))),
      );
    });

    test('业务失败 → business 带 error_code', () {
      expect(
        () => decodeBusinessEnvelope(
          envelope(<String, Object?>{
            'status': 0,
            'error_code': 152,
            'data': <String, Object?>{},
          }),
        ),
        throwsA(
          predicate(
            (Object e) => '$e'.contains('business') && '$e'.contains('152'),
          ),
        ),
      );
    });

    test('20018 登录过期 → authentication（decode 层统一判）', () {
      expect(
        () => decodeBusinessEnvelope(
          envelope(<String, Object?>{
            'status': 1,
            'error_code': 20018,
            'data': <String, Object?>{},
          }),
        ),
        throwsA(predicate((Object e) => '$e'.contains('authentication'))),
      );
      // 即使端点层另做分支（register_dev 直用 decodeEnvelope），20018 也先判。
      expect(
        () => decodeEnvelope(
          envelope(<String, Object?>{
            'status': 1,
            'error_code': 20018,
            'data': <String, Object?>{},
          }),
        ),
        throwsA(predicate((Object e) => '$e'.contains('authentication'))),
      );
    });
  });
}
