/// 小说全量备份：把本模块的可重建数据打成一个 JSON 包，经 WebDAV PUT/GET 上传/恢复。
///
/// 备份范围（都是"可重建的本地数据"，不含正文/图片）：
/// 书架收藏（含分组与阅读进度）、阅读历史、搜索历史、书源（含规则）、模块偏好/目标。
/// WebDAV 用现成的 dio 手写 PUT/GET + Basic 认证，不引入新依赖——避免改 pubspec.lock
/// 触发 CI 的 --enforce-lockfile 全量重解析。
///
/// 配置（URL / 账号 / 密码）存模块 kv（NovelPrefsApi）；窄接口 [NovelWebDavClient]
/// 让测试注入假客户端，全程离线。
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'library_api.dart';
import 'models/novel_models.dart';
import 'source/novel_source_model.dart';
import 'source/novel_source_store.dart' show NovelSourceStorage;

/// 备份文件格式标识与版本（恢复时校验，避免把任意 JSON 当备份包）。
const String novelBackupFormat = 'mimao-novel-backup';
const int novelBackupVersion = 1;

/// WebDAV 配置键（存 NovelPrefsApi）。
const String novelWebDavUrlKey = 'webdav_url';
const String novelWebDavUserKey = 'webdav_user';
const String novelWebDavPasswordKey = 'webdav_password';

/// 一台 WebDAV 服务器上的配置。
class NovelWebDavConfig {
  const NovelWebDavConfig({
    required this.url,
    this.user = '',
    this.password = '',
  });

  /// [url] 是完整目录 + 文件名，例如
  /// `https://dav.example.com/mimao/novel-backup.json`。
  final String url;
  final String user;
  final String password;

  bool get isValid => Uri.tryParse(url)?.isAbsolute == true;

  Map<String, Object?> toJson() => <String, Object?>{
    'url': url,
    'user': user,
    'password': password,
  };

  factory NovelWebDavConfig.fromJson(Map<String, Object?> json) =>
      NovelWebDavConfig(
        url: '${json['url'] ?? ''}',
        user: '${json['user'] ?? ''}',
        password: '${json['password'] ?? ''}',
      );
}

/// 从模块 kv 读取配置；三项都没有时返回 null（未配置）。
Future<NovelWebDavConfig?> readWebDavConfig(NovelPrefsApi prefs) async {
  final url = await prefs.read(novelWebDavUrlKey);
  if (url == null || url.trim().isEmpty) return null;
  return NovelWebDavConfig(
    url: url.trim(),
    user: (await prefs.read(novelWebDavUserKey)) ?? '',
    password: (await prefs.read(novelWebDavPasswordKey)) ?? '',
  );
}

/// 保存配置（密码明文落本地 kv——本机 debug 库，无生产凭据）。
Future<void> writeWebDavConfig(
  NovelPrefsApi prefs,
  NovelWebDavConfig config,
) async {
  await prefs.write(novelWebDavUrlKey, config.url.trim());
  await prefs.write(novelWebDavUserKey, config.user);
  await prefs.write(novelWebDavPasswordKey, config.password);
}

/// WebDAV 客户端窄接口（可注入 fake）。
abstract interface class NovelWebDavClient {
  Future<void> put(String url, String body, NovelWebDavConfig config);

  Future<String> get(String url, NovelWebDavConfig config);
}

/// 生产实现：dio + Basic 认证，PUT 写文件、GET 读文件。
class DioNovelWebDavClient implements NovelWebDavClient {
  DioNovelWebDavClient({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 30),
              followRedirects: true,
            ),
          );

  final Dio _dio;

  Map<String, String> _headers(NovelWebDavConfig config) {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
    };
    if (config.user.isNotEmpty || config.password.isNotEmpty) {
      final credentials = base64Encode(
        utf8.encode('${config.user}:${config.password}'),
      );
      headers['Authorization'] = 'Basic $credentials';
    }
    return headers;
  }

  @override
  Future<void> put(String url, String body, NovelWebDavConfig config) async {
    await _dio.put<String>(
      url,
      data: body,
      options: Options(headers: _headers(config)),
    );
  }

  @override
  Future<String> get(String url, NovelWebDavConfig config) async {
    final response = await _dio.get<String>(
      url,
      options: Options(
        headers: _headers(config),
        responseType: ResponseType.plain,
      ),
    );
    return response.data ?? '';
  }
}

/// 全量备份文档。
class NovelBackupDocument {
  const NovelBackupDocument({
    required this.collects,
    required this.histories,
    required this.searchKeywords,
    required this.sources,
    required this.prefs,
    required this.exportedAt,
  });

  final List<NovelBackupCollect> collects;
  final List<NovelBackupHistory> histories;
  final List<String> searchKeywords;
  final List<NovelBookSource> sources;
  final Map<String, String> prefs;
  final DateTime exportedAt;

  String encode() {
    final document = <String, Object?>{
      'format': novelBackupFormat,
      'version': novelBackupVersion,
      'exportedAt': exportedAt.toIso8601String(),
      'collects': <Object?>[for (final item in collects) item.toJson()],
      'histories': <Object?>[for (final item in histories) item.toJson()],
      'searchKeywords': <Object?>[...searchKeywords],
      'sources': <Object?>[for (final source in sources) source.toJson()],
      'prefs': <String, Object?>{...prefs},
    };
    return '${const JsonEncoder.withIndent('  ').convert(document)}\n';
  }

  /// 解析并校验格式；不合法抛 [FormatException]。
  static NovelBackupDocument decode(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('备份文件不是 JSON 对象');
    if (decoded['format'] != novelBackupFormat) {
      throw const FormatException('不是 mimao 小说备份文件');
    }
    final version = decoded['version'];
    if (version is! int || version > novelBackupVersion) {
      throw const FormatException('备份版本不兼容');
    }
    List<NovelBackupCollect> collectOf(Object? value) {
      if (value is! List) return const <NovelBackupCollect>[];
      return value
          .whereType<Map>()
          .map((e) => NovelBackupCollect.fromJson(Map<String, Object?>.from(e)))
          .where((e) => e.book.id.isNotEmpty)
          .toList();
    }

    List<NovelBackupHistory> historyOf(Object? value) {
      if (value is! List) return const <NovelBackupHistory>[];
      return value
          .whereType<Map>()
          .map((e) => NovelBackupHistory.fromJson(Map<String, Object?>.from(e)))
          .where((e) => e.book.id.isNotEmpty)
          .toList();
    }

    DateTime? exportedAt;
    final rawExportedAt = decoded['exportedAt'];
    if (rawExportedAt is String) {
      exportedAt = DateTime.tryParse(rawExportedAt);
    }
    final searchKeywords = <String>[];
    final rawKeywords = decoded['searchKeywords'];
    if (rawKeywords is List) {
      for (final keyword in rawKeywords) {
        final text = keyword?.toString().trim() ?? '';
        if (text.isNotEmpty) searchKeywords.add(text);
      }
    }
    final sources = <NovelBookSource>[];
    final rawSources = decoded['sources'];
    if (rawSources is List) {
      for (final raw in rawSources) {
        if (raw is! Map) continue;
        try {
          sources.add(NovelBookSource.fromJson(Map<String, Object?>.from(raw)));
        } on Object {
          // 单条坏源不影响其余。
        }
      }
    }
    final prefs = <String, String>{};
    final rawPrefs = decoded['prefs'];
    if (rawPrefs is Map) {
      for (final entry in rawPrefs.entries) {
        prefs['${entry.key}'] = '${entry.value}';
      }
    }
    return NovelBackupDocument(
      collects: collectOf(decoded['collects']),
      histories: historyOf(decoded['histories']),
      searchKeywords: searchKeywords,
      sources: sources,
      prefs: prefs,
      exportedAt: exportedAt ?? DateTime.now(),
    );
  }
}

/// 备份里的一本收藏（书籍快照 + 分组 + 进度）。
class NovelBackupCollect {
  const NovelBackupCollect({
    required this.book,
    this.groupName,
    this.chapterIndex = 0,
    this.chapterCount = 0,
  });

  final NovelSummary book;
  final String? groupName;
  final int chapterIndex;
  final int chapterCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'book': book.toJson(),
    if (groupName != null && groupName!.isNotEmpty) 'groupName': groupName,
    'chapterIndex': chapterIndex,
    'chapterCount': chapterCount,
  };

  factory NovelBackupCollect.fromJson(Map<String, Object?> json) {
    final rawBook = json['book'];
    final book = rawBook is Map
        ? NovelSummary.fromJson(Map<String, Object?>.from(rawBook))
        : NovelSummary(
            id: '${json['id'] ?? ''}',
            title: '${json['title'] ?? ''}',
            coverUrl: '',
          );
    final group = json['groupName'];
    return NovelBackupCollect(
      book: book,
      groupName: group is String && group.trim().isNotEmpty ? group : null,
      chapterIndex: json['chapterIndex'] is num
          ? (json['chapterIndex']! as num).toInt()
          : 0,
      chapterCount: json['chapterCount'] is num
          ? (json['chapterCount']! as num).toInt()
          : 0,
    );
  }
}

/// 备份里的一条阅读历史。
class NovelBackupHistory {
  const NovelBackupHistory({
    required this.book,
    this.chapterIndex = 0,
    this.chapterCount = 0,
    this.openedAt,
  });

  final NovelSummary book;
  final int chapterIndex;
  final int chapterCount;
  final DateTime? openedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'book': book.toJson(),
    'chapterIndex': chapterIndex,
    'chapterCount': chapterCount,
    if (openedAt != null) 'openedAt': openedAt!.toIso8601String(),
  };

  factory NovelBackupHistory.fromJson(Map<String, Object?> json) {
    final rawBook = json['book'];
    final book = rawBook is Map
        ? NovelSummary.fromJson(Map<String, Object?>.from(rawBook))
        : NovelSummary(
            id: '${json['id'] ?? ''}',
            title: '${json['title'] ?? ''}',
            coverUrl: '',
          );
    DateTime? openedAt;
    final rawOpenedAt = json['openedAt'];
    if (rawOpenedAt is String) openedAt = DateTime.tryParse(rawOpenedAt);
    return NovelBackupHistory(
      book: book,
      chapterIndex: json['chapterIndex'] is num
          ? (json['chapterIndex']! as num).toInt()
          : 0,
      chapterCount: json['chapterCount'] is num
          ? (json['chapterCount']! as num).toInt()
          : 0,
      openedAt: openedAt,
    );
  }
}

/// 备份服务：采集 → 编码 → PUT；GET → 解码 → 恢复。
class NovelWebDavBackupService {
  NovelWebDavBackupService({
    required this.client,
    required this.collect,
    required this.history,
    required this.searchHistory,
    required this.sourceStorage,
    required this.prefs,
  });

  final NovelWebDavClient client;
  final NovelCollectApi? collect;
  final NovelHistoryApi? history;
  final NovelSearchHistoryApi? searchHistory;
  final NovelSourceStorage? sourceStorage;
  final NovelPrefsApi? prefs;

  /// 采集当前全量数据并上传。返回写入的书源/收藏/历史条数供 UI 反馈。
  Future<({int collects, int histories, int sources})> backup(
    NovelWebDavConfig config,
  ) async {
    final collects = <NovelBackupCollect>[];
    final collectApi = collect;
    if (collectApi != null) {
      for (final item in await collectApi.list()) {
        final progress = await history?.latest(item.ref.id);
        collects.add(
          NovelBackupCollect(
            book:
                item.book ??
                NovelSummary(
                  id: item.ref.id,
                  title: item.title,
                  coverUrl: item.coverUrl ?? '',
                ),
            groupName: item.groupName,
            chapterIndex: progress?.chapterIndex ?? 0,
            chapterCount: progress?.chapterCount ?? 0,
          ),
        );
      }
    }
    final histories = <NovelBackupHistory>[];
    final historyApi = history;
    if (historyApi != null) {
      for (final item in await historyApi.recent(limit: 100000)) {
        histories.add(
          NovelBackupHistory(
            book: item.book,
            chapterIndex: item.chapterIndex,
            chapterCount: item.chapterCount,
            openedAt: item.openedAt,
          ),
        );
      }
    }
    final keywords = <String>[];
    final searchApi = searchHistory;
    if (searchApi != null) {
      keywords.addAll(await searchApi.recent(limit: 100000));
    }
    final sources = <NovelBookSource>[];
    final storage = sourceStorage;
    if (storage != null) sources.addAll(await storage.loadAll());
    final prefsMap = <String, String>{};
    final prefsApi = prefs;
    if (prefsApi != null) {
      for (final key in <String>[
        novelPrefGoalMinutes,
        novelPrefShelfLayout,
        novelPrefShelfColumns,
        novelPrefShelfSort,
        novelPrefShelfView,
        novelPrefShelfOrder,
        novelPrefHomeModules,
        novelPrefReaderFontSize,
        novelPrefReaderSettings,
        novelPrefReaderBookSettings,
        novelPrefReaderPositions,
      ]) {
        final value = await prefsApi.read(key);
        if (value != null) prefsMap[key] = value;
      }
    }

    final document = NovelBackupDocument(
      collects: collects,
      histories: histories,
      searchKeywords: keywords,
      sources: sources,
      prefs: prefsMap,
      exportedAt: DateTime.now(),
    );
    await client.put(config.url, document.encode(), config);
    return (
      collects: collects.length,
      histories: histories.length,
      sources: sources.length,
    );
  }

  /// 从 WebDAV 下载并恢复。返回恢复的条数供 UI 反馈。
  Future<({int collects, int histories, int sources})> restore(
    NovelWebDavConfig config,
  ) async {
    final text = await client.get(config.url, config);
    final document = NovelBackupDocument.decode(text);

    final storage = sourceStorage;
    if (storage != null && document.sources.isNotEmpty) {
      await storage.saveAll(document.sources);
    }
    final searchApi = searchHistory;
    if (searchApi != null) {
      await searchApi.clear();
      for (final keyword in document.searchKeywords) {
        await searchApi.record(keyword);
      }
    }
    final historyApi = history;
    if (historyApi != null) {
      await historyApi.clear();
      for (final item in document.histories) {
        await historyApi.saveProgress(
          item.book,
          item.chapterIndex,
          item.chapterCount,
        );
      }
    }
    final collectApi = collect;
    if (collectApi != null) {
      for (final item in document.collects) {
        await collectApi.collect(item.book);
        if (item.groupName != null) {
          await collectApi.setGroup(item.book.id, item.groupName);
        }
        final historyApi = history;
        if (historyApi != null && item.chapterCount > 0) {
          await historyApi.saveProgress(
            item.book,
            item.chapterIndex,
            item.chapterCount,
          );
        }
      }
    }
    final prefsApi = prefs;
    if (prefsApi != null) {
      for (final entry in document.prefs.entries) {
        await prefsApi.write(entry.key, entry.value);
      }
    }
    return (
      collects: document.collects.length,
      histories: document.histories.length,
      sources: document.sources.length,
    );
  }
}
