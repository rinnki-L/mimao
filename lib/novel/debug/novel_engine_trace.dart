/// 书源调试的追踪模型：引擎在跑真实流水线时把每一步抛给一个 sink。
///
/// 为什么挂在引擎上而不是另写一套解析路径：调试面板必须看到「跑的时候到底
/// 发生了什么」。sink 是引擎的可选观察者（默认 null，零开销），调试会话把
/// 它挂到**同一个** [LegadoNovelEngine] 实例上，跑完再摘掉——调的和跑的是
/// 同一份代码，不存在「调试器说没问题、阅读时却失败」。
///
/// 纯数据 + 窄接口，不 import UI、不碰 IO，可单测。
library;

/// 追踪事件类型。
enum NovelTraceKind {
  /// 一次 HTTP 请求（含原始响应体）。
  http('HTTP'),

  /// 一条解析规则的执行（选择器 / JSONPath / 正则 / JS）。
  rule('规则'),

  /// JS 控制台输出（`java.log`）。
  js('JS'),

  /// 非致命警告（如 WebView 降级、字段暂不支持）。
  warning('警告'),

  /// 致命错误（异常消息 + 堆栈）。
  error('错误'),

  /// 阶段分隔（搜索 / 详情 / 目录 / 正文），用于 UI 分组。
  phase('阶段');

  const NovelTraceKind(this.label);

  final String label;
}

/// 一条追踪事件。
class NovelTraceEvent {
  NovelTraceEvent({
    required this.kind,
    required this.label,
    this.detail = '',
    this.elapsedMs = 0,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final NovelTraceKind kind;

  /// 短标题（UI 一行能读完）。
  final String label;

  /// 详情：HTTP 是响应体，规则是规则串与结果摘要，JS 是日志文本，错误是堆栈。
  final String detail;

  /// 从所在阶段开始到本事件发生的毫秒数（0 表示未计时）。
  final int elapsedMs;

  final DateTime at;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'label': label,
    if (detail.isNotEmpty) 'detail': detail,
    if (elapsedMs > 0) 'elapsedMs': elapsedMs,
  };
}

/// 追踪接收端。引擎在关键节点同步调用 [add]，实现方必须不阻塞、不抛异常。
abstract interface class NovelTraceSink {
  void add(NovelTraceEvent event);
}

/// 把事件收进内存列表的 sink（调试会话 / 测试用）。
///
/// [maxEvents] 与 [maxDetailChars] 防一次跑崩内存：响应体动辄几百 KB，
/// 调试面板只需要能看和复制，超长部分截断并标注。
class NovelMemoryTraceSink implements NovelTraceSink {
  NovelMemoryTraceSink({this.maxEvents = 400, this.maxDetailChars = 200000});

  final int maxEvents;
  final int maxDetailChars;

  final List<NovelTraceEvent> _events = <NovelTraceEvent>[];

  /// 被截断的响应体数量（UI 提示用）。
  int truncated = 0;

  List<NovelTraceEvent> get events =>
      List<NovelTraceEvent>.unmodifiable(_events);

  /// 最近一条 [NovelTraceKind.http] 事件的完整响应体（调试面板「原始 HTML」）。
  String? get lastHttpBody {
    for (var i = _events.length - 1; i >= 0; i--) {
      final event = _events[i];
      if (event.kind == NovelTraceKind.http) return event.detail;
    }
    return null;
  }

  /// 最近一次 HTTP 的 URL。
  String? get lastHttpUrl {
    for (var i = _events.length - 1; i >= 0; i--) {
      final event = _events[i];
      if (event.kind == NovelTraceKind.http) return event.label;
    }
    return null;
  }

  /// 所有 JS 日志（按发生顺序）。
  List<String> get jsLogs => <String>[
    for (final event in _events)
      if (event.kind == NovelTraceKind.js) event.detail,
  ];

  /// 错误事件。
  List<NovelTraceEvent> get errors => <NovelTraceEvent>[
    for (final event in _events)
      if (event.kind == NovelTraceKind.error) event,
  ];

  void clear() {
    _events.clear();
    truncated = 0;
  }

  @override
  void add(NovelTraceEvent event) {
    var detail = event.detail;
    if (detail.length > maxDetailChars) {
      detail =
          '${detail.substring(0, maxDetailChars)}\n…（已截断，原文 '
          '${event.detail.length} 字符）';
      truncated++;
    }
    if (_events.length >= maxEvents) _events.removeAt(0);
    _events.add(
      NovelTraceEvent(
        kind: event.kind,
        label: event.label,
        detail: detail,
        elapsedMs: event.elapsedMs,
        at: event.at,
      ),
    );
  }
}

/// 取消令牌：长任务（批量校验 / 调试）在步骤之间检查它。
///
/// 单个 HTTP 请求内部无法中断（dio 的请求没有协作取消点），所以取消的粒度
/// 是「步骤之间」——面板上点取消后，当前这一步会跑完再停，已经拿到的结果
/// 保留。这一语义写进 UI 文案，不假装能立刻掐断。
class NovelDebugCancellation {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// 可取消任务被中断时抛出（由调用方捕获后展示「已取消」）。
class NovelDebugCancelled implements Exception {
  const NovelDebugCancelled();

  @override
  String toString() => '已取消';
}
