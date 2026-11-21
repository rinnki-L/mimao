// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 歌单封面图片选择缝——页面只依赖 [MusicPlaylistImagePicker] 接口；生产实现
/// 委托 file_picker（widget 测试注入 fake 返回固定内存字节，绝不真调插件）。
///
/// 同时提供与 playlist_pic_upload 端点同域的 PNG 前置校验：非 PNG/超大文件
/// 在 base64 与网络往返之前就拦下，文案与端点一致（端点仍会复核）。
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:mimao/music/api/playlist_pic_upload.dart';

/// 歌单封面图片选择接口：返回 PNG 原始字节；用户取消选择 → null。
abstract interface class MusicPlaylistImagePicker {
  Future<Uint8List?> pickPng();
}

/// 生产实现：file_picker 选一张 PNG 并读入字节。
///
/// 注意：仓库里的 file_picker 13.x 与旧版 API 不同——`pickFiles` 是静态
/// 方法（没有 `FilePicker.platform`），也没有 `withData` 参数；取消时返回
/// 空列表，字节经 `PlatformFile.readAsBytes()` 读取。
class FilePickerPlaylistImagePicker implements MusicPlaylistImagePicker {
  const FilePickerPlaylistImagePicker();

  @override
  Future<Uint8List?> pickPng() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: '选择歌单封面',
      type: FileType.custom,
      allowedExtensions: <String>['png'],
    );
    if (files.isEmpty) return null;
    return files.first.readAsBytes();
  }
}

/// 与 playlist_pic_upload 端点一致的 PNG 前置校验：返回 null 表示字节可用，
/// 否则为可直接展示的中文错误（空/超 8 MB/签名或 IHDR 首块不合法）。
///
/// 校验顺序与端点对齐（长度→签名→首块），把明显不合法的选择拦在上传之前。
String? validatePlaylistCoverPng(Uint8List bytes) {
  if (bytes.length < 33 || bytes.length > maxPlaylistPngBytes) {
    return '请选择有效的 PNG 封面';
  }
  const signature = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var index = 0; index < signature.length; index++) {
    if (bytes[index] != signature[index]) return '请选择有效的 PNG 封面';
  }
  // 13u32.to_be_bytes() = [0,0,0,13]（IHDR 长度），首块类型必须是 'IHDR'。
  const ihdrFrame = <int>[0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52];
  for (var index = 0; index < ihdrFrame.length; index++) {
    if (bytes[8 + index] != ihdrFrame[index]) return '请选择有效的 PNG 封面';
  }
  return null;
}
