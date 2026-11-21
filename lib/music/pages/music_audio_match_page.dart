// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 听歌识曲页（L1）：麦克风录制约 5 秒 → base64 → audioMatch → 候选列表。
///
/// 页面只依赖注入的 [MusicPlaybackExtApi] / [MusicAudioCapture] /
/// [MusicPlayerUi]；`capture` 为空时惰性构造生产实现（record 插件，见
/// [RecordAudioCapture]）并在页面销毁时释放。录音时长可注入（测试传
/// Duration.zero，不碰真实计时器；生产默认约 5 秒，16000Hz 单声道 PCM16
/// 上限 160000 字节，超出部分截断——识别不需要更长样本）。
///
/// 权限拒绝 / 录音失败 / 无匹配 / 识别失败都有中文提示与重试；识别中主按钮
/// 禁用。点候选歌调用注入的 [MusicPlayerUi.playSong]（候选里的歌曲事实 →
/// [MusicSong]，见 [_songOf]）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/audio_match.dart';
import 'package:mimao/music/api/playback_ext_api.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playback_ext_models.dart';
import 'package:mimao/music/pages/music_audio_capture.dart';
import 'package:mimao/music/player/player_ui.dart';

/// 识曲协议的 PCM 上限（audio_match.rs：≤ 160000 字节 = 10 秒单声道 16-bit）。
const int _maxPcmBytes = 160000;

/// 一次识别的 UI 阶段；recording/matching 都算「识别中」（按钮禁用）。
enum _MatchPhase {
  idle,
  recording,
  matching,
  result,
  noMatch,
  failed,
  permissionDenied,
}

/// 听歌识曲页。
class MusicAudioMatchPage extends StatefulWidget {
  const MusicAudioMatchPage({
    super.key,
    required this.playbackExt,
    this.capture,
    this.player,
    this.recordDuration = const Duration(seconds: 5),
  });

  /// 播放补全端点组（识曲端点 audioMatch）。
  final MusicPlaybackExtApi playbackExt;

  /// 录音缝；null 时惰性构造 [RecordAudioCapture] 并在页面销毁时 dispose。
  final MusicAudioCapture? capture;

  /// 播放 UI；null 时候选不可点（只展示识别结果）。
  final MusicPlayerUi? player;

  /// 录音时长（生产默认 5 秒；测试注入 Duration.zero 避开真实计时器）。
  final Duration recordDuration;

  @override
  State<MusicAudioMatchPage> createState() => _MusicAudioMatchPageState();
}

class _MusicAudioMatchPageState extends State<MusicAudioMatchPage> {
  _MatchPhase _phase = _MatchPhase.idle;
  String _failure = '';
  List<MusicRecognitionMatch> _matches = const <MusicRecognitionMatch>[];

  /// 页面自建的生产录音实现（测试注入 fake 时保持 null）。
  RecordAudioCapture? _ownedCapture;

  /// 本次识别实际使用的缝（start 后记录；dispose 时若有录音进行中则丢弃）。
  MusicAudioCapture? _usedCapture;

  MusicAudioCapture get _effectiveCapture =>
      widget.capture ?? (_ownedCapture ??= RecordAudioCapture());

  @override
  void dispose() {
    // 离开页面时丢掉进行中的录音；自建的插件实现一并释放（注入的缝不 dispose，
    // 生命周期归注入方）。
    final capture = _usedCapture;
    final busy =
        _phase == _MatchPhase.recording || _phase == _MatchPhase.matching;
    if (capture != null && busy) {
      capture.cancel().catchError((Object _) {});
    }
    _ownedCapture?.dispose().catchError((Object _) {});
    super.dispose();
  }

  // ── 识别流程 ──────────────────────────────────────────────────────────

  Future<void> _start() async {
    final busy =
        _phase == _MatchPhase.recording || _phase == _MatchPhase.matching;
    if (busy) return;
    final capture = _effectiveCapture;
    _usedCapture = capture;

    // 1) 权限：拒绝则停在权限态，不碰录音。
    bool granted;
    try {
      granted = await capture.hasPermission();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _MatchPhase.failed;
        _failure = '获取麦克风权限失败：$error';
      });
      return;
    }
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _phase = _MatchPhase.permissionDenied;
        _failure = '未获得麦克风权限，无法识别歌曲；请在系统设置中授权后重试';
      });
      return;
    }

    // 2) 录音：start → 等注入的时长（流式累积在缝里）→ stop 拿 PCM。
    setState(() => _phase = _MatchPhase.recording);
    try {
      await capture.start();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _MatchPhase.failed;
        _failure = '录音失败：$error';
      });
      return;
    }
    await Future<void>.delayed(widget.recordDuration);
    Uint8List pcm;
    try {
      pcm = await capture.stop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _MatchPhase.failed;
        _failure = '录音失败：$error';
      });
      return;
    }
    if (!mounted) return;
    if (pcm.isEmpty) {
      setState(() {
        _phase = _MatchPhase.failed;
        _failure = '没有录到有效音频，请检查麦克风后重试';
      });
      return;
    }
    // 协议上限：超过 10 秒的样本对识别没有增益，截断到 160000 字节。
    if (pcm.length > _maxPcmBytes) {
      pcm = pcm.sublist(0, _maxPcmBytes);
    }

    // 3) 识别：PCM → base64 → audioMatch。
    setState(() => _phase = _MatchPhase.matching);
    try {
      final matches = await widget.playbackExt.audioMatch(
        AudioMatchQuery(pcmBase64: base64Encode(pcm)),
      );
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _phase = matches.isEmpty ? _MatchPhase.noMatch : _MatchPhase.result;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _MatchPhase.failed;
        _failure = '识别失败：$error';
      });
    }
  }

  // ── 展示 ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final busy =
        _phase == _MatchPhase.recording || _phase == _MatchPhase.matching;
    final label = busy
        ? '识别中…'
        : _phase == _MatchPhase.idle
        ? '开始识别'
        : '重新识别';
    return Scaffold(
      appBar: AppBar(title: const Text('听歌识曲')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: _buildBody(context)),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('audio-match-start'),
              // 识别中禁用重复提交；识别完成后按钮变「重新识别」即重试入口。
              onPressed: busy ? null : _start,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_phase) {
      case _MatchPhase.idle:
        return _HintView(
          icon: Icons.mic_none,
          title: '播放一段歌曲，帮你认出它',
          subtitle: '点击下方按钮开始，需要录制约 ${widget.recordDuration.inSeconds} 秒',
        );
      case _MatchPhase.recording:
        return const _HintView(
          icon: Icons.graphic_eq,
          title: '正在聆听，请对着音源播放歌曲…',
          subtitle: '请保持环境安静',
          waveform: true,
        );
      case _MatchPhase.matching:
        return const _HintView(
          icon: Icons.graphic_eq,
          title: '正在识别…',
          subtitle: '最多需要几十秒',
        );
      case _MatchPhase.result:
        return _ResultList(
          matches: _matches,
          playable: widget.player != null,
          onPlay: _play,
        );
      case _MatchPhase.noMatch:
        return _HintView(
          icon: Icons.search_off,
          title: '没有识别到歌曲',
          subtitle: '请靠近音源、调高音量后再试一次',
        );
      case _MatchPhase.failed:
        return _HintView(
          icon: Icons.error_outline,
          title: '识别失败',
          subtitle: _failure,
          error: true,
        );
      case _MatchPhase.permissionDenied:
        return _HintView(
          icon: Icons.mic_off_outlined,
          title: '无法访问麦克风',
          subtitle: _failure,
          error: true,
        );
    }
  }

  /// 点候选歌：候选里的歌曲事实 → [MusicSong] 交给播放 UI。
  void _play(MusicRecognitionMatch match) {
    final player = widget.player;
    if (player == null) return;
    player.playSong(_songOf(match));
  }

  /// [MusicRecognitionSong]（识曲投影）→ 播放链路的 [MusicSong]：
  /// 候选没带的字段用骨架模型的缺省语义（专辑名缺失记空串）。
  MusicSong _songOf(MusicRecognitionMatch match) {
    final song = match.song;
    return MusicSong(
      id: song.id,
      hash: song.hash,
      title: song.title,
      artists: song.artists,
      albumId: song.albumId,
      albumTitle: song.albumTitle ?? '',
      durationMs: song.durationMs,
      coverUrl: song.coverUrl,
      privilege: song.privilege,
      resources: song.facts.resources,
    );
  }
}

/// 大图标 + 主副标题的提示视图（引导/识别中/失败/空结果共用）。
class _HintView extends StatelessWidget {
  const _HintView({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.error = false,
    this.waveform = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool error;

  /// 录音阶段的静态「波形」占位（不依赖动画，测试可 pumpAndSettle）。
  final bool waveform;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 48, color: error ? cs.error : cs.primary),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          if (waveform) ...<Widget>[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // 静态灰条模拟声浪起伏，纯展示。
                for (final height in const <double>[
                  12,
                  24,
                  36,
                  20,
                  44,
                  28,
                  16,
                  32,
                  40,
                  18,
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Container(
                      width: 5,
                      height: height,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: MimaoShapes.pill,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 识别结果列表：歌名 / 歌手 / 专辑 / 置信度；`player` 接线后可点播放。
class _ResultList extends StatelessWidget {
  const _ResultList({
    required this.matches,
    required this.playable,
    required this.onPlay,
  });

  final List<MusicRecognitionMatch> matches;
  final bool playable;
  final void Function(MusicRecognitionMatch match) onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('识别结果', style: theme.textTheme.titleMedium),
        ),
        Expanded(
          child: ListView.builder(
            key: const Key('audio-match-results'),
            itemCount: matches.length,
            itemBuilder: (context, index) {
              final match = matches[index];
              final song = match.song;
              final confidence = match.confidence;
              final confidenceText = confidence == null
                  ? '置信度未知'
                  : '置信度 ${(confidence * 100).round()}%';
              final artistText = song.artists
                  .map((artist) => artist.name)
                  .where((name) => name.isNotEmpty)
                  .join(' / ');
              final subtitle = <String>[
                if (artistText.isNotEmpty) artistText,
                if (song.albumTitle != null && song.albumTitle!.isNotEmpty)
                  song.albumTitle!,
              ].join(' · ');
              return ListTile(
                leading: _MatchCover(url: song.coverUrl),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: subtitle.isEmpty
                    ? null
                    : Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                trailing: Text(
                  confidenceText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                // 未接播放 UI 时只展示，不可点。
                onTap: playable ? () => onPlay(match) : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 候选封面：无 URL / 加载失败回退音符占位。
class _MatchCover extends StatelessWidget {
  const _MatchCover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: MimaoShapes.sm,
      ),
      child: Icon(Icons.music_note, color: cs.primary),
    );
    if (url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: MimaoShapes.sm,
      child: Image.network(
        url,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}
