// 朗读导出（L2）：把段落合成成 wav，再拼成一个文件。
//
// Windows 走 System.Speech 的 `SetOutputToWaveFile`（见 novel_tts.dart 的常驻
// 宿主）；这里只负责：逐段落临时文件 → 追加 PCM 数据 → 回填 RIFF 头。
// 纯 Dart 拼接，测试用假引擎写最小 wav 即可验证，不必真起语音。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'novel_tts.dart';

/// 导出结果。
class NovelTtsExportResult {
  const NovelTtsExportResult({
    required this.path,
    required this.paragraphs,
    required this.bytes,
  });

  final String path;

  /// 实际合成的段数（含章节标题）。
  final int paragraphs;
  final int bytes;
}

/// 用户取消导出（不是错误，页面不弹错误提示）。
class NovelTtsExportCancelled implements Exception {
  const NovelTtsExportCancelled();
}

/// 按章流式导出：每项是一章的朗读文本（标题 + 段落）。
class NovelTtsExporter {
  NovelTtsExporter({required this.engine, required this.workDirectory});

  final NovelTtsEngine engine;
  final Directory workDirectory;

  /// [chapters] 按顺序给出每章要念的文本；[onProgress] 每完成一章回调一次。
  /// [isCancelled] 返回 true 时中止并删除半成品，抛 [NovelTtsExportCancelled]。
  Future<NovelTtsExportResult> export({
    required String outputPath,
    required Stream<List<String>> chapters,
    required double rate,
    String voice = '',
    int? totalChapters,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!await workDirectory.exists()) {
      await workDirectory.create(recursive: true);
    }
    final writer = await _WavWriter.open(outputPath);
    var paragraphCount = 0;
    var chapterIndex = 0;
    try {
      await for (final paragraphs in chapters) {
        if (isCancelled?.call() ?? false) {
          throw const NovelTtsExportCancelled();
        }
        for (var i = 0; i < paragraphs.length; i++) {
          if (isCancelled?.call() ?? false) {
            throw const NovelTtsExportCancelled();
          }
          final text = paragraphs[i].trim();
          if (text.isEmpty) continue;
          final temp = File(
            '${workDirectory.path}${Platform.pathSeparator}'
            'seg-$chapterIndex-$i.wav',
          );
          await engine.synthesizeToFile(
            text,
            temp.path,
            rate: rate,
            voice: voice,
          );
          await writer.addFile(temp.path);
          paragraphCount++;
          try {
            await temp.delete();
          } on Object {
            // 临时文件删不掉不阻塞导出；退出时整目录再清一次。
          }
        }
        chapterIndex++;
        onProgress?.call(chapterIndex, totalChapters ?? chapterIndex);
        await Future<void>.delayed(Duration.zero);
      }
      final bytes = await writer.finish();
      return NovelTtsExportResult(
        path: outputPath,
        paragraphs: paragraphCount,
        bytes: bytes,
      );
    } on Object {
      await writer.abort();
      // 半成品不留：用户取消/合成失败都删掉目标文件。
      try {
        final file = File(outputPath);
        if (await file.exists()) await file.delete();
      } on Object {
        // 文件被占用就留给用户自己处理。
      }
      rethrow;
    }
  }
}

/// 把所有段落的 PCM 数据写进一个 wav；格式取第一段，后续不一致直接报错。
class _WavWriter {
  _WavWriter._(this._file, this._headerLength);

  final RandomAccessFile _file;
  Uint8List? _fmt;
  int _headerLength;
  int _dataBytes = 0;
  bool _closed = false;

  /// 44 字节基础头之外，fmt 块可能带扩展（如 18 字节），头长度随之变化。
  static const int _riffSizeOffset = 4;
  static int _dataSizeOffset(int headerLength) => headerLength - 4;

  static Future<_WavWriter> open(String path) async {
    final file = await File(path).open(mode: FileMode.write);
    // 先写占位头（fmt 等第一段确定格式后回填）。
    final header = _buildHeader(Uint8List.fromList(const <int>[1, 0, 1, 0]));
    await file.writeFrom(header);
    return _WavWriter._(file, header.length);
  }

  Future<void> addFile(String path) async {
    final bytes = await File(path).readAsBytes();
    final parsed = _parseWav(bytes);
    final fmt = _fmt;
    if (fmt == null) {
      _fmt = parsed.fmt;
      // 重写头：fmt 长度可能不是 16。先截断，避免占位头尾部残留。
      await _file.truncate(0);
      await _file.setPosition(0);
      final header = _buildHeader(parsed.fmt);
      await _file.writeFrom(header);
      _headerLength = header.length;
    } else if (!_bytesEqual(fmt, parsed.fmt)) {
      throw StateError('合成音频格式不一致，无法拼接');
    }
    await _file.setPosition(_headerLength + _dataBytes);
    await _file.writeFrom(parsed.data);
    _dataBytes += parsed.data.length;
    if (parsed.data.length.isOdd) {
      await _file.writeByte(0);
      _dataBytes++;
    }
  }

  Future<int> finish() async {
    if (_closed) return _headerLength + _dataBytes;
    _closed = true;
    if (_fmt == null) {
      await _file.close();
      throw StateError('没有可导出的段落');
    }
    final total = _headerLength + _dataBytes;
    await _file.setPosition(_riffSizeOffset);
    await _file.writeFrom(_u32(total - 8));
    await _file.setPosition(_dataSizeOffset(_headerLength));
    await _file.writeFrom(_u32(_dataBytes));
    await _file.flush();
    await _file.close();
    return total;
  }

  Future<void> abort() async {
    if (_closed) return;
    _closed = true;
    try {
      await _file.close();
    } on Object {
      // 已关闭/被占用。
    }
  }

  static Uint8List _buildHeader(Uint8List fmt) {
    final data = BytesBuilder(copy: false);
    data.add(ascii.encode('RIFF'));
    data.add(_u32(0));
    data.add(ascii.encode('WAVE'));
    data.add(ascii.encode('fmt '));
    data.add(_u32(fmt.length));
    data.add(fmt);
    data.add(ascii.encode('data'));
    data.add(_u32(0));
    if (fmt.length.isOdd) data.addByte(0);
    return data.takeBytes();
  }

  static ({Uint8List fmt, Uint8List data}) _parseWav(Uint8List bytes) {
    if (bytes.length < 44 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw StateError(
        '不是有效的 wav 文件（${bytes.length} 字节，'
        '头=${bytes.take(12).map((b) => b.toRadixString(16)).join(' ')}）',
      );
    }
    Uint8List? fmt;
    Uint8List? data;
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = _readU32(bytes, offset + 4);
      final start = offset + 8;
      if (start + size > bytes.length) {
        // 有些合成器把 data size 写成 0 或超出文件长度，按实际剩余取。
        if (id == 'data') {
          data = Uint8List.sublistView(bytes, start);
          break;
        }
        break;
      }
      if (id == 'fmt ') {
        fmt = Uint8List.sublistView(bytes, start, start + size);
      } else if (id == 'data') {
        data = Uint8List.sublistView(bytes, start, start + size);
        break;
      }
      offset = start + size + (size.isOdd ? 1 : 0);
    }
    if (fmt == null || data == null) {
      throw StateError(
        'wav 缺少 fmt/data 块（${bytes.length} 字节，fmt=$fmt data=$data）',
      );
    }
    return (fmt: fmt, data: data);
  }

  static int _readU32(Uint8List bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  static Uint8List _u32(int value) => Uint8List(4)
    ..[0] = value & 0xFF
    ..[1] = (value >> 8) & 0xFF
    ..[2] = (value >> 16) & 0xFF
    ..[3] = (value >> 24) & 0xFF;

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
