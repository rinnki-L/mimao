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
}

class _FakePrefs implements NovelPrefsApi {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
