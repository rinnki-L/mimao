/// 正文 / 简介的 HTML → 纯文本（legado `HtmlFormatter` 的最小等价实现）。
///
/// 书源正文规则通常返回 `<p>`/`<br>` 混排；阅读器只吃段落列表。这里保留块级
/// 分隔与换行，去掉 script/style/注释，图片先落成行内占位（后续阅读器可升级
/// 为图片块），并压缩多余空行。
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

const Set<String> _blockTags = <String>{
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
  'table',
};

/// 正文 HTML → 段落列表。
List<String> htmlToParagraphs(String html) {
  if (html.trim().isEmpty) return const <String>[];
  final fragment = html_parser.parseFragment(html);
  final buffer = StringBuffer();
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
    if (tag == 'script' || tag == 'style' || tag == 'noscript') return;
    if (tag == 'br') {
      buffer.write('\n');
      return;
    }
    if (tag == 'img') {
      final alt = node.attributes['alt']?.trim() ?? '';
      buffer.write(alt.isEmpty ? '[图片]' : '[$alt]');
      return;
    }
    final block = _blockTags.contains(tag);
    if (block) buffer.write('\n');
    for (final child in node.nodes) {
      walk(child);
    }
    if (block) buffer.write('\n');
  }

  for (final node in fragment.nodes) {
    walk(node);
  }
  return _normalizeLines(buffer.toString());
}

/// 简介等单块文本：保留换行，压缩空白。
String htmlToText(String html) {
  if (!html.contains('<')) {
    return html.replaceAll(RegExp(r'[ \t\f\v]+'), ' ').trim();
  }
  final paragraphs = htmlToParagraphs(html);
  return paragraphs.join('\n');
}

/// 章节标题 / 书名的轻量清洗（去掉 HTML、图标私用区码点与控制字符）。
String cleanTitle(String value) => htmlToText(value)
    // 图标字体常把私用区码点直接写进章节名（如 sfacg 的 icn 字符），
    // 阅读器显示成方框；控制字符也一并清掉。
    .replaceAll(RegExp(r'[\uE000-\uF8FF\u0000-\u001F\u007F]'), '')
    .replaceAll('\n', ' ')
    .trim();

List<String> _normalizeLines(String text) {
  final lines = text
      .replaceAll('\u00A0', ' ')
      .replaceAll('\u3000', ' ')
      .replaceAll(RegExp(r'[ \t\f\v]+'), ' ')
      .split('\n');
  final result = <String>[];
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (result.isNotEmpty && result.last == trimmed) continue;
    result.add(trimmed);
  }
  return result;
}
