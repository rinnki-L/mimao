import 'dart:convert';

import 'package:drift/drift.dart';

import 'anime_db.dart';
import 'anime_models.dart';

/// 弹幕显示模式（滚动/顶部/底部）。数值不写死，序列化用枚举名，跨源稳定。
enum DanmakuMode { scroll, top, bottom }

/// 一条弹幕。
///
/// 只保留播放器画弹幕需要的最小字段；第三方源的原始字段留在源适配器里。
class DanmakuComment {
  /// 相对本话开头的出现时间。
  final Duration time;
  final String text;
  final DanmakuMode mode;
  final int color;
  final double fontSize;

  const DanmakuComment({
    required this.time,
    required this.text,
    this.mode = DanmakuMode.scroll,
    this.color = 0xFFFFFF,
    this.fontSize = 25,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'timeMs': time.inMilliseconds,
    'text': text,
    'mode': mode.name,
    'color': color,
    'fontSize': fontSize,
  };

  /// 宽容解码：未知字段忽略，可选字段取默认值；缺时间/文本则视为坏数据。
  factory DanmakuComment.fromJson(Map<String, Object?> json) {
    final timeMs = json['timeMs'];
    if (timeMs is! num || timeMs.isNegative) {
      throw const FormatException('弹幕 timeMs 必须是非负数字');
    }
    final text = json['text'];
    if (text is! String) {
      throw const FormatException('弹幕 text 必须是字符串');
    }
    final rawMode = json['mode'];
    return DanmakuComment(
      time: Duration(milliseconds: timeMs.round()),
      text: text,
      mode: DanmakuMode.values.firstWhere(
        (mode) => mode.name == rawMode,
        orElse: () => DanmakuMode.scroll,
      ),
      color: _asInt(json['color']) ?? 0xFFFFFF,
      fontSize: _asDouble(json['fontSize']) ?? 25,
    );
  }

  static int? _asInt(Object? value) => value is num ? value.toInt() : null;

  static double? _asDouble(Object? value) =>
      value is num ? value.toDouble() : null;
}

/// 一话弹幕的缓存快照。
class AnimeDanmakuCacheEntry {
  final List<DanmakuComment> comments;
  final DateTime fetchedAt;

  const AnimeDanmakuCacheEntry({
    required this.comments,
    required this.fetchedAt,
  });
}

/// 第三方弹幕源的接入槽。
///
/// 本轮不绑定任何真实 API；将来的适配器（如 Kazumi 弹幕库/自建源）
/// 实现本接口后注入 [AnimeDanmakuService] 即可，缓存与模型层不用改。
abstract class DanmakuSource {
  Future<List<DanmakuComment>> fetch({
    required AnimeRef ref,
    required int episode,
  });
}

/// 弹幕本地缓存服务：内部库存 JSON 快照，按（作品, 源, 话）单行覆盖。
///
/// 读取顺序：未过期缓存 → 弹幕源 → 源缺失时回退旧缓存/空列表。
/// 缓存写入不产生 core 书架投影（弹幕不是媒体条目，见双记账清单）。
class AnimeDanmakuService {
  final AnimeDb db;
  final DanmakuSource? source;
  final Duration maxCacheAge;

  AnimeDanmakuService(
    this.db, {
    this.source,
    this.maxCacheAge = const Duration(days: 7),
  });

  /// 取一话弹幕。`refresh` 强制绕过新鲜缓存（用户手动刷新时用）。
  Future<List<DanmakuComment>> load(
    AnimeRef ref,
    int episode, {
    bool refresh = false,
    DateTime? now,
  }) async {
    if (episode < 1) throw ArgumentError.value(episode, 'episode', '话数从 1 开始');
    final cached = await readCache(ref, episode);
    final at = now ?? DateTime.now();
    final fresh =
        cached != null && at.difference(cached.fetchedAt) <= maxCacheAge;
    if (fresh && !refresh) return cached.comments;

    if (source == null) return cached?.comments ?? const <DanmakuComment>[];

    final fetched = await source!.fetch(ref: ref, episode: episode);
    await writeCache(ref, episode, fetched, fetchedAt: at);
    return fetched;
  }

  Future<AnimeDanmakuCacheEntry?> readCache(AnimeRef ref, int episode) async {
    final row = await db.danmakuCacheRow(ref, episode);
    if (row == null) return null;
    try {
      final decoded = jsonDecode(row.commentsJson);
      if (decoded is! List) return null;
      final comments = <DanmakuComment>[
        for (final item in decoded)
          if (item is Map)
            DanmakuComment.fromJson(Map<String, Object?>.from(item)),
      ];
      return AnimeDanmakuCacheEntry(
        comments: comments,
        fetchedAt: row.fetchedAt,
      );
    } catch (_) {
      // 坏缓存等价于没缓存：下次 load 会重新拉取并覆盖。
      return null;
    }
  }

  Future<void> writeCache(
    AnimeRef ref,
    int episode,
    List<DanmakuComment> comments, {
    DateTime? fetchedAt,
  }) async {
    if (episode < 1) throw ArgumentError.value(episode, 'episode', '话数从 1 开始');
    final payload = jsonEncode([
      for (final comment in comments) comment.toJson(),
    ]);
    await db
        .into(db.animeDanmakuCacheEntries)
        .insertOnConflictUpdate(
          AnimeDanmakuCacheEntriesCompanion.insert(
            id: ref.id,
            sourceName: ref.sourceName,
            episode: episode,
            commentsJson: payload,
            fetchedAt: fetchedAt ?? DateTime.now(),
          ),
        );
  }

  Future<void> clearCache(AnimeRef ref, int episode) async {
    await (db.delete(db.animeDanmakuCacheEntries)..where(
          (t) =>
              t.id.equals(ref.id) &
              t.sourceName.equals(ref.sourceName) &
              t.episode.equals(episode),
        ))
        .go();
  }
}
