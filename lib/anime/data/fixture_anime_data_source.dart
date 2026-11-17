import 'package:mimao/anime/data/anime_data_source.dart';
import 'package:mimao/anime/data/anime_models.dart';

/// 离线假数据源——D 线 UI 先用它驱动，A 线引擎接入后换实现即可。
///
/// 所有数据固定、可预测：测试直接引用 [defaultSearchResults] 等常量断言，
/// 不发网络请求、不读磁盘。封面统一留空（coverUrl == ''），由 UI 的
/// 渐变占位图兜底，保证 widget 测试完全离线。
class FixtureAnimeDataSource implements AnimeDataSource {
  const FixtureAnimeDataSource({
    this.searchResults = defaultSearchResults,
    this.details = defaultDetails,
    this.scheduleSections = defaultScheduleSections,
  });

  final List<AnimeSummary> searchResults;
  final Map<String, AnimeDetail> details;
  final List<AnimeScheduleSection> scheduleSections;

  @override
  Future<List<AnimeSummary>> search(String keyword) async {
    final query = keyword.trim().toLowerCase();
    if (query.isEmpty) return searchResults;
    return searchResults
        .where(
          (item) =>
              item.title.toLowerCase().contains(query) ||
              (item.subtitle ?? '').toLowerCase().contains(query) ||
              (item.sourceName ?? '').toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Future<AnimeDetail> detail(AnimeSummary item) async {
    final found = details[item.id];
    if (found != null) return found;
    // 时间表里可能有搜索 fixture 之外的条目；缺详情时给一个空壳，
    // 保证导航永远不会因为假数据缺项而崩溃。
    return AnimeDetail(
      title: item.title,
      coverUrl: item.coverUrl,
      detailUrl: item.detailUrl,
      description: '',
      sourceName: item.sourceName,
      episodes: const <AnimeEpisode>[],
    );
  }

  @override
  Future<List<AnimeScheduleSection>> schedule() async => scheduleSections;

  // ── 固定 fixture ────────────────────────────────────────────────

  static const AnimeSummary xinghai = AnimeSummary(
    id: 'xinghai',
    title: '星海旅人',
    coverUrl: '',
    detailUrl: 'https://example.com/anime/xinghai',
    subtitle: '更新至第 12 话',
    sourceName: '樱花动漫',
  );
  static const AnimeSummary saibo = AnimeSummary(
    id: 'saibo',
    title: '赛博厨房',
    coverUrl: '',
    detailUrl: 'https://example.com/anime/saibo',
    subtitle: '全 24 话',
    sourceName: '蜜柑',
  );
  static const AnimeSummary wudu = AnimeSummary(
    id: 'wudu',
    title: '雾都侦探社',
    coverUrl: '',
    detailUrl: 'https://example.com/anime/wudu',
    subtitle: '连载中 · 每周三更新',
    sourceName: '樱花动漫',
  );
  static const AnimeSummary xiari = AnimeSummary(
    id: 'xiari',
    title: '夏日回声',
    coverUrl: '',
    detailUrl: 'https://example.com/anime/xiari',
    subtitle: '剧场版',
    sourceName: '蜜柑',
  );
  static const AnimeSummary yuemian = AnimeSummary(
    id: 'yuemian',
    title: '月面邮差',
    coverUrl: '',
    detailUrl: 'https://example.com/anime/yuemian',
    subtitle: '更新至第 8 话',
    sourceName: '樱花动漫',
  );
  static const AnimeSummary shenhai = AnimeSummary(
    id: 'shenhai',
    title: '深海信号',
    coverUrl: '',
    detailUrl: 'https://example.com/anime/shenhai',
    subtitle: '更新至第 5 话',
    sourceName: '樱花动漫',
  );
  static const AnimeSummary zhishang = AnimeSummary(
    id: 'zhishang',
    title: '纸上王国',
    coverUrl: '',
    detailUrl: 'https://example.com/anime/zhishang',
    subtitle: '全 12 话',
    sourceName: '蜜柑',
  );

  /// 搜索页默认显示 4 条。
  static const List<AnimeSummary> defaultSearchResults = <AnimeSummary>[
    xinghai,
    saibo,
    wudu,
    xiari,
  ];

  /// 时间表共 4 天 / 7 部（周一 2、周三 1、周五 3、周六 1）。
  static const List<AnimeScheduleSection> defaultScheduleSections =
      <AnimeScheduleSection>[
        AnimeScheduleSection(
          weekday: AnimeWeekday.monday,
          items: <AnimeSummary>[xinghai, saibo],
        ),
        AnimeScheduleSection(
          weekday: AnimeWeekday.wednesday,
          items: <AnimeSummary>[wudu],
        ),
        AnimeScheduleSection(
          weekday: AnimeWeekday.friday,
          items: <AnimeSummary>[xiari, yuemian, shenhai],
        ),
        AnimeScheduleSection(
          weekday: AnimeWeekday.saturday,
          items: <AnimeSummary>[zhishang],
        ),
      ];

  /// 详情 fixture：星海旅人 5 集（测试断言「渲染 M 集」用这一条）。
  static const Map<String, AnimeDetail> defaultDetails = <String, AnimeDetail>{
    'xinghai': AnimeDetail(
      title: '星海旅人',
      coverUrl: '',
      detailUrl: 'https://example.com/anime/xinghai',
      description:
          '一艘失联百年的殖民船在星海深处重新亮起。少年领航员与一支临时拼凑的船队'
          '踏上归途，沿途打捞被遗忘的航线与旧日通信。',
      sourceName: '樱花动漫',
      tags: <String>['科幻', '冒险', '治愈'],
      episodes: <AnimeEpisode>[
        AnimeEpisode(
          number: 1,
          title: '启航',
          url: 'https://example.com/play/xinghai/1',
          duration: '24:00',
        ),
        AnimeEpisode(
          number: 2,
          title: '星图',
          url: 'https://example.com/play/xinghai/2',
          duration: '24:00',
        ),
        AnimeEpisode(
          number: 3,
          title: '失重',
          url: 'https://example.com/play/xinghai/3',
          duration: '24:00',
        ),
        AnimeEpisode(
          number: 4,
          title: '信号',
          url: 'https://example.com/play/xinghai/4',
          duration: '24:00',
        ),
        AnimeEpisode(
          number: 5,
          title: '回家',
          url: 'https://example.com/play/xinghai/5',
          duration: '24:00',
        ),
      ],
    ),
    'saibo': AnimeDetail(
      title: '赛博厨房',
      coverUrl: '',
      detailUrl: 'https://example.com/anime/saibo',
      description: '在霓虹与油烟交织的赛博城市里，一台旧料理机用一碗热汤收买人心。',
      sourceName: '蜜柑',
      tags: <String>['美食', '喜剧'],
      episodes: <AnimeEpisode>[
        AnimeEpisode(
          number: 1,
          title: '开门营业',
          url: 'https://example.com/play/saibo/1',
          duration: '23:40',
        ),
        AnimeEpisode(
          number: 2,
          title: '辣味算法',
          url: 'https://example.com/play/saibo/2',
          duration: '23:40',
        ),
        AnimeEpisode(
          number: 3,
          title: '最后一桌',
          url: 'https://example.com/play/saibo/3',
          duration: '23:40',
        ),
      ],
    ),
    'wudu': AnimeDetail(
      title: '雾都侦探社',
      coverUrl: '',
      detailUrl: 'https://example.com/anime/wudu',
      description: '雾都的雨夜从不缺少谜案，三位性格迥异的侦探共用一间漏雨的办公室。',
      sourceName: '樱花动漫',
      tags: <String>['悬疑', '推理'],
      episodes: <AnimeEpisode>[
        AnimeEpisode(
          number: 1,
          title: '雨夜来客',
          url: 'https://example.com/play/wudu/1',
          duration: '24:10',
        ),
        AnimeEpisode(
          number: 2,
          title: '消失的钟表匠',
          url: 'https://example.com/play/wudu/2',
          duration: '24:10',
        ),
        AnimeEpisode(
          number: 3,
          title: '雾中列车',
          url: 'https://example.com/play/wudu/3',
          duration: '24:10',
        ),
        AnimeEpisode(
          number: 4,
          title: '真相的背面',
          url: 'https://example.com/play/wudu/4',
          duration: '24:10',
        ),
      ],
    ),
    'xiari': AnimeDetail(
      title: '夏日回声',
      coverUrl: '',
      detailUrl: 'https://example.com/anime/xiari',
      description: '多年后回到海边小镇的夏天，录音机里还留着那年没有说完的话。',
      sourceName: '蜜柑',
      tags: <String>['青春', '剧场版'],
      episodes: <AnimeEpisode>[
        AnimeEpisode(
          number: 1,
          title: '夏日回声',
          url: 'https://example.com/play/xiari/1',
          duration: '1:52:00',
        ),
      ],
    ),
    'yuemian': AnimeDetail(
      title: '月面邮差',
      coverUrl: '',
      detailUrl: 'https://example.com/anime/yuemian',
      description: '月球背面的邮差每周穿越一次静默区，把地球的信送到环形山脚下。',
      sourceName: '樱花动漫',
      tags: <String>['科幻', '温情'],
      episodes: <AnimeEpisode>[
        AnimeEpisode(
          number: 1,
          title: '静默区',
          url: 'https://example.com/play/yuemian/1',
          duration: '24:00',
        ),
        AnimeEpisode(
          number: 2,
          title: '环形山下的信',
          url: 'https://example.com/play/yuemian/2',
          duration: '24:00',
        ),
      ],
    ),
    'zhishang': AnimeDetail(
      title: '纸上王国',
      coverUrl: '',
      detailUrl: 'https://example.com/anime/zhishang',
      description: '折纸成国，墨线为界。一位地图绘制师发现自己的地图正在改变现实。',
      sourceName: '蜜柑',
      tags: <String>['奇幻', '冒险'],
      episodes: <AnimeEpisode>[
        AnimeEpisode(
          number: 1,
          title: '第一道折痕',
          url: 'https://example.com/play/zhishang/1',
          duration: '24:00',
        ),
        AnimeEpisode(
          number: 2,
          title: '墨线之外',
          url: 'https://example.com/play/zhishang/2',
          duration: '24:00',
        ),
      ],
    ),
    'shenhai': AnimeDetail(
      title: '深海信号',
      coverUrl: '',
      detailUrl: 'https://example.com/anime/shenhai',
      description: '深海考察站收到一段来自海沟底部的规律信号，像心跳，也像倒计时。',
      sourceName: '樱花动漫',
      tags: <String>['悬疑', '科幻'],
      episodes: <AnimeEpisode>[
        AnimeEpisode(
          number: 1,
          title: '心跳频率',
          url: 'https://example.com/play/shenhai/1',
          duration: '24:00',
        ),
        AnimeEpisode(
          number: 2,
          title: '下潜',
          url: 'https://example.com/play/shenhai/2',
          duration: '24:00',
        ),
      ],
    ),
  };
}
