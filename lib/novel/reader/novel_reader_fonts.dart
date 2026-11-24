// 阅读器导入字体：把 .ttf/.otf 复制到本地字体目录，并用 FontLoader 在运行时
// 注册成 fontFamily。字体选择本身仍落在 reader_settings 的 fontFamily 字段，
// 不新建第二套存储；文件名（去扩展名）就是持久化的 family。
//
// 目录：<applicationSupport>/mimao/reader_fonts/。桌面/Android 都可写；
// 测试/CI 没有 path_provider 插件时，[NovelFontRegistry] 的公开方法会捕获
// 异常返回空列表，界面照样能打开（只是看不到导入项）。

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 一个已导入的字体文件。
class NovelFontFile {
  const NovelFontFile({
    required this.path,
    required this.family,
    required this.label,
  });

  final String path;

  /// FontLoader 注册名，同时也是 reader_settings.fontFamily 的值。
  final String family;

  /// 界面上显示的名字（文件名去扩展名）。
  final String label;
}

/// 导入字体仓库（进程内单例；只做文件 IO 与 FontLoader 注册）。
class NovelFontRegistry {
  NovelFontRegistry({String? directory}) : _overrideDirectory = directory;

  static final NovelFontRegistry instance = NovelFontRegistry();

  final String? _overrideDirectory;
  final Set<String> _loadedFamilies = <String>{};
  Directory? _resolvedDirectory;

  static const List<String> fontExtensions = <String>['ttf', 'otf'];

  /// 字体目录；拿不到 platform 目录时返回 null。
  Future<Directory?> fontDirectory() async {
    final override = _overrideDirectory;
    if (override != null) {
      final dir = Directory(override);
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    final cached = _resolvedDirectory;
    if (cached != null) return cached;
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(p.join(support.path, 'mimao', 'reader_fonts'));
      if (!await dir.exists()) await dir.create(recursive: true);
      _resolvedDirectory = dir;
      return dir;
    } on Object {
      return null;
    }
  }

  /// 列出目录里所有字体文件；失败/空目录返回空列表。
  Future<List<NovelFontFile>> list() async {
    final dir = await fontDirectory();
    if (dir == null) return const <NovelFontFile>[];
    try {
      final entries = await dir.list(followLinks: false).toList();
      final result = <NovelFontFile>[];
      for (final entry in entries) {
        if (entry is! File) continue;
        final ext = p.extension(entry.path).toLowerCase().replaceFirst('.', '');
        if (!fontExtensions.contains(ext)) continue;
        final family = p.basenameWithoutExtension(entry.path);
        if (family.isEmpty) continue;
        result.add(
          NovelFontFile(path: entry.path, family: family, label: family),
        );
      }
      result.sort((a, b) => a.label.compareTo(b.label));
      return result;
    } on Object {
      return const <NovelFontFile>[];
    }
  }

  /// 把 [sourcePath] 复制进字体目录；同名覆盖。返回导入后的记录。
  Future<NovelFontFile?> importFile(String sourcePath) async {
    final dir = await fontDirectory();
    if (dir == null) return null;
    final source = File(sourcePath);
    if (!await source.exists()) return null;
    try {
      final name = p.basename(sourcePath);
      final target = File(p.join(dir.path, name));
      if (p.normalize(source.absolute.path) !=
          p.normalize(target.absolute.path)) {
        await source.copy(target.path);
      }
      final family = p.basenameWithoutExtension(name);
      final font = NovelFontFile(
        path: target.path,
        family: family,
        label: family,
      );
      await loadFont(font);
      return font;
    } on Object {
      return null;
    }
  }

  /// 注册单个字体；重复注册同一 family 直接跳过。
  Future<void> loadFont(NovelFontFile font) async {
    if (_loadedFamilies.contains(font.family)) return;
    try {
      final bytes = await File(font.path).readAsBytes();
      final loader = FontLoader(font.family)
        ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
      await loader.load();
      _loadedFamilies.add(font.family);
    } on Object {
      // 文件坏/字体非法都不该让阅读器起不来；选择项仍会显示，渲染回退系统字体。
    }
  }

  /// 注册目录里的全部字体（进入阅读器时调一次）。
  Future<void> loadAll() async {
    for (final font in await list()) {
      await loadFont(font);
    }
  }
}

/// 弹出系统文件选择框选一个 .ttf/.otf；取消返回 null。
Future<String?> pickNovelFontFile() async {
  final files = await FilePicker.pickFiles(
    dialogTitle: '选择字体文件',
    type: FileType.custom,
    allowedExtensions: NovelFontRegistry.fontExtensions,
  );
  if (files.isEmpty) return null;
  return files.first.path;
}
