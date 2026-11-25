// 凭据存储：内存实现、无实现降级、Windows DPAPI 真实往返（非 Windows 跳过）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/backup/credential_store.dart';

void main() {
  test('内存实现：读写删', () async {
    final store = NovelMemoryCredentialStore();
    expect(await store.read('k'), isNull);
    await store.write('k', 'v');
    expect(await store.read('k'), 'v');
    await store.delete('k');
    expect(await store.read('k'), isNull);
  });

  test('没有安全存储的平台：读当没有，写明确失败（不静默丢密码）', () async {
    const store = NovelUnavailableCredentialStore();
    expect(await store.read('k'), isNull);
    await expectLater(store.write('k', 'v'), throwsStateError);
    await store.delete('k'); // 删是空操作，不抛。
  });

  test('Windows DPAPI：密文只在本机可解，删掉即没有', () async {
    final temp = await Directory.systemTemp.createTemp('mimao-cred-');
    addTearDown(() => temp.delete(recursive: true));
    final store = NovelDpapiCredentialStore(supportDirectory: () async => temp);

    await store.write('mimao.novel.webdav.password', '密码 p@ss:中文');
    expect(await store.read('mimao.novel.webdav.password'), '密码 p@ss:中文');

    // 落盘的是密文，不是明文。
    final dir = Directory('${temp.path}/novel_credentials');
    final files = await dir.list().toList();
    expect(files, hasLength(1));
    final raw = await File(files.single.path).readAsBytes();
    expect(String.fromCharCodes(raw.take(12)), isNot(contains('p@ss')));

    await store.delete('mimao.novel.webdav.password');
    expect(await store.read('mimao.novel.webdav.password'), isNull);
  }, skip: Platform.isWindows ? false : 'DPAPI 只在 Windows 上有');

  test('默认实现按平台挑', () {
    final store = defaultNovelCredentialStore();
    if (Platform.isWindows) {
      expect(store, isA<NovelDpapiCredentialStore>());
    } else {
      expect(store, isA<NovelUnavailableCredentialStore>());
    }
  });
}
