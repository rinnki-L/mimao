/// legado `AnalyzeByRegex` 的 Dart 重译：用于 `getElement/getElements` 的
/// 正则模式（`:` 开头 + `&&` 串），返回匹配的捕获组数组。
library;

class RegexAnalyzer {
  /// 单个匹配的捕获组列表（组 0 是整段）。
  ///
  /// 对齐 Kotlin `AnalyzeByRegex.getElement` 的多段 `&&` 递归：非末段把当前
  /// 规则**所有匹配的整段**拼起来喂给下一段；只有末段才收集捕获组。
  static List<String>? getElement(
    String content,
    List<String> patterns, {
    int index = 0,
  }) {
    if (patterns.isEmpty || index >= patterns.length) return null;
    final regex = _compile(patterns[index]);
    if (regex == null) return null;
    final firstMatch = regex.firstMatch(content);
    if (firstMatch == null) return null;
    if (index + 1 == patterns.length) {
      return <String>[
        for (var i = 0; i <= firstMatch.groupCount; i++)
          firstMatch.group(i) ?? '',
      ];
    }
    final buffer = StringBuffer();
    for (final match in regex.allMatches(content)) {
      buffer.write(match.group(0) ?? '');
    }
    return getElement(buffer.toString(), patterns, index: index + 1);
  }

  /// 每个匹配一组捕获组（多段规则同样逐段递归）。
  static List<List<String>> getElements(
    String content,
    List<String> patterns, {
    int index = 0,
  }) {
    if (patterns.isEmpty || index >= patterns.length) {
      return const <List<String>>[];
    }
    final regex = _compile(patterns[index]);
    if (regex == null) return const <List<String>>[];
    final matches = regex.allMatches(content).toList();
    if (matches.isEmpty) return const <List<String>>[];
    if (index + 1 == patterns.length) {
      return <List<String>>[
        for (final match in matches)
          <String>[
            for (var i = 0; i <= match.groupCount; i++) match.group(i) ?? '',
          ],
      ];
    }
    final buffer = StringBuffer();
    for (final match in matches) {
      buffer.write(match.group(0) ?? '');
    }
    return getElements(buffer.toString(), patterns, index: index + 1);
  }

  static RegExp? _compile(String pattern) {
    try {
      return RegExp(pattern, multiLine: true);
    } on Object {
      return null;
    }
  }
}
