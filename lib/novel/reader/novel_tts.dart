// 朗读后端：按段落顺序朗读，可随时停止。
//
// Windows 不走 flutter_tts 的原生端：本机实测 FlutterTts.speak 一调用就与
// 引擎断开（C++/WinRT 协程里未观测的异常），而且异常在原生层无法 catch。
// 这里改用独立 PowerShell 进程调系统 System.Speech（SAPI），文本用 base64
// 传入避免中文编码/引号问题；停止 = 杀子进程，故障隔离在进程外。
//
// Android 仍走 flutter_tts（系统语音引擎），与 Windows 共用同一套顺序朗读。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 朗读后端窄接口（测试注入假实现）。
abstract interface class NovelTtsEngine {
  Future<void> configure();
  Future<void> speak(String text);
  Future<void> stop();
}

/// 按平台创建后端；测试环境/Web 返回 null（不朗读）。
NovelTtsEngine? createNovelTtsEngine() {
  if (kIsWeb) return null;
  if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
  if (Platform.isWindows) return WindowsSapiTts();
  return FlutterTtsEngine(FlutterTts());
}

/// Windows：PowerShell + System.Speech。
class WindowsSapiTts implements NovelTtsEngine {
  Process? _process;
  bool _stopped = false;

  @override
  Future<void> configure() async {}

  @override
  Future<void> speak(String text) async {
    await stop();
    _stopped = false;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    for (final chunk in _chunks(trimmed)) {
      if (_stopped) return;
      await _speakChunk(chunk);
    }
  }

  Future<void> _speakChunk(String chunk) async {
    // 用 base64 传文本：命令行不需要引号处理，中文按 UTF-8 还原。
    final payload = base64Encode(utf8.encode(chunk));
    final script =
        'Add-Type -AssemblyName System.Speech; '
        "\$t=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$payload')); "
        r'$s=New-Object System.Speech.Synthesis.SpeechSynthesizer; '
        r'$zh=$s.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -eq "zh-CN" } | Select-Object -First 1; '
        r'if ($zh) { $s.SelectVoice($zh.VoiceInfo.Name) }; '
        r'$s.Rate=0;$s.Volume=100;$s.Speak($t)';

    final process = await Process.start('powershell', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      script,
    ]);
    _process = process;
    // 排空输出，避免子进程写满管道卡住。
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    final code = await process.exitCode;
    if (!identical(_process, process)) return; // 已被 stop
    _process = null;
    if (_stopped) return;
    if (code != 0) {
      throw StateError('朗读进程退出码 $code');
    }
  }

  /// Windows 命令行上限 32k：按 3000 字切片，优先切在句末。
  Iterable<String> _chunks(String text) sync* {
    const limit = 3000;
    var start = 0;
    while (start < text.length) {
      var end = (start + limit).clamp(0, text.length);
      if (end < text.length) {
        final cut = text.lastIndexOf(RegExp(r'[。！？!?\n]'), end);
        if (cut > start + limit ~/ 2) end = cut + 1;
      }
      yield text.substring(start, end);
      start = end;
    }
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    final process = _process;
    _process = null;
    if (process == null) return;
    try {
      process.kill();
    } on Object {
      // 已经退出。
    }
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on Object {
      // 杀不掉也不阻塞切章/退出。
    }
  }
}

/// 其它平台：flutter_tts。
class FlutterTtsEngine implements NovelTtsEngine {
  FlutterTtsEngine(this._tts);

  final FlutterTts _tts;

  @override
  Future<void> configure() async {
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(true);
    } on Object {
      // 某些平台不支持逐词完成回调；朗读仍可排队进行。
    }
  }

  @override
  Future<void> speak(String text) => _tts.speak(text);

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Object {
      // 停止失败不阻塞。
    }
  }
}
