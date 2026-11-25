// 备份加密：AES-256-GCM 往返、密码错、篡改、信封校验、PBKDF2 参数生效。
// 纯 Dart，不需要任何插件或 IO。
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/backup/backup_crypto.dart';
import 'package:mimao/novel/backup/backup_document.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

/// 测试用低迭代次数：只要验证算法链路，不把单测拖成几秒。
const int _fastIterations = 1000;

NovelBackupDocument _doc() => NovelBackupDocument(
  collects: const <NovelBackupCollect>[],
  histories: const <NovelBackupHistory>[],
  searchKeywords: const <String>['三体'],
  sources: const <NovelBookSource>[],
  prefs: const <String, String>{'reader_settings': '{"fontSize":22}'},
  exportedAt: DateTime.utc(2026, 11, 25, 8),
  deviceId: 'device-a',
  deviceName: 'Windows-PC',
);

void main() {
  test('加密往返：同一密码解回原文档', () {
    final text = _doc().encode();
    final envelope = encryptNovelBackupText(
      text,
      'hunter2',
      iterations: _fastIterations,
      random: Random(7),
    );
    final bundle = parseNovelBackupBundle(envelope.encode());
    expect(bundle, isA<NovelBackupEncryptedBundle>());
    final doc = (bundle as NovelBackupEncryptedBundle).decrypt('hunter2');
    expect(doc.searchKeywords, <String>['三体']);
    expect(doc.deviceId, 'device-a');
    expect(doc.prefs[novelPrefReaderSettings], '{"fontSize":22}');
  });

  test('密码错：给可读异常，不是乱码', () {
    final envelope = encryptNovelBackupText(
      _doc().encode(),
      'right',
      iterations: _fastIterations,
      random: Random(3),
    );
    final bundle = parseNovelBackupBundle(envelope.encode());
    expect(
      () => (bundle as NovelBackupEncryptedBundle).decrypt('wrong'),
      throwsA(
        isA<NovelBackupCryptoException>().having(
          (error) => error.message,
          'message',
          contains('密码不对'),
        ),
      ),
    );
  });

  test('篡改密文：认证失败', () {
    final envelope = encryptNovelBackupText(
      _doc().encode(),
      'pw',
      iterations: _fastIterations,
      random: Random(11),
    );
    final tampered = <String, Object?>{
      ...envelope.toJson(),
      'payload': base64Encode(<int>[
        ...envelope.payload.sublist(0, envelope.payload.length - 1),
        envelope.payload.last ^ 0x01,
      ]),
    };
    expect(
      () => NovelBackupEnvelope.decode(tampered).decrypt('pw'),
      throwsA(isA<NovelBackupCryptoException>()),
    );
  });

  test('空密码：拒绝且不产生信封', () {
    expect(
      () => encryptNovelBackupText(_doc().encode(), ''),
      throwsA(isA<NovelBackupCryptoException>()),
    );
  });

  test('信封参数写进文件：换迭代次数也能解老文件', () {
    final envelope = encryptNovelBackupText(
      _doc().encode(),
      'pw',
      iterations: 777,
      random: Random(5),
    );
    final json = envelope.toJson();
    expect(json['iterations'], 777);
    expect(json['cipher'], novelBackupCipherName);
    expect(json['kdf'], novelBackupKdfName);
    // 用默认迭代次数解一次 777 的文件，证明解密只认信封里记的参数。
    final bundle = parseNovelBackupBundle(envelope.encode());
    expect(
      (bundle as NovelBackupEncryptedBundle).decrypt('pw').deviceId,
      'device-a',
    );
  });

  test('明文包：parseNovelBackupBundle 直接给文档', () {
    final bundle = parseNovelBackupBundle(_doc().encode());
    expect(bundle, isA<NovelBackupPlainBundle>());
    expect((bundle as NovelBackupPlainBundle).document.deviceId, 'device-a');
  });

  test('非备份 JSON：拒绝', () {
    expect(
      () => parseNovelBackupBundle('{"format":"other"}'),
      throwsFormatException,
    );
  });
}
