/// 歌词解析器测试：KRC 完整解密链、LRC、纯文本与损坏内容降级。
///
/// KRC 夹具由测试用**同一把** 16 字节密钥按 `krc1` + XOR + zlib 反向构造，
/// 只验证本仓库实现的解密链与解析行为；不声称附带真实歌曲歌词。
library;

import 'dart:convert';
import 'dart:io' show ZLibEncoder;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/lyric/lyric_models.dart';
import 'package:mimao/music/lyric/lyric_parser.dart';
import 'package:mimao/music/models/lyric_models.dart';

/// 与 `lib/music/lyric/lyric_parser.dart` 中 `_krcXorKey` 一致的测试密钥。
const List<int> _testKey = <int>[
  0x40,
  0x47,
  0x61,
  0x77,
  0x5e,
  0x32,
  0x74,
  0x47,
  0x51,
  0x36,
  0x31,
  0x2d,
  0xce,
  0xd2,
  0x6e,
  0x69,
];

/// 用生产解密链的逆过程构造 KRC 文档：UTF-8 → zlib → XOR → `krc1` → base64。
String encryptKrcFixture(String plainText) {
  final compressed = ZLibEncoder().convert(utf8.encode(plainText));
  final packed = <int>[0x6b, 0x72, 0x63, 0x31]; // krc1
  for (var i = 0; i < compressed.length; i++) {
    packed.add(compressed[i] ^ _testKey[i % _testKey.length]);
  }
  return base64Encode(packed);
}

MusicLyricDownload download(String format, String content) =>
    MusicLyricDownload(format: format, encoding: 'base64', content: content);

void main() {
  group('KRC', () {
    final languageJson = jsonEncode(<String, Object?>{
      'content': <Object?>[
        <String, Object?>{
          'type': 1,
          'language': 0,
          'lyricContent': <Object?>[
            <Object?>['你好，世界'],
            <Object?>['第二行翻译'],
          ],
        },
        <String, Object?>{
          'type': 0,
          'language': 0,
          'lyricContent': <Object?>[
            <Object?>['ni hao shi jie'],
            <Object?>['di er hang'],
          ],
        },
      ],
    });
    final language = base64Encode(utf8.encode(languageJson));

    final plain =
        '''
[id:00000000]
[ar:测试歌手]
[ti:测试歌曲]
[language:$language]
[0,2000]<0,500,0>你<500,500,0>好<1000,1000,0>世界
[2000,3000]<0,1500,0>第二<1500,1500,0>行
''';

    test('完整解密并解析出行、翻译、音译', () {
      final parsed = parseLyric(download('krc', encryptKrcFixture(plain)));

      expect(parsed.lines, hasLength(2));
      final first = parsed.lines[0];
      expect(first.start, Duration.zero);
      expect(first.end, const Duration(seconds: 2));
      expect(first.original, '你好世界');
      expect(first.translation, '你好，世界');
      expect(first.transliteration, 'ni hao shi jie');

      final second = parsed.lines[1];
      expect(second.start, const Duration(seconds: 2));
      expect(second.end, const Duration(seconds: 5));
      expect(second.original, '第二行');
      expect(second.translation, '第二行翻译');
      expect(second.transliteration, 'di er hang');
    });

    test('language 块在正文之后出现也能按行对齐', () {
      final tailPlain =
          '''
[0,1000]<0,500,0>甲
[1000,1000]<0,500,0>乙
[language:$language]
''';
      final parsed = parseLyric(download('krc', encryptKrcFixture(tailPlain)));

      expect(parsed.lines, hasLength(2));
      expect(parsed.lines[0].translation, '你好，世界');
      expect(parsed.lines[1].translation, '第二行翻译');
      expect(parsed.lines[0].transliteration, 'ni hao shi jie');
    });

    test('缺少 language 块时翻译/音译为 null', () {
      const noLanguage = '[0,1000]<0,500,0>只有原文\n';
      final parsed = parseLyric(download('krc', encryptKrcFixture(noLanguage)));

      expect(parsed.lines, hasLength(1));
      expect(parsed.lines.single.translation, isNull);
      expect(parsed.lines.single.transliteration, isNull);
    });

    test('魔数错误、base64 损坏、zlib 损坏均返回空列表且不抛异常', () {
      final badMagic = base64Encode(utf8.encode('not-a-krc-document'));
      final badZlib = base64Encode(<int>[0x6b, 0x72, 0x63, 0x31, 1, 2, 3, 4]);

      for (final content in <String>[
        badMagic,
        badZlib,
        '这不是合法的 base64 !!!',
        '',
      ]) {
        late ParsedLyric parsed;
        expect(
          () => parsed = parseLyric(download('krc', content)),
          returnsNormally,
        );
        expect(parsed.lines, isEmpty);
      }
    });
  });

  group('LRC', () {
    test('解析 [mm:ss.xx] 行并按时长补齐结束时间', () {
      final content = base64Encode(
        utf8.encode('[ar:测试]\n[00:01.50]第一行\n[00:10.00]第二行\n'),
      );
      final parsed = parseLyric(download('lrc', content));

      expect(parsed.lines, hasLength(2));
      expect(parsed.lines[0].start, const Duration(milliseconds: 1500));
      expect(parsed.lines[0].end, const Duration(seconds: 10));
      expect(parsed.lines[0].original, '第一行');
      expect(parsed.lines[1].start, const Duration(seconds: 10));
      expect(parsed.lines[1].end, const Duration(seconds: 14));
      expect(parsed.lines[1].original, '第二行');
    });

    test('一行多个时间戳会展开成多行', () {
      final content = base64Encode(
        utf8.encode('[00:01.00][00:05.00]副歌\n[00:09.00]结尾\n'),
      );
      final parsed = parseLyric(download('lrc', content));

      expect(parsed.lines, hasLength(3));
      expect(parsed.lines[0].start, const Duration(seconds: 1));
      expect(parsed.lines[1].start, const Duration(seconds: 5));
      expect(parsed.lines[2].start, const Duration(seconds: 9));
      expect(parsed.lines[0].original, '副歌');
      expect(parsed.lines[1].original, '副歌');
      expect(parsed.lines[2].original, '结尾');
    });

    test('没有时间戳或 base64 损坏时返回空列表', () {
      final noTimestamp = base64Encode(utf8.encode('只是一段普通文本\n'));
      expect(parseLyric(download('lrc', noTimestamp)).lines, isEmpty);
      expect(parseLyric(download('lrc', '%%%')).lines, isEmpty);
    });
  });

  group('纯文本', () {
    test('按行切分并给递增伪时间', () {
      final content = base64Encode(utf8.encode('第一行\n\n第二行\n'));
      final parsed = parseLyric(download('text', content));

      expect(parsed.lines, hasLength(2));
      expect(parsed.lines[0].original, '第一行');
      expect(parsed.lines[0].start, Duration.zero);
      expect(parsed.lines[1].original, '第二行');
      expect(parsed.lines[1].start, const Duration(seconds: 4));
      expect(parsed.lines[1].translation, isNull);
    });
  });

  test('未知格式返回空列表且不抛异常', () {
    late ParsedLyric parsed;
    expect(
      () => parsed = parseLyric(download('ttml', 'anything')),
      returnsNormally,
    );
    expect(parsed.lines, isEmpty);
  });
}
