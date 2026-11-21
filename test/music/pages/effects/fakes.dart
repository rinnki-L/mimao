// ignore_for_file: deprecated_member_use — 与页面测试同款说明。
/// L1（音效/品牌/识曲）页面测试的注入桩：fake 接口 + 模型构造器。
/// 不联网、不碰 record 插件、不用真实计时器。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mimao/music/api/audio_match.dart';
import 'package:mimao/music/api/effects_api.dart';
import 'package:mimao/music/api/effects_artist.dart';
import 'package:mimao/music/api/effects_brand.dart';
import 'package:mimao/music/api/effects_brand_detail.dart';
import 'package:mimao/music/api/get_model.dart';
import 'package:mimao/music/api/images_audio.dart';
import 'package:mimao/music/api/krm_audio.dart';
import 'package:mimao/music/api/playback_ext_api.dart';
import 'package:mimao/music/api/privilege_lite.dart';
import 'package:mimao/music/models/effects_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playback_ext_models.dart';
import 'package:mimao/music/pages/music_audio_capture.dart';
import 'package:mimao/music/player/player_ui.dart';

// ── 模型构造器 ─────────────────────────────────────────────────────────────

/// 音效条目（icon 留空走占位，避免测试碰 Image.network）。
MusicEffect fakeEffect({
  int id = 1,
  String name = '音效A',
  String author = '作者甲',
  List<String> labels = const <String>['古风'],
  int? userCount = 1200,
  String? unavailableReason,
  String source = 'market',
}) => MusicEffect(
  id: id,
  name: name,
  author: author,
  intro: '',
  iconUrl: '',
  labels: labels,
  userCount: userCount,
  source: source,
  soundUrls: const <String>[],
  vpfUrls: const <String>[],
  fileSize: null,
  unavailableReason: unavailableReason,
);

/// 耳机品牌条目。
MusicEarphoneBrand fakeBrand({
  int id = 7,
  String name = '品牌A',
  int? modelCount = 3,
}) =>
    MusicEarphoneBrand(id: id, name: name, iconUrl: '', modelCount: modelCount);

/// 识曲候选（songName/歌手/专辑/置信度可定制）。
MusicRecognitionMatch fakeMatch({
  String id = '101',
  String hash = 'hash_hit_1',
  String title = '晴天',
  String artist = '周杰伦',
  String albumId = 'album1',
  String? albumTitle = '叶惠美',
  double? confidence = 0.98,
}) {
  final song = MusicRecognitionSong(
    id: id,
    hash: hash,
    title: title,
    artists: <MusicArtistRef>[MusicArtistRef(id: 3, name: artist)],
    albumId: albumId,
    albumTitle: albumTitle,
    durationMs: 269000,
    coverUrl: '',
    facts: const MusicCatalogSongFacts(resources: <MusicAudioResource>[]),
  );
  return MusicRecognitionMatch(
    song: song,
    distance: null,
    confidence: confidence,
    timeOffset: null,
  );
}

/// 固定内容的假 PCM：递增字节便于断言「原样进入请求」。
Uint8List fakePcm({int length = 4000}) {
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = i & 0xFF;
  }
  return bytes;
}

/// 按页取目录批次；越界页返回空表（分页收口）。
MusicPage<T> _pageOf<T>(
  int page,
  int pageSize,
  List<List<T>> pages,
  int? total,
) {
  final index = page - 1;
  final items = index >= 0 && index < pages.length ? pages[index] : <T>[];
  return MusicPage<T>(
    page: page,
    pageSize: pageSize,
    total: total,
    items: items,
  );
}

// ── FakeEffectsApi ─────────────────────────────────────────────────────────

/// 音效/品牌端点组 fake：每方法支持「批次按页返回 + 剩余失败次数」注入。
class FakeEffectsApi implements MusicEffectsApi {
  FakeEffectsApi({
    this.brandPages = const <List<MusicEarphoneBrand>>[],
    this.brandTotal,
    this.brandFailuresLeft = 0,
    this.brandDetailPages = const <List<MusicEffect>>[],
    this.brandDetailTotal,
    this.brandDetailFailuresLeft = 0,
    this.matchResults = const <MusicEffect?>[null],
    this.matchFailuresLeft = 0,
  });

  // 音效商城目录（getModel）在 FakePlaybackExtApi 上，不在本接口。
  final List<List<MusicEarphoneBrand>> brandPages;
  final int? brandTotal;
  int brandFailuresLeft;
  final List<List<MusicEffect>> brandDetailPages;
  final int? brandDetailTotal;
  int brandDetailFailuresLeft;
  final List<MusicEffect?> matchResults;
  int matchFailuresLeft;

  int brandCalls = 0;
  int brandDetailCalls = 0;
  int matchCalls = 0;
  final List<EffectsBrandQuery> brandQueries = <EffectsBrandQuery>[];
  final List<EffectsBrandDetailQuery> brandDetailQueries =
      <EffectsBrandDetailQuery>[];

  @override
  Future<MusicPage<MusicEffect>> effectsArtist(
    EffectsArtistQuery query,
  ) async => MusicPage<MusicEffect>(items: <MusicEffect>[]);

  @override
  Future<MusicPage<MusicEarphoneBrand>> effectsBrand(
    EffectsBrandQuery query,
  ) async {
    brandQueries.add(query);
    brandCalls++;
    if (brandFailuresLeft > 0) {
      brandFailuresLeft--;
      throw Exception('耳机品牌挂了');
    }
    return _pageOf(query.page, query.pageSize, brandPages, brandTotal);
  }

  @override
  Future<MusicPage<MusicEffect>> effectsBrandDetail(
    EffectsBrandDetailQuery query,
  ) async {
    brandDetailQueries.add(query);
    brandDetailCalls++;
    if (brandDetailFailuresLeft > 0) {
      brandDetailFailuresLeft--;
      throw Exception('耳机音效挂了');
    }
    return _pageOf(
      query.page,
      query.pageSize,
      brandDetailPages,
      brandDetailTotal,
    );
  }

  @override
  Future<MusicEffect?> effectsMatch() async {
    matchCalls++;
    if (matchFailuresLeft > 0) {
      matchFailuresLeft--;
      throw Exception('设备匹配挂了');
    }
    // 结果批次按「成功调用」取：失败的调用不消耗批次。
    final index = _matchSuccessCalls++;
    return index < matchResults.length
        ? matchResults[index]
        : matchResults.last;
  }

  int _matchSuccessCalls = 0;
}

// ── FakePlaybackExtApi ─────────────────────────────────────────────────────

/// 播放补全端点组 fake：getModel（音效商城目录）与 audioMatch（识曲）带记录；
/// 其余端点页面不会调用，直接 UnimplementedError。
class FakePlaybackExtApi implements MusicPlaybackExtApi {
  FakePlaybackExtApi({
    this.marketPages = const <List<MusicEffect>>[],
    this.marketTotal,
    this.marketFailuresLeft = 0,
    this.audioMatchResults = const <List<MusicRecognitionMatch>>[],
    this.audioMatchFailuresLeft = 0,
  });

  final List<List<MusicEffect>> marketPages;
  final int? marketTotal;
  int marketFailuresLeft;
  final List<List<MusicRecognitionMatch>> audioMatchResults;
  int audioMatchFailuresLeft;

  int marketCalls = 0;
  int audioMatchCalls = 0;
  final List<GetModelQuery> marketQueries = <GetModelQuery>[];
  final List<AudioMatchQuery> audioMatchQueries = <AudioMatchQuery>[];

  @override
  Future<List<MusicRecognitionMatch>> audioMatch(AudioMatchQuery query) async {
    audioMatchQueries.add(query);
    audioMatchCalls++;
    if (audioMatchFailuresLeft > 0) {
      audioMatchFailuresLeft--;
      throw Exception('识曲服务挂了');
    }
    // 结果批次按「成功调用」取：失败的调用不消耗批次（重试场景可编排
    // 「失败 → 成功」而不被空批干扰）。
    final index = _audioMatchSuccessCalls++;
    return index < audioMatchResults.length
        ? audioMatchResults[index]
        : const <MusicRecognitionMatch>[];
  }

  int _audioMatchSuccessCalls = 0;

  @override
  Future<MusicPage<MusicEffect>> getModel(GetModelQuery query) async {
    marketQueries.add(query);
    marketCalls++;
    if (marketFailuresLeft > 0) {
      marketFailuresLeft--;
      throw Exception('音效商城挂了');
    }
    return _pageOf(query.page, query.pageSize, marketPages, marketTotal);
  }

  @override
  Future<List<MusicResourcePrivileges>> privilegeLite(
    PrivilegeLiteQuery query,
  ) => throw UnimplementedError();

  @override
  Future<List<List<MusicAuthorImages>>> imagesAudio(ImagesAudioQuery query) =>
      throw UnimplementedError();

  @override
  Future<List<MusicSongPresentation>> krmAudio(KrmAudioQuery query) =>
      throw UnimplementedError();
}

// ── FakeAudioCapture ───────────────────────────────────────────────────────

/// 录音缝 fake：权限/启动/停止均可注入失败；[stopGate] 可挂住 stop 让测试
/// 断言「识别中」状态；[pcm] 是 stop 返回的固定字节。
class FakeAudioCapture implements MusicAudioCapture {
  FakeAudioCapture({
    this.permissionGranted = true,
    this.permissionError,
    this.startError,
    this.stopError,
    Uint8List? pcm,
    this.stopGate,
  }) : pcm = pcm ?? fakePcm();

  bool permissionGranted;
  Object? permissionError;
  Object? startError;
  Object? stopError;
  Uint8List pcm;

  /// 非空时 stop 会先等它完成（测试控制识别时长内的状态断言）。
  Completer<void>? stopGate;

  int permissionCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;

  @override
  Future<bool> hasPermission() async {
    permissionCalls++;
    final error = permissionError;
    if (error != null) throw error;
    return permissionGranted;
  }

  @override
  Future<void> start() async {
    startCalls++;
    final error = startError;
    if (error != null) throw error;
  }

  @override
  Future<Uint8List> stop() async {
    stopCalls++;
    final gate = stopGate;
    if (gate != null) await gate.future;
    final error = stopError;
    if (error != null) throw error;
    return pcm;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }
}

// ── FakePlayerUi ───────────────────────────────────────────────────────────

/// 播放 UI fake：记录 playSong 收到的歌曲。
class FakePlayerUi implements MusicPlayerUi {
  final List<MusicSong> played = <MusicSong>[];

  @override
  Future<void> playSong(
    MusicSong song, {
    Duration startAt = Duration.zero,
  }) async {
    played.add(song);
  }

  @override
  Widget? buildMiniPlayer(BuildContext context) => null;

  @override
  Widget buildPlayerPage(BuildContext context) =>
      const Scaffold(body: Text('播放页占位'));

  @override
  void dispose() {}
}
