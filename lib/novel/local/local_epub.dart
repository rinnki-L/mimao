/// EPUB 解析：container.xml → OPF → spine，保留章节顺序。
///
/// 只做阅读需要的三件事：
/// 1. 找到 OPF（`META-INF/container.xml` 的 `rootfile/@full-path`）；
/// 2. 读 OPF 的 `<metadata>`（书名/作者）与 `<manifest>`（id → href）；
/// 3. 按 `<spine>` 的 `itemref` 顺序产出章节（`idref` → manifest href）。
///
/// 与上游 `EpubFile.kt` 的差别：
/// - 不依赖 epub 专用解析库，用 `archive` + `html` 两个已有依赖；
/// - 图片**不提取**：正文里的 `<img>` 由 HTML→段落转换降级成 `[图片]` 占位
///   （阅读器目前没有图片块；提取图片属于后续能力，不在这里假装支持）；
/// - spine 里 `linear="no"` 的项仍然保留（legado 也保留，只是不主动跳过去），
///   顺序一律以 spine 为准，不按文件名排序。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:chinese_codec/chinese_codec.dart' as cc;
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import 'local_models.dart';
import 'local_source.dart';

/// EPUB 解析结果。
class NovelEpubBook {
  const NovelEpubBook({
    required this.title,
    required this.author,
    required this.chapters,
    this.warning,
  });

  final String title;
  final String author;
  final List<NovelLocalChapter> chapters;
  final String? warning;
}

/// EPUB 结构不合法（不是 zip / 缺 container.xml / OPF 读不出来）。
///
/// 与 [NovelLocalFileMissing] 区分：前者是「文件在但不是 EPUB」，后者是
/// 「文件不在」——导入页对两者的提示完全不同。
class NovelEpubFormatException implements Exception {
  const NovelEpubFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 解析 EPUB 的目录结构（不读正文）。
Future<NovelEpubBook> parseNovelEpub(NovelLocalBytes source) async {
  final bytes = await source.readAll();
  final archive = _decodeZip(bytes);
  final files = <String, ArchiveFile>{};
  for (final file in archive) {
    if (file.isFile) files[_normalize(file.name)] = file;
  }

  // 1) container.xml → OPF 路径。
  final container = files['META-INF/container.xml'];
  if (container == null) {
    throw const NovelEpubFormatException(
      'EPUB 缺少 META-INF/container.xml，不是完整的电子书文件。',
    );
  }
  final containerDoc = _parseXml(container, 'container.xml');
  final rootfile = containerDoc.querySelector('rootfile');
  final opfPath = _normalize(rootfile?.attributes['full-path'] ?? '');
  if (opfPath.isEmpty) {
    throw const NovelEpubFormatException(
      'EPUB 的 container.xml 里没有 rootfile 路径。',
    );
  }
  final opfFile = files[opfPath];
  if (opfFile == null) {
    throw NovelEpubFormatException('EPUB 里找不到 OPF 文件：$opfPath');
  }

  // 2) OPF：metadata + manifest + spine。
  final opfDoc = _parseXml(opfFile, opfPath);
  final opfDir = p.posix.dirname(opfPath);

  var title = _firstText(opfDoc, const <String>{'title'});
  final author = _firstText(opfDoc, const <String>{'creator'});

  final manifest = <String, String>{}; // id → 绝对（archive 内）路径
  // 用标签名而不是 `manifest > item`：OPF 里的 `<item .../>` 是自闭合的，
  // HTML 解析器会把它们当成嵌套（`<item><item/></item>`），组合选择器只命中
  // 第一个，spine 里的 idref 就全查不到了。按标签名 + id 属性取最稳。
  for (final item in opfDoc.querySelectorAll('item')) {
    final id = item.attributes['id'];
    final href = item.attributes['href'];
    if (id == null || href == null || href.isEmpty) continue;
    manifest[id] = _resolve(opfDir, href);
  }

  final spineItems = opfDoc.querySelectorAll('itemref');
  final chapters = <NovelLocalChapter>[];
  for (final itemref in spineItems) {
    final idref = itemref.attributes['idref'];
    if (idref == null) continue;
    final href = manifest[idref];
    if (href == null || href.isEmpty) continue;
    final file = files[href];
    if (file == null) continue;
    final label = _chapterLabel(file, href);
    chapters.add(NovelLocalChapter(title: label, href: href));
  }

  // spine 为空：退回「manifest 里所有 xhtml/html 按出现顺序」，比报错好。
  if (chapters.isEmpty) {
    for (final entry in manifest.entries) {
      if (!_isHtml(entry.value)) continue;
      final file = files[entry.value];
      if (file == null) continue;
      chapters.add(
        NovelLocalChapter(
          title: _chapterLabel(file, entry.value),
          href: entry.value,
        ),
      );
    }
  }
  if (chapters.isEmpty) {
    throw const NovelEpubFormatException('EPUB 的 spine 里没有可读的章节（可能只有封面/图片）。');
  }

  if (title.isEmpty) title = p.posix.basenameWithoutExtension(opfPath);
  return NovelEpubBook(
    title: title,
    author: author,
    chapters: chapters,
    warning: spineItems.isEmpty ? 'EPUB 没有 spine，已按 manifest 顺序取章节。' : null,
  );
}

/// 读 EPUB 里某一章的正文段落。
///
/// [href] 是 [NovelLocalChapter.href]；文件不存在时抛
/// [NovelLocalFileMissing]（书被改坏了，与「文件被移动」同类处理）。
Future<List<String>> readNovelEpubChapter(
  NovelLocalBytes source,
  String href,
) async {
  final bytes = await source.readAll();
  final archive = _decodeZip(bytes);
  final target = _normalize(href);
  ArchiveFile? found;
  for (final file in archive) {
    if (file.isFile && _normalize(file.name) == target) {
      found = file;
      break;
    }
  }
  if (found == null) {
    throw NovelLocalFileMissing(href, 'EPUB 里找不到这一章');
  }
  final html = _decodeXmlFile(found);
  return _htmlToParagraphs(html);
}

/// EPUB 章节标题：优先 `<title>`，其次第一个 `<h1>/<h2>/<h3>`，最后文件名。
String _chapterLabel(ArchiveFile file, String href) {
  try {
    final doc = html_parser.parse(_decodeXmlFile(file));
    final title = doc.querySelector('title')?.text.trim() ?? '';
    if (title.isNotEmpty && title.length <= novelEpubTitleMaxLength) {
      return title;
    }
    for (final tag in const <String>['h1', 'h2', 'h3']) {
      final heading = doc.querySelector(tag)?.text.trim() ?? '';
      if (heading.isNotEmpty && heading.length <= novelEpubTitleMaxLength) {
        return heading;
      }
    }
  } on Object {
    // 标题解析失败不该让整本导入失败，退回文件名。
  }
  return p.posix.basenameWithoutExtension(href);
}

/// 章节标题上限：过长的 `<title>` 多半是「书名 - 站点名」拼接，不适合当章名。
const int novelEpubTitleMaxLength = 60;

/// EPUB 内嵌 HTML → 段落。
///
/// 与 `engine/content_text.dart` 的 `htmlToParagraphs` 同思路，但这里额外：
/// - 去掉 `<head>`/`<style>`/`<script>` 与注释；
/// - `<img>` 降级成 `[图片]`（阅读器没有图片块，不假装能显示）；
/// - `<br>` 当软换行、块级标签当分段。
List<String> _htmlToParagraphs(String html) {
  final doc = html_parser.parse(html);
  final body = doc.body;
  if (body == null) return const <String>[];

  final paragraphs = <String>[];
  final buffer = StringBuffer();

  void flush() {
    final text = buffer.toString().trim();
    if (text.isNotEmpty) paragraphs.add(text);
    buffer.clear();
  }

  void walk(Node node) {
    if (node is Text) {
      buffer.write(node.data);
      return;
    }
    if (node is Comment) return;
    if (node is! Element) {
      for (final child in node.nodes) {
        walk(child);
      }
      return;
    }
    final tag = node.localName ?? '';
    if (const <String>{
      'script',
      'style',
      'head',
      'title',
      'meta',
      'link',
    }.contains(tag)) {
      return;
    }
    if (tag == 'br') {
      buffer.write('\n');
      return;
    }
    if (tag == 'img') {
      final alt = node.attributes['alt']?.trim() ?? '';
      buffer.write(alt.isEmpty ? '[图片]' : '[$alt]');
      return;
    }
    final block = const <String>{
      'p',
      'div',
      'section',
      'article',
      'header',
      'footer',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'li',
      'tr',
      'blockquote',
      'pre',
    }.contains(tag);
    if (block) flush();
    for (final child in node.nodes) {
      walk(child);
    }
    if (block) flush();
  }

  walk(body);
  flush();
  return paragraphs;
}

// ── 内部 ────────────────────────────────────────────────────────────────

/// 解 zip；任何失败都收敛成 [NovelEpubFormatException]（不让 zip 库的异常
/// 类型泄漏到界面）。空文件/非 zip 会在这里就被挡住。
Archive _decodeZip(Uint8List bytes) {
  if (bytes.isEmpty) {
    throw const NovelEpubFormatException('文件是空的，不是有效的 EPUB。');
  }
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    if (archive.isEmpty) {
      throw const NovelEpubFormatException('不是有效的 EPUB（zip 里没有任何文件）。');
    }
    return archive;
  } on NovelEpubFormatException {
    rethrow;
  } on Object catch (error) {
    throw NovelEpubFormatException('不是有效的 EPUB（zip 解不开）：$error');
  }
}

Document _parseXml(ArchiveFile file, String label) {
  final text = _decodeXmlFile(file);
  final doc = html_parser.parse(text);
  // `html` 包会把非 HTML 内容塞进 <html><body>，不会产出 parsererror 节点；
  // 这里只兜住「解析出空文档」这种明显坏掉的情况。
  if (doc.documentElement == null) {
    throw NovelEpubFormatException('EPUB 里的 $label 不是合法 XML。');
  }
  return doc;
}

/// 读 EPUB 内的 XML/HTML 文件并按声明解码。
///
/// EPUB 规范要求 UTF-8/UTF-16，但老工具产出的文件有 GBK：先看 BOM（最可靠），
/// 再看 XML 声明里的 `encoding="…"`，最后按 UTF-8 宽松解。
String _decodeXmlFile(ArchiveFile file) {
  final bytes = file.readBytes() ?? Uint8List(0);
  if (bytes.isEmpty) return '';

  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16(bytes.sublist(2), littleEndian: false);
  }

  final head = ascii
      .decode(
        bytes.sublist(0, bytes.length < 200 ? bytes.length : 200),
        allowInvalid: true,
      )
      .toLowerCase();
  final declared = RegExp(
    r'''encoding\s*=\s*["']([^"']+)["']''',
  ).firstMatch(head)?.group(1);
  if (declared != null) {
    final legacy = switch (declared) {
      'gbk' || 'gb2312' || 'cp936' => const cc.GbkCodec(allowInvalid: true),
      'gb18030' => const cc.Gb18030Codec(allowInvalid: true),
      'big5' || 'cp950' => const cc.Big5Codec(allowInvalid: true),
      _ => null,
    };
    if (legacy != null) return legacy.decode(bytes);
  }
  return utf8.decode(bytes, allowMalformed: true);
}

String _utf16(Uint8List bytes, {required bool littleEndian}) {
  final usable = bytes.length - (bytes.length % 2);
  final data = ByteData.sublistView(bytes, 0, usable);
  final units = Uint16List(usable ~/ 2);
  for (var i = 0; i < units.length; i++) {
    units[i] = data.getUint16(i * 2, littleEndian ? Endian.little : Endian.big);
  }
  return String.fromCharCodes(units);
}

/// 取第一个非空文本的元数据元素（按标签名比较，忽略命名空间前缀）。
///
/// 不能用 `querySelector('dc:title')`：`html` 包的选择器引擎把 `:` 当伪类，
/// 直接抛 UnimplementedError。OPF 的元数据标签在解析后 localName 就是
/// `dc:title`（带前缀原样保留），所以遍历元素按「去掉前缀的标签名」比较。
String _firstText(Document doc, Set<String> bareNames) {
  for (final element in doc.querySelectorAll('*')) {
    final local = (element.localName ?? '').toLowerCase();
    final bare = local.contains(':') ? local.split(':').last : local;
    if (!bareNames.contains(bare)) continue;
    final text = element.text.trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

/// archive 内路径统一成 posix 风格、去掉前导 `./`。
String _normalize(String path) {
  var value = path.replaceAll('\\', '/');
  while (value.startsWith('./')) {
    value = value.substring(2);
  }
  if (value.startsWith('/')) value = value.substring(1);
  return value;
}

/// OPF 里的 href 相对 OPF 所在目录解析，再归一化（处理 `../`）。
String _resolve(String opfDir, String href) {
  final decoded = Uri.decodeComponent(href.split('#').first);
  if (opfDir.isEmpty || opfDir == '.') return _normalize(decoded);
  return _normalize(p.posix.normalize(p.posix.join(opfDir, decoded)));
}

bool _isHtml(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.xhtml') ||
      lower.endsWith('.html') ||
      lower.endsWith('.htm');
}
