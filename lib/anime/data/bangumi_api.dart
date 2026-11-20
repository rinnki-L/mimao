/// Bangumi 搜索 API——直接照抄 Kazumi `request/apis/bangumi_api.dart` 的搜索语义。
///
/// 对齐 Kazumi 原版：buildBangumiSearchParams / bangumiSearch（只保留 nameCn 非空、
/// 按 id 去重）/ BangumiItem.fromJson（nameCn 回退链、images 兜底、rating/tags/date）。
/// 差异：host 镜像用 api.bgmapi.com（实测按关键词过滤、无需签名），直连 api.bgm.tv。
library;

import 'package:dio/dio.dart';

/// Kazumi 搜索 filter 构造（原样照抄 buildBangumiSearchParams 核心）。
Map<String, dynamic> buildBangumiSearchParams(String keyword) =>
    <String, dynamic>{
      'keyword': keyword,
      'sort': 'heat',
      'filter': <String, dynamic>{
        'type': <int>[2],
        'tag': <String>[],
        'rank': <String>['>=0', '<=99999'],
        'nsfw': false,
      },
    };

/// Kazumi BangumiItem 精简版（搜索结果展示字段，语义逐字对齐）。
class BangumiItem {
  const BangumiItem({
    required this.id,
    required this.type,
    required this.name,
    required this.nameCn,
    required this.summary,
    required this.airDate,
    required this.rank,
    required this.images,
    required this.ratingScore,
    required this.votes,
    required this.tags,
  });

  final int id;
  final int type;
  final String name;
  final String nameCn;
  final String summary;
  final String airDate;
  final int rank;
  final Map<String, String> images;
  final double ratingScore;
  final int votes;
  final List<String> tags;

  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  String get coverUrl {
    final large = images['large']?.trim() ?? '';
    if (large.isNotEmpty) return large;
    return images['common']?.trim() ?? '';
  }

  String get searchKeyword => displayName;

  factory BangumiItem.fromJson(Map<String, dynamic> json) {
    final rawNameCn = (json['name_cn'] ?? '').toString();
    final rawNameCN = (json['nameCN'] ?? '').toString();
    final name = (json['name'] ?? '').toString();
    final nameCn = rawNameCn.isEmpty
        ? (rawNameCN.isEmpty ? name : rawNameCN)
        : rawNameCn;

    var airDate = (json['date'] ?? '').toString().trim();
    if (airDate.isEmpty && json['airtime'] is Map) {
      airDate = (json['airtime']['date'] ?? '').toString().trim();
    }

    final rawImages = json['images'];
    final images = <String, String>{};
    if (rawImages is Map) {
      for (final entry in rawImages.entries) {
        if (entry.value != null) {
          images[entry.key.toString()] = entry.value.toString();
        }
      }
    }
    if (images.isEmpty) {
      final image = json['image']?.toString() ?? '';
      images
        ..['large'] = image
        ..['common'] = ''
        ..['medium'] = ''
        ..['small'] = ''
        ..['grid'] = '';
    }

    final rating = json['rating'];
    var score = 0.0;
    var rank = 0;
    var votes = 0;
    if (rating is Map) {
      score =
          double.tryParse(
            ((rating['score'] ?? 0.0) as num).toDouble().toStringAsFixed(1),
          ) ??
          0.0;
      rank = (rating['rank'] is num) ? (rating['rank'] as num).toInt() : 0;
      votes = (rating['total'] is num) ? (rating['total'] as num).toInt() : 0;
    }

    final tags = <String>[];
    final rawTags = json['tags'];
    if (rawTags is List) {
      for (final tag in rawTags) {
        if (tag is Map && tag['name'] != null) {
          tags.add(tag['name'].toString());
        }
      }
    }

    return BangumiItem(
      id: (json['id'] is num)
          ? (json['id'] as num).toInt()
          : int.tryParse(json['id']?.toString() ?? '') ?? 0,
      type: (json['type'] is num) ? (json['type'] as num).toInt() : 2,
      name: name,
      nameCn: nameCn,
      summary: (json['summary'] ?? '').toString(),
      airDate: airDate,
      rank: rank,
      images: Map<String, String>.unmodifiable(images),
      ratingScore: score,
      votes: votes,
      tags: List<String>.unmodifiable(tags),
    );
  }
}

/// Kazumi bangumiSearch 返回（items 已过滤 + rawCount 供分页）。
class BangumiSearchPage {
  const BangumiSearchPage({required this.items, required this.rawCount});

  final List<BangumiItem> items;
  final int rawCount;
}

/// 可替换的 Bangumi 抓取接口——测试用假实现脱离网络。
abstract interface class BangumiClient {
  Future<BangumiSearchPage?> bangumiSearch(
    String keyword, {
    required String baseUrl,
    int limit = 20,
    int offset = 0,
  });
}

/// Kazumi host 常量（直连官方 / 本项目可用镜像）。
class BangumiEndpoints {
  static const String direct = 'https://api.bgm.tv';
  static const String mirror = 'https://api.bgmapi.com';
  static const String searchPath = '/v0/search/subjects';

  static String searchUrl(String baseUrl, {int limit = 20, int offset = 0}) =>
      '$baseUrl$searchPath?limit=$limit&offset=$offset';
}

/// 基于 dio——照抄 Kazumi bangumiSearch：POST + nameCn 过滤 + id 去重。
class DioBangumiClient implements BangumiClient {
  DioBangumiClient({Dio? dio, this.timeout = const Duration(seconds: 15)})
    : _dio = dio ?? Dio();

  final Dio _dio;
  final Duration timeout;

  @override
  Future<BangumiSearchPage?> bangumiSearch(
    String keyword, {
    required String baseUrl,
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        BangumiEndpoints.searchUrl(baseUrl, limit: limit, offset: offset),
        data: buildBangumiSearchParams(keyword),
        options: Options(
          headers: <String, String>{
            'User-Agent':
                'Predidit/Kazumi/4.0 (Android) '
                '(https://github.com/Predidit/Kazumi)',
            'Content-Type': 'application/json; charset=utf-8',
            'Accept': 'application/json',
          },
          responseType: ResponseType.json,
          receiveTimeout: timeout,
          sendTimeout: timeout,
          validateStatus: (status) => status != null,
        ),
      );
      final data = response.data;
      if (data == null || data['data'] is! List) return null;
      final jsonList = data['data'] as List;
      final items = <BangumiItem>[];
      final seen = <int>{};
      for (final entry in jsonList) {
        final map = entry is Map<String, dynamic>
            ? entry
            : (entry is Map ? Map<String, dynamic>.from(entry) : null);
        if (map == null) continue;
        try {
          final item = BangumiItem.fromJson(map);
          if (item.nameCn.isNotEmpty && seen.add(item.id)) items.add(item);
        } on Object {
          // 单条解析失败跳过。
        }
      }
      return BangumiSearchPage(items: items, rawCount: jsonList.length);
    } on Object {
      return null;
    }
  }
}
