// 章节评论：数据模型 + 源引擎调用 + 分页/回复状态机。
//
// 对照 Venera-Next `models.dart` 的 Comment、`source_comments_parser.dart` 的
// `comic.loadChapterComments` 契约、`comments_controller.dart` 的分页/回复逻辑。
//
// 本仓只做"读"：发评论/点赞/点踩需要登录态与写接口，源支持率低且风险高，
// 不在本轮范围（UI 也不给入口，避免点了没反应）。

import 'package:flutter/foundation.dart';

/// 一条评论（字段与上游对齐，缺省都允许为空）。
class NovelComment {
  const NovelComment({
    required this.userName,
    required this.content,
    this.avatar,
    this.time,
    this.replyCount,
    this.id,
    this.score,
    this.isLiked,
  });

  final String userName;
  final String content;
  final String? avatar;
  final String? time;
  final int? replyCount;
  final String? id;
  final int? score;
  final bool? isLiked;

  /// 时间字段可能是秒/毫秒时间戳或已格式化字符串。
  static String? parseTime(Object? value) {
    if (value == null) return null;
    if (value is int) {
      final millis = value < 10000000000 ? value * 1000 : value;
      try {
        return DateTime.fromMillisecondsSinceEpoch(
          millis,
        ).toString().substring(0, 19);
      } on Object {
        return null;
      }
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static NovelComment? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final map = <String, Object?>{};
    for (final entry in raw.entries) {
      map['${entry.key}'] = entry.value;
    }
    final content = map['content']?.toString() ?? '';
    if (content.trim().isEmpty) return null;
    return NovelComment(
      userName: map['userName']?.toString() ?? '',
      content: content,
      avatar: map['avatar']?.toString(),
      time: parseTime(map['time']),
      replyCount: (map['replyCount'] as num?)?.toInt(),
      id: map['id']?.toString(),
      score: (map['score'] as num?)?.toInt(),
      isLiked: map['isLiked'] is bool ? map['isLiked']! as bool : null,
    );
  }
}

/// 一页评论。
class NovelCommentPage {
  const NovelCommentPage({required this.comments, this.maxPage});

  final List<NovelComment> comments;

  /// 源返回的总页数；null 表示不知道（按"本页为空即到底"处理）。
  final int? maxPage;

  bool get isEmpty => comments.isEmpty;
}

/// 评论加载失败：消息可直接展示给用户（不含堆栈）。
class NovelCommentException implements Exception {
  const NovelCommentException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 评论加载端口：集成层用源引擎实现，测试注入假实现。
abstract interface class NovelCommentSource {
  /// 是否支持章节评论（不支持时阅读器不显示入口）。
  bool get supportsChapterComments;

  /// 加载第 [page]（1 基）页评论；[replyTo] 非空时加载该评论的回复。
  Future<NovelCommentPage> loadChapterComments({
    required String comicId,
    required String episodeId,
    required int page,
    String? replyTo,
  });
}

/// 章节评论状态机：分页累加、回复栈、加载/错误/空态。
class NovelCommentsController extends ChangeNotifier {
  NovelCommentsController({
    required this.source,
    required this.comicId,
    required this.episodeId,
  });

  final NovelCommentSource source;
  final String comicId;
  final String episodeId;

  final List<NovelComment> _comments = <NovelComment>[];
  final List<({String replyTo, String userName})> _replyStack =
      <({String replyTo, String userName})>[];
  int _page = 0;
  int? _maxPage;
  bool _loading = false;
  bool _disposed = false;
  String? _error;

  List<NovelComment> get comments => List<NovelComment>.unmodifiable(_comments);
  bool get loading => _loading;
  String? get error => _error;
  int get page => _page;
  int? get maxPage => _maxPage;

  /// 当前回复上下文（null = 顶层评论）。
  String? get replyTo => _replyStack.isEmpty ? null : _replyStack.last.replyTo;
  String? get replyToUserName =>
      _replyStack.isEmpty ? null : _replyStack.last.userName;

  bool get hasMore {
    final max = _maxPage;
    if (max != null) return _page < max;
    // 不知道总页数时：上次取到满页就认为可能还有。
    return _comments.isNotEmpty && _lastPageWasFull;
  }

  bool _lastPageWasFull = true;

  /// 加载下一页；正在加载或已到底时是空操作。
  Future<void> loadMore() async {
    if (_disposed || _loading) return;
    if (_page > 0 && !hasMore) return;
    await _load(_page + 1);
  }

  /// 重新加载顶层评论（清空当前列表与回复栈）。
  Future<void> reload() async {
    if (_disposed) return;
    _comments.clear();
    _replyStack.clear();
    _page = 0;
    _maxPage = null;
    _error = null;
    _lastPageWasFull = true;
    _notify();
    await _load(1);
  }

  /// 进入某条评论的回复列表。
  Future<void> openReplies(NovelComment comment) async {
    final id = comment.id;
    if (_disposed || id == null || id.isEmpty) return;
    _replyStack.add((replyTo: id, userName: comment.userName));
    _comments.clear();
    _page = 0;
    _maxPage = null;
    _error = null;
    _lastPageWasFull = true;
    _notify();
    await _load(1);
  }

  /// 退回上一级（回复 → 顶层评论）。
  Future<void> back() async {
    if (_disposed || _replyStack.isEmpty) return;
    _replyStack.removeLast();
    _comments.clear();
    _page = 0;
    _maxPage = null;
    _error = null;
    _lastPageWasFull = true;
    _notify();
    await _load(1);
  }

  Future<void> _load(int page) async {
    _loading = true;
    _error = null;
    _notify();
    try {
      final result = await source.loadChapterComments(
        comicId: comicId,
        episodeId: episodeId,
        page: page,
        replyTo: replyTo,
      );
      if (_disposed) return;
      _page = page;
      _maxPage = result.maxPage;
      _lastPageWasFull = result.comments.isNotEmpty;
      _comments.addAll(result.comments);
      _error = null;
    } on NovelCommentException catch (error) {
      if (_disposed) return;
      _error = error.message;
    } on Object catch (error) {
      if (_disposed) return;
      _error = '评论加载失败：$error';
    } finally {
      if (!_disposed) {
        _loading = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
