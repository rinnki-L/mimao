// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 pages/ 文件头同款说明。
import 'package:flutter/material.dart';
import 'package:mimao/anime/anime_models.dart';
import 'package:mimao/anime/collect_service.dart';
import 'package:mimao/anime/data/anime_data_source.dart';
import 'package:mimao/anime/data/anime_models.dart';
import 'package:mimao/anime/engine/engine.dart';
import 'package:mimao/anime/history_service.dart';
import 'package:mimao/anime/pages/anime_module_page.dart';
import 'package:mimao/anime/pages/anime_rule_settings.dart';
import 'package:mimao/anime/player/anime_player_page.dart';
import 'package:mimao/anime/player/episode_progress.dart';
import 'package:mimao/anime/player/playback_engine.dart';
import 'package:mimao/anime/player/player_controller.dart';
import 'package:mimao/core/contract.dart';

/// 番剧模块对壳的唯一出口——实现 [AppModule]，由 app_registry 注入全部依赖。
///
/// 本类不 new 任何服务/DB：数据源、收藏/历史服务、规则仓库、播放器工厂都从构造
/// 参数进来，测试可逐个替换（docs/prompts/closure-01 §1）。
class AnimeModule implements AppModule {
  AnimeModule({
    required this.dataSource,
    required this.collect,
    required this.history,
    required this.ruleStore,
    required this.ruleImporter,
    this.playbackEngineFactory,
  });

  final AnimeDataSource dataSource;
  final AnimeCollectService collect;
  final AnimeHistoryService history;
  final RuleStore ruleStore;
  final RuleImporter ruleImporter;

  /// 播放器后端工厂；app_registry 生产路径注入 MediaKitPlaybackEngine，
  /// 测试注入 FakePlaybackEngine。为 null 时点剧集显示提示而不崩溃。
  final PlaybackEngine Function()? playbackEngineFactory;

  @override
  MediaType get type => MediaType.anime;

  @override
  String get label => '番剧';

  @override
  IconData get icon => MediaType.anime.icon;

  @override
  Widget buildHome(BuildContext context) {
    return AnimeModulePage(
      dataSource: dataSource,
      embedded: true,
      onOpenDetail: (item) => history.open(refOf(item)),
      isFavorite: (item) => collect.isCollected(refOf(item)),
      onFavoriteChanged: (item, favorite) =>
          _setFavorite(item, favorite, context),
      onEpisodeTap: (item, detail, episode) =>
          _openPlayer(item, detail, episode, context),
    );
  }

  @override
  Widget buildSettings(BuildContext context) {
    return AnimeRuleSettings(store: ruleStore, importer: ruleImporter);
  }

  /// 列表项 → 模块内部权威主键。id 由 03 适配器定义为绝对详情 URL，
  /// 与 core 投影主键 {id, mediaType, sourceName} 逐维对齐。
  static AnimeRef refOf(AnimeSummary item) =>
      AnimeRef(id: item.id, sourceName: item.sourceName ?? '未知源');

  Future<void> _setFavorite(
    AnimeSummary item,
    bool favorite,
    BuildContext context,
  ) async {
    final ref = refOf(item);
    try {
      if (favorite) {
        await collect.collect(
          ref,
          title: item.title,
          coverUrl: item.coverUrl.isEmpty ? null : item.coverUrl,
        );
      } else {
        await collect.remove(ref);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(favorite ? '追番失败：$e' : '取消追番失败：$e')),
        );
      }
    }
  }

  /// 播放器装配方：打开点校正 → push 播放器。详情入口可能已校正过一次，
  /// [AnimeHistoryService.open] 幂等，播放入口再调无害；校正失败不挡播放
  /// （播放器内的 recorder 随后仍会经 saveProgress 写权威行并同步投影）。
  Future<void> _openPlayer(
    AnimeSummary item,
    AnimeDetail detail,
    AnimeEpisode episode,
    BuildContext context,
  ) async {
    final factory = playbackEngineFactory;
    if (factory == null) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('播放器尚未配置')));
      }
      return;
    }

    // 播放入口的打开点校正：把漏写/写旧的投影在进播放器前校正回来。
    try {
      await history.open(refOf(item));
    } on Object {
      // 校正是纯收益动作，失败静默。
    }
    // 校正跨了异步间隙，页面可能已不在树上。
    if (!context.mounted) return;

    final episodes = <Episode>[
      for (final e in detail.episodes)
        Episode(number: e.number, title: e.title, url: e.url),
    ];
    final found = detail.episodes.indexWhere(
      (e) => e.number == episode.number && e.url == episode.url,
    );
    final initialIndex = found < 0 ? 0 : found;

    final recorder = AnimeHistoryProgressRecorder(
      history: history,
      entryId: item.id,
      sourceName: item.sourceName ?? '未知源',
      title: item.title,
      coverUrl: item.coverUrl.isEmpty ? null : item.coverUrl,
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnimePlayerPage(
          title: item.title,
          episodes: episodes,
          initialIndex: initialIndex,
          recorder: recorder,
          engineFactory: factory,
        ),
      ),
    );
  }
}
