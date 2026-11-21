/// 音乐偏好页的官方标签候选（来自风格推荐端点的标签组）。
///
/// 上游没有独立的「偏好官方标签表」，偏好页要展示可点选的候选，只能复用
/// `everyday_style_recommend` 返回的标签组（[MusicStyleTagGroup]）。本文件
/// 按组名把标签归类成「语种」与「曲风」两类候选：
/// - 语种类：组名含「语种/语言/方言」→ 供 `lang`、`song_lang` 使用；
/// - 曲风类：组名含「曲风/风格/流派」→ 供 `style` 使用；
/// - 其它组（场景/心情等）不进入候选，避免把非偏好语义的标签塞进权重表。
///
/// 关键限制：偏好权重键在上游是「不透明 ID」，风格标签的 id 体系**未验证**
/// 与偏好权重同源。因此候选只作为「便捷添加入口」——写入的仍是标签 id，
/// 不校验、不改写已有权重键；读取到的任何键都必须原样保留展示。
library;

import 'package:mimao/music/models/discovery_models.dart';

/// 单个偏好标签候选（名称只用于展示，id 才是写入权重行的键）。
class MusicPreferenceTagCandidate {
  const MusicPreferenceTagCandidate({required this.id, required this.name});

  /// 标签 id（写入偏好权重的键；上游语义为不透明 ID）。
  final String id;

  /// 标签名称（候选 chip 展示用；可能为空，此时回退显示 id）。
  final String name;

  /// chip 展示文本：名称缺失时回退 id，绝不显示空 chip。
  String get label => name.isEmpty ? id : name;
}

/// 偏好候选目录：按权重字段（lang/style/song_lang）提供候选标签。
class MusicPreferenceTagCatalog {
  const MusicPreferenceTagCatalog({
    required this.languageTags,
    required this.styleTags,
  });

  /// 空目录（候选加载失败/为空时的静默态）。
  static const MusicPreferenceTagCatalog empty = MusicPreferenceTagCatalog(
    languageTags: <MusicPreferenceTagCandidate>[],
    styleTags: <MusicPreferenceTagCandidate>[],
  );

  /// 语种类候选（`lang` / `song_lang`）。
  final List<MusicPreferenceTagCandidate> languageTags;

  /// 曲风类候选（`style`）。
  final List<MusicPreferenceTagCandidate> styleTags;

  /// 把风格推荐接口的标签组归类成偏好候选。
  ///
  /// 组名匹配不区分大小写（接口返回中文组名，这里兼容可能的英文别名）；
  /// 无 id / 重复 id 的标签跳过，保证同一候选只出现一次。
  factory MusicPreferenceTagCatalog.fromGroups(
    List<MusicStyleTagGroup> groups,
  ) {
    final List<MusicPreferenceTagCandidate> language =
        <MusicPreferenceTagCandidate>[];
    final List<MusicPreferenceTagCandidate> style =
        <MusicPreferenceTagCandidate>[];
    final Set<String> languageIds = <String>{};
    final Set<String> styleIds = <String>{};

    for (final MusicStyleTagGroup group in groups) {
      final _TagKind? kind = _kindOfGroup(group.name);
      if (kind == null) continue;
      final List<MusicPreferenceTagCandidate> target = kind == _TagKind.language
          ? language
          : style;
      final Set<String> seen = kind == _TagKind.language
          ? languageIds
          : styleIds;
      for (final MusicStyleTag tag in group.child) {
        if (tag.id.isEmpty) continue;
        if (!seen.add(tag.id)) continue;
        target.add(MusicPreferenceTagCandidate(id: tag.id, name: tag.name));
      }
    }
    return MusicPreferenceTagCatalog(languageTags: language, styleTags: style);
  }

  /// 某个权重字段可用的候选（未知字段返回空表）。
  ///
  /// `song_lang`（推荐语种）与 `lang`（语言偏好）共用语种类候选。
  List<MusicPreferenceTagCandidate> candidatesFor(String wireKey) {
    switch (wireKey) {
      case 'lang':
      case 'song_lang':
        return languageTags;
      case 'style':
        return styleTags;
      default:
        return const <MusicPreferenceTagCandidate>[];
    }
  }

  /// 权重键 id 对应的候选名称；没有对应候选/名称为空 → null（回退显示原 id）。
  String? nameForId(String wireKey, String id) {
    for (final MusicPreferenceTagCandidate candidate in candidatesFor(
      wireKey,
    )) {
      if (candidate.id == id) {
        return candidate.name.isEmpty ? null : candidate.name;
      }
    }
    return null;
  }

  /// 组名归类：只认语种/曲风两类，其余组不进入候选。
  static _TagKind? _kindOfGroup(String name) {
    final String normalized = name.toLowerCase();
    if (normalized.contains('语种') ||
        normalized.contains('语言') ||
        normalized.contains('方言') ||
        normalized.contains('language')) {
      return _TagKind.language;
    }
    if (normalized.contains('曲风') ||
        normalized.contains('风格') ||
        normalized.contains('流派') ||
        normalized.contains('style') ||
        normalized.contains('genre')) {
      return _TagKind.style;
    }
    return null;
  }
}

/// 候选归类：语种 / 曲风。
enum _TagKind { language, style }
