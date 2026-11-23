/// legado 规则字符串的通用切分器（`RuleAnalyzer.kt` 的 Dart 重译）。
///
/// 书源规则里 `&&` / `||` / `%%` / `@` / `{{}}` 都可能出现在选择器、CSS
/// 属性值或 JS 字符串里；直接 `split` 会把 `a[href^="x@y"]` 切坏。这里按
/// legado 的语义只在「顶层」切：跳过方括号 / 圆括号平衡组与单双引号，
/// 保证 `li > a[title="A&&B"]` 仍是一段规则。
///
/// 只做字符串处理，不解析选择器、不执行 JS；可在纯 Dart 单测里直接验证。
library;

/// 通用规则切分器。
class RuleSplitter {
  RuleSplitter(this.source, {this.code = false});

  /// 待切分文本。
  final String source;

  /// JSON / JS 片段使用代码平衡（`{` `}` 也计入嵌套），否则只认 `[` `(`。
  final bool code;

  /// 最近一次 [splitRule] 使用的分隔符（对齐 Kotlin 的 `elementsType`）。
  String elementsType = '';

  /// 按顶层分隔符切分；多个候选分隔符时，只按文本里**最先出现**的那个切。
  ///
  /// 返回值保留空段（调用方自行 trim/过滤），与 Kotlin 版的 `splitRule` 对齐。
  List<String> splitRule(List<String> separators) {
    elementsType = '';
    if (separators.isEmpty) return <String>[source];
    if (source.isEmpty) return <String>[source];

    final first = _findFirstSeparator(separators);
    if (first == null) return <String>[source];

    final sep = separators[first.$1];
    elementsType = sep;
    final parts = <String>[];
    var start = 0;
    var index = 0;
    while (index < source.length) {
      final hit = _matchSeparatorAt(index, sep);
      if (hit) {
        parts.add(source.substring(start, index));
        index += sep.length;
        start = index;
        continue;
      }
      index = _skipUnit(index);
    }
    parts.add(source.substring(start));
    return parts;
  }

  /// 把 `{{expr}}`（或任意成对标记）替换成 [onInner] 的返回值。
  ///
  /// [onInner] 返回 null 时保留原文（Kotlin `innerRule` 的语义）；返回空串
  /// 则真正删除该段。未匹配到任何标记时返回原文。
  String innerRule(
    String open,
    String close,
    String? Function(String inner) onInner,
  ) {
    if (source.isEmpty) return source;
    final out = StringBuffer();
    var copied = 0;
    var index = 0;
    var replaced = false;
    while (index < source.length) {
      if (source.startsWith(open, index)) {
        final end = _balancedEnd(index + open.length, open, close);
        if (end != null) {
          final inner = source.substring(index + open.length, end);
          final value = onInner(inner);
          if (value != null) {
            out
              ..write(source.substring(copied, index))
              ..write(value);
            copied = end + close.length;
            replaced = true;
          }
          index = end + close.length;
          continue;
        }
      }
      index = _skipUnit(index);
    }
    if (!replaced) return source;
    out.write(source.substring(copied));
    return out.toString();
  }

  /// 找到从 [from] 开始、与 [open]/[close] 平衡的结束位置（不含结束标记）。
  int? _balancedEnd(int from, String open, String close) {
    var depth = 1;
    var index = from;
    while (index < source.length) {
      if (source.startsWith(close, index)) {
        depth--;
        if (depth == 0) return index;
        index += close.length;
        continue;
      }
      if (source.startsWith(open, index)) {
        depth++;
        index += open.length;
        continue;
      }
      final char = source.codeUnitAt(index);
      if (_isSingleQuote(char)) {
        index = _skipQuoted(index, _isSingleQuote);
      } else if (_isDoubleQuote(char)) {
        index = _skipQuoted(index, _isDoubleQuote);
      } else if (char == 0x5C) {
        index += 2;
      } else {
        index++;
      }
    }
    return null;
  }

  /// 返回 `(分隔符下标, 候选下标)`；没有顶层分隔符返回 null。
  (int, int)? _findFirstSeparator(List<String> separators) {
    var index = 0;
    while (index < source.length) {
      for (var i = 0; i < separators.length; i++) {
        if (_matchSeparatorAt(index, separators[i])) {
          return (i, index);
        }
      }
      index = _skipUnit(index);
    }
    return null;
  }

  bool _matchSeparatorAt(int index, String sep) =>
      source.startsWith(sep, index);

  /// 跳过当前「语法单元」：引号内整体跳过，括号平衡组整体跳过，其余前进一个字符。
  ///
  /// 返回下一个待检查的下标，始终 > [index]（不会死循环）。
  int _skipUnit(int index) {
    if (index >= source.length) return source.length;
    final char = source.codeUnitAt(index);
    if (_isSingleQuote(char)) {
      return _skipQuoted(index, _isSingleQuote);
    }
    if (_isDoubleQuote(char)) {
      return _skipQuoted(index, _isDoubleQuote);
    }
    if (char == 0x5C /* \ */ ) {
      return index + 2 <= source.length ? index + 2 : source.length;
    }
    if (char == 0x5B /* [ */ || (code && char == 0x7B /* { */ )) {
      return _skipBalanced(index, char == 0x5B ? 0x5D : 0x7D);
    }
    if (char == 0x28 /* ( */ ) {
      return _skipBalanced(index, 0x29);
    }
    return index + 1;
  }

  int _skipQuoted(int index, bool Function(int) quote) {
    var cursor = index + 1;
    while (cursor < source.length) {
      if (quote(source.codeUnitAt(cursor))) return cursor + 1;
      cursor++;
    }
    return source.length;
  }

  int _skipBalanced(int index, int close) {
    var depth = 0;
    var cursor = index;
    while (cursor < source.length) {
      final char = source.codeUnitAt(cursor);
      if (_isSingleQuote(char)) {
        cursor = _skipQuoted(cursor, _isSingleQuote);
        continue;
      }
      if (_isDoubleQuote(char)) {
        cursor = _skipQuoted(cursor, _isDoubleQuote);
        continue;
      }
      if (char == 0x5C) {
        cursor += 2;
        continue;
      }
      if (char == source.codeUnitAt(index)) depth++;
      if (char == close) {
        depth--;
        if (depth == 0) return cursor + 1;
      }
      cursor++;
    }
    return source.length;
  }

  static bool _isSingleQuote(int char) => char == 0x27;

  static bool _isDoubleQuote(int char) => char == 0x22;
}
