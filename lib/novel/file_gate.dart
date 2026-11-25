/// 通用 JSON 文件选择/保存缝（词典规则导入、主题包导入导出共用）。
///
/// 与 `booklist_io.dart` 的书单闸门同思路：页面只认窄接口，测试注入内存
/// 实现；生产走 file_picker 的静态 API（13.x 没有 `FilePicker.platform`）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// 用户选中的 JSON 文件（已按 UTF-8 宽松解码成文本）。
class NovelPickedJsonFile {
  const NovelPickedJsonFile({required this.name, required this.text});

  final String name;
  final String text;
}

/// 文件闸门窄接口。
abstract interface class NovelJsonFileGate {
  /// 让用户选一个 JSON 文件；取消返回 null。
  Future<NovelPickedJsonFile?> pick({
    String dialogTitle = '选择 JSON 文件',
    String suggestedExtension = 'json',
  });

  /// 让用户选保存位置并写入；取消/失败返回 null，成功返回路径。
  Future<String?> save(
    String suggestedName,
    Uint8List bytes, {
    String dialogTitle = '保存 JSON 文件',
    String mimeType = 'application/json',
  });
}

/// file_picker 生产实现。
class FilePickerJsonFileGate implements NovelJsonFileGate {
  const FilePickerJsonFileGate();

  @override
  Future<NovelPickedJsonFile?> pick({
    String dialogTitle = '选择 JSON 文件',
    String suggestedExtension = 'json',
  }) async {
    final file = await FilePicker.pickFile(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: <String>[suggestedExtension, 'txt'],
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return NovelPickedJsonFile(
      name: file.name,
      text: const Utf8Decoder(allowMalformed: true).convert(bytes),
    );
  }

  @override
  Future<String?> save(
    String suggestedName,
    Uint8List bytes, {
    String dialogTitle = '保存 JSON 文件',
    String mimeType = 'application/json',
  }) async {
    final uri = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: suggestedName,
      bytes: bytes,
      mimeType: mimeType,
    );
    return uri?.toString();
  }
}
