/// Bangumi 元数据服务（纯 Dart + dio）——提供番剧封面，对齐 Kazumi 的接入方式。
///
/// Kazumi 搜索主走 Bangumi API 拿元数据/封面（lain.bgm.tv），播放源交给规则站点
/// 按标题搜索。本项目保留现有「规则站点搜索 + 播放」链路，仅按标题向 Bangumi
/// 补一张更可靠的封面——不动 detail/watchSources/播放器契约。
///
/// 两态 host（对齐 Kazumi 的 direct/mirror，去掉需原生依赖的 ECH）：
/// - 直连：api.bgm.tv（国内常超时，Kazumi direct）
/// - 镜像：api.bgmapi.com（Kazumi bangumiAuthAPIMirrorDomain，无需签名，实测可达）
/// 搜索接口无 token；签名仅 api.kazumi.fyi 需要（我们不用它）。
library;

import 'package:dio/dio.dart';

/// 可替换的 Bangumi 抓取接口——测试用假实现脱离网络。
abstract interface class BangumiClient {
  Future<BangumiSearchResponse> searchSubjects(
    String keyword, {
    required String baseUrl,
    int limit = 5,
    int offset = 0,
  });
}

/// 一条 Bangumi 番剧元数据（只保留补封面所需字段）。
class BangumiSubject {
  const BangumiSubject({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.images,
  });

  final int id;
  final String name;
  final String nameCn;

  /// images 各尺寸 URL（large/common/medium/small/grid）；域名通常 lain.bgm.tv。
  final Map<String, String> images;

  /// 展示名：中文名优先，回退原名（Kazumi BangumiItem.nameCn 同款逻辑）。
  String get displayName => nameCn.trim().isEmpty ? name : nameCn;

  /// 封面 URL：large → common → medium → small → image，按 Kazumi 卡片优先级。
  String get coverUrl {
    for (final key in <String>['large', 'common', 'medium', 'small', 'grid']) {
      final url = images[key]?.trim() ?? '';
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  factory BangumiSubject.fromJson(Map<String, dynamic> json) {
    final rawImages = json['images'];
    final images = <String, String>{};
    if (rawImages is Map) {
      for (final entry in rawImages.entries) {
        if (entry.value != null) {
          images[entry.key.toString()] = entry.value.toString();
        }
      }
    }
    final singleImage = json['image']?.toString();
    if (images.isEmpty && singleImage != null && singleImage.isNotEmpty) {
      images['large'] = singleImage;
    }
    return BangumiSubject(
      id: (json['id'] is num)
          ? (json['id'] as num).toInt()
          : int.tryParse(json['id']?.toString() ?? '') ?? 0,
      name: json['name']?.toString() ?? '',
      nameCn: json['name_cn']?.toString() ?? json['nameCN']?.toString() ?? '',
      images: Map<String, String>.unmodifiable(images),
    );
  }
}

class BangumiSearchResponse {
  const BangumiSearchResponse({required this.subjects, this.statusCode = 200});

  final List<BangumiSubject> subjects;
  final int statusCode;

  bool get isSuccessful => statusCode >= 200 && statusCode < 300;
}

/// 搜索接口两态 host（Kazumi api_endpoints.dart 同款常量）。
class BangumiEndpoints {
  static const String direct = 'https://api.bgm.tv';
  static const String mirror = 'https://api.bgmapi.com';
  static const String searchPath = '/v0/search/subjects';

  /// 构造搜索 URL（Kazumi `bangumiRankSearch` 同款 limit/offset query）。
  static String searchUrl(String baseUrl, {int limit = 5, int offset = 0}) =>
      '$baseUrl$searchPath?limit=$limit&offset=$offset';

  /// 构造搜索 JSON body（Kazumi `buildBangumiSearchParams` 精简版：只取 type=2 动画 +
  /// nsfw=false，避免返回漫画/里番干扰封面匹配）。
  static Map<String, dynamic> searchBody(String keyword) => <String, dynamic>{
    'keyword': keyword,
    'sort': 'heat',
    'filter': <String, dynamic>{
      'type': <int>[2],
      'nsfw': false,
    },
  };
}

/// 基于 dio 的实现。
class DioBangumiClient implements BangumiClient {
  DioBangumiClient({Dio? dio, this.timeout = const Duration(seconds: 15)})
    : _dio = dio ?? Dio();

  final Dio _dio;
  final Duration timeout;

  @override
  Future<BangumiSearchResponse> searchSubjects(
    String keyword, {
    required String baseUrl,
    int limit = 5,
    int offset = 0,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      BangumiEndpoints.searchUrl(baseUrl, limit: limit, offset: offset),
      data: BangumiEndpoints.searchBody(keyword),
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
    final status = response.statusCode ?? 0;
    final data = response.data;
    if (data == null) {
      return BangumiSearchResponse(
        subjects: const <BangumiSubject>[],
        statusCode: status,
      );
    }
    final list = data['data'];
    if (list is! List) {
      return BangumiSearchResponse(
        subjects: const <BangumiSubject>[],
        statusCode: status,
      );
    }
    final subjects = <BangumiSubject>[];
    for (final item in list) {
      if (item is Map<String, dynamic>) {
        subjects.add(BangumiSubject.fromJson(item));
      } else if (item is Map) {
        subjects.add(BangumiSubject.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return BangumiSearchResponse(subjects: subjects, statusCode: status);
  }
}

/// 按标题查 Bangumi 封面：取第一个有封面的条目（Bangumi 按热度排序，首条最相关）。
///
/// 返回 null 表示没查到 / 请求失败——调用方保留规则站点原封面，绝不因此打断搜索。
Future<String?> lookupBangumiCover(
  String title,
  BangumiClient client, {
  required String baseUrl,
}) async {
  final keyword = title.trim();
  if (keyword.isEmpty) return null;
  try {
    final response = await client.searchSubjects(keyword, baseUrl: baseUrl);
    if (!response.isSuccessful) return null;
    for (final subject in response.subjects) {
      final cover = subject.coverUrl;
      if (cover.isNotEmpty) return cover;
    }
    return null;
  } on Object {
    // 网络失败/解析异常一律回退：封面是纯增益，不能挡搜索。
    return null;
  }
}
