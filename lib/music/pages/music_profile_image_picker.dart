// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 头像图片选择缝——页面只依赖 [MusicProfileImagePicker] 接口；生产实现
/// 委托 file_picker（widget 测试只注入 fake，绝不真调插件）。
///
/// 同时提供与 user_avatar_upload 端点同域的前置校验：超大文件/非图片在
/// base64 编码与网络往返之前就拦下，提示与端点文案一致。
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// 头像图片选择接口：返回图片原始字节；用户取消选择 → null。
abstract interface class MusicProfileImagePicker {
  Future<Uint8List?> pickImage();
}

/// 生产实现：file_picker 选一张图片并读入字节。
///
/// 注意：仓库里的 file_picker 13.x 与旧版 API 不同——`pickFiles` 是静态
/// 方法（没有 `FilePicker.platform`），也没有 `withData` 参数；取消时返回
/// 空列表，字节经 `PlatformFile.readAsBytes()` 读取。
class FilePickerProfileImagePicker implements MusicProfileImagePicker {
  const FilePickerProfileImagePicker();

  @override
  Future<Uint8List?> pickImage() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return null;
    return files.first.readAsBytes();
  }
}

/// 与 user_avatar_upload 端点一致的原始字节上限（8 MB）。
const int kAvatarImageByteLimit = 8 * 1024 * 1024;

/// 前置校验：返回 null 表示字节可用，否则为可直接展示的中文错误。
///
/// 与端点校验同域（空文件/超 8 MB 拒绝 + PNG/GIF/JPEG 魔数识别），
/// 把明显不合法的选择拦在编码与上传之前。
String? validateAvatarImageBytes(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > kAvatarImageByteLimit) {
    return '头像图片不能超过 8 MB';
  }
  bool startsWith(List<int> magic) {
    if (bytes.length < magic.length) return false;
    for (var index = 0; index < magic.length; index++) {
      if (bytes[index] != magic[index]) return false;
    }
    return true;
  }

  const pngMagic = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (startsWith(pngMagic) ||
      startsWith('GIF87a'.codeUnits) ||
      startsWith('GIF89a'.codeUnits) ||
      startsWith(const <int>[0xFF, 0xD8, 0xFF])) {
    return null;
  }
  return '请选择 JPEG、PNG 或 GIF 图片';
}
