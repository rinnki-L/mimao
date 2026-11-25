/// TXT / Markdown 目录规则与分章（流式，不整本进内存）。
///
/// 做法对齐 legado 的 `TextFile.getChapterList`：**按行扫描**，每行单独解码后
/// 用规则正则匹配，命中即视为章标题；章节边界记成**字节区间**，读某一章时
/// 只 seek 这一段。整本 20 MB 的 TXT 也只占用一个 256 KB 读缓冲。
///
/// 与上游的差别：
/// - 规则是「一行一条正则」的表（可编辑、可停用），不是硬编码一坨正则；
/// - 单行长度上限（[novelTxtTitleMaxLength]）用来挡住「正文里提到『第一章』」
///   造成的误切，上游同样有长度阈值；
/// - 第一个标题之前的内容若够多，单独成「前言」章，不丢正文。
library;

import 'dart:typed_data';

import 'local_encoding.dart';
import 'local_models.dart';
import 'local_source.dart';

/// 章标题行的最大长度（字符）。超过的多半是正文里的一句话，不是标题。
const int novelTxtTitleMaxLength = 40;

/// 一次扫描读多少字节。
const int novelScanChunk = 256 * 1024;

/// 一条 TXT 目录规则（纯值对象，与 drift 行解耦）。
class NovelTxtRule {
  const NovelTxtRule({
    required this.name,
    required this.pattern,
    this.enabled = true,
    this.builtin = false,
    this.sortOrder = 0,
    this.id = 0,
  });

  final int id;
  final String name;
  final String pattern;
  final bool enabled;
  final bool builtin;
  final int sortOrder;

  /// 编译后的正则；规则写坏时返回 null（导入页标红，不炸整次扫描）。
  RegExp? compile() {
    try {
      return RegExp(pattern);
    } on FormatException {
      return null;
    }
  }

  /// 是否是一条能用的规则（正则能编译）。
  bool get isValid => compile() != null;

  NovelTxtRule copyWith({
    String? name,
    String? pattern,
    bool? enabled,
    int? sortOrder,
  }) => NovelTxtRule(
    id: id,
    name: name ?? this.name,
    pattern: pattern ?? this.pattern,
    enabled: enabled ?? this.enabled,
    builtin: builtin,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'pattern': pattern,
    'enabled': enabled,
  };

  factory NovelTxtRule.fromJson(Map<String, Object?> json) => NovelTxtRule(
    name: '${json['name'] ?? ''}',
    pattern: '${json['pattern'] ?? ''}',
    enabled: json['enabled'] != false,
  );
}

/// 内置规则：与 legado 默认 `txtTocRule` 同一思路（中文数字 + 阿拉伯数字的
/// 「第 X 章/节/卷/回/话」、纯数字标题、「序章/楔子/尾声」这类特殊章节）。
///
/// 顺序即优先级：先宽后窄，命中即停。
const List<NovelTxtRule> novelDefaultTxtRules = <NovelTxtRule>[
  NovelTxtRule(
    name: '第 X 章（中/阿拉伯数字）',
    pattern:
        r'^\s*(?:正文\s*)?第\s*[0-9０-９一二三四五六七八九十百千万零〇两]+\s*[章节回话]\s*[^\s]{0,30}$',
    builtin: true,
    sortOrder: 0,
  ),
  NovelTxtRule(
    name: '第 X 卷 / 集 / 部',
    pattern: r'^\s*第\s*[0-9０-９一二三四五六七八九十百千万零〇两]+\s*[卷集部篇]\s*[^\s]{0,30}$',
    builtin: true,
    sortOrder: 1,
  ),
  NovelTxtRule(
    name: '第 X 章 · 副标题带冒号',
    pattern: r'^\s*第\s*[0-9０-９一二三四五六七八九十百千万零〇两]+\s*[章节][:：、\s].*$',
    builtin: true,
    sortOrder: 2,
  ),
  NovelTxtRule(
    name: '纯数字章号（1. / 001 标题）',
    pattern: r'^\s*[0-9]{1,5}[.、．]\s*\S.{0,30}$',
    builtin: true,
    sortOrder: 3,
  ),
  NovelTxtRule(
    name: '序章 / 楔子 / 尾声 / 番外',
    pattern: r'^\s*(?:序章|序言|楔子|引子|尾声|后记|终章|番外)[\s:：、].{0,30}$',
    builtin: true,
    sortOrder: 4,
  ),
  NovelTxtRule(
    name: 'Chapter N（英文章节）',
    pattern: r'^\s*Chapter\s+\d{1,5}\b.{0,30}$',
    builtin: true,
    sortOrder: 5,
  ),
];

/// 分章结果。
class NovelTxtSplitResult {
  const NovelTxtSplitResult({
    required this.chapters,
    required this.usedRule,
    this.warning,
  });

  final List<NovelLocalChapter> chapters;

  /// 实际命中的规则名（null = 没有任何规则命中）。
  final String? usedRule;

  final String? warning;
}

/// 流式分章。
///
/// [rules] 里只取启用的、能编译的；全部失效时退回整本一章并给警告。
/// [onProgress] 每读一块回调一次（0..1），导入页用它画进度条。
Future<NovelTxtSplitResult> splitNovelTxt({
  required NovelLocalBytes source,
  required NovelTextEncoding encoding,
  required List<NovelTxtRule> rules,
  void Function(double progress)? onProgress,
}) async {
  final total = await source.length();
  if (total == 0) {
    return const NovelTxtSplitResult(
      chapters: <NovelLocalChapter>[],
      usedRule: null,
      warning: '文件是空的，没有可导入的内容。',
    );
  }

  final active = _activeRules(rules);
  final headings = <_Heading>[];
  final matched = <String>{};

  await _scanLines(
    source: source,
    encoding: encoding,
    onLine: (start, line) {
      if (active.isEmpty) return;
      if (line.isEmpty || line.length > novelTxtTitleMaxLength) return;
      for (final (rule, regex) in active) {
        if (regex.hasMatch(line)) {
          headings.add(_Heading(start: start, title: line));
          matched.add(rule.name);
          return;
        }
      }
    },
    onProgress: onProgress,
  );

  if (headings.isEmpty) {
    return NovelTxtSplitResult(
      chapters: <NovelLocalChapter>[
        NovelLocalChapter(title: '全文', start: 0, end: total),
      ],
      usedRule: null,
      warning: active.isEmpty
          ? '没有可用的目录规则（全部停用或正则写错），已按整本一章导入。'
          : '没有匹配到任何章节标题，已按整本一章导入；可以在「TXT 目录规则」里调整后重新分章。',
    );
  }

  final chapters = <NovelLocalChapter>[];
  // 第一个标题之前的内容单独成「前言」，不丢正文（纯空白不生成）。
  final firstStart = headings.first.start;
  if (firstStart > 0) {
    final head = await source.read(0, firstStart);
    if (decodeNovelText(head, encoding, lossy: true).trim().isNotEmpty) {
      chapters.add(NovelLocalChapter(title: '前言', start: 0, end: firstStart));
    }
  }
  for (var i = 0; i < headings.length; i++) {
    final start = headings[i].start;
    final end = i + 1 < headings.length ? headings[i + 1].start : total;
    if (end <= start) continue;
    chapters.add(
      NovelLocalChapter(title: headings[i].title, start: start, end: end),
    );
  }

  return NovelTxtSplitResult(
    chapters: chapters,
    usedRule: matched.isEmpty ? null : matched.join(' · '),
  );
}

/// 用一批规则预演匹配结果（导入页「预览」用）：只返回命中的前若干行。
///
/// 与 [splitNovelTxt] 共用扫描逻辑，但只看前 [scanBytes] 字节与
/// [maxSamples] 个命中，避免预览把整本大书扫一遍。
Future<List<String>> previewNovelTxtMatches({
  required NovelLocalBytes source,
  required NovelTextEncoding encoding,
  required List<NovelTxtRule> rules,
  int maxSamples = 8,
  int scanBytes = 512 * 1024,
}) async {
  final active = _activeRules(rules);
  if (active.isEmpty) return const <String>[];
  final samples = <String>[];
  await _scanLines(
    source: source,
    encoding: encoding,
    maxBytes: scanBytes,
    onLine: (start, line) {
      if (samples.length >= maxSamples) return;
      if (line.isEmpty || line.length > novelTxtTitleMaxLength) return;
      if (active.any((entry) => entry.$2.hasMatch(line))) samples.add(line);
    },
    shouldStop: () => samples.length >= maxSamples,
  );
  return samples;
}

/// Markdown 分章：按最高一级标题切（`#` 最少的那种），标题文字去掉井号。
///
/// 没有标题时退回整本一章；只用到某一级标题时按那一级切——比「按行数硬切」
/// 更符合用户预期。标题行本身留在所属章的开头（阅读器按段落展示）。
Future<NovelTxtSplitResult> splitNovelMarkdown({
  required NovelLocalBytes source,
  required NovelTextEncoding encoding,
}) async {
  final total = await source.length();
  if (total == 0) {
    return const NovelTxtSplitResult(
      chapters: <NovelLocalChapter>[],
      usedRule: null,
      warning: '文件是空的，没有可导入的内容。',
    );
  }

  // 第一遍：量出最浅的标题层级。
  var shallowest = 0;
  await _scanLines(
    source: source,
    encoding: encoding,
    onLine: (start, line) {
      final level = _headingLevel(line);
      if (level > 0 && (shallowest == 0 || level < shallowest)) {
        shallowest = level;
      }
    },
  );
  if (shallowest == 0) {
    return NovelTxtSplitResult(
      chapters: <NovelLocalChapter>[
        NovelLocalChapter(title: '全文', start: 0, end: total),
      ],
      usedRule: null,
      warning: 'Markdown 里没有标题（`#` 开头的行），已按整本一章导入。',
    );
  }

  // 第二遍：按该层级切章。
  final headings = <_Heading>[];
  await _scanLines(
    source: source,
    encoding: encoding,
    onLine: (start, line) {
      if (_headingLevel(line) != shallowest) return;
      final title = line.replaceFirst(RegExp(r'^\s*#+\s*'), '').trim();
      headings.add(
        _Heading(start: start, title: title.isEmpty ? '未命名章节' : title),
      );
    },
  );

  final chapters = <NovelLocalChapter>[];
  for (var i = 0; i < headings.length; i++) {
    final start = headings[i].start;
    final end = i + 1 < headings.length ? headings[i + 1].start : total;
    if (end <= start) continue;
    chapters.add(
      NovelLocalChapter(title: headings[i].title, start: start, end: end),
    );
  }
  if (chapters.isEmpty) {
    return NovelTxtSplitResult(
      chapters: <NovelLocalChapter>[
        NovelLocalChapter(title: '全文', start: 0, end: total),
      ],
      usedRule: null,
      warning: '没能按标题分章，已按整本一章导入。',
    );
  }
  return NovelTxtSplitResult(
    chapters: chapters,
    usedRule: 'Markdown 标题（$shallowest 级）',
  );
}

/// 把一段字节按章区间解码成段落（阅读器正文）。
///
/// 空行分段、行内首尾空白剥掉；`\r\n` 与 `\r` 统一成 `\n` 再切。行首全角空格
/// （中文排版的段首缩进）保留原样——阅读器有自己的段首缩进样式。
List<String> paragraphsFromNovelText(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final paragraphs = <String>[];
  final buffer = StringBuffer();
  for (final line in normalized.split('\n')) {
    final trimmed = line.trimRight();
    if (trimmed.trim().isEmpty) {
      if (buffer.isNotEmpty) {
        paragraphs.add(buffer.toString());
        buffer.clear();
      }
      continue;
    }
    if (buffer.isNotEmpty) buffer.write('\n');
    buffer.write(trimmed);
  }
  if (buffer.isNotEmpty) paragraphs.add(buffer.toString());
  return paragraphs;
}

// ── 内部 ────────────────────────────────────────────────────────────────

class _Heading {
  const _Heading({required this.start, required this.title});

  final int start;
  final String title;
}

List<(NovelTxtRule, RegExp)> _activeRules(List<NovelTxtRule> rules) =>
    <(NovelTxtRule, RegExp)>[
      for (final rule in rules)
        if (rule.enabled)
          if (rule.compile() case final RegExp compiled) (rule, compiled),
    ];

/// 逐行扫描字节流：跨块的行拼起来，回调给「整行起点 + 解码后的行文本」。
///
/// [maxBytes] 限制扫描范围（预览用），[shouldStop] 让调用方提前收工。
Future<void> _scanLines({
  required NovelLocalBytes source,
  required NovelTextEncoding encoding,
  required void Function(int start, String line) onLine,
  int? maxBytes,
  bool Function()? shouldStop,
  void Function(double progress)? onProgress,
}) async {
  final total = await source.length();
  final limit = maxBytes == null || maxBytes > total ? total : maxBytes;
  if (limit <= 0) return;

  var scanned = 0;
  var pending = Uint8List(0);
  var pendingStart = 0;

  while (scanned < limit) {
    if (shouldStop?.call() ?? false) return;
    final want = limit - scanned;
    final chunk = await source.read(
      scanned,
      want < novelScanChunk ? want : novelScanChunk,
    );
    if (chunk.isEmpty) break;

    final buffer = Uint8List(pending.length + chunk.length)
      ..setRange(0, pending.length, pending)
      ..setRange(pending.length, pending.length + chunk.length, chunk);
    final base = pending.isEmpty ? scanned : pendingStart;

    var lineStart = 0;
    var index = 0;
    while (index < buffer.length) {
      final newlineLength = _newlineLengthAt(buffer, index, encoding);
      if (newlineLength == 0) {
        index++;
        continue;
      }
      final lineBytes = Uint8List.sublistView(buffer, lineStart, index);
      onLine(
        base + lineStart,
        decodeNovelText(lineBytes, encoding, lossy: true).trim(),
      );
      index += newlineLength;
      lineStart = index;
      if (shouldStop?.call() ?? false) return;
    }

    pending = Uint8List.fromList(Uint8List.sublistView(buffer, lineStart));
    pendingStart = base + lineStart;
    scanned += chunk.length;
    onProgress?.call((scanned / limit).clamp(0.0, 1.0));
    if (chunk.length < novelScanChunk) break;
  }

  // 末尾没有换行的最后一行。
  if (pending.isNotEmpty) {
    onLine(
      pendingStart,
      decodeNovelText(pending, encoding, lossy: true).trim(),
    );
  }
  onProgress?.call(1);
}

/// 当前位置是不是换行，是则返回换行占用的字节数（1 或 2）。
int _newlineLengthAt(Uint8List bytes, int index, NovelTextEncoding encoding) {
  if (encoding.isUtf16) {
    if (index + 1 >= bytes.length) return 0;
    final le = encoding == NovelTextEncoding.utf16le;
    final low = le ? bytes[index] : bytes[index + 1];
    final high = le ? bytes[index + 1] : bytes[index];
    return low == 0x0A && high == 0 ? 2 : 0;
  }
  return bytes[index] == 0x0A ? 1 : 0;
}

int _headingLevel(String line) {
  final match = RegExp(r'^\s{0,3}(#{1,6})\s+\S').firstMatch(line);
  return match == null ? 0 : match.group(1)!.length;
}
