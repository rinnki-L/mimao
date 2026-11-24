// 墨水屏整页刷新：间隔计数与闪屏时序。

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/comic/reader/reader_eink_refresh.dart';

void main() {
  test('每 N 页闪一次，间隔变更后重新计数', () {
    final controller = EInkRefreshController();
    bool tick() => controller.onPageChanged(
      interval: 2,
      durationMilliseconds: 200,
      style: EInkRefreshStyle.black,
    );

    expect(tick(), isTrue, reason: '第 1 页（计数 0）触发');
    expect(tick(), isFalse);
    expect(tick(), isTrue, reason: '第 3 页触发');
    expect(controller.request!.id, 2);

    expect(
      controller.onPageChanged(
        interval: 3,
        durationMilliseconds: 200,
        style: EInkRefreshStyle.black,
      ),
      isTrue,
      reason: '间隔变化后从 0 重新计数',
    );
  });

  test('间隔与时长被钳制', () {
    final controller = EInkRefreshController();
    controller.onPageChanged(
      interval: 99,
      durationMilliseconds: 99999,
      style: EInkRefreshStyle.white,
    );
    expect(controller.request!.durationMilliseconds, 1500);

    controller.onPageChanged(
      interval: 0,
      durationMilliseconds: 1,
      style: EInkRefreshStyle.white,
    );
    expect(controller.request!.durationMilliseconds, 100);
  });

  test('reset 清空计数', () {
    final controller = EInkRefreshController();
    controller.onPageChanged(
      interval: 2,
      durationMilliseconds: 100,
      style: EInkRefreshStyle.black,
    );
    controller.reset();
    expect(
      controller.onPageChanged(
        interval: 2,
        durationMilliseconds: 100,
        style: EInkRefreshStyle.black,
      ),
      isTrue,
    );
  });

  test('样式 key 往返', () {
    for (final style in EInkRefreshStyle.values) {
      expect(EInkRefreshStyle.fromKey(style.key), style);
    }
    expect(EInkRefreshStyle.fromKey('bogus'), EInkRefreshStyle.black);
    expect(EInkRefreshStyle.fromKey(null), EInkRefreshStyle.black);
  });

  testWidgets('闪屏覆盖层：请求后短暂覆盖再清空', (tester) async {
    final controller = EInkRefreshController();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: <Widget>[EInkRefreshOverlay(controller: controller)],
        ),
      ),
    );

    controller.onPageChanged(
      interval: 1,
      durationMilliseconds: 200,
      style: EInkRefreshStyle.black,
    );
    await tester.pump();
    expect(find.byType(ColoredBox), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(ColoredBox), findsNothing);
  });
}
