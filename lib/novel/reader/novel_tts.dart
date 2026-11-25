// 朗读后端与顺序播放队列。
//
// Windows 不走 flutter_tts 的原生端：本机实测 FlutterTts.speak 一调用就与
// 引擎断开（C++/WinRT 协程里未观测的异常），而且异常在原生层无法 catch。
// 这里改用**常驻** PowerShell 宿主进程调系统 System.Speech（SAPI）：
// - 文本/路径用 base64 传入，命令行与管道都没有编码/引号问题；
// - 每次朗读只是一行 JSON 命令，不再每段起一次 powershell（旧实现每 3000
//   字一个进程，切段频繁时进程开销比合成还大）；
// - 停止 = 结束宿主进程，故障隔离在进程外，下一次朗读自动重启。
//
// Android 仍走 flutter_tts（系统语音引擎），与 Windows 共用同一套顺序朗读。

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'novel_tts_cache.dart';

/// 系统可用音色（Windows：VoiceInfo.Name；Android：voice map 的 name）。
class NovelTtsVoice {
  const NovelTtsVoice({
    required this.id,
    required this.label,
    this.locale = '',
  });

  /// 传给引擎的选择键。
  final String id;

  /// 展示文案。
  final String label;

  /// 语言/地区（`zh-CN` 等）；空串表示未知。
  final String locale;

  @override
  String toString() => label;
}

/// 一次朗读的运行时参数（每段开始前读取，改设置立即作用于后一段）。
class NovelTtsRuntime {
  const NovelTtsRuntime({
    this.rate = 1.0,
    this.voice = '',
    this.paragraphPauseMs = 300,
    this.autoNextChapter = true,
  });

  /// 0.5–2.0，1.0 为正常语速。
  final double rate;
  final String voice;

  /// 段与段之间的停顿。
  final int paragraphPauseMs;

  /// 本章读完是否自动开下一章继续读。
  final bool autoNextChapter;
}

/// 朗读后端窄接口（测试注入假实现，不要真起语音引擎）。
abstract interface class NovelTtsEngine {
  /// 能否把合成结果写成 wav 文件（导出 / 缓存前提）。
  bool get supportsFileOutput;

  /// 能否直接播放 wav 文件（缓存命中时免重合成）。
  bool get supportsFilePlayback;

  Future<void> configure();

  /// 系统可用音色；失败返回空列表（不阻塞朗读）。
  Future<List<NovelTtsVoice>> voices();

  /// 朗读一段文本；[rate] 0.5–2.0，[voice] 为 [NovelTtsVoice.id]（空 = 自动）。
  /// [cacheKey] 非空且后端支持文件时，由缓存装饰器决定播缓存还是重合成。
  Future<void> speak(
    String text, {
    required double rate,
    String voice = '',
    String? cacheKey,
  });

  /// 合成到 wav 文件；不支持时抛 [UnsupportedError]。
  Future<void> synthesizeToFile(
    String text,
    String path, {
    required double rate,
    String voice = '',
  });

  /// 播放 wav 文件；不支持时抛 [UnsupportedError]。
  Future<void> playFile(String path);

  Future<void> stop();
}

/// 按平台创建后端；测试环境/Web 返回 null（不朗读）。
NovelTtsEngine? createNovelTtsEngine() {
  if (kIsWeb) return null;
  if (Platform.environment.containsKey('FLUTTER_TEST')) return null;
  if (Platform.isWindows) return WindowsSapiTts();
  return FlutterTtsEngine(FlutterTts());
}

// ── 行通道：把子进程 stdout 的每一行交给等待中的命令 ─────────────────────

class _LineChannel {
  final Queue<String> _lines = Queue<String>();
  Completer<String>? _pending;
  Object? _error;

  void reset() {
    _lines.clear();
    _pending = null;
    _error = null;
  }

  void add(String line) {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      _pending = null;
      pending.complete(line);
      return;
    }
    _lines.add(line);
  }

  void fail(Object error) {
    _error = error;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) pending.completeError(error);
  }

  Future<String> next() {
    if (_lines.isNotEmpty) return Future<String>.value(_lines.removeFirst());
    final error = _error;
    if (error != null) return Future<String>.error(error);
    final pending = _pending ??= Completer<String>();
    return pending.future;
  }
}

// ── Windows：常驻 PowerShell + System.Speech ─────────────────────────────

/// 常驻宿主脚本。逐行读 JSON 命令，回一行 `OK` / `VOICES <base64>` / `ERR …`。
///
/// 用 UTF-16LE + `-EncodedCommand` 启动：多行脚本、中文、引号都不经命令行
/// 解析；命令里的文本与路径全部 base64，stdin 只需处理 ASCII。
const String _sapiHostScript = r'''
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
Add-Type -AssemblyName System.Speech
$sapi = New-Object System.Speech.Synthesis.SpeechSynthesizer
function Reply([string]$line) {
  [Console]::Out.WriteLine($line)
  [Console]::Out.Flush()
}
function Decode([string]$b64) {
  return [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
}
while ($true) {
  $line = [Console]::In.ReadLine()
  if ($null -eq $line) { break }
  if ([string]::IsNullOrWhiteSpace($line)) { continue }
  try {
    $cmd = $line | ConvertFrom-Json
    $op = [string]$cmd.op
    if ($op -eq 'voices') {
      $list = @()
      foreach ($v in $sapi.GetInstalledVoices()) {
        if ($v.Enabled) {
          $list += @{ id = [string]$v.VoiceInfo.Name; locale = [string]$v.VoiceInfo.Culture.Name }
        }
      }
      $json = ConvertTo-Json -InputObject @($list) -Compress
      if ([string]::IsNullOrEmpty($json)) { $json = '[]' }
      Reply ('VOICES ' + [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)))
    } elseif ($op -eq 'speak') {
      if ($cmd.voice) { try { $sapi.SelectVoice([string]$cmd.voice) } catch {} }
      $sapi.Rate = [int]$cmd.rate
      $sapi.SetOutputToDefaultAudioDevice()
      $sapi.Speak((Decode ([string]$cmd.text)))
      Reply 'OK'
    } elseif ($op -eq 'synth') {
      if ($cmd.voice) { try { $sapi.SelectVoice([string]$cmd.voice) } catch {} }
      $sapi.Rate = [int]$cmd.rate
      $path = Decode ([string]$cmd.path)
      $sapi.SetOutputToWaveFile($path)
      try { $sapi.Speak((Decode ([string]$cmd.text))) } finally { $sapi.SetOutputToNull() }
      Reply 'OK'
    } elseif ($op -eq 'play') {
      $path = Decode ([string]$cmd.path)
      $player = New-Object System.Media.SoundPlayer($path)
      $player.PlaySync()
      Reply 'OK'
    } else {
      Reply 'ERR unknown op'
    }
  } catch {
    Reply ('ERR ' + $_.Exception.Message)
  }
}
''';

String _encodePowerShell(String script) {
  final bytes = Uint8List(script.length * 2);
  for (var i = 0; i < script.length; i++) {
    final unit = script.codeUnitAt(i);
    bytes[i * 2] = unit & 0xFF;
    bytes[i * 2 + 1] = (unit >> 8) & 0xFF;
  }
  return base64Encode(bytes);
}

/// System.Speech 的 Rate 是 -10..10（0 正常）；0.5–2.0 线性映射并夹紧。
int sapiRateFor(double rate) => ((rate - 1.0) * 10).round().clamp(-10, 10);

/// Windows：常驻 PowerShell 宿主。
class WindowsSapiTts implements NovelTtsEngine {
  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  Future<void>? _starting;
  Future<void> _tail = Future<void>.value();
  String? _lastError;
  final _LineChannel _lines = _LineChannel();

  @override
  bool get supportsFileOutput => true;

  @override
  bool get supportsFilePlayback => true;

  @override
  Future<void> configure() async {
    // 预热宿主：首次朗读少一次进程启动的延迟；失败不致命，真正朗读时再报。
    try {
      await _ensureStarted();
    } on Object {
      // 预热失败交给 speak 决定。
    }
  }

  Future<void> _ensureStarted() async {
    if (_process != null) return;
    final pending = _starting;
    if (pending != null) return pending;
    final future = _spawn();
    _starting = future;
    try {
      await future;
    } finally {
      _starting = null;
    }
  }

  Future<void> _spawn() async {
    _lastError = null;
    final process = await Process.start('powershell', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-STA',
      '-EncodedCommand',
      _encodePowerShell(_sapiHostScript),
    ]);
    _lines.reset();
    _process = process;
    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _lines.add,
          onError: (Object error) => _lines.fail(StateError('朗读引擎输出错误：$error')),
          onDone: () => _lines.fail(StateError('朗读引擎已退出')),
        );
    _stderrSub = process.stderr.transform(utf8.decoder).listen((line) {
      if (line.trim().isNotEmpty) _lastError = line.trim();
    });
    unawaited(
      process.exitCode.then((code) {
        if (!identical(_process, process)) return;
        _process = null;
        _lines.fail(
          StateError(
            '朗读引擎退出码 $code'
            '${_lastError == null ? '' : '：$_lastError'}',
          ),
        );
        unawaited(_stdoutSub?.cancel());
        unawaited(_stderrSub?.cancel());
      }),
    );
  }

  /// 一条命令 = 一行 JSON；响应按到达顺序一一对应。
  Future<String> _request(Map<String, Object?> command) {
    final payload = jsonEncode(command);
    final next = _tail.then((_) => _requestNow(payload));
    // 链条上的失败不能堵住后续命令。
    _tail = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<String> _requestNow(String payload) async {
    await _ensureStarted();
    final process = _process;
    if (process == null) throw StateError('朗读引擎未启动');
    process.stdin.writeln(payload);
    await process.stdin.flush();
    final line = await _lines.next();
    if (line.startsWith('ERR')) {
      throw StateError('朗读引擎：${line.substring(3).trim()}');
    }
    return line;
  }

  @override
  Future<List<NovelTtsVoice>> voices() async {
    try {
      final line = await _request(<String, Object?>{'op': 'voices'});
      if (!line.startsWith('VOICES ')) return const <NovelTtsVoice>[];
      final decoded = utf8.decode(
        base64Decode(line.substring(7).trim()),
        allowMalformed: true,
      );
      final raw = jsonDecode(decoded);
      if (raw is! List) return const <NovelTtsVoice>[];
      final voices = <NovelTtsVoice>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final id = '${item['id'] ?? ''}';
        if (id.isEmpty) continue;
        voices.add(
          NovelTtsVoice(id: id, label: id, locale: '${item['locale'] ?? ''}'),
        );
      }
      // 中文音色排前面：本书正文几乎都是中文。
      voices.sort((a, b) {
        final az = a.locale.toLowerCase().startsWith('zh');
        final bz = b.locale.toLowerCase().startsWith('zh');
        if (az != bz) return az ? -1 : 1;
        return a.label.compareTo(b.label);
      });
      return voices;
    } on Object {
      return const <NovelTtsVoice>[];
    }
  }

  @override
  Future<void> speak(
    String text, {
    required double rate,
    String voice = '',
    String? cacheKey,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // 命令行不是瓶颈了，但单次 Speak 仍不宜塞整章：按句末切 3000 字上限，
    // 与旧实现一致，避免某些 SAPI 音色在超长文本上截断。
    for (final chunk in _chunks(trimmed)) {
      await _request(<String, Object?>{
        'op': 'speak',
        'text': base64Encode(utf8.encode(chunk)),
        'rate': sapiRateFor(rate),
        'voice': voice,
      });
    }
  }

  @override
  Future<void> synthesizeToFile(
    String text,
    String path, {
    required double rate,
    String voice = '',
  }) async {
    final trimmed = text.trim();
    // 写文件走 stdin，没有旧命令行 32k 限制；一次 Synth 写完整个段落，
    // 分多次写同一路径会把前一段覆盖掉。
    await _request(<String, Object?>{
      'op': 'synth',
      'text': base64Encode(utf8.encode(trimmed.isEmpty ? ' ' : trimmed)),
      'path': base64Encode(utf8.encode(path)),
      'rate': sapiRateFor(rate),
      'voice': voice,
    });
  }

  @override
  Future<void> playFile(String path) async {
    await _request(<String, Object?>{
      'op': 'play',
      'path': base64Encode(utf8.encode(path)),
    });
  }

  /// 单次命令的文本上限。Windows 命令行已不是瓶颈（走 stdin），
  /// 普通朗读仍保持 3000 字一段、优先切在句末。
  Iterable<String> _chunks(String text, {int limit = 3000}) sync* {
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
    final process = _process;
    _process = null;
    _lines.fail(StateError('朗读已停止'));
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

// ── 其它平台：flutter_tts ────────────────────────────────────────────────

class FlutterTtsEngine implements NovelTtsEngine {
  FlutterTtsEngine(this._tts);

  final FlutterTts _tts;
  final Map<String, String> _locales = <String, String>{};

  @override
  bool get supportsFileOutput => true;

  @override
  bool get supportsFilePlayback => false;

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
  Future<List<NovelTtsVoice>> voices() async {
    try {
      final raw = await _tts.getVoices;
      if (raw is! List) return const <NovelTtsVoice>[];
      final voices = <NovelTtsVoice>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final id = '${item['name'] ?? ''}';
        if (id.isEmpty) continue;
        final locale = '${item['locale'] ?? ''}';
        _locales[id] = locale;
        voices.add(NovelTtsVoice(id: id, label: id, locale: locale));
      }
      voices.sort((a, b) {
        final az = a.locale.toLowerCase().startsWith('zh');
        final bz = b.locale.toLowerCase().startsWith('zh');
        if (az != bz) return az ? -1 : 1;
        return a.label.compareTo(b.label);
      });
      return voices;
    } on Object {
      return const <NovelTtsVoice>[];
    }
  }

  @override
  Future<void> speak(
    String text, {
    required double rate,
    String voice = '',
    String? cacheKey,
  }) async {
    // flutter_tts 的 speechRate 是 0..1，0.5 为正常；0.5–2.0 映射到 0.25–1.0。
    final speechRate = (rate * 0.5).clamp(0.0, 1.0);
    await _tts.setSpeechRate(speechRate);
    if (voice.isNotEmpty) {
      try {
        await _tts.setVoice(<String, String>{
          'name': voice,
          'locale': _locales[voice] ?? '',
        });
      } on Object {
        // 选不到音色就沿用系统默认，不打断朗读。
      }
    }
    await _tts.speak(text);
  }

  @override
  Future<void> synthesizeToFile(
    String text,
    String path, {
    required double rate,
    String voice = '',
  }) async {
    await _tts.setSpeechRate((rate * 0.5).clamp(0.0, 1.0));
    if (voice.isNotEmpty) {
      try {
        await _tts.setVoice(<String, String>{
          'name': voice,
          'locale': _locales[voice] ?? '',
        });
      } on Object {
        // 同上。
      }
    }
    await _tts.synthesizeToFile(text, path);
  }

  @override
  Future<void> playFile(String path) async {
    throw UnsupportedError('当前平台不支持播放合成文件');
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } on Object {
      // 停止失败不阻塞。
    }
  }
}

// ── 缓存装饰器：合成结果落盘、命中直接播文件 ───────────────────────────

/// 给后端套一层音频缓存：有 [NovelTtsEngine.supportsFilePlayback] 才启用。
///
/// 合成失败会退回直接朗读，缓存永远不挡住「有声音」；键由播放队列按
/// `(章节, 段落, 音色, 语速)` 给出，换音色/语速自然落到新键。
class CachedNovelTtsEngine implements NovelTtsEngine {
  CachedNovelTtsEngine({required this.inner, required this.cache});

  final NovelTtsEngine inner;
  final NovelTtsCache cache;

  @override
  bool get supportsFileOutput => inner.supportsFileOutput;

  @override
  bool get supportsFilePlayback => inner.supportsFilePlayback;

  @override
  Future<void> configure() => inner.configure();

  @override
  Future<List<NovelTtsVoice>> voices() => inner.voices();

  @override
  Future<void> speak(
    String text, {
    required double rate,
    String voice = '',
    String? cacheKey,
  }) async {
    final canCache =
        cacheKey != null &&
        text.trim().isNotEmpty &&
        inner.supportsFileOutput &&
        inner.supportsFilePlayback;
    if (!canCache) {
      return inner.speak(text, rate: rate, voice: voice);
    }
    final cached = await cache.find(cacheKey);
    if (cached != null) {
      await inner.playFile(cached);
      return;
    }
    final path = await cache.pathFor(cacheKey);
    try {
      await inner.synthesizeToFile(text, path, rate: rate, voice: voice);
      await cache.put(cacheKey: cacheKey, path: path);
      await inner.playFile(path);
    } on Object {
      // 合成/落盘失败不挡朗读。
      await inner.speak(text, rate: rate, voice: voice);
    }
  }

  @override
  Future<void> synthesizeToFile(
    String text,
    String path, {
    required double rate,
    String voice = '',
  }) => inner.synthesizeToFile(text, path, rate: rate, voice: voice);

  @override
  Future<void> playFile(String path) => inner.playFile(path);

  @override
  Future<void> stop() => inner.stop();
}

// ── 顺序播放队列 ─────────────────────────────────────────────────────────

enum NovelTtsPlaybackState { idle, speaking, paused }

/// 按段顺序朗读 + 章末续章 + 暂停/继续的纯逻辑队列。
///
/// 与阅读页/控制器解耦：引擎、参数、下一章都由调用方注入，因此测试可以
/// 用 fake 引擎驱动整条队列，不碰真实语音。
class NovelTtsPlayer {
  NovelTtsPlayer({
    required this.engine,
    required this.runtime,
    required this.loadNextChapter,
    this.cacheKey,
    this.onParagraphChanged,
    this.onStateChanged,
    this.onError,
  });

  final NovelTtsEngine engine;

  /// 每段开始前读取；改语速/音色/段间停顿从下一段生效。
  final NovelTtsRuntime Function() runtime;

  /// 当前章读完后调用；返回下一章的段落，null 表示没有下一章/停止续章。
  final Future<List<String>?> Function() loadNextChapter;

  /// 每段的缓存键；null = 本轮不走缓存（无缓存服务/测试 fake）。
  final String? Function(int paragraph)? cacheKey;

  final void Function(int paragraph)? onParagraphChanged;
  final void Function(NovelTtsPlaybackState state)? onStateChanged;
  final void Function(Object error)? onError;

  List<String> _paragraphs = const <String>[];
  int _paragraph = 0;
  NovelTtsPlaybackState _state = NovelTtsPlaybackState.idle;
  int _runId = 0;
  int _speakToken = 0;
  Completer<void>? _resumeSignal;
  Future<void>? _loop;

  NovelTtsPlaybackState get state => _state;

  bool get isActive => _state != NovelTtsPlaybackState.idle;

  bool get isSpeaking => _state == NovelTtsPlaybackState.speaking;

  int get paragraph => _paragraph;

  /// 队列自然结束（或出错）时完成；测试可 await。
  Future<void> get finished => _loop ?? Future<void>.value();

  Future<void> start(List<String> paragraphs, {int from = 0}) async {
    if (paragraphs.isEmpty) return;
    if (_state != NovelTtsPlaybackState.idle) await stop();
    _paragraphs = List<String>.of(paragraphs);
    _paragraph = from.clamp(0, paragraphs.length);
    final run = ++_runId;
    _setState(NovelTtsPlaybackState.speaking);
    _loop = _run(run);
    onParagraphChanged?.call(_paragraph);
  }

  void pause() {
    if (_state != NovelTtsPlaybackState.speaking) return;
    _speakToken++;
    _setState(NovelTtsPlaybackState.paused);
    // 立刻掐掉当前句；继续时从当前段开头重读。
    unawaited(engine.stop());
  }

  void resume() {
    if (_state != NovelTtsPlaybackState.paused) return;
    _setState(NovelTtsPlaybackState.speaking);
    _wake();
  }

  /// 跳到指定段（手动翻页「跟随」模式 / 恢复位置）。
  /// 正在读时打断当前句，从目标段的开头继续。
  void seek(int paragraph) {
    final clamped = _paragraphs.isEmpty
        ? 0
        : paragraph.clamp(0, _paragraphs.length - 1);
    _paragraph = clamped;
    onParagraphChanged?.call(clamped);
    if (_state == NovelTtsPlaybackState.speaking) {
      _speakToken++;
      unawaited(engine.stop());
    }
  }

  Future<void> stop() async {
    if (_state == NovelTtsPlaybackState.idle) return;
    _runId++;
    _speakToken++;
    _setState(NovelTtsPlaybackState.idle);
    _wake();
    await engine.stop();
  }

  void _setState(NovelTtsPlaybackState next) {
    if (_state == next) return;
    _state = next;
    onStateChanged?.call(next);
  }

  bool _alive(int run) => run == _runId && _state != NovelTtsPlaybackState.idle;

  void _wake() {
    final signal = _resumeSignal;
    _resumeSignal = null;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  Future<void> _waitWhilePaused(int run) async {
    while (_alive(run) && _state == NovelTtsPlaybackState.paused) {
      final signal = _resumeSignal ??= Completer<void>();
      await signal.future;
    }
  }

  Future<void> _run(int run) async {
    try {
      while (_alive(run)) {
        await _waitWhilePaused(run);
        if (!_alive(run)) return;
        final list = _paragraphs;
        if (list.isEmpty) return;
        if (_paragraph >= list.length) {
          if (!await _advanceChapter(run)) return;
          continue;
        }
        final index = _paragraph;
        if (list[index].trim().isEmpty) {
          if (_paragraph == index) _paragraph = index + 1;
          continue;
        }
        final tuning = runtime();
        onParagraphChanged?.call(index);
        final token = ++_speakToken;
        try {
          await engine.speak(
            list[index],
            rate: tuning.rate,
            voice: tuning.voice,
            cacheKey: cacheKey?.call(index),
          );
        } on Object catch (error) {
          // 停止/暂停/跳段会打断当前 Speak，这不是故障。
          if (!_alive(run)) return;
          if (token != _speakToken) continue;
          _setState(NovelTtsPlaybackState.idle);
          onError?.call(error);
          return;
        }
        if (!_alive(run)) return;
        if (token == _speakToken && _paragraph == index) {
          _paragraph = index + 1;
        }
        final pauseMs = tuning.paragraphPauseMs;
        if (pauseMs > 0 && _paragraph < _paragraphs.length) {
          await Future<void>.delayed(Duration(milliseconds: pauseMs));
        }
      }
    } finally {
      // 自然读完（没有下一章）时回到 idle；被 stop 打断时状态已经是 idle。
      if (run == _runId) _setState(NovelTtsPlaybackState.idle);
    }
  }

  Future<bool> _advanceChapter(int run) async {
    if (!runtime().autoNextChapter) return false;
    List<String>? next;
    try {
      next = await loadNextChapter();
    } on Object catch (error) {
      if (_alive(run)) {
        _setState(NovelTtsPlaybackState.idle);
        onError?.call(error);
      }
      return false;
    }
    if (!_alive(run)) return false;
    if (next == null || next.isEmpty) return false;
    _paragraphs = next;
    _paragraph = 0;
    onParagraphChanged?.call(0);
    return true;
  }
}
