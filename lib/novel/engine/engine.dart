/// 小说流水线窄接口（M5 地基切片）。
///
/// [NovelDataSource] 是抓取实现方提供的原始数据源；[NovelEngine] 是在其之上
/// 多带一个 [BookSource] 参数的四阶段流水线接口。两者都只定义签名、零实现，
/// 上层（页面/测试）只依赖接口，可用 fake 注入。
library;

import 'package:mimao/novel/analyzer/rule_models.dart';
import 'package:mimao/novel/models/novel_models.dart';

/// 小说原始数据入口：搜索 → 发现 → 目录 → 正文。
abstract class NovelDataSource {
  Future<List<NovelSummary>> search(String keyword);

  Future<List<NovelSummary>> discover();

  Future<NovelDetail> bookList(NovelRef ref);

  Future<NovelContent> bookContent(NovelRef ref, NovelChapter chapter);
}

/// 小说规则引擎流水线：签名与 [NovelDataSource] 对齐，额外接收 [BookSource]。
abstract class NovelEngine {
  Future<List<NovelSummary>> search(BookSource source, String keyword);

  Future<List<NovelSummary>> discover(BookSource source);

  Future<NovelDetail> chapters(BookSource source, NovelRef ref);

  Future<NovelContent> content(
    BookSource source,
    NovelRef ref,
    NovelChapter chapter,
  );
}
