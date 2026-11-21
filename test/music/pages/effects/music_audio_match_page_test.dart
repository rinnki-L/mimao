// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// 听歌识曲页 widget 测试（L1）：fake capture + fake playbackExt，
/// 不联网、不碰 record 插件、不用真实计时器（recordDuration 注入
/// Duration.zero）。
///
/// 覆盖：请求装配（PCM 原样 base64、长度、canonical）、候选渲染与置信度、
/// 点候选播放（player fake 收到歌曲）、权限拒绝、无匹配、识别失败、录音失败、
/// PCM 超上限截断、识别中按钮禁用、空 PCM。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/models/playback_ext_models.dart';
import 'package:mimao/music/pages/music_audio_match_page.dart';

import 'fakes.dart';

Widget _host(Widget page) => MaterialApp(
  theme: buildMimaoTheme(
    seedColor: const Color(0xFF4A6CF7),
    brightness: Brightness.light,
  ),
  home: page,
);

Widget _page({
  required FakePlaybackExtApi playbackExt,
  FakeAudioCapture? capture,
  FakePlayerUi? player,
}) => MusicAudioMatchPage(
  playbackExt: playbackExt,
  capture: capture,
  player: player,
  // 测试不碰真实计时器：录音时长归零。
  recordDuration: Duration.zero,
);

Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(_host(page));
  await tester.pump();
}

/// 跑完一次识别流程：tap 后多 pump 几帧，让「权限→录音→停止→识别」的
/// 异步链全部落地。每次 pump 推进 1ms 假时钟——页面里的
/// `Future.delayed(recordDuration)`（Duration.zero）也要等时钟走一格才触发。
Future<void> _runFlow(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('audio-match-start')));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

void main() {
  testWidgets('识别成功：PCM 原样进入请求，候选渲染歌名/歌手/专辑/置信度', (tester) async {
    final capture = FakeAudioCapture();
    final ext = FakePlaybackExtApi(
      audioMatchResults: <List<MusicRecognitionMatch>>[
        <MusicRecognitionMatch>[fakeMatch()],
      ],
    );
    await _pumpPage(tester, _page(playbackExt: ext, capture: capture));

    await _runFlow(tester);

    // 录音缝被完整走一遍。
    expect(capture.permissionCalls, 1);
    expect(capture.startCalls, 1);
    expect(capture.stopCalls, 1);
    // 请求装配：base64 canonical、解码后与 fake PCM 完全一致。
    expect(ext.audioMatchQueries, hasLength(1));
    final base64Text = ext.audioMatchQueries.single.pcmBase64;
    expect(
      base64Text.length % 4,
      0,
      reason: 'STANDARD base64 要求 canonical padding',
    );
    expect(base64Decode(base64Text), capture.pcm);
    expect(ext.audioMatchCalls, 1);

    // 候选渲染。
    expect(find.text('识别结果'), findsOneWidget);
    expect(find.text('晴天'), findsOneWidget);
    expect(find.textContaining('周杰伦'), findsOneWidget);
    expect(find.textContaining('叶惠美'), findsOneWidget);
    expect(find.text('置信度 98%'), findsOneWidget);

    // 未接 player：候选行不可点。
    final tile = tester.widget<ListTile>(find.byType(ListTile).first);
    expect(tile.onTap, isNull);
  });

  testWidgets('点候选播放：player fake 收到候选里的歌曲', (tester) async {
    final player = FakePlayerUi();
    final ext = FakePlaybackExtApi(
      audioMatchResults: <List<MusicRecognitionMatch>>[
        <MusicRecognitionMatch>[fakeMatch()],
      ],
    );
    await _pumpPage(
      tester,
      _page(playbackExt: ext, capture: FakeAudioCapture(), player: player),
    );

    await _runFlow(tester);
    await tester.tap(find.text('晴天'));
    await tester.pump();

    expect(player.played, hasLength(1));
    final song = player.played.single;
    expect(song.id, '101');
    expect(song.hash, 'hash_hit_1');
    expect(song.title, '晴天');
    expect(song.albumId, 'album1');
    expect(song.albumTitle, '叶惠美');
    expect(song.artists.single.name, '周杰伦');
    // 识曲候选的资源事实随歌曲透传给播放链路。
    expect(song.resources, isEmpty);
  });

  testWidgets('权限拒绝：不碰录音，授权后可重试成功', (tester) async {
    final capture = FakeAudioCapture(permissionGranted: false);
    final ext = FakePlaybackExtApi(
      audioMatchResults: <List<MusicRecognitionMatch>>[
        <MusicRecognitionMatch>[fakeMatch()],
      ],
    );
    await _pumpPage(tester, _page(playbackExt: ext, capture: capture));

    await _runFlow(tester);

    expect(find.text('无法访问麦克风'), findsOneWidget);
    expect(find.textContaining('未获得麦克风权限'), findsOneWidget);
    expect(capture.startCalls, 0);
    expect(ext.audioMatchCalls, 0);
    // 主按钮变「重新识别」即重试入口。
    expect(find.text('重新识别'), findsOneWidget);

    // 授权后重试 → 成功。
    capture.permissionGranted = true;
    await _runFlow(tester);
    expect(find.text('晴天'), findsOneWidget);
    expect(ext.audioMatchQueries, hasLength(1));
  });

  testWidgets('无匹配：空态提示，重试后出结果', (tester) async {
    final ext = FakePlaybackExtApi(
      audioMatchResults: <List<MusicRecognitionMatch>>[
        const <MusicRecognitionMatch>[],
        <MusicRecognitionMatch>[fakeMatch()],
      ],
    );
    await _pumpPage(
      tester,
      _page(playbackExt: ext, capture: FakeAudioCapture()),
    );

    await _runFlow(tester);
    expect(find.text('没有识别到歌曲'), findsOneWidget);
    expect(find.textContaining('请靠近音源'), findsOneWidget);
    expect(ext.audioMatchCalls, 1);

    await _runFlow(tester);
    expect(find.text('晴天'), findsOneWidget);
    expect(ext.audioMatchCalls, 2);
  });

  testWidgets('识别失败（网络）：提示 + 重试恢复', (tester) async {
    final ext = FakePlaybackExtApi(
      audioMatchFailuresLeft: 1,
      audioMatchResults: <List<MusicRecognitionMatch>>[
        <MusicRecognitionMatch>[fakeMatch()],
      ],
    );
    await _pumpPage(
      tester,
      _page(playbackExt: ext, capture: FakeAudioCapture()),
    );

    await _runFlow(tester);
    expect(find.text('识别失败'), findsOneWidget);
    expect(find.textContaining('识曲服务挂了'), findsOneWidget);

    await _runFlow(tester);
    expect(find.text('晴天'), findsOneWidget);
    expect(ext.audioMatchCalls, 2);
  });

  testWidgets('录音失败：start 抛错直接进错误态，不调 stop/识别', (tester) async {
    final capture = FakeAudioCapture(startError: Exception('麦克风被占用'));
    final ext = FakePlaybackExtApi();
    await _pumpPage(tester, _page(playbackExt: ext, capture: capture));

    await _runFlow(tester);

    expect(find.text('识别失败'), findsOneWidget);
    expect(find.textContaining('录音失败'), findsOneWidget);
    expect(find.textContaining('麦克风被占用'), findsOneWidget);
    expect(capture.stopCalls, 0);
    expect(ext.audioMatchCalls, 0);
  });

  testWidgets('PCM 超协议上限：截断到 160000 字节再进请求', (tester) async {
    final capture = FakeAudioCapture(pcm: fakePcm(length: 200000));
    final ext = FakePlaybackExtApi(
      audioMatchResults: <List<MusicRecognitionMatch>>[
        <MusicRecognitionMatch>[fakeMatch()],
      ],
    );
    await _pumpPage(tester, _page(playbackExt: ext, capture: capture));

    await _runFlow(tester);

    final bytes = base64Decode(ext.audioMatchQueries.single.pcmBase64);
    expect(bytes.length, 160000);
    // 截断保留头部字节（内容原样，不做重采样/变换）。
    expect(bytes.take(16), capture.pcm.take(16));
  });

  testWidgets('识别中：按钮禁用、文案「识别中…」，stop 放行后出结果', (tester) async {
    final gate = Completer<void>();
    final capture = FakeAudioCapture(stopGate: gate);
    final ext = FakePlaybackExtApi(
      audioMatchResults: <List<MusicRecognitionMatch>>[
        <MusicRecognitionMatch>[fakeMatch()],
      ],
    );
    await _pumpPage(tester, _page(playbackExt: ext, capture: capture));

    await tester.tap(find.byKey(const Key('audio-match-start')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }

    // 卡在 fake stop 上：录音/识别阶段按钮禁用。
    expect(find.text('识别中…'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('audio-match-start')),
    );
    expect(button.onPressed, isNull);
    expect(capture.startCalls, 1);

    // 放行 → 流程继续到结果。
    gate.complete();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(find.text('晴天'), findsOneWidget);
    expect(ext.audioMatchCalls, 1);
  });

  testWidgets('空 PCM：提示没有录到有效音频，不发识别请求', (tester) async {
    final capture = FakeAudioCapture(pcm: Uint8List(0));
    final ext = FakePlaybackExtApi();
    await _pumpPage(tester, _page(playbackExt: ext, capture: capture));

    await _runFlow(tester);

    expect(find.textContaining('没有录到有效音频'), findsOneWidget);
    expect(ext.audioMatchCalls, 0);
  });
}
