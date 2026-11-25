// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart。
/// 主题包缩略预览：不截真实阅读页，而是把设置「画」成一张小样张。
///
/// 好处：导入别人的包时不需要对方提供截图也能看到效果（预览图缺失时用它兜底）；
/// 导出时再把这张小样张抓成 PNG 塞进包里，别人收到就有图可看。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mimao/novel/reader/novel_reader_chrome.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';

class NovelThemePreview extends StatelessWidget {
  const NovelThemePreview({
    super.key,
    required this.settings,
    this.width = 240,
    this.height = 320,
  });

  final NovelReaderSettings settings;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final background = novelReaderBackgroundColor(settings);
    final textColor = novelReaderTextColor(settings);
    final secondary = novelReaderSecondaryColor(settings);
    const scale = 0.55;
    final titleSize = (settings.effectiveTitleFontSize * scale)
        .clamp(10.0, 26.0)
        .toDouble();
    final bodySize = (settings.fontSize * scale).clamp(8.0, 20.0).toDouble();
    final padding = (settings.horizontalPadding * 0.6)
        .clamp(10.0, 28.0)
        .toDouble();
    final titleAlign = switch (settings.titleMode) {
      NovelTitleMode.left => TextAlign.left,
      NovelTitleMode.center => TextAlign.center,
      NovelTitleMode.hide => TextAlign.left,
    };
    final family = settings.fontFamily.isEmpty ? null : settings.fontFamily;
    final imagePath = settings.backgroundImagePath;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: background),
            if (imagePath != null && File(imagePath).existsSync())
              IgnorePointer(
                child: Opacity(
                  opacity: settings.backgroundImageOpacity / 100,
                  child: Image.file(
                    File(imagePath),
                    fit: novelBackgroundBoxFit(settings.backgroundImageFit),
                    alignment: novelBackgroundAlignment(
                      settings.backgroundImageAlign,
                    ),
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            if (settings.backgroundTexture != NovelBackgroundTexture.none)
              IgnorePointer(
                child: CustomPaint(
                  painter: NovelBackgroundTexturePainter(
                    texture: settings.backgroundTexture,
                    color: textColor,
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(padding, padding, padding, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (settings.showHeader)
                    Text(
                      '章节 · 书名',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: family,
                        fontSize: 8,
                        color: secondary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  if (settings.titleMode != NovelTitleMode.hide) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      '第一章  风起',
                      textAlign: titleAlign,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: family,
                        fontSize: titleSize,
                        height: 1.2,
                        color: textColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Expanded(
                    child: ClipRect(
                      child: ListView(
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        children: <Widget>[
                          for (final line in _sampleLines)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: (settings.paragraphSpacing * 0.5)
                                    .clamp(2.0, 12.0)
                                    .toDouble(),
                              ),
                              child: Text(
                                '${settings.indent}$line',
                                maxLines: 2,
                                overflow: TextOverflow.fade,
                                style: TextStyle(
                                  fontFamily: family,
                                  fontSize: bodySize,
                                  height: settings.lineHeight,
                                  color: textColor,
                                  letterSpacing: settings.letterSpacing * 0.5,
                                  fontWeight: settings.textBold
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  fontStyle: settings.textItalic
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                  decoration:
                                      settings.underlineStyle ==
                                          NovelUnderlineStyle.none
                                      ? TextDecoration.none
                                      : TextDecoration.underline,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (settings.showFooter)
                    Text(
                      '第 12 页 · 37%',
                      style: TextStyle(
                        fontFamily: family,
                        fontSize: 8,
                        color: secondary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const List<String> _sampleLines = <String>[
    '这是主题包的预览样张，用来快速判断背景、字号与行距是否合眼。',
    '正文颜色、标题样式和页边距都会跟着预览一起变。',
    '导入后可以在阅读页右上角继续微调，改动只影响你自己的设置。',
  ];
}
