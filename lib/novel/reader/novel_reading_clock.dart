/// 阅读计时器的抽象：阅读页每章一段计时，退出/切章时结算。
///
/// 抽出接口只为测试：`Stopwatch` 读的是真实时间，widget 测试里跑不出「读了
/// 两分钟」这种时长，也就验证不了「这段时间记到哪一章」。生产默认用
/// [StopwatchNovelReadingClock]（行为与裸 `Stopwatch` 一致），测试注入可控实现。
library;

abstract interface class NovelReadingClock {
  void start();

  void stop();

  void reset();

  Duration get elapsed;

  bool get isRunning;
}

/// 默认实现：直接包一层 [Stopwatch]。
class StopwatchNovelReadingClock implements NovelReadingClock {
  final Stopwatch _stopwatch = Stopwatch();

  @override
  void start() => _stopwatch.start();

  @override
  void stop() => _stopwatch.stop();

  @override
  void reset() => _stopwatch.reset();

  @override
  Duration get elapsed => _stopwatch.elapsed;

  @override
  bool get isRunning => _stopwatch.isRunning;
}
