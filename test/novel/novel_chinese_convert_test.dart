// 简繁转换：离线映射双向可用，长度不变，none 不改动。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/reader/novel_chinese_convert.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';

void main() {
  test('简体转繁体', () {
    expect(
      convertNovelChinese('汉字风云', NovelChineseConvert.simplifiedToTraditional),
      '漢字風雲',
    );
  });

  test('繁体转简体', () {
    expect(
      convertNovelChinese('漢字風雲', NovelChineseConvert.traditionalToSimplified),
      '汉字风云',
    );
  });

  test('none 原样返回；未收录字符保持不动', () {
    const text = 'abc 123 未知字';
    expect(convertNovelChinese(text, NovelChineseConvert.none), text);
    expect(
      convertNovelChinese('abc漢', NovelChineseConvert.simplifiedToTraditional),
      'abc漢',
    );
  });

  test('转换不改变字符串长度（逐字映射）', () {
    const text = '后来发现里面有个门';
    final converted = convertNovelChinese(
      text,
      NovelChineseConvert.simplifiedToTraditional,
    );
    expect(converted.length, text.length);
  });
}
