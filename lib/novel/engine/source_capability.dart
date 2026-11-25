/// 书源字段能力报告：把「解析了但没生效」的规则字段显式标出来。
///
/// 只描述当前实现的能力边界，不做运行时探测：书源详情页与正文抓取共用同一
/// 张表，避免页面写一套、引擎做另一套。
library;

import 'package:mimao/novel/source/novel_source_model.dart';

enum NovelCapabilityStatus {
  supported('已支持'),
  degraded('降级可用'),
  unsupported('暂不支持');

  const NovelCapabilityStatus(this.label);

  final String label;
}

class NovelSourceCapability {
  const NovelSourceCapability({
    required this.field,
    required this.label,
    required this.status,
    required this.detail,
  });

  /// 规则字段名（与 Legado JSON 键一致，便于对照书源原文）。
  final String field;

  /// 中文展示名。
  final String label;

  final NovelCapabilityStatus status;

  /// 具体说明：支持什么、降级成什么、为什么不支持。
  final String detail;
}

/// 正文规则字段的能力表（书源详情页与引擎共用同一份）。
List<NovelSourceCapability> novelContentCapabilities(NovelSourceRules rules) {
  return <NovelSourceCapability>[
    NovelSourceCapability(
      field: 'content',
      label: '正文',
      status: rules.contentRule.isEmpty
          ? NovelCapabilityStatus.unsupported
          : NovelCapabilityStatus.supported,
      detail: rules.contentRule.isEmpty ? '书源没有配置正文规则' : '按规则抓取并转纯文本',
    ),
    NovelSourceCapability(
      field: 'subContent',
      label: '副文',
      status: NovelCapabilityStatus.supported,
      detail: rules.contentSubContent.isEmpty ? '未配置' : '拼接在正文后',
    ),
    NovelSourceCapability(
      field: 'title',
      label: '正文内标题',
      status: NovelCapabilityStatus.supported,
      detail: rules.contentTitle.isEmpty ? '未配置' : '从正文页提取章节名',
    ),
    NovelSourceCapability(
      field: 'nextContentUrl',
      label: '下一页',
      status: NovelCapabilityStatus.supported,
      detail: rules.contentNextUrl.isEmpty ? '未配置' : '链式翻页抓取',
    ),
    NovelSourceCapability(
      field: 'webJs',
      label: 'WebView 取正文（webJs）',
      status: rules.contentWebJs.isEmpty
          ? NovelCapabilityStatus.supported
          : NovelCapabilityStatus.degraded,
      detail: rules.contentWebJs.isEmpty
          ? '未配置'
          : '桌面端没有 WebView，已降级为 HTTP 抓取；动态渲染的页面可能拿不到正文',
    ),
    NovelSourceCapability(
      field: 'sourceRegex',
      label: 'WebView 源码正则（sourceRegex）',
      status: rules.contentSourceRegex.isEmpty
          ? NovelCapabilityStatus.supported
          : NovelCapabilityStatus.unsupported,
      detail: rules.contentSourceRegex.isEmpty
          ? '未配置'
          : '只在 WebView 渲染后生效，桌面端暂不支持；按 HTTP 抓取时忽略',
    ),
    NovelSourceCapability(
      field: 'replaceRegex',
      label: '正文替换（replaceRegex）',
      status: NovelCapabilityStatus.supported,
      detail: rules.contentReplaceRegex.isEmpty ? '未配置' : '已应用',
    ),
    NovelSourceCapability(
      field: 'imageStyle',
      label: '插图样式（imageStyle）',
      status: rules.contentImageStyle.isEmpty
          ? NovelCapabilityStatus.supported
          : NovelCapabilityStatus.unsupported,
      detail: rules.contentImageStyle.isEmpty
          ? '未配置'
          : '正文暂不渲染插图，图片只落为「[图片]」占位；该字段暂不支持',
    ),
    NovelSourceCapability(
      field: 'payAction',
      label: '付费操作（payAction）',
      status: rules.contentPayAction.isEmpty
          ? NovelCapabilityStatus.supported
          : NovelCapabilityStatus.unsupported,
      detail: rules.contentPayAction.isEmpty
          ? '未配置'
          : '未接入书源购买流程，VIP 章节可能拿不到正文；该字段暂不支持',
    ),
  ];
}
