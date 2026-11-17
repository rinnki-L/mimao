// 进度持久化：模块内部库（权威）+ core 统一书架投影（索引）。
//
// 双记账规则（docs/architecture.md §3.1）在本文件里落地：
//   ① 权威 = 模块内部存储（[AnimeProgressStore]，这里给出内存与 JSON 文件两种实现）；
//   ② 写入点 = [LibraryProgressRecorder.persist] 这一个函数——先写权威，
//      紧接着 upsert core 投影，绝不挂"内存状态变化"回调；
//   ③ 校正点 = 打开详情时用内部库值回写投影（M2 联调详情页时接，本线不做）；
//   ④ 展示 = 壳只读 progressText，payload 只有本模块自己解释。
import 'dart:convert';
import 'dart:io';

import 'package:mimao/core/contract.dart';
import 'package:mimao/core/library.dart';

/// 一次进度持久化事件的运行时值（controller → recorder）。
class EpisodeProgress {
  /// 集号（1 起的展示号，不是列表下标）。
  final int episode;
  final String episodeTitle;
  final Duration position;
  final Duration total;

  const EpisodeProgress({
    required this.episode,
    required this.episodeTitle,
    required this.position,
    required this.total,
  });
}

/// controller 与持久化层之间的窄接口：单测注入假实现即可，不碰数据库。
abstract interface class ProgressRecorder {
  Future<void> persist(EpisodeProgress progress);
}

/// 模块内部权威记录。payload 的字段名与 `lib/anime/anime_projection.dart`
/// （A 线投影）保持一致：`episode` / `positionSec` / `durationSec`——验收点名
/// 前两个；A 线联调时两边写出的 payload 可互相解码。
class AnimeEpisodeProgress {
  final int episode;
  final int positionSec;
  final int durationSec;
  final String? episodeTitle;

  const AnimeEpisodeProgress({
    required this.episode,
    required this.positionSec,
    this.durationSec = 0,
    this.episodeTitle,
  });

  /// 交给 core 的 payload（原样 JSON 往返，core/壳都不解释）。
  Map<String, Object?> toPayload() => <String, Object?>{
    'episode': episode,
    'positionSec': positionSec,
    'durationSec': durationSec,
    if (episodeTitle != null) 'episodeTitle': episodeTitle,
  };

  factory AnimeEpisodeProgress.fromPayload(Map<String, Object?> json) =>
      AnimeEpisodeProgress(
        episode: (json['episode'] as num).toInt(),
        positionSec: (json['positionSec'] as num).toInt(),
        durationSec:
            (json['durationSec'] as num?)?.toInt() ??
            (json['totalSec'] as num?)?.toInt() ??
            0,
        episodeTitle: json['episodeTitle'] as String?,
      );

  factory AnimeEpisodeProgress.decode(String raw) =>
      AnimeEpisodeProgress.fromPayload(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );

  /// 壳直接展示的文案（模块解释好的字符串，壳不解析）。
  ///
  /// 与 A 线 `animeProgressText` 同款：有时长且已看进画面时报百分比，
  /// 否则只报话数——保证两条线写进书架的文案风格一致。
  String get progressText {
    if (durationSec <= 0 || positionSec <= 0) return '看到第 $episode 话';
    final percent = (positionSec * 100 / durationSec).clamp(0, 100).round();
    return '第 $episode 话 · $percent%';
  }
}

/// 模块内部存储的读写面。真实产品里可换成本模块自己的 sqlite/hive；
/// 本线只给内存（单测）与 JSON 文件（演示/本地持久化）两种最小实现。
abstract interface class AnimeProgressStore {
  Future<AnimeEpisodeProgress?> read(String key);

  Future<void> write(String key, AnimeEpisodeProgress progress);
}

/// 单测用：不落盘，保留最近一次写入。
class InMemoryAnimeProgressStore implements AnimeProgressStore {
  final Map<String, AnimeEpisodeProgress> _records =
      <String, AnimeEpisodeProgress>{};

  @override
  Future<AnimeEpisodeProgress?> read(String key) async => _records[key];

  @override
  Future<void> write(String key, AnimeEpisodeProgress progress) async {
    _records[key] = progress;
  }
}

/// 演示/本地持久化用：一个 JSON 文件按 entryId 存多条。
///
/// 刻意不引入新依赖（path_provider 已在 pubspec）；写操作串行 await，
/// 演示场景无需并发控制。
class JsonFileAnimeProgressStore implements AnimeProgressStore {
  final File file;

  JsonFileAnimeProgressStore(this.file);

  @override
  Future<AnimeEpisodeProgress?> read(String key) async {
    final all = await _readAll();
    final raw = all[key];
    if (raw is! Map) return null;
    return AnimeEpisodeProgress.fromPayload(Map<String, Object?>.from(raw));
  }

  @override
  Future<void> write(String key, AnimeEpisodeProgress progress) async {
    final all = await _readAll();
    all[key] = progress.toPayload();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(all));
  }

  Future<Map<String, Object?>> _readAll() async {
    if (!await file.exists()) return <String, Object?>{};
    final text = await file.readAsString();
    if (text.trim().isEmpty) return <String, Object?>{};
    return Map<String, Object?>.from(jsonDecode(text) as Map);
  }
}

/// 把进度写进 core 统一书架投影的实现（验收点③）。
///
/// 每次 [persist] 都在同一个函数里完成"内部库 → 投影"两笔账；
/// 两次写之间进程被杀，最多丢最后一次持久化，不会出现两库分叉。
class LibraryProgressRecorder implements ProgressRecorder {
  final LibraryRepository library;
  final AnimeProgressStore store;

  /// 源内唯一键，如 `anime:demo:hardcoded`；M2 联调时换成规则源作品 id。
  final String entryId;
  final String sourceName;
  final String title;
  final String? coverUrl;

  const LibraryProgressRecorder({
    required this.library,
    required this.store,
    required this.entryId,
    required this.sourceName,
    required this.title,
    this.coverUrl,
  });

  @override
  Future<void> persist(EpisodeProgress progress) async {
    final record = AnimeEpisodeProgress(
      episode: progress.episode,
      positionSec: progress.position.inSeconds,
      durationSec: progress.total.inSeconds,
      episodeTitle: progress.episodeTitle,
    );

    // ① 模块内部库（权威）。
    await store.write(entryId, record);

    // ② core 投影（索引）：payload 原样透传，progressText 是模块写好的文案。
    await library.upsert(
      id: entryId,
      type: MediaType.anime,
      sourceName: sourceName,
      title: title,
      coverUrl: coverUrl,
      payload: jsonEncode(record.toPayload()),
      progressText: record.progressText,
    );
  }
}
