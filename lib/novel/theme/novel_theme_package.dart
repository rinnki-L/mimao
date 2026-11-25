// 阅读主题包（JSON）的纯编解码与版本校验。
//
// 包内容 = 一份 `NovelReaderSettings`（区 1 那套模型，不另造设置）+ 可选的
// 键位映射 + 可选的预览图（PNG base64）。`version` 是**包格式**版本，不是
// 设置字段版本；导入时高于当前支持版本一律拒绝，并给出可读提示——不做
// "尽力猜"的静默降级，免得新版本字段被旧版吃掉后用户以为应用了。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/novel/reader/novel_keyboard_assist.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';

/// 包格式标识（写进 JSON 的 `format`，导入时校验）。
const String novelThemePackageFormat = 'mimao-novel-reader-theme';

/// 当前支持的包格式版本。
const int novelThemePackageVersion = 1;

/// 包解析失败的类型（页面据此给不同提示）。
enum NovelThemePackageError {
  /// 不是合法 JSON。
  notJson,

  /// JSON 合法但不是 mimao 主题包。
  notTheme,

  /// 包版本高于当前支持版本。
  versionTooNew,

  /// 包版本非法（<=0）。
  versionTooOld,

  /// 结构坏了（缺 settings / 版本号不是数字等）。
  corrupt,
}

/// 主题包解析异常：带可读文案与（可选的）包内版本号。
class NovelThemePackageException implements Exception {
  const NovelThemePackageException(
    this.error,
    this.message, {
    this.foundVersion,
  });

  final NovelThemePackageError error;
  final String message;
  final int? foundVersion;

  @override
  String toString() => 'NovelThemePackageException(${error.name}): $message';
}

/// 一份主题包。
class NovelThemePackage {
  const NovelThemePackage({
    required this.name,
    required this.settings,
    this.version = novelThemePackageVersion,
    this.exportedAt,
    this.keyBindings = const <NovelKeyboardBinding>[],
    this.previewPng,
  });

  final String name;

  final NovelReaderSettings settings;

  /// 包格式版本（写出的包固定用 [novelThemePackageVersion]）。
  final int version;

  final DateTime? exportedAt;

  /// 可选的键位映射（主题包显式带上；用户导入时可选择是否应用）。
  final List<NovelKeyboardBinding> keyBindings;

  /// 可选预览图（PNG 字节）。缺失时页面现场渲染缩略图。
  final Uint8List? previewPng;

  NovelThemePackage copyWith({
    String? name,
    NovelReaderSettings? settings,
    List<NovelKeyboardBinding>? keyBindings,
    Uint8List? previewPng,
    bool clearPreview = false,
  }) => NovelThemePackage(
    name: name ?? this.name,
    settings: settings ?? this.settings,
    version: version,
    exportedAt: exportedAt,
    keyBindings: keyBindings ?? this.keyBindings,
    previewPng: clearPreview ? null : (previewPng ?? this.previewPng),
  );

  /// 序列化成落库/保存文件用的 JSON。
  ///
  /// [includePreview] 关掉时不写预览图（文件体积敏感的场景）；
  /// [includeKeyBindings] 关掉时键位不进包。
  Map<String, Object?> toJson({
    bool includePreview = true,
    bool includeKeyBindings = true,
  }) => <String, Object?>{
    'format': novelThemePackageFormat,
    'version': version,
    'name': name,
    'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
    'settings': settings.toJson(),
    if (includeKeyBindings && keyBindings.isNotEmpty)
      'keyBindings': <Object?>[
        for (final item in normalizedNovelKeyboardBindings(keyBindings))
          item.toJson(),
      ],
    if (includePreview && previewPng != null && previewPng!.isNotEmpty)
      'preview': <String, Object?>{
        'mime': 'image/png',
        'data': base64Encode(previewPng!),
      },
  };

  String encode({bool includePreview = true, bool includeKeyBindings = true}) =>
      const JsonEncoder.withIndent('  ').convert(
        toJson(
          includePreview: includePreview,
          includeKeyBindings: includeKeyBindings,
        ),
      );

  /// 解析主题包 JSON。失败抛 [NovelThemePackageException]。
  static NovelThemePackage decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object {
      throw const NovelThemePackageException(
        NovelThemePackageError.notJson,
        '文件不是合法的 JSON',
      );
    }
    if (decoded is! Map) {
      throw const NovelThemePackageException(
        NovelThemePackageError.notTheme,
        '不是 mimao 阅读主题包',
      );
    }
    return fromJson(Map<String, Object?>.from(decoded));
  }

  /// 从已解析的 JSON 构造；版本与结构校验都在这里。
  static NovelThemePackage fromJson(Map<String, Object?> json) {
    final format = '${json['format'] ?? ''}'.trim();
    if (format.isEmpty || format != novelThemePackageFormat) {
      throw const NovelThemePackageException(
        NovelThemePackageError.notTheme,
        '不是 mimao 阅读主题包（缺少 format 或格式不符）',
      );
    }
    final rawVersion = json['version'];
    final version = rawVersion is num
        ? rawVersion.toInt()
        : int.tryParse('${rawVersion ?? ''}');
    if (version == null) {
      throw const NovelThemePackageException(
        NovelThemePackageError.corrupt,
        '主题包缺少版本号',
      );
    }
    if (version <= 0) {
      throw NovelThemePackageException(
        NovelThemePackageError.versionTooOld,
        '主题包版本号 v$version 无效',
        foundVersion: version,
      );
    }
    if (version > novelThemePackageVersion) {
      throw NovelThemePackageException(
        NovelThemePackageError.versionTooNew,
        '这个主题包来自更新的版本（v$version），当前只支持 v$novelThemePackageVersion；'
        '请升级应用后再导入。',
        foundVersion: version,
      );
    }
    final settingsJson = json['settings'];
    if (settingsJson is! Map) {
      throw const NovelThemePackageException(
        NovelThemePackageError.corrupt,
        '主题包里没有设置内容（settings）',
      );
    }
    final bindings = <NovelKeyboardBinding>[];
    final rawBindings = json['keyBindings'];
    if (rawBindings is List) {
      for (final item in rawBindings) {
        final parsed = NovelKeyboardBinding.fromJson(item);
        if (parsed != null) bindings.add(parsed);
      }
    }
    Uint8List? preview;
    final rawPreview = json['preview'];
    if (rawPreview is Map) {
      final data = '${rawPreview['data'] ?? ''}'.trim();
      if (data.isNotEmpty) {
        try {
          preview = base64Decode(data);
        } on Object {
          preview = null;
        }
      }
    }
    final exportedAtRaw = '${json['exportedAt'] ?? ''}'.trim();
    return NovelThemePackage(
      name: _cleanName('${json['name'] ?? ''}'),
      settings: NovelReaderSettings.fromJson(
        Map<String, Object?>.from(settingsJson),
      ),
      version: version,
      exportedAt: DateTime.tryParse(exportedAtRaw),
      keyBindings: normalizedNovelKeyboardBindings(bindings),
      previewPng: preview,
    );
  }

  static String _cleanName(String raw) {
    final text = raw.trim();
    return text.isEmpty ? '未命名主题' : text;
  }
}

/// 一份可读的「这个包会改什么」摘要（导入预览用）。
///
/// 只列用户能感知的项；未知字段不编造。空列表 = 与当前设置完全一致。
List<String> describeNovelThemeDifferences(
  NovelReaderSettings current,
  NovelReaderSettings next,
) {
  final currentJson = current.toJson();
  final nextJson = next.toJson();
  final labels = <String, String>{
    'fontSize': '字号',
    'fontFamily': '字体',
    'lineHeight': '行距',
    'paragraphSpacing': '段距',
    'horizontalPadding': '左右边距',
    'backgroundIndex': '背景',
    'customBackgroundArgb': '自定义背景色',
    'pageMode': '翻页方式',
    'pageAnimStyle': '翻页动画',
    'letterSpacing': '字距',
    'indentCount': '段首缩进',
    'chineseConvert': '简繁转换',
    'twoColumn': '双栏',
    'titleMode': '标题样式',
    'showHeader': '页眉',
    'showFooter': '页脚',
    'menuIconItemsPerRow': '菜单每行图标数',
    'menuIconRowCount': '菜单行数',
  };
  final result = <String>[];
  for (final entry in labels.entries) {
    if (!_sameValue(currentJson[entry.key], nextJson[entry.key])) {
      result.add(entry.value);
    }
  }
  return result;
}

bool _sameValue(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
  return a == b;
}
