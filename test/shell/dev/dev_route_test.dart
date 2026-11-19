import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/shell/dev/dev_route.dart';

void main() {
  setUp(devRouteTracker.reset);
  tearDown(devRouteTracker.reset);

  /// 匿名路由用 PageRouteBuilder（与生产 MaterialPageRoute 同属
  /// TransitionRoute 家族，runtimeType 断言用基类名判形）。
  Route<Object?> namedRoute(String name) => PageRouteBuilder<void>(
    settings: RouteSettings(name: name),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
  );

  Route<Object?> anonymousRoute() => PageRouteBuilder<void>(
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
  );

  test('didPush/didPop 维护栈深与快照', () {
    devRouteTracker.didPush(namedRoute('home'), null);
    devRouteTracker.didPush(namedRoute('comic/detail'), namedRoute('home'));

    expect(devRouteTracker.depth, 2);
    final stack = devRouteTracker.snapshot();
    expect(stack[0]['index'], 0);
    expect(stack[0]['name'], 'home');
    expect(stack[1]['name'], 'comic/detail');
    expect(stack[1]['type'], contains('PageRouteBuilder'));

    devRouteTracker.didPop(namedRoute('comic/detail'), namedRoute('home'));
    expect(devRouteTracker.depth, 1);
    expect(devRouteTracker.snapshot().single['name'], 'home');
  });

  test('匿名路由如实报 null name（现状：全匿名 MaterialPageRoute）', () {
    devRouteTracker.didPush(anonymousRoute(), null);
    final frame = devRouteTracker.snapshot().single;
    expect(frame['name'], isNull);
    expect(frame['type'], contains('PageRouteBuilder'));
  });

  test('didReplace 顶替栈顶；空栈时等价 push', () {
    devRouteTracker.didPush(namedRoute('a'), null);
    devRouteTracker.didReplace(
      newRoute: namedRoute('b'),
      oldRoute: namedRoute('a'),
    );
    expect(devRouteTracker.snapshot().single['name'], 'b');

    devRouteTracker.reset();
    devRouteTracker.didReplace(newRoute: namedRoute('c'));
    expect(devRouteTracker.depth, 1);
    expect(devRouteTracker.snapshot().single['name'], 'c');
  });

  test('didRemove 按栈顶弹出（popUntil 的近似语义）', () {
    devRouteTracker.didPush(namedRoute('a'), null);
    devRouteTracker.didPush(namedRoute('b'), namedRoute('a'));
    devRouteTracker.didRemove(namedRoute('b'), namedRoute('a'));
    expect(devRouteTracker.depth, 1);
  });

  test('reset 清空栈', () {
    devRouteTracker.didPush(namedRoute('a'), null);
    devRouteTracker.reset();
    expect(devRouteTracker.depth, 0);
    expect(devRouteTracker.snapshot(), isEmpty);
  });
}
