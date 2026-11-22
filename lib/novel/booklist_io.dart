/// 书单导入/导出：纯 JSON 编解码 + 文件选择缝（可注入 fake，测试不碰插件）。
///
/// 格式刻意与 Legado 书源无关：只带走"我的书架有哪些书、读到哪、在哪个分组"，
/// 换机/备份用；不含正文。导出不写进 `tmp/` 或仓库，落盘位置由用户选。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';

/// 书单文件标识（导入时校验，避免把任意 JSON 当书单）。
const String novelBooklistFormat = 'mimao-novel-booklist';

/// 书单版本；未来字段变化时递增并保留旧版解析分支。
const int novelBooklistVersion = 1;

/// 书单里的一本书。
class NovelBooklistBook {
  const NovelBooklistBook({
    required this.id,
    required this.title,
    this.author = '',
    this.coverUrl = '',
    this.sourceName = novelSourceName,
    this.groupName,
    this.chapterIndex = 0,
    this.chapterCount = 0,
  });

  final String id;
  final String title;
  final String author;
  final String coverUrl;
  final String sourceName;
  final String? groupName;
  final int chapterIndex;
  final int chapterCount;

  NovelSummary toSummary() => NovelSummary(
    id: id,
    title: title,
    coverUrl: coverUrl,
    author: author,
    sourceName: sourceName,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'title': title,
    'author': author,
    'coverUrl': coverUrl,
    'sourceName': sourceName,
    if (groupName != null && groupName!.isNotEmpty) 'groupName': groupName,
    'chapterIndex': chapterIndex,
    'chapterCount': chapterCount,
  };

  factory NovelBooklistBook.fromJson(Map<String, Object?> json) =>
      NovelBooklistBook(
        id: '${json['id'] ?? ''}'.trim(),
        title: '${json['title'] ?? ''}'.trim(),
        author: '${json['author'] ?? ''}'.trim(),
        coverUrl: '${json['coverUrl'] ?? ''}'.trim(),
        sourceName: '${json['sourceName'] ?? novelSourceName}',
        groupName: _optional(json['groupName']),
        chapterIndex: _int(json['chapterIndex']),
        chapterCount: _int(json['chapterCount']),
      );

  /// 从收藏行导出（书名/作者/封面/分组/进度一应从权威行与历史来）。
  factory NovelBooklistBook.fromCollect(
    NovelCollectItem item, {
    int chapterIndex = 0,
    int chapterCount = 0,
  }) => NovelBooklistBook(
    id: item.ref.id,
    title: item.title,
    author: item.book?.author ?? '',
    coverUrl: item.coverUrl ?? item.book?.coverUrl ?? '',
    sourceName: item.ref.sourceName,
    groupName: item.groupName,
    chapterIndex: chapterIndex,
    chapterCount: chapterCount,
  );

  bool get hasProgress => chapterCount > 0 && chapterIndex > 0;
}

/// 导出书单正文（带缩进，方便用户手改）。
String encodeNovelBooklist(
  Iterable<NovelBooklistBook> books, {
  DateTime? exportedAt,
}) {
  final document = <String, Object?>{
    'format': novelBooklistFormat,
    'version': novelBooklistVersion,
    'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
    'books': <Object?>[for (final book in books) book.toJson()],
  };
  return '${const JsonEncoder.withIndent('  ').convert(document)}\n';
}

/// 解析书单正文。
///
/// 接受三种形态：本应用导出的对象、纯书籍数组、单个书籍对象。缺 id 或书名
/// 的条目跳过（不整单失败）；完全解析不出书时抛 [FormatException]。
List<NovelBooklistBook> decodeNovelBooklist(String text) {
  final decoded = jsonDecode(text);
  final List<Object?> rawBooks;
  if (decoded is List) {
    rawBooks = decoded;
  } else if (decoded is Map) {
    if (decoded['format'] != null && decoded['format'] != novelBooklistFormat) {
      throw const FormatException('不是 mimao 书单文件');
    }
    final books = decoded['books'];
    if (books is List) {
      rawBooks = books;
    } else if (decoded.containsKey('id') || decoded.containsKey('title')) {
      // 单个书籍对象。
      rawBooks = <Object?>[decoded];
    } else {
      throw const FormatException('书单里没有 books 数组');
    }
  } else {
    throw const FormatException('书单文件不是合法的 JSON 对象/数组');
  }

  final result = <NovelBooklistBook>[];
  for (final raw in rawBooks) {
    if (raw is! Map) continue;
    final book = NovelBooklistBook.fromJson(Map<String, Object?>.from(raw));
    if (book.id.isEmpty || book.title.isEmpty) continue;
    result.add(book);
  }
  if (result.isEmpty) {
    throw const FormatException('书单里没有可导入的书籍（缺 id 或书名）');
  }
  return result;
}

String? _optional(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}

/// 文件选择/保存的窄接口（页面注入；生产走 file_picker，测试注入 fake）。
abstract interface class NovelBooklistFileGate {
  /// 让用户选一个书单文件；取消返回 null。
  Future<NovelPickedFile?> pick();

  /// 让用户选保存位置并写文件；取消/失败返回 null。
  Future<String?> save(String suggestedName, Uint8List bytes);
}

class NovelPickedFile {
  const NovelPickedFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// 生产实现：file_picker 13.x 的静态 API（没有 `FilePicker.platform`）。
class FilePickerBooklistFileGate implements NovelBooklistFileGate {
  const FilePickerBooklistFileGate();

  @override
  Future<NovelPickedFile?> pick() async {
    final file = await FilePicker.pickFile(
      dialogTitle: '选择书单文件',
      type: FileType.custom,
      allowedExtensions: const <String>['json', 'txt'],
    );
    if (file == null) return null;
    return NovelPickedFile(name: file.name, bytes: await file.readAsBytes());
  }

  @override
  Future<String?> save(String suggestedName, Uint8List bytes) async {
    final uri = await FilePicker.saveFile(
      dialogTitle: '导出书单',
      fileName: suggestedName,
      bytes: bytes,
      mimeType: 'application/json',
    );
    return uri?.toString();
  }
}
