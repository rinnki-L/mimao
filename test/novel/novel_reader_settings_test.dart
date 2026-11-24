// 阅读设置模型：序列化、边界收敛、背景明暗与文字色。

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/reader/novel_reader_settings.dart';

void main() {
  test('默认设置：滚动模式、深灰背景、20 号字', () {
    const settings = NovelReaderSettings();
    expect(settings.pageMode, NovelPageMode.scroll);
    expect(settings.fontSize, 20);
    expect(settings.background.name, '深灰');
    expect(settings.darkBackground, isTrue);
    expect(settings.textColorArgb, isNot(settings.backgroundColorArgb));
  });

  test('JSON 往返保持字段', () {
    const settings = NovelReaderSettings(
      fontSize: 26,
      fontFamily: 'SimSun',
      lineHeight: 2.1,
      paragraphSpacing: 20,
      horizontalPadding: 32,
      backgroundIndex: 4,
      dimBrightness: 60,
      pageMode: NovelPageMode.page,
      pageAnimation: false,
      pageAnimationMs: 400,
      autoPageSeconds: 30,
      showFooter: false,
      footerLeft: NovelFooterLeft.book,
      footerRight: NovelFooterRight.percent,
      eyeProtection: true,
      autoBrightness: true,
    );
    final restored = NovelReaderSettings.deserialize(settings.serialize());
    expect(restored.fontSize, 26);
    expect(restored.fontFamily, 'SimSun');
    expect(restored.lineHeight, 2.1);
    expect(restored.paragraphSpacing, 20);
    expect(restored.horizontalPadding, 32);
    expect(restored.backgroundIndex, 4);
    expect(restored.dimBrightness, 60);
    expect(restored.pageMode, NovelPageMode.page);
    expect(restored.pageAnimation, isFalse);
    expect(restored.pageAnimationMs, 400);
    expect(restored.autoPageSeconds, 30);
    expect(restored.showFooter, isFalse);
    expect(restored.footerLeft, NovelFooterLeft.book);
    expect(restored.footerRight, NovelFooterRight.percent);
    expect(restored.eyeProtection, isTrue);
    expect(restored.autoBrightness, isTrue);
  });

  test('kv 存储往返，老版本字号迁移到新设置', () async {
    final prefs = _FakePrefs();
    final store = PrefsNovelReaderSettingsStore(prefs);

    await store.save(const NovelReaderSettings(fontSize: 26));
    expect((await store.load()).fontSize, 26);

    // 只有旧 reader_font_size 时迁移为字号，其余走默认。
    final legacy = _FakePrefs()..values[novelPrefReaderFontSize] = '28';
    final migrated = await PrefsNovelReaderSettingsStore(legacy).load();
    expect(migrated.fontSize, 28);
    expect(migrated.pageMode, NovelPageMode.scroll);
  });

  test('坏数据回退默认值，越界值收敛', () {
    expect(NovelReaderSettings.deserialize('not json').fontSize, 20);
    final restored = NovelReaderSettings.fromJson(<String, Object?>{
      'fontSize': 999,
      'lineHeight': -2,
      'dimBrightness': 0,
      'backgroundIndex': 99,
      'pageMode': 'unknown',
      'autoPageSeconds': 9999,
    });
    expect(restored.fontSize, NovelReaderSettings.maxFontSize);
    expect(restored.lineHeight, NovelReaderSettings.minLineHeight);
    expect(restored.dimBrightness, 20);
    expect(restored.backgroundIndex, novelReaderBackgrounds.length - 1);
    expect(restored.pageMode, NovelPageMode.scroll);
    expect(restored.autoPageSeconds, NovelReaderSettings.maxAutoPageSeconds);
  });

  test('自定义背景优先于预设，并按亮度切换文字色', () {
    const light = NovelReaderSettings(customBackgroundArgb: 0xFFFFFFFF);
    expect(light.background.name, '自定义');
    expect(light.darkBackground, isFalse);
    expect(light.textColorArgb, 0xFF232323);

    const dark = NovelReaderSettings(customBackgroundArgb: 0xFF000000);
    expect(dark.darkBackground, isTrue);

    final cleared = light.useBackground(2);
    expect(cleared.customBackgroundArgb, isNull);
    expect(cleared.background.name, '墨绿');
  });

  test('copyWith 不丢自定义背景，字号步进被收敛', () {
    const settings = NovelReaderSettings(customBackgroundArgb: 0xFF112233);
    final bigger = settings.copyWith(fontSize: 999);
    expect(bigger.customBackgroundArgb, 0xFF112233);
    expect(bigger.fontSize, NovelReaderSettings.maxFontSize);
    final smaller = settings.copyWith(fontSize: -5);
    expect(smaller.fontSize, NovelReaderSettings.minFontSize);
  });

  test('新增排版参数 JSON 往返保持', () {
    const settings = NovelReaderSettings(
      textAlignJustify: true,
      letterSpacing: 1.2,
      textBold: true,
      textItalic: true,
      indentCount: 3,
      lineHeightIncludesPadding: false,
      titleMode: NovelTitleMode.center,
      titleSize: 10,
      titleSizeRelative: false,
      titleTopSpacing: 8,
      titleBottomSpacing: 24,
      titleSegment: true,
      titleSegmentDivider: '—',
      titleSegmentScale: 0.6,
      shadowRadius: 5,
      shadowOffsetX: -2,
      shadowOffsetY: 3,
      shadowColorArgb: 0xFF112233,
      underlineStyle: NovelUnderlineStyle.wave,
      underlineThickness: 2,
      underlineSpacing: 4,
      underlineExtend: true,
      showHeader: true,
      headerSlots: <NovelChromeSlot>[
        NovelChromeSlot.book,
        NovelChromeSlot.chapter,
        NovelChromeSlot.page,
      ],
      footerSlots: <NovelChromeSlot>[
        NovelChromeSlot.custom,
        NovelChromeSlot.percent,
        NovelChromeSlot.pageAndPercent,
      ],
      headerCustomText: '页眉',
      footerCustomText: '页脚',
      headerFontSize: 11,
      footerFontSize: 13,
      backgroundImagePath: r'C:\pics\bg.jpg',
      backgroundImageFit: NovelBackgroundFit.fitWidth,
      backgroundImageOpacity: 55,
      backgroundImageAlign: NovelBackgroundAlign.bottomRight,
      backgroundTexture: NovelBackgroundTexture.grid,
      chineseConvert: NovelChineseConvert.simplifiedToTraditional,
      twoColumn: true,
    );
    final restored = NovelReaderSettings.deserialize(settings.serialize());
    expect(restored.textAlignJustify, isTrue);
    expect(restored.letterSpacing, 1.2);
    expect(restored.textBold, isTrue);
    expect(restored.textItalic, isTrue);
    expect(restored.indentCount, 3);
    expect(restored.indent, '　　　');
    expect(restored.lineHeightIncludesPadding, isFalse);
    expect(restored.titleMode, NovelTitleMode.center);
    expect(restored.titleSize, 10);
    expect(restored.titleSizeRelative, isFalse);
    expect(restored.effectiveTitleFontSize, 10);
    expect(restored.titleTopSpacing, 8);
    expect(restored.titleBottomSpacing, 24);
    expect(restored.titleSegment, isTrue);
    expect(restored.titleSegmentDivider, '—');
    expect(restored.titleSegmentScale, 0.6);
    expect(restored.shadowRadius, 5);
    expect(restored.shadowOffsetX, -2);
    expect(restored.shadowOffsetY, 3);
    expect(restored.shadowColorArgb, 0xFF112233);
    expect(restored.underlineStyle, NovelUnderlineStyle.wave);
    expect(restored.underlineThickness, 2);
    expect(restored.underlineSpacing, 4);
    expect(restored.underlineExtend, isTrue);
    expect(restored.showHeader, isTrue);
    expect(restored.headerSlots, <NovelChromeSlot>[
      NovelChromeSlot.book,
      NovelChromeSlot.chapter,
      NovelChromeSlot.page,
    ]);
    expect(restored.footerSlots, <NovelChromeSlot>[
      NovelChromeSlot.custom,
      NovelChromeSlot.percent,
      NovelChromeSlot.pageAndPercent,
    ]);
    expect(restored.headerCustomText, '页眉');
    expect(restored.footerCustomText, '页脚');
    expect(restored.headerFontSize, 11);
    expect(restored.footerFontSize, 13);
    expect(restored.backgroundImagePath, r'C:\pics\bg.jpg');
    expect(restored.backgroundImageFit, NovelBackgroundFit.fitWidth);
    expect(restored.backgroundImageOpacity, 55);
    expect(restored.backgroundImageAlign, NovelBackgroundAlign.bottomRight);
    expect(restored.backgroundTexture, NovelBackgroundTexture.grid);
    expect(
      restored.chineseConvert,
      NovelChineseConvert.simplifiedToTraditional,
    );
    expect(restored.twoColumn, isTrue);
  });

  test('老 JSON 缺新字段：回退默认，旧页脚键迁移到三槽', () {
    final restored = NovelReaderSettings.fromJson(<String, Object?>{
      'fontSize': 26,
      'fontFamily': 'SimSun',
      'footerLeft': 'book',
      'footerRight': 'percent',
    });
    expect(restored.fontSize, 26);
    expect(restored.fontFamily, 'SimSun');
    expect(restored.textAlignJustify, isFalse);
    expect(restored.letterSpacing, 0);
    expect(restored.indentCount, 2);
    expect(restored.indent, '　　');
    expect(restored.titleMode, NovelTitleMode.left);
    expect(restored.titleSizeRelative, isTrue);
    expect(restored.showHeader, isFalse);
    expect(restored.footerSlots, <NovelChromeSlot>[
      NovelChromeSlot.book,
      NovelChromeSlot.none,
      NovelChromeSlot.percent,
    ]);
    expect(restored.headerSlots[1], NovelChromeSlot.chapter);
    expect(restored.backgroundImagePath, isNull);
    expect(restored.backgroundTexture, NovelBackgroundTexture.none);
    expect(restored.chineseConvert, NovelChineseConvert.none);
    expect(restored.twoColumn, isFalse);
  });

  test('新参数越界值一律 clamp', () {
    final restored = NovelReaderSettings.fromJson(<String, Object?>{
      'letterSpacing': 99,
      'indentCount': 99,
      'titleSize': 999,
      'titleSizeRelative': false,
      'titleTopSpacing': -5,
      'titleSegmentScale': 0,
      'shadowRadius': 99,
      'shadowOffsetX': -99,
      'underlineThickness': 0,
      'underlineSpacing': 99,
      'headerFontSize': 99,
      'footerFontSize': 1,
      'backgroundImageOpacity': -20,
      'headerSlots': <String>['book'],
    });
    expect(restored.letterSpacing, NovelReaderSettings.maxLetterSpacing);
    expect(restored.indentCount, NovelReaderSettings.maxIndentCount);
    expect(restored.titleSize, NovelReaderSettings.maxTitleSizeAbsolute);
    expect(restored.titleTopSpacing, NovelReaderSettings.minTitleSpacing);
    expect(
      restored.titleSegmentScale,
      NovelReaderSettings.minTitleSegmentScale,
    );
    expect(restored.shadowRadius, NovelReaderSettings.maxShadowRadius);
    expect(restored.shadowOffsetX, NovelReaderSettings.minShadowOffset);
    expect(
      restored.underlineThickness,
      NovelReaderSettings.minUnderlineThickness,
    );
    expect(restored.underlineSpacing, NovelReaderSettings.maxUnderlineSpacing);
    expect(restored.headerFontSize, NovelReaderSettings.maxChromeFontSize);
    expect(restored.footerFontSize, NovelReaderSettings.minChromeFontSize);
    expect(restored.backgroundImageOpacity, 0);
    // 槽位列表统一补齐成 3 个。
    expect(restored.headerSlots, <NovelChromeSlot>[
      NovelChromeSlot.book,
      NovelChromeSlot.none,
      NovelChromeSlot.none,
    ]);
  });

  test('copyWith 可清空自定义背景/阴影色/背景图', () {
    const settings = NovelReaderSettings(
      customBackgroundArgb: 0xFF112233,
      shadowColorArgb: 0xFF445566,
      backgroundImagePath: r'C:\a.png',
    );
    final cleared = settings.copyWith(
      clearCustomBackground: true,
      clearShadowColor: true,
      clearBackgroundImage: true,
    );
    expect(cleared.customBackgroundArgb, isNull);
    expect(cleared.shadowColorArgb, isNull);
    expect(cleared.backgroundImagePath, isNull);
    expect(settings.customBackgroundArgb, 0xFF112233);
  });
}

class _FakePrefs implements NovelPrefsApi {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
