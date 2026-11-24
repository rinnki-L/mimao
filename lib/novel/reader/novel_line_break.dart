// 避头尾（kinsoku）断行：把 TextPainter 给出的行首下标重排成中文排版可接受的断点。
//
// 纯函数，不依赖 TextPainter / Widget 树，单测直接喂字符串与行首下标。
// 规则只有两条（与 legado 的 ChineseLineBreaker 同向）：
// - 句读、后引号、后括号不能出现在行首 → 断点前移一位，把上一个字带下来；
// - 前引号、前括号不能出现在行尾 → 断点后移一位，把它推到下一行。
//
// 这里只调整「行边界」，不改字符内容，所以切片首尾仍严格相接，不会丢字。

/// 不能出现在行首的字符（句读 + 收尾括号/引号）。
const Set<String> novelNoLineStart = <String>{
  '。',
  '，',
  '、',
  '；',
  '：',
  '？',
  '！',
  '…',
  '—',
  '·',
  '٫',
  '）',
  '】',
  '》',
  '」',
  '』',
  '〉',
  '〕',
  '］',
  '｝',
  '”',
  '’',
  '％',
  '‰',
  '℃',
  ',',
  '.',
  ';',
  ':',
  '?',
  '!',
  ')',
  ']',
  '}',
  '%',
};

/// 不能出现在行尾的字符（起首括号/引号）。
const Set<String> novelNoLineEnd = <String>{
  '（',
  '【',
  '《',
  '「',
  '『',
  '〈',
  '〔',
  '［',
  '｛',
  '“',
  '‘',
  '(',
  '[',
  '{',
};

/// 把 [lineStarts] 修正为避头尾之后的断点。
///
/// 输入约定：[lineStarts] 单调不减、首个元素为 0；返回同长度列表，仍单调，
/// 且只改变内部断点（不新增/删除行）。越界或异常输入原样返回。
List<int> applyKinsokuBreaks(
  String text,
  List<int> lineStarts, {
  Set<String> noStart = novelNoLineStart,
  Set<String> noEnd = novelNoLineEnd,
}) {
  if (lineStarts.length <= 1 || text.isEmpty) {
    return List<int>.from(lineStarts);
  }
  final result = List<int>.from(lineStarts);
  result[0] = result[0].clamp(0, text.length);

  for (var i = 1; i < result.length; i++) {
    var start = result[i].clamp(result[i - 1], text.length);
    final lower = result[i - 1];

    // 行首是句读/收尾符号：把断点往前挪，让它跟上一个字一起留在上一行。
    var guard = 0;
    while (start > lower + 1 &&
        guard < 4 &&
        _isNoStart(_charBefore(text, start + 1))) {
      start -= 1;
      guard += 1;
    }

    // 行尾是起首符号：把断点往后挪，把它带到下一行。
    guard = 0;
    while (start < text.length &&
        start - 1 >= lower &&
        guard < 4 &&
        _isNoEnd(_charBefore(text, start))) {
      start += 1;
      guard += 1;
    }

    result[i] = start.clamp(lower, text.length);
  }

  // 修正过程中可能把某行推到下一行之后，向回压平（只压边界，不动内容）。
  for (var i = result.length - 2; i >= 1; i--) {
    if (result[i] > result[i + 1]) result[i] = result[i + 1];
  }
  return result;
}

/// [position] 处的字符是否允许作为行首。
///
/// [position] 是「行在原文里的起始下标」，即该行的第一个字符。
bool canStartLineAt(String text, int position) {
  if (position <= 0 || position >= text.length) return true;
  return !_isNoStart(text[position]);
}

/// [position] 是断点（下一行起始），上一行最后一个字符是否允许收行。
bool canEndLineBefore(String text, int position) {
  if (position <= 0 || position > text.length) return true;
  return !_isNoEnd(text[position - 1]);
}

String _charBefore(String text, int position) {
  final index = position - 1;
  if (index < 0 || index >= text.length) return '';
  return text[index];
}

bool _isNoStart(String char) => novelNoLineStart.contains(char);

bool _isNoEnd(String char) => novelNoLineEnd.contains(char);
