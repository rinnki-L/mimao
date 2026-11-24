// 避头尾断行：句读不出现在行首、前引号不出现在行尾，且只移动边界不丢字。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/reader/novel_line_break.dart';

void main() {
  test('句读不出现在行首：断点前移一位', () {
    const text = '甲乙丙丁。戊己庚辛';
    final starts = applyKinsokuBreaks(text, <int>[0, 4, 8]);
    expect(starts[0], 0);
    expect(starts[1], 3);
    for (var i = 1; i < starts.length; i++) {
      expect(canStartLineAt(text, starts[i]), isTrue);
    }
  });

  test('前引号不出现在行尾：断点后移一位', () {
    const text = '甲「乙丙丁';
    final starts = applyKinsokuBreaks(text, <int>[0, 2]);
    expect(starts[1], 3);
    expect(canEndLineBefore(text, starts[1]), isTrue);
  });

  test('连续句读尽量一起带到上一行，且不越界', () {
    const text = '一二三四五。，！六七八九十';
    final starts = applyKinsokuBreaks(text, <int>[0, 5, 8, text.length]);
    expect(starts.first, 0);
    expect(starts.last, text.length);
    for (var i = 1; i < starts.length; i++) {
      expect(starts[i], greaterThanOrEqualTo(starts[i - 1]));
      expect(starts[i], lessThanOrEqualTo(text.length));
    }
    // 行首尽量不是句读（受最多回退 4 字限制，这里 1 个断点完全够）。
    expect(canStartLineAt(text, starts[1]), isTrue);
  });

  test('空行/单行/异常输入原样返回', () {
    expect(applyKinsokuBreaks('', <int>[0]), <int>[0]);
    const text = '只有一行';
    expect(applyKinsokuBreaks(text, <int>[0]), <int>[0]);
  });

  test('规则集合方向正确', () {
    expect(novelNoLineStart.contains('。'), isTrue);
    expect(novelNoLineStart.contains('，'), isTrue);
    expect(novelNoLineStart.contains('（'), isFalse);
    expect(novelNoLineEnd.contains('（'), isTrue);
    expect(novelNoLineEnd.contains('。'), isFalse);
  });
}
