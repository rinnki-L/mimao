// 登录取 Cookie 的纯逻辑测试：Cookie 合并进 header 的行为。
//
// WebView 本体不在这里测（需要 native 插件）；页面用注入 builder 的渲染
// 由 novel_pages_test 覆盖。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/pages/novel_source_login_page.dart';

void main() {
  test('空 header 生成只含 Cookie 的对象', () {
    final merged = mergeNovelCookieIntoHeader('', 'a=1; b=2');
    expect(jsonDecode(merged), <String, dynamic>{'Cookie': 'a=1; b=2'});
  });

  test('保留已有请求头，只加/换 Cookie', () {
    final header = jsonEncode(<String, String>{
      'User-Agent': 'UA',
      'Referer': 'https://s.example/',
    });
    final merged = mergeNovelCookieIntoHeader(header, 'sid=abc');
    final decoded = jsonDecode(merged) as Map<String, dynamic>;
    expect(decoded['User-Agent'], 'UA');
    expect(decoded['Referer'], 'https://s.example/');
    expect(decoded['Cookie'], 'sid=abc');
  });

  test('已有 Cookie 被替换而不是追加', () {
    final header = jsonEncode(<String, String>{'Cookie': 'old=1'});
    final merged = mergeNovelCookieIntoHeader(header, 'new=2');
    expect((jsonDecode(merged) as Map)['Cookie'], 'new=2');
  });

  test('空 Cookie 原样返回 header', () {
    const header = '{"User-Agent":"UA"}';
    expect(mergeNovelCookieIntoHeader(header, '   '), header);
  });

  test('非法 header 不静默丢弃：原样返回，由调用方提示', () {
    const broken = '{oops';
    expect(mergeNovelCookieIntoHeader(broken, 'a=1'), broken);
  });

  test('Cookie 结果 isEmpty 判定', () {
    const empty = NovelLoginCookieResult(cookieHeader: '  ', url: 'u');
    expect(empty.isEmpty, isTrue);
    const filled = NovelLoginCookieResult(cookieHeader: 'a=1', url: 'u');
    expect(filled.isEmpty, isFalse);
  });
}
