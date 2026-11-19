import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/shell/dev/dev_log.dart';

void main() {
  setUp(DevLog.clearForTest);
  tearDown(DevLog.uninstall);

  group('环形缓冲', () {
    test('快照按时间正序返回，info/warn/error 便捷入口落位正确', () {
      DevLog.info('dev', '第一条');
      DevLog.warn('app', '第二条');
      DevLog.error('flutter', '第三条');

      final snapshot = DevLog.snapshot();
      expect(snapshot, hasLength(3));
      expect(snapshot[0]['level'], 'info');
      expect(snapshot[0]['kind'], 'dev');
      expect(snapshot[0]['message'], '第一条');
      expect(snapshot[1]['level'], 'warn');
      expect(snapshot[2]['level'], 'error');
      // 时间戳可解析（ISO8601）。
      expect(DateTime.tryParse(snapshot[0]['ts']! as String), isNotNull);
    });

    test('超过容量丢弃最旧条目', () {
      for (var i = 0; i < DevLog.capacity + 5; i++) {
        DevLog.info('dev', 'msg-$i');
      }
      final snapshot = DevLog.snapshot(limit: DevLog.capacity);
      expect(snapshot, hasLength(DevLog.capacity));
      expect(snapshot.first['message'], 'msg-5');
      expect(snapshot.last['message'], 'msg-${DevLog.capacity + 4}');
    });

    test('level 过滤与 limit 截取', () {
      DevLog.info('dev', 'i1');
      DevLog.error('dev', 'e1');
      DevLog.error('dev', 'e2');

      expect(DevLog.snapshot(level: 'error'), hasLength(2));
      // limit 取最新 N 条（时间正序）。
      final newest = DevLog.snapshot(limit: 2);
      expect(newest.map((e) => e['message']), ['e1', 'e2']);
    });

    test('details 附件序列化进条目', () {
      DevLog.info('dev', '带附件', details: StackTrace.current);
      final snapshot = DevLog.snapshot();
      expect(snapshot.single['details'], isNotNull);
    });
  });

  group('错误钩子', () {
    test('install 幂等：重复安装不叠加 handler', () {
      FlutterError.onError = null;
      DevLog.install();
      final first = FlutterError.onError;
      DevLog.install();
      expect(identical(FlutterError.onError, first), isTrue);
    });

    test('FlutterError.onError 记录 kind=flutter 并链式调用原 handler', () {
      var chained = false;
      FlutterError.onError = (FlutterErrorDetails details) => chained = true;

      DevLog.install();
      FlutterError.reportError(
        FlutterErrorDetails(exception: StateError('构建炸了')),
      );

      expect(chained, isTrue, reason: '原 handler 必须被保留调用，不吞错误');
      final snapshot = DevLog.snapshot(level: 'error');
      expect(snapshot, hasLength(1));
      expect(snapshot.single['kind'], 'flutter');
      expect(snapshot.single['message'], contains('构建炸了'));
    });

    test('platform onError 记录 kind=platform；无原 handler 时返回 false', () {
      DevLog.install();
      final callback = PlatformDispatcher.instance.onError!;
      final handled = callback(StateError('异步炸了'), StackTrace.current);

      expect(handled, isFalse, reason: '没有原 handler 时交还 zone 默认路径');
      final snapshot = DevLog.snapshot(level: 'error');
      expect(snapshot.single['kind'], 'platform');
      expect(snapshot.single['message'], contains('异步炸了'));
    });

    test('platform onError 链式调用原 handler 并沿用其返回值', () {
      var chained = false;
      bool prev(Object error, StackTrace stack) {
        chained = true;
        return true;
      }

      PlatformDispatcher.instance.onError = prev;

      DevLog.install();
      final handled = PlatformDispatcher.instance.onError!(
        StateError('x'),
        StackTrace.current,
      );

      expect(chained, isTrue);
      expect(handled, isTrue);
    });

    test('uninstall 恢复原 handler', () {
      void originalHandler(FlutterErrorDetails details) {}
      FlutterError.onError = originalHandler;

      DevLog.install();
      DevLog.uninstall();

      expect(identical(FlutterError.onError, originalHandler), isTrue);
    });
  });
}
