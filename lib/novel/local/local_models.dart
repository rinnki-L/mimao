/// 本地书的纯领域模型：格式、编码、目录项与探测结果。
///
/// 本文件不含 IO、不含 drift、不碰 Flutter——TXT 分章、Markdown 分章、EPUB
/// 解析、编码嗅探都只在这里进出，测试可以直接构造内存数据验证。
///
/// 目录项用**字节区间**（[NovelLocalChapter.start]/[NovelLocalChapter.end]）
/// 而不是字符偏移：读某一章时只 seek 这一段、只解码这一段，几 MB 的 TXT 不必
/// 整本进内存；EPUB 的章节用 spine 里的 [NovelLocalChapter.href] 定位。
library;

import 'dart:convert';

/// 本地书格式。
enum NovelLocalFormat {
  txt('txt', 'TXT'),
  epub('epub', 'EPUB'),
  markdown('md', 'Markdown');

  const NovelLocalFormat(this.key, this.label);

  /// 落库值（[NovelLocalBook.format]）与文件扩展名判断都用它。
  final String key;

  /// 界面展示名。
  final String label;

  /// 由文件名/扩展名判格式；不认识的扩展名返回 null（导入页据此拒绝）。
  static NovelLocalFormat? fromPath(String path) {
    final name = path.toLowerCase();
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1);
    return switch (ext) {
      'txt' => NovelLocalFormat.txt,
      'epub' => NovelLocalFormat.epub,
      'md' || 'markdown' => NovelLocalFormat.markdown,
      _ => null,
    };
  }

  static NovelLocalFormat? fromKey(String key) {
    for (final value in NovelLocalFormat.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// 嗅探出的文本编码。
///
/// [gbk] 与 [gb18030] 的映射表在常见字上一致，但 GB18030 多出四字节序列与
/// 生僻字：嗅探时优先 GB18030（超集），展示时仍按具体判定结果标注，避免把
/// 「用 GBK 存的简体」误标成 GB18030 之外的第三种编码。
enum NovelTextEncoding {
  utf8('utf-8', 'UTF-8'),
  utf16le('utf-16le', 'UTF-16 LE'),
  utf16be('utf-16be', 'UTF-16 BE'),
  gbk('gbk', 'GBK'),
  gb18030('gb18030', 'GB18030'),
  big5('big5', 'Big5');

  const NovelTextEncoding(this.key, this.label);

  final String key;
  final String label;

  /// UTF-16 两种按 2 字节对齐找换行（0x0A 单字节扫会撞上汉字的高/低位字节）。
  bool get isUtf16 =>
      this == NovelTextEncoding.utf16le || this == NovelTextEncoding.utf16be;

  static NovelTextEncoding? fromKey(String? key) {
    if (key == null || key.isEmpty) return null;
    for (final value in NovelTextEncoding.values) {
      if (value.key == key) return value;
    }
    return null;
  }
}

/// 目录里的一章。
///
/// TXT / Markdown 用 [start]（含）与 [end]（不含）的**字节**区间；EPUB 用
/// [href]（相对 opf 的路径）定位。两种定位方式同时存在时以 [href] 优先，
/// 导入页展示的「第 N 章」序号由列表下标决定，不进模型。
class NovelLocalChapter {
  const NovelLocalChapter({
    required this.title,
    this.start = 0,
    this.end = 0,
    this.href = '',
  });

  final String title;
  final int start;
  final int end;
  final String href;

  int get byteLength => end > start ? end - start : 0;

  bool get isEmptyRange => href.isEmpty && byteLength <= 0;

  Map<String, Object?> toJson() => <String, Object?>{
    't': title,
    if (href.isNotEmpty)
      'h': href
    else ...<String, Object?>{'s': start, 'e': end},
  };

  factory NovelLocalChapter.fromJson(Map<String, Object?> json) =>
      NovelLocalChapter(
        title: '${json['t'] ?? ''}',
        start: _int(json['s']),
        end: _int(json['e']),
        href: '${json['h'] ?? ''}',
      );

  @override
  String toString() => 'NovelLocalChapter($title, $start..$end, $href)';
}

/// 目录解析结果：[chapters] 为章节列表，[warning] 是「结果可能不理想」的可读
/// 说明（例如一条都没匹配上、退回整本一章），导入页原样展示给用户。
class NovelLocalToc {
  const NovelLocalToc({required this.chapters, this.warning});

  static const NovelLocalToc empty = NovelLocalToc(
    chapters: <NovelLocalChapter>[],
  );

  final List<NovelLocalChapter> chapters;
  final String? warning;

  bool get isEmpty => chapters.isEmpty;

  String encode() =>
      jsonEncode(<Object?>[for (final chapter in chapters) chapter.toJson()]);

  /// 解析落库的目录 JSON；坏数据退回空目录而不是抛（书还在，重扫即可）。
  static List<NovelLocalChapter> decode(String raw) {
    if (raw.isEmpty) return const <NovelLocalChapter>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <NovelLocalChapter>[];
      return <NovelLocalChapter>[
        for (final item in decoded)
          if (item is Map)
            NovelLocalChapter.fromJson(Map<String, Object?>.from(item)),
      ];
    } on Object {
      return const <NovelLocalChapter>[];
    }
  }
}

/// 导入前的探测结果：格式、编码、大小、目录与可读警告。
class NovelLocalProbe {
  const NovelLocalProbe({
    required this.format,
    required this.title,
    required this.byteSize,
    required this.toc,
    this.encoding,
    this.lossy = false,
    this.author = '',
    this.warning,
  });

  final NovelLocalFormat format;
  final String title;
  final String author;
  final int byteSize;
  final NovelLocalToc toc;

  /// 文本编码；EPUB 为 null（XML 自己带 encoding 声明，按字节直读）。
  final NovelTextEncoding? encoding;

  /// 解码时出现过替换字符（编码判定失败或文件本身有坏字节）。
  final bool lossy;

  /// 汇总警告（编码回退、目录为空等），导入页原样展示。
  final String? warning;

  bool get hasChapters => !toc.isEmpty;
}

/// 本地书的持久化快照（[NovelLocalBookRow] 的纯领域副本）。
class NovelLocalBook {
  const NovelLocalBook({
    required this.id,
    required this.path,
    required this.title,
    required this.format,
    required this.byteSize,
    required this.chapterCount,
    required this.chapters,
    required this.addedAt,
    this.author = '',
    this.encoding,
  });

  final String id;
  final String path;
  final String title;
  final String author;
  final NovelLocalFormat format;
  final NovelTextEncoding? encoding;
  final int byteSize;
  final int chapterCount;
  final List<NovelLocalChapter> chapters;
  final DateTime addedAt;

  /// 书源主键口径与在线书一致：本地书全部挂在同一个虚拟源下，
  /// 引擎按 id 找书，不按源分叉。
  String get sourceName => novelLocalSourceName;
}

/// 本地虚拟书源的展示名与主键。
///
/// 主键不用 base64url（不像在线源那样由 URL 派生），因为它是固定的内部源：
/// 换机器、换路径都不该变，否则书架里同一本书会被当成两条记录。
const String novelLocalSourceName = 'local';
const String novelLocalSourceKey = 'mimao-local-file';
const String novelLocalSourceUrl = 'mimao://local';

/// 本地书 id 前缀：`local:<路径指纹>`。前缀让书架/历史一眼能认出是本地书，
/// 也让投影层不必额外查库就能区分来源。
const String novelLocalBookIdPrefix = 'local:';

/// 是否本地书 id。
bool isNovelLocalBookId(String id) => id.startsWith(novelLocalBookIdPrefix);

/// 本地书在书架/详情里展示的来源标记。
const String novelLocalSourceLabel = '本地文件';

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}
