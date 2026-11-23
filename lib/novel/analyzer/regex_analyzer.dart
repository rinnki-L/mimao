/// legado `AnalyzeByRegex` 的 Dart 重译：用于 `getElement/getElements` 的
/// 正则模式（`:` 开头 + `&&` 串），返回匹配的捕获组数组。
library;

class RegexAnalyzer {
  /// 单个匹配的捕获组列表（组 0 是整段）。
  static List<String>? getElement(String content, List<String> patterns) {
    if (patterns.isEmpty) return null;
    final regex = _compile(patterns.first);
    if (regex == null) return null;
    final match = regex.firstMatch(content);
    if (match == null) return null;
    return <String>[
      for (var i = 0; i <= match.groupCount; i++) match.group(i) ?? '',
    ];
  }

  /// 每个匹配一组捕获组。
  static List<List<String>> getElements(String content, List<String> patterns) {
    if (patterns.isEmpty) return const <List<String>>[];
    final regex = _compile(patterns.first);
    if (regex == null) return const <List<String>>[];
    return <List<String>>[
      for (final match in regex.allMatches(content))
        <String>[
          for (var i = 0; i <= match.groupCount; i++) match.group(i) ?? '',
        ],
    ];
  }

  static RegExp? _compile(String pattern) {
    try {
      return RegExp(pattern, multiLine: true);
    } on Object {
      return null;
    }
  }
}
