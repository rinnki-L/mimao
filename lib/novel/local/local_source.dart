/// 本地书的字节来源抽象：真实文件与内存文件走同一接口。
///
/// 分章与解码只依赖 [NovelLocalBytes]，测试用 [NovelMemoryFile] 构造字节，
/// 完全不碰真实文件系统路径；生产用 [NovelLocalFile]（`dart:io` 按需读区段）。
/// 文件被移动/删除时抛 [NovelLocalFileMissing]，页面据此给「重新定位文件」。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 本地书文件不存在/不可读（被移动、被删、权限变了）。
///
/// 单独成类型而不是让 [FileSystemException] 冒到界面：页面要按它渲染
/// 「重新定位文件」的可操作错误态，其余异常仍走通用错误分支。
class NovelLocalFileMissing implements Exception {
  const NovelLocalFileMissing(this.path, [this.cause]);

  final String path;
  final Object? cause;

  @override
  String toString() => '本地文件已不可读：$path${cause == null ? '' : '（$cause）'}';
}

/// 本地书的字节来源。
abstract interface class NovelLocalBytes {
  /// 展示/落库用的路径或标识（内存文件给一个 `memory:…` 名字）。
  String get path;

  /// 文件字节数（不读内容）。
  Future<int> length();

  /// 读 [start] 起的至多 [length] 字节；越界自动截断，返回可能短于请求。
  Future<Uint8List> read(int start, int length);

  /// 全量字节。只在「整本必须一次读」的场合用（EPUB 是 zip，必须全量）；
  /// TXT/Markdown 分章走 [read] 的分段读取，不要用它。
  Future<Uint8List> readAll();
}

/// 真实文件：按区段 seek 读取，不整本进内存。
class NovelLocalFile implements NovelLocalBytes {
  const NovelLocalFile(this.path);

  @override
  final String path;

  File get _file => File(path);

  Future<void> _ensureReadable() async {
    try {
      if (!await _file.exists()) {
        throw NovelLocalFileMissing(path, '文件不存在');
      }
    } on FileSystemException catch (error) {
      throw NovelLocalFileMissing(path, error);
    }
  }

  @override
  Future<int> length() async {
    await _ensureReadable();
    try {
      return await _file.length();
    } on FileSystemException catch (error) {
      throw NovelLocalFileMissing(path, error);
    }
  }

  @override
  Future<Uint8List> read(int start, int length) async {
    if (length <= 0) return Uint8List(0);
    await _ensureReadable();
    RandomAccessFile? handle;
    try {
      handle = await _file.open();
      final total = await handle.length();
      if (start >= total) return Uint8List(0);
      final count = (total - start).clamp(0, length);
      await handle.setPosition(start);
      return await handle.read(count);
    } on FileSystemException catch (error) {
      throw NovelLocalFileMissing(path, error);
    } finally {
      try {
        await handle?.close();
      } on Object {
        // 关闭失败不该盖住上面的读取结果/错误。
      }
    }
  }

  @override
  Future<Uint8List> readAll() async {
    await _ensureReadable();
    try {
      return await _file.readAsBytes();
    } on FileSystemException catch (error) {
      throw NovelLocalFileMissing(path, error);
    }
  }
}

/// 内存文件：测试与「导入页预览」共用（预览时已经读过一遍字节，不必再读盘）。
///
/// [path] 原样保留调用方给的名字：导入页把真实文件路径传进来，落库的就是
/// 那个路径；测试传 `样本.txt` 这类假名字也不会被当成真实文件。
class NovelMemoryFile implements NovelLocalBytes {
  NovelMemoryFile(this.path, Uint8List bytes) : _bytes = bytes;

  /// 从字符串构造（UTF-8 编码），测试里最常用。
  factory NovelMemoryFile.text(String name, String text) =>
      NovelMemoryFile(name, Uint8List.fromList(utf8.encode(text)));

  @override
  final String path;

  final Uint8List _bytes;

  @override
  Future<int> length() async => _bytes.length;

  @override
  Future<Uint8List> read(int start, int length) async {
    if (length <= 0 || start >= _bytes.length) return Uint8List(0);
    final end = (start + length).clamp(0, _bytes.length);
    return Uint8List.sublistView(_bytes, start, end);
  }

  @override
  Future<Uint8List> readAll() async => _bytes;
}

/// 小工具：把一段字节按 UTF-8 编成字符串（仅用于测试/调试）。
Uint8List utf8BytesOf(String text) => Uint8List.fromList(utf8.encode(text));
