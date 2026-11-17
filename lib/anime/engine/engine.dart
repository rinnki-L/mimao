/// 番剧规则引擎的公开入口。
///
/// 上层只 import 这一个文件即可拿到：规则模型、XPath 抽取、导入、本地存储、
/// 抓取编排。内部拆成多个文件是为了每块都能单独测试。
library;

export '../request/web_client.dart';
export 'anime_rule_engine.dart';
export 'extractor.dart';
export 'result.dart';
export 'rule.dart';
export 'rule_importer.dart';
export 'rule_store.dart';
