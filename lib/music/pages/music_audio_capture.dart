/// 录音缝（听歌识曲用）——把 `record` 插件的平台调用藏在本文件，
/// widget 测试注入 fake 实现、绝不触发插件（docs/music-longtail-ui.md §3-L1）。
///
/// 为什么做成接口缝：`record` 的 [AudioRecorder] 一调方法就进平台通道，
/// widget 测试无法离线运行；识曲页只认 [MusicAudioCapture]，生产装配
/// [RecordAudioCapture]，测试装配内存版。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

/// 可注入的录音缝：一次「开始 →（外部等待录音时长）→ 停止」拿到一段 PCM。
abstract interface class MusicAudioCapture {
  /// 是否有麦克风权限（实现方负责触发系统授权弹窗）。
  Future<bool> hasPermission();

  /// 开始录音：16000Hz / 单声道 / PCM16（识曲协议要求的采样形态）。
  Future<void> start();

  /// 停止录音并返回从 [start] 起累积的原始 PCM16 小端、单声道字节。
  Future<Uint8List> stop();

  /// 丢弃本次录音（页面离开时收尾用，不返回数据）。
  Future<void> cancel();
}

/// [MusicAudioCapture] 的生产实现：record 7.x 的 AudioRecorder 流模式。
///
/// 用 [AudioRecorder.startStream] 而不是 start(path)：识曲端点要的是裸 PCM
/// （audio_match.rs 直接把 PCM 字节当 POST body），文件模式会带容器头；
/// 流模式配 pcm16bits 编码器给的就是原始采样块，累积即可。Windows 端
/// （MediaFoundation）同样走 startStream，接口缝不因平台变化。
class RecordAudioCapture implements MusicAudioCapture {
  RecordAudioCapture();

  /// 识曲协议的固定采样形态（audio_match.rs：10 秒内单声道 PCM16）。
  static const RecordConfig _config = RecordConfig(
    encoder: AudioEncoder.pcm16bits,
    numChannels: 1,
    sampleRate: 16000,
  );

  /// stop 后等平台补发尾巴数据的有界时长（record 文档：流模式要靠流关闭
  /// 事件拿全量数据；收尾是异步的，给一次机会并入缓冲即可）。
  static const Duration _tailFlush = Duration(milliseconds: 300);

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;
  Completer<void>? _streamClosed;
  final List<Uint8List> _chunks = <Uint8List>[];

  @override
  Future<bool> hasPermission() =>
      (_recorder ??= AudioRecorder()).hasPermission();

  @override
  Future<void> start() async {
    final recorder = _recorder ??= AudioRecorder();
    _chunks.clear();
    final stream = await recorder.startStream(_config);
    final closed = Completer<void>();
    _streamClosed = closed;
    _subscription = stream.listen(
      _chunks.add,
      onDone: () => _closeStream(closed),
      // 出错也放行 stop：返回已积累的数据，空数据由页面按失败呈现。
      onError: (Object _) => _closeStream(closed),
    );
  }

  @override
  Future<Uint8List> stop() async {
    await _recorder?.stop();
    // 平台 stop 后尾巴数据异步补发、流随后关闭；等关闭（有界）再汇总，
    // 流异常没关闭也照样返回已积累的数据，不让识曲卡死。
    try {
      await _streamClosed?.future.timeout(_tailFlush);
    } on TimeoutException {
      // 流未正常关闭：放弃尾巴，返回已有数据。
    }
    await _subscription?.cancel();
    _subscription = null;
    _streamClosed = null;
    return _join(_chunks);
  }

  @override
  Future<void> cancel() async {
    await _subscription?.cancel();
    _subscription = null;
    _streamClosed = null;
    _chunks.clear();
    await _recorder?.cancel();
  }

  /// 释放底层 recorder；识曲页销毁时对「页面自建的实例」调用。
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _recorder?.dispose();
    _recorder = null;
  }

  void _closeStream(Completer<void> closed) {
    if (!closed.isCompleted) closed.complete();
  }

  static Uint8List _join(List<Uint8List> chunks) {
    var total = 0;
    for (final chunk in chunks) {
      total += chunk.length;
    }
    final out = Uint8List(total);
    var offset = 0;
    for (final chunk in chunks) {
      out.setAll(offset, chunk);
      offset += chunk.length;
    }
    return out;
  }
}
