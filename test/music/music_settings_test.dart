/// 本地设置落盘测试：settings.json 的听歌上报 / 歌词开关 / 歌词模式 /
/// 播放模式读写。
///
/// 只碰临时目录，不初始化 path_provider、不联网；覆盖缺省值、未知枚举回退、
/// 四个键互不覆盖（同一文件整写）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/lyric/lyric_models.dart';
import 'package:mimao/music/music_settings.dart';
import 'package:mimao/music/player/play_mode.dart';

void main() {
  late Directory root;
  late MusicFileSettings settings;

  File settingsFile() =>
      File('${root.path}${Platform.pathSeparator}settings.json');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mimao_music_settings_');
    settings = MusicFileSettings(root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('无设置文件：四个字段都回默认值（上报开/歌词开/原文/列表循环）', () async {
    await settings.ensureLoaded();

    expect(settings.listenReportEnabled, isTrue);
    expect(settings.lyricEnabled, isTrue);
    expect(settings.lyricMode, LyricMode.original);
    expect(settings.playMode, PlayMode.listLoop);
  });

  test('歌词开关/模式与播放模式写入 settings.json，并能被新实例读回', () async {
    await settings.setLyricEnabled(false);
    await settings.setLyricMode(LyricMode.originalWithTransliteration);
    await settings.setPlayMode(PlayMode.shuffle);

    final decoded =
        jsonDecode(await settingsFile().readAsString()) as Map<String, dynamic>;
    expect(decoded['lyricEnabled'], isFalse);
    expect(decoded['lyricMode'], 'originalWithTransliteration');
    expect(decoded['playMode'], 'shuffle');
    expect(decoded.containsKey('listenReportEnabled'), isTrue);

    final reloaded = MusicFileSettings(root);
    await reloaded.ensureLoaded();
    expect(reloaded.lyricEnabled, isFalse);
    expect(reloaded.lyricMode, LyricMode.originalWithTransliteration);
    expect(reloaded.playMode, PlayMode.shuffle);

    // 再切换听歌上报不会丢其它偏好（整文件重写）。
    await reloaded.setListenReportEnabled(false);
    final decodedAgain =
        jsonDecode(await settingsFile().readAsString()) as Map<String, dynamic>;
    expect(decodedAgain['listenReportEnabled'], isFalse);
    expect(decodedAgain['lyricEnabled'], isFalse);
    expect(decodedAgain['lyricMode'], 'originalWithTransliteration');
    expect(decodedAgain['playMode'], 'shuffle');

    // 再切换播放模式也不会丢其它键。
    await reloaded.setPlayMode(PlayMode.repeatOne);
    final decodedThird =
        jsonDecode(await settingsFile().readAsString()) as Map<String, dynamic>;
    expect(decodedThird['playMode'], 'repeatOne');
    expect(decodedThird['listenReportEnabled'], isFalse);
    expect(decodedThird['lyricEnabled'], isFalse);
    expect(decodedThird['lyricMode'], 'originalWithTransliteration');
  });

  test('未知 lyricMode/playMode 名、非法类型：回默认值，不影响其它字段', () async {
    await settingsFile().writeAsString(
      jsonEncode(<String, Object?>{
        'listenReportEnabled': false,
        'lyricEnabled': 'yes',
        'lyricMode': 'translationOnly',
        'playMode': 'randomUnknown',
      }),
    );

    await settings.ensureLoaded();

    expect(settings.listenReportEnabled, isFalse);
    expect(settings.lyricEnabled, isTrue, reason: '非法 bool 类型被忽略');
    expect(settings.lyricMode, LyricMode.original, reason: '未知模式名回原文');
    expect(settings.playMode, PlayMode.listLoop, reason: '未知播放模式名回列表循环');
  });

  test('设置文件损坏：整体回默认值且不抛错', () async {
    await settingsFile().writeAsString('{oops');

    await settings.ensureLoaded();

    expect(settings.listenReportEnabled, isTrue);
    expect(settings.lyricEnabled, isTrue);
    expect(settings.lyricMode, LyricMode.original);
    expect(settings.playMode, PlayMode.listLoop);
  });

  test('LazyMusicSettings：解析前走默认值，解析后透传并落盘', () async {
    final lazy = LazyMusicSettings(() async => MusicFileSettings(root));

    // 解析前不碰 factory：默认开/原文/列表循环。
    expect(lazy.lyricEnabled, isTrue);
    expect(lazy.lyricMode, LyricMode.original);
    expect(lazy.playMode, PlayMode.listLoop);

    await lazy.setLyricEnabled(false);
    await lazy.setLyricMode(LyricMode.originalWithTranslation);
    await lazy.setPlayMode(PlayMode.shuffle);
    expect(lazy.lyricEnabled, isFalse);
    expect(lazy.lyricMode, LyricMode.originalWithTranslation);
    expect(lazy.playMode, PlayMode.shuffle);

    final reloaded = MusicFileSettings(root);
    await reloaded.ensureLoaded();
    expect(reloaded.lyricEnabled, isFalse);
    expect(reloaded.lyricMode, LyricMode.originalWithTranslation);
    expect(reloaded.playMode, PlayMode.shuffle);
  });
}
