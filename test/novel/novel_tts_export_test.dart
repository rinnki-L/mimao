// 朗读导出（L2）：多段 wav 拼接、进度、取消清理；用假引擎写最小 wav。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/reader/novel_tts.dart';
import 'package:mimao/novel/reader/novel_tts_export.dart';

class _WavEngine implements NovelTtsEngine {
  final List<String> synthesized = <String>[];

  @override
  bool get supportsFileOutput => true;

  @override
  bool get supportsFilePlayback => true;

  @override
  Future<void> configure() async {}

  @override
  Future<List<NovelTtsVoice>> voices() async => const <NovelTtsVoice>[];

  @override
  Future<void> speak(
    String text, {
    required double rate,
    String voice = '',
    String? cacheKey,
  }) async {}

  @override
  Future<void> synthesizeToFile(
    String text,
    String path, {
    required double rate,
    String voice = '',
  }) async {
    synthesized.add(text);
    await File(path).writeAsBytes(_wavBytes(8));
  }

  @override
  Future<void> playFile(String path) async {}

  @override
  Future<void> stop() async {}
}

Uint8List _wavBytes(int dataLength) {
  final data = Uint8List(dataLength);
  final out = BytesBuilder(copy: false);
  out.add(ascii.encode('RIFF'));
  out.add(_u32(36 + dataLength));
  out.add(ascii.encode('WAVE'));
  out.add(ascii.encode('fmt '));
  out.add(_u32(16));
  out.add(_u16(1)); // PCM（格式标签是 2 字节）
  out.add(_u16(1)); // 单声道
  out.add(_u32(22050));
  out.add(_u32(44100));
  out.add(_u16(2));
  out.add(_u16(16));
  out.add(ascii.encode('data'));
  out.add(_u32(dataLength));
  out.add(data);
  return out.takeBytes();
}

Uint8List _u16(int value) => Uint8List(2)
  ..[0] = value & 0xFF
  ..[1] = (value >> 8) & 0xFF;

Uint8List _u32(int value) => Uint8List(4)
  ..[0] = value & 0xFF
  ..[1] = (value >> 8) & 0xFF
  ..[2] = (value >> 16) & 0xFF
  ..[3] = (value >> 24) & 0xFF;

int _readU32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

void main() {
  late Directory work;
  late Directory outDir;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('mimao_tts_work_');
    outDir = await Directory.systemTemp.createTemp('mimao_tts_out_');
  });

  tearDown(() async {
    for (final dir in <Directory>[work, outDir]) {
      try {
        await dir.delete(recursive: true);
      } on Object {
        // Windows 占用时留给系统临时目录清理。
      }
    }
  });

  test('两章四段拼成一个合法 wav，RIFF/data 长度回填正确', () async {
    final engine = _WavEngine();
    final exporter = NovelTtsExporter(engine: engine, workDirectory: work);
    final progress = <int>[];
    final output = '${outDir.path}${Platform.pathSeparator}book.wav';

    final result = await exporter.export(
      outputPath: output,
      chapters: Stream<List<String>>.fromIterable(<List<String>>[
        <String>['第一章', '甲'],
        <String>['第二章', '乙', '丙'],
      ]),
      rate: 1.0,
      totalChapters: 2,
      onProgress: (done, total) => progress.add(done),
    );

    expect(result.paragraphs, 5);
    expect(progress, <int>[1, 2]);
    expect(engine.synthesized, <String>['第一章', '甲', '第二章', '乙', '丙']);

    final bytes = await File(output).readAsBytes();
    expect(bytes.length, 44 + 8 * 5);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(_readU32(bytes, 4), bytes.length - 8);
    expect(_readU32(bytes, 40), 8 * 5, reason: 'data 块长度 = 所有段之和');
    // 临时段文件已删。
    expect(work.listSync().whereType<File>(), isEmpty);
  });

  test('取消导出会删掉半成品目标文件', () async {
    final engine = _WavEngine();
    final exporter = NovelTtsExporter(engine: engine, workDirectory: work);
    final output = '${outDir.path}${Platform.pathSeparator}cancel.wav';
    var calls = 0;

    await expectLater(
      exporter.export(
        outputPath: output,
        chapters: Stream<List<String>>.fromIterable(<List<String>>[
          <String>['第一章', '甲', '乙', '丙'],
        ]),
        rate: 1.0,
        isCancelled: () => calls++ >= 2,
      ),
      throwsA(isA<NovelTtsExportCancelled>()),
    );
    expect(File(output).existsSync(), isFalse);
  });

  test('合成格式不一致时报错并删掉半成品', () async {
    final engine = _FormatMismatchEngine();
    final exporter = NovelTtsExporter(engine: engine, workDirectory: work);
    final output = '${outDir.path}${Platform.pathSeparator}mismatch.wav';

    await expectLater(
      exporter.export(
        outputPath: output,
        chapters: Stream<List<String>>.fromIterable(<List<String>>[
          <String>['甲', '乙'],
        ]),
        rate: 1.0,
      ),
      throwsA(isA<StateError>()),
    );
    expect(File(output).existsSync(), isFalse);
  });
}

class _FormatMismatchEngine extends _WavEngine {
  var _index = 0;

  @override
  Future<void> synthesizeToFile(
    String text,
    String path, {
    required double rate,
    String voice = '',
  }) async {
    final bytes = _wavBytes(8);
    if (_index++ > 0) {
      // 改采样率：fmt 内容不同，拼接必须拒绝。
      bytes[24] = 0x44;
    }
    await File(path).writeAsBytes(bytes);
  }
}
