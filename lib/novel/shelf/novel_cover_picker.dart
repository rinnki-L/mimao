// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与小说其他页面同款说明。
/// 书架自定义封面的图片选择缝 + 落盘。
///
/// 页面只依赖 [NovelCoverPicker]；生产实现用 file_picker 选一张本地图片，
/// 复制进应用支持目录（`novel_covers/`）后返回绝对路径——不能直接存用户
/// 原路径：用户挪动/删除原文件后封面就空了，且卸载重装无法恢复。
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 选一张本地图片作为书封；返回已复制进应用目录的绝对路径，取消 → null。
abstract interface class NovelCoverPicker {
  Future<String?> pickAndStore(String bookId);
}

/// 生产实现：file_picker（png/jpg/jpeg/webp/gif）→ 复制到支持目录。
class FilePickerNovelCoverPicker implements NovelCoverPicker {
  const FilePickerNovelCoverPicker();

  @override
  Future<String?> pickAndStore(String bookId) async {
    final files = await FilePicker.pickFiles(
      dialogTitle: '选择书籍封面',
      type: FileType.custom,
      allowedExtensions: <String>['png', 'jpg', 'jpeg', 'webp', 'gif'],
    );
    if (files.isEmpty) return null;
    final sourcePath = files.first.path;
    if (sourcePath == null || sourcePath.trim().isEmpty) return null;

    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'novel_covers'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final extension = p.extension(sourcePath).toLowerCase();
    // 文件名带 bookId 的稳定哈希后缀，同一本书重复设置只留最新一份。
    final name =
        '${_safeName(bookId)}_${DateTime.now().millisecondsSinceEpoch}'
        '$extension';
    final target = p.join(directory.path, name);
    await File(sourcePath).copy(target);
    await _pruneOldCovers(directory, _safeName(bookId), keep: target);
    return target;
  }

  /// 只保留这本书最新的一张，避免反复换封面把支持目录堆满。
  Future<void> _pruneOldCovers(
    Directory directory,
    String prefix, {
    required String keep,
  }) async {
    try {
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith('${prefix}_')) continue;
        if (p.equals(entity.path, keep)) continue;
        await entity.delete();
      }
    } on Object {
      // 清理失败不影响本次设置（新文件已就位）。
    }
  }

  /// bookId 可能是 URL，去掉路径分隔符与非法字符。
  static String _safeName(String bookId) {
    final cleaned = bookId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    if (cleaned.length <= 48) return cleaned;
    return cleaned.substring(cleaned.length - 48);
  }
}
