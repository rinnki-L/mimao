// ignore_for_file: deprecated_member_use — Flutter 3.47+ 弃用 material.dart，
// 与 main.dart/上游镜像同款纪律：M1 继续用，保类型一致。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/shell/dev/dev_tap.dart';

void main() {
  /// fake-async 下 dispatchTap 的 50ms gap 要靠 pump 推进时钟。
  Future<Map<String, Object?>> pumpTap(
    WidgetTester tester,
    TapSelector selector, {
    required Element root,
  }) {
    final future = performTap(selector, root: root);
    return tester.pump(const Duration(milliseconds: 60)).then((_) => future);
  }

  Future<Element> pumpScaffold(WidgetTester tester, Widget body) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: body)),
      ),
    );
    await tester.pump();
    return tester.binding.rootElement!;
  }

  testWidgets('按 text 命中并真实触发 onTap（走 handlePointerEvent 通路）', (tester) async {
    var tapped = 0;
    final root = await pumpScaffold(
      tester,
      TextButton(onPressed: () => tapped++, child: const Text('点我')),
    );

    final result = await pumpTap(
      tester,
      const TapSelector(text: '点我'),
      root: root,
    );

    expect(result['ok'], true);
    expect(result['tapped'], contains('Text'));
    expect(tapped, 1, reason: 'down→up 注入应触发真实 tap 手势');
  });

  testWidgets('按 key 命中（toString 包含语义）', (tester) async {
    var tappedA = 0;
    var tappedB = 0;
    final root = await pumpScaffold(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            key: const ValueKey<String>('dev-btn-a'),
            onPressed: () => tappedA++,
            child: const Text('A'),
          ),
          TextButton(onPressed: () => tappedB++, child: const Text('B')),
        ],
      ),
    );

    final result = await pumpTap(
      tester,
      const TapSelector(key: 'dev-btn-a'),
      root: root,
    );

    expect(result['ok'], true);
    expect(tappedA, 1);
    expect(tappedB, 0);
  });

  testWidgets('dryRun 只报候选不注入', (tester) async {
    var tapped = 0;
    final root = await pumpScaffold(
      tester,
      TextButton(onPressed: () => tapped++, child: const Text('探查目标')),
    );

    final result = await pumpTap(
      tester,
      const TapSelector(text: '探查目标', dryRun: true),
      root: root,
    );

    expect(result['ok'], true);
    expect(result['dryRun'], true);
    expect(result['count'], 1);
    expect(
      ((result['candidates']! as List<Object?>).single
          as Map<String, Object?>)['center'],
      isNotNull,
    );
    expect(tapped, 0);
    await tester.pump(const Duration(milliseconds: 60));
  });

  testWidgets('多个命中按 index 选择；越界报候选数', (tester) async {
    var aTaps = 0;
    var bTaps = 0;
    final root = await pumpScaffold(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(onPressed: () => aTaps++, child: const Text('同名')),
          TextButton(onPressed: () => bTaps++, child: const Text('同名')),
        ],
      ),
    );

    final second = await pumpTap(
      tester,
      const TapSelector(text: '同名', index: 1),
      root: root,
    );
    expect(second['count'], 2);
    expect(bTaps, 1);
    expect(aTaps, 0);

    final overflow = await performTap(
      const TapSelector(text: '同名', index: 5),
      root: root,
    );
    expect(overflow['ok'], false);
    expect(overflow['error'], contains('越界'));
    expect(overflow['count'], 2);
  });

  testWidgets('Offstage 子树不参与解析', (tester) async {
    var tapped = 0;
    final root = await pumpScaffold(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Offstage(offstage: true, child: Text('隐藏目标')),
          TextButton(onPressed: () => tapped++, child: const Text('可见目标')),
        ],
      ),
    );

    final result = await pumpTap(
      tester,
      const TapSelector(text: '隐藏目标'),
      root: root,
    );
    expect(result['ok'], false);
    expect(result['count'], 0, reason: 'offstage 目标不可见也不可点');

    final visible = await pumpTap(
      tester,
      const TapSelector(text: '可见目标'),
      root: root,
    );
    expect(visible['ok'], true);
    expect(tapped, 1);
  });

  test('空选择器直接拒绝', () async {
    final result = await performTap(const TapSelector());
    expect(result['ok'], false);
    expect(result['error'], contains('key 或 text'));
  });
}
