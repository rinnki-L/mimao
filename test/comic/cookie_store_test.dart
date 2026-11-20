/// 持久 Cookie 测试：落盘 → 新实例读回；挑战 UA 一起保存。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mimao/comic/request/cookie_store.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('mimao-cookies-');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  File cookieFile() => File('${dir.path}/comic_cookies.json');

  test('Cookie 落盘后新实例能读回（含 domain 属性）', () async {
    final jar = ComicCookieJar(file: cookieFile());
    await jar.ensureLoaded();
    await jar.saveFromResponse(Uri.parse('https://site.test/'), <Cookie>[
      Cookie('sid', 'abc')..domain = 'site.test',
      Cookie('cf_clearance', 'token')..domain = 'site.test',
    ]);
    expect(jar.allCookies, hasLength(2));
    await jar.persist();

    final reloaded = ComicCookieJar(file: cookieFile());
    await reloaded.ensureLoaded();
    final cookies = await reloaded.loadForRequest(
      Uri.parse('https://site.test/list'),
    );
    expect(cookies.map((c) => c.name).toSet(), <String>{'sid', 'cf_clearance'});
    expect(reloaded.allCookies, hasLength(2));
  });

  test('挑战 UA 与 Cookie 一起持久化，主机名大小写不敏感', () async {
    final jar = ComicCookieJar(file: cookieFile());
    await jar.ensureLoaded();
    await jar.setUserAgentFor('WWW.YKMH.NET', 'Mozilla/5.0 webview');

    final reloaded = ComicCookieJar(file: cookieFile());
    await reloaded.ensureLoaded();
    expect(reloaded.userAgentFor('www.ykmh.net'), 'Mozilla/5.0 webview');
  });

  test('坏文件按空库处理，不抛异常', () async {
    await cookieFile().writeAsString('{not json');
    final jar = ComicCookieJar(file: cookieFile());
    await jar.ensureLoaded();
    expect(jar.allCookies, isEmpty);
  });

  test('delete 后落盘文件也不再包含该 Cookie', () async {
    final jar = ComicCookieJar(file: cookieFile());
    await jar.ensureLoaded();
    await jar.saveFromResponse(Uri.parse('https://site.test/'), <Cookie>[
      Cookie('sid', 'abc')..domain = 'site.test',
    ]);
    await jar.persist();

    final reloaded = ComicCookieJar(file: cookieFile());
    await reloaded.ensureLoaded();
    await reloaded.delete(Uri.parse('https://site.test/'), true);
    await reloaded.persist();

    final again = ComicCookieJar(file: cookieFile());
    await again.ensureLoaded();
    expect(again.allCookies, isEmpty);
  });
}
