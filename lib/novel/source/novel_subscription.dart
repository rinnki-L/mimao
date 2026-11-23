/// 小说书源订阅：一个订阅 = 一个书源来源站点的集合。
///
/// 与"订阅页展示书源列表"的旧形态不同，订阅页现在只展示用户订阅的来源：
/// 每个订阅指向一个书源站点（`yuedu://` 一键导入的落地页），点进去是它的
/// 书源集合（落到现有规则管理页）。默认内置"喵公子书源管理"一条——本机
/// 的书源都从该站导入，无需用户再手工建一条。
///
/// 订阅列表存一份 JSON 到应用支持目录，可追加；删除订阅只删这条记录，
/// 不删已导入的书源（书源仍归书源仓库所有）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'novel_source_model.dart';

/// 一条书源订阅。
class NovelSourceSubscription {
  const NovelSourceSubscription({
    required this.id,
    required this.name,
    required this.siteUrl,
    this.note = '',
  });

  final String id;
  final String name;
  final String siteUrl;
  final String note;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'siteUrl': siteUrl,
    'note': note,
  };

  factory NovelSourceSubscription.fromJson(Map<String, Object?> json) =>
      NovelSourceSubscription(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        siteUrl: '${json['siteUrl'] ?? ''}',
        note: '${json['note'] ?? ''}',
      );
}

/// 本机默认订阅：喵公子书源站，书源都从这里一键导入。
const NovelSourceSubscription defaultNovelSubscription =
    NovelSourceSubscription(
      id: 'miaogongzi',
      name: '喵公子书源管理',
      siteUrl: novelSourceSiteUrl,
      note: 'yuedu.miaogongzi.net 一键导入的书源集合',
    );

/// 订阅仓库的窄接口（页面依赖它，测试可注入内存实现）。
abstract interface class NovelSubscriptionStore {
  Future<List<NovelSourceSubscription>> loadAll();

  Future<void> saveAll(Iterable<NovelSourceSubscription> subscriptions);
}

/// 文件实现：`<应用支持目录>/novel_subscriptions.json`，清单缺失时回落到默认订阅。
class NovelSubscriptionFileStore implements NovelSubscriptionStore {
  static NovelSubscriptionFileStore lazy() =>
      NovelSubscriptionFileStore(() async {
        final support = await getApplicationSupportDirectory();
        return File(p.join(support.path, 'novel_subscriptions.json'));
      });

  static Future<NovelSubscriptionFileStore> openDefault() async {
    final support = await getApplicationSupportDirectory();
    return NovelSubscriptionFileStore.file(
      File(p.join(support.path, 'novel_subscriptions.json')),
    );
  }

  /// 从已知文件路径同步构造（装配期拿不到 app support 目录时用）。
  NovelSubscriptionFileStore.file(File file) : _file = file, _fileLoader = null;

  /// 惰性构造：装配期零 IO，首次读写才解析路径。
  NovelSubscriptionFileStore(this._fileLoader);

  final Future<File> Function()? _fileLoader;
  File? _file;

  Future<File> _resolveFile() async {
    final current = _file;
    if (current != null) return current;
    final loader = _fileLoader;
    if (loader == null) throw StateError('订阅仓库没有文件来源');
    final resolved = await loader();
    _file = resolved;
    return resolved;
  }

  @override
  Future<List<NovelSourceSubscription>> loadAll() async {
    final file = await _resolveFile();
    if (!await file.exists()) {
      return const <NovelSourceSubscription>[defaultNovelSubscription];
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        return const <NovelSourceSubscription>[defaultNovelSubscription];
      }
      final result = decoded
          .whereType<Map>()
          .map(
            (e) =>
                NovelSourceSubscription.fromJson(Map<String, Object?>.from(e)),
          )
          .where((s) => s.id.isNotEmpty && s.name.isNotEmpty)
          .toList();
      return result.isEmpty
          ? const <NovelSourceSubscription>[defaultNovelSubscription]
          : List<NovelSourceSubscription>.unmodifiable(result);
    } on Object {
      return const <NovelSourceSubscription>[defaultNovelSubscription];
    }
  }

  @override
  Future<void> saveAll(Iterable<NovelSourceSubscription> subscriptions) async {
    const encoder = JsonEncoder.withIndent('  ');
    final file = await _resolveFile();
    await file.writeAsString(
      '${encoder.convert(subscriptions.map((s) => s.toJson()).toList())}\n',
      flush: true,
    );
  }
}
