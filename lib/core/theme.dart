// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 shell 各页同款说明：Kazumi/Venera 上游镜像全部用它，保持类型一致。
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

/// mimao 的圆角阶梯（MD3 shape scale 收紧版）。页面不再手搓半径数字，
/// 统一引用这里的常量，保证整 app 一个节奏：
///   sm  = 10  小容器（封面缩略图、计数徽标、二维码底板）
///   md  = 14  行级容器（章节/剧集行、列表小卡、迷你播放条）
///   lg  = 20  卡片（海报卡、分组块、时间线卡）
///   xl  = 28  大容器（bento 入口卡、对话框、底部抽屉顶角、播放页大封面）
///   pill = 999 药丸（tag chip、胶囊形容器）
abstract final class MimaoRadii {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}

/// 圆角阶梯常量的 BorderRadius 便捷形态。
abstract final class MimaoShapes {
  static final BorderRadius sm = BorderRadius.circular(MimaoRadii.sm);
  static final BorderRadius md = BorderRadius.circular(MimaoRadii.md);
  static final BorderRadius lg = BorderRadius.circular(MimaoRadii.lg);
  static final BorderRadius xl = BorderRadius.circular(MimaoRadii.xl);
  static final BorderRadius pill = BorderRadius.circular(MimaoRadii.pill);
}

/// mimao 的全局字体与字重阶梯。
///
/// 字体族显式锁定为 Microsoft YaHei（Windows 系统自带、DirectWrite 可按名加载，
/// 且拉丁与中文字形齐全）。此前不设 fontFamily，Flutter 在 Windows 用
/// {Segoe UI, Arial} 作默认族——两者都无中文字形，中文全部走系统 fallback，
/// 再叠加雅黑的离散字重（Regular 400 / Bold 700 / Light 290 是三个独立文件），
/// 500/600 这类中间字重会被就近乱配到不同文件，造成同一句里个别字（如「剧」）
/// 忽然变粗/变细、刺眼。锁定家族 + 只用真实存在的两档字重即可根治。
///
/// 字号 / 行高 / 字距沿用 M3 基线（Typography.material2021），只收口字重：
///   标题类（display / headline / title）= w700 bold   → msyhbd.ttc
///   正文 / 标签 / 按钮 / chip（body / label）= w400   → msyh.ttc
abstract final class MimaoFonts {
  static const String family = 'Microsoft YaHei';
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight bold = FontWeight.w700;
}

TextTheme _buildMimaoTextTheme(ColorScheme scheme) {
  final m3 = Typography.material2021(colorScheme: scheme).black;
  // 先在整份 TextTheme 上锁定字体族，再逐档收口字重到真实存在的两档。
  final themed = m3.apply(fontFamily: MimaoFonts.family);
  return themed.copyWith(
    displayLarge: themed.displayLarge?.copyWith(fontWeight: MimaoFonts.bold),
    displayMedium: themed.displayMedium?.copyWith(fontWeight: MimaoFonts.bold),
    displaySmall: themed.displaySmall?.copyWith(fontWeight: MimaoFonts.bold),
    headlineLarge: themed.headlineLarge?.copyWith(fontWeight: MimaoFonts.bold),
    headlineMedium: themed.headlineMedium?.copyWith(
      fontWeight: MimaoFonts.bold,
    ),
    headlineSmall: themed.headlineSmall?.copyWith(fontWeight: MimaoFonts.bold),
    titleLarge: themed.titleLarge?.copyWith(fontWeight: MimaoFonts.bold),
    titleMedium: themed.titleMedium?.copyWith(fontWeight: MimaoFonts.bold),
    titleSmall: themed.titleSmall?.copyWith(fontWeight: MimaoFonts.bold),
    bodyLarge: themed.bodyLarge?.copyWith(fontWeight: MimaoFonts.regular),
    bodyMedium: themed.bodyMedium?.copyWith(fontWeight: MimaoFonts.regular),
    bodySmall: themed.bodySmall?.copyWith(fontWeight: MimaoFonts.regular),
    labelLarge: themed.labelLarge?.copyWith(fontWeight: MimaoFonts.regular),
    labelMedium: themed.labelMedium?.copyWith(fontWeight: MimaoFonts.regular),
    labelSmall: themed.labelSmall?.copyWith(fontWeight: MimaoFonts.regular),
  );
}

/// 构建 mimao 的 MD3 主题。种子色来自设置（基础色板 / 系统强调色 / 动态取色），
/// 亮度由主题模式（跟随系统 / 浅色 / 深色）决定——app.dart 据此组装
/// theme / darkTheme 两套。
///
/// 这里集中所有组件级 MD3 定制，页面级不再各自覆写 shape：
///   卡片 = 无阴影填充卡（surfaceContainerLow，r20）
///   对话框 / 底部抽屉 = r28 + 拖拽把手
///   SnackBar = 浮动胶囊（r14，inverseSurface）
///   ListTile / 卡片内行 = r14 水波纹
///   输入框 = MD3 填充式（surfaceContainerHigh，r10，聚焦 2px 描边）
///   SearchBar = 平面化（无阴影 + outlineVariant 细描边）
///   ExpansionTile = MD3 手风琴（描边 r20，抽屉分组圆角块）
///   NavigationBar = 64 高（桌面窗口不臃肿）
ThemeData buildMimaoTheme({
  required Color seedColor,
  required Brightness brightness,
}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  );
  final hairline = BorderSide(color: scheme.outlineVariant);
  final textTheme = _buildMimaoTextTheme(scheme);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // 统一字体族 + 两档字重（标题 w700 / 正文标签 w400），字号行高留 M3 基线。
    textTheme: textTheme,
    // ── 容器 ──────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: MimaoShapes.lg),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: MimaoShapes.xl),
      backgroundColor: scheme.surfaceContainerHigh,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: scheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MimaoRadii.xl),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: scheme.inverseSurface,
      shape: RoundedRectangleBorder(borderRadius: MimaoShapes.md),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: MimaoShapes.md),
        ),
        side: WidgetStatePropertyAll(hairline),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      // 番剧播放器的菜单悬浮在视频画面上：无阴影必须补细描边，否则
      // 亮色帧前会「融进画面」。PopupMenuThemeData 没有 side 参数，
      // 描边只能挂在 shape 上。
      shape: RoundedRectangleBorder(
        borderRadius: MimaoShapes.md,
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    // ── 行 / 列表 ─────────────────────────────────────────────────
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: MimaoShapes.md),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: RoundedRectangleBorder(
        side: hairline,
        borderRadius: MimaoShapes.lg,
      ),
      collapsedShape: RoundedRectangleBorder(
        side: hairline,
        borderRadius: MimaoShapes.lg,
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 64,
      indicatorColor: scheme.secondaryContainer,
    ),
    // ── 输入 ──────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      // hint / 输入文字显式走统一字体族与字重，避免 SearchBar/TextField 的
      // 默认 hintStyle 绕过 textTheme、回落到系统 fallback 导致个别字变粗。
      hintStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      border: OutlineInputBorder(
        borderRadius: MimaoShapes.sm,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: MimaoShapes.sm,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: MimaoShapes.sm,
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
      side: WidgetStatePropertyAll(hairline),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: MimaoShapes.xl),
      ),
      textStyle: WidgetStatePropertyAll(textTheme.bodyMedium),
      hintStyle: WidgetStatePropertyAll(
        textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),
    ),
    // ── 按钮 / chip ───────────────────────────────────────────────
    // FilledButton / OutlinedButton / TextButton / SegmentedButton 保持
    // MD3 默认（全圆药丸），不覆写；页面层也据此不再手搓 RoundedRectangleBorder。
    chipTheme: ChipThemeData(
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: MimaoShapes.pill),
    ),
  );
}

/// 全局滚动手势：桌面端默认 [ScrollBehavior] 的拖动设备不含鼠标，横向滚动区
/// （搜索来源筛选行、发现/分类的源 chip 行、海报行）在 Windows 上「鼠标拖不动」，
/// 排序靠后的源够不着。把 mouse 加入 dragDevices，所有滚动区与触屏同款可拖。
class MimaoScrollBehavior extends MaterialScrollBehavior {
  const MimaoScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}
