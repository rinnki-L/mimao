// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 用户中心页测试替身与模型工厂：纯内存、不联网、无真实计时器。
///
/// fake 聚合按调用次序消费响应队列，可按方法注入失败（重试测试先清空
/// 失败再点重试即可成功）。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mimao/music/api/user_library_api.dart';
import 'package:mimao/music/api/user_profile_api.dart';
import 'package:mimao/music/api/user_update.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/catalog_models.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/user_library_models.dart';
import 'package:mimao/music/models/user_models.dart';
import 'package:mimao/music/pages/music_profile_image_picker.dart';
import 'package:mimao/music/player/player_ui.dart';

// ── 模型工厂（字段取最小可信值） ─────────────────────────────────────────

MusicUserProfileIdentity fakeIdentity() => const MusicUserProfileIdentity(
  actorCode: null,
  businessCode: null,
  starCode: null,
  singerCode: null,
  legacyStarCode: null,
  talentBits: null,
  actor: false,
  business: false,
  star: false,
  singer: false,
  authorizations: <String>[],
  talentAuthorizations: <String>[],
  singerAuthorizations: <String>[],
);

MusicUserProfile fakeProfile({
  int id = 9001,
  String nickname = '示例昵称',
  int? grade = 7,
  String biography = '一句话简介',
  int? follows = 3,
  int? fans = 9,
  int? listeningMinutes = 1234,
  String ipLocation = '广东深圳',
  int? gender,
  String birthday = '',
  String province = '',
  String city = '',
}) => MusicUserProfile(
  id: id,
  nickname: nickname,
  avatarUrl: '',
  gender: gender,
  vipType: 1,
  follows: follows,
  fans: fans,
  biography: biography,
  friends: null,
  grade: grade,
  listeningMinutes: listeningMinutes,
  visitors: null,
  registeredAtSeconds: null,
  province: province,
  city: city,
  ipLocation: ipLocation,
  birthday: birthday,
  identity: fakeIdentity(),
);

MusicUserIdentityTags fakeTags({List<String> tags = const <String>['夜猫子']}) =>
    MusicUserIdentityTags(
      studentStatus: null,
      studentSchool: '',
      studentExpireTime: '',
      tags: tags,
    );

MusicUserVipMemberships fakeVip({
  String? deluxeExpiresAt = '2027-01-01 00:00:00',
  List<MusicUserVipMembershipProduct> products =
      const <MusicUserVipMembershipProduct>[],
}) => MusicUserVipMemberships(
  userId: 9001,
  vipTypeCode: 1,
  userTypeCode: null,
  deluxeBeginsAt: null,
  superBeginsAt: null,
  deluxeExpiresAt: deluxeExpiresAt,
  superExpiresAt: null,
  products: products,
);

MusicUserVipMembershipProduct fakeVipProduct({
  bool? active = true,
  String product = '酷狗豪华VIP',
  String expiresAt = '2026-12-31 23:59:59',
}) => MusicUserVipMembershipProduct(
  active: active,
  activeCode: active == true ? 1 : 0,
  product: product,
  business: 'kugou',
  beginsAt: null,
  expiresAt: expiresAt,
);

MusicUserGradeInfo fakeGrade({
  int? grade = 7,
  int? listeningSeconds = 7380,
  int? currentPoints = 300,
  int? gradePoints = 0,
  int? nextGradePoints = 600,
  int? nextGrade = 8,
}) => MusicUserGradeInfo(
  userId: 9001,
  grade: grade,
  listeningSeconds: listeningSeconds,
  currentPoints: currentPoints,
  gradePoints: gradePoints,
  nextGradePoints: nextGradePoints,
  nextGrade: nextGrade,
);

MusicHistoryItem fakeHistoryItem({
  String songId = '7001',
  String name = '历史歌一',
  String artist = '歌手甲',
  String album = '专辑甲',
  String hash = '0123456789abcdef0123456789abcdef',
  int? playCount = 3,
  int? lastPlayedAt = 1760000000,
  String? cover,
}) => MusicHistoryItem(
  songId: songId,
  name: name,
  artist: artist,
  album: album,
  albumId: '4101',
  audioId: '9001',
  hash: hash,
  cover: cover,
  durationMs: 213000,
  bitrate: 128,
  playCount: playCount,
  lastPlayedAt: lastPlayedAt,
);

MusicHistoryPage fakeHistoryPage({
  List<MusicHistoryItem> items = const <MusicHistoryItem>[],
  String? cursor,
  bool? hasMore,
}) => MusicHistoryPage(
  userId: '9001',
  cursor: cursor,
  finished: hasMore != true,
  hasMore: hasMore,
  items: items,
);

MusicUserPlaylist fakePlaylist({
  int? cloudListId = 100,
  String globalId = 'g-collection-100',
  String title = '歌单一',
  int? songCount = 12,
  String coverUrl = '',
  int? defaultKind,
}) => MusicUserPlaylist(
  cloudListId: cloudListId,
  globalId: globalId,
  creatorGlobalId: '',
  title: title,
  descriptionPresent: false,
  tagsPresent: false,
  description: '',
  tags: '',
  coverUrl: coverUrl,
  creatorId: 9001,
  creatorName: '示例昵称',
  creatorListId: null,
  songCount: songCount,
  revision: 0,
  sortIndex: 0,
  sourceCode: 0,
  kind: MusicCloudPlaylistKind.owned,
  kindCode: 0,
  editable: null,
  private: null,
  published: null,
  deleted: null,
  dropped: null,
  customCover: null,
  defaultKind: defaultKind,
  flagCodes: const MusicPlaylistFlagCodes(
    editable: null,
    private: null,
    published: null,
    deleted: null,
    dropped: null,
    customCover: null,
  ),
  createdAtSeconds: null,
  updatedAtSeconds: null,
);

MusicUserPlaylists fakePlaylists({required List<MusicUserPlaylist> items}) =>
    MusicUserPlaylists(
      page: MusicPage<MusicUserPlaylist>(
        page: 1,
        pageSize: 20,
        total: items.length,
        items: items,
      ),
      userId: 9001,
      totalRevision: null,
      collectionCount: 0,
      albumCount: 0,
    );

MusicPurchasedAlbum fakePurchasedAlbum({int? id = 321, String title = '专辑甲'}) =>
    MusicPurchasedAlbum(
      album: MusicAlbumSummary(
        id: id,
        title: title,
        artists: const <MusicArtistRef>[MusicArtistRef(name: '歌手甲')],
        coverUrl: '',
        songCount: 10,
        publishedAt: '',
      ),
      publicationCode: null,
      providerExtension: const <String, Object?>{},
    );

MusicPurchasedSong fakePurchasedSong({String title = '已购单曲一'}) =>
    MusicPurchasedSong(
      song: MusicSongSummary(
        id: '8001',
        hash: 'fedcba9876543210fedcba9876543210',
        title: title,
        artists: const <MusicArtistRef>[MusicArtistRef(name: '歌手乙')],
        albumId: '4202',
        albumTitle: '专辑乙',
        durationMs: 224000,
        coverUrl: '',
        privilege: 0,
      ),
      metadata: MusicPurchasedSongMetadata(
        catalog: const MusicCatalogFacts(
          paymentType: null,
          failureCode: null,
          oldCopyrightCode: null,
          originalityCode: null,
          rights: null,
          resources: <MusicAudioResource>[],
        ),
        sourceFileName: '',
        language: null,
        artists: const <MusicArtistDetail>[],
        providerExtension: null,
      ),
    );

// ── API 替身 ─────────────────────────────────────────────────────────────

/// 用户资料替身：可按方法注入失败并记录调用次数。
class FakeUserProfileApi implements MusicUserProfileApi {
  MusicUserProfile? detail;
  Object? detailError;
  int detailCalls = 0;

  MusicUserIdentityTags? tags;
  Object? tagsError;
  int tagsCalls = 0;

  MusicUserVipMemberships? vip;
  Object? vipError;
  int vipCalls = 0;

  MusicUserGradeInfo? grade;
  Object? gradeError;
  List<int?> gradeUserIds = <int?>[];
  int gradeCalls = 0;

  @override
  Future<MusicUserProfile> userDetail() async {
    detailCalls++;
    final Object? error = detailError;
    if (error != null) throw error;
    final MusicUserProfile? data = detail;
    if (data == null) throw StateError('FakeUserProfileApi: 未配置 detail');
    return data;
  }

  @override
  Future<MusicUserIdentityTags> userInfo() async {
    tagsCalls++;
    final Object? error = tagsError;
    if (error != null) throw error;
    final MusicUserIdentityTags? data = tags;
    if (data == null) throw StateError('FakeUserProfileApi: 未配置 tags');
    return data;
  }

  @override
  Future<MusicUserVipMemberships> userVipDetail() async {
    vipCalls++;
    final Object? error = vipError;
    if (error != null) throw error;
    final MusicUserVipMemberships? data = vip;
    if (data == null) throw StateError('FakeUserProfileApi: 未配置 vip');
    return data;
  }

  @override
  Future<MusicUserGradeInfo> userGradeInfo(int? userId) async {
    gradeCalls++;
    gradeUserIds.add(userId);
    final Object? error = gradeError;
    if (error != null) throw error;
    final MusicUserGradeInfo? data = grade;
    if (data == null) throw StateError('FakeUserProfileApi: 未配置 grade');
    return data;
  }

  // ── 资料写 / 头像（L3）：调用记录 + 可注入失败 ─────────────────────────
  final List<MusicUserUpdateQuery> updateQueries = <MusicUserUpdateQuery>[];
  Object? updateError;

  /// userUpdate 回执的 updated（端点成功恒为 true；false 用于防御分支）。
  bool updateResult = true;

  /// 头像图片上传的入参记录（imageBase64/localDate）。
  final List<({String imageBase64, String localDate})> avatarUploads =
      <({String imageBase64, String localDate})>[];
  Object? avatarUploadError;

  /// 上传端点回吐的文件引用（userUpdateAvatar 断言它被原样透传）。
  String avatarUploadFileName = 'abc123.png';

  final List<String> updateAvatarFileNames = <String>[];
  Object? updateAvatarError;
  bool avatarReviewPending = false;

  /// 头像两步接口的调用次序记录（'upload' / 'submit'）。
  final List<String> avatarCallOrder = <String>[];

  @override
  Future<MusicUserUpdateResult> userUpdate(MusicUserUpdateQuery query) async {
    updateQueries.add(query);
    final Object? error = updateError;
    if (error != null) throw error;
    return MusicUserUpdateResult(updated: updateResult);
  }

  @override
  Future<MusicUserAvatarUpload> userAvatarUpload({
    required String imageBase64,
    required String localDate,
  }) async {
    avatarUploads.add((imageBase64: imageBase64, localDate: localDate));
    avatarCallOrder.add('upload');
    final Object? error = avatarUploadError;
    if (error != null) throw error;
    return MusicUserAvatarUpload(fileName: avatarUploadFileName);
  }

  @override
  Future<MusicUserAvatarUpdate> userUpdateAvatar(String fileName) async {
    updateAvatarFileNames.add(fileName);
    avatarCallOrder.add('submit');
    final Object? error = updateAvatarError;
    if (error != null) throw error;
    return MusicUserAvatarUpdate(
      avatarUrl: 'http://c1.kgimg.com/v2/kugouicon/$fileName',
      reviewPending: avatarReviewPending,
    );
  }

  @override
  Future<List<MusicUserBatchAuthorProducts>> userBatchUnionVipinfo(
    List<int> userIds,
  ) => throw UnimplementedError();
}

/// 用户库替身：响应队列按调用次序消费，查询参数被记录供断言。
class FakeUserLibraryApi implements MusicUserLibraryApi {
  Object? historyError;
  final List<MusicHistoryPage> historyPages = <MusicHistoryPage>[];
  final List<MusicUserHistoryQuery> historyQueries = <MusicUserHistoryQuery>[];

  Object? purchasedAlbumsError;
  final List<MusicPage<MusicPurchasedAlbum>> purchasedAlbumPages =
      <MusicPage<MusicPurchasedAlbum>>[];
  final List<MusicUserPagedQuery> purchasedAlbumQueries =
      <MusicUserPagedQuery>[];

  Object? purchasedSongsError;
  final List<MusicPage<MusicPurchasedSong>> purchasedSongPages =
      <MusicPage<MusicPurchasedSong>>[];
  final List<MusicUserPagedQuery> purchasedSongQueries =
      <MusicUserPagedQuery>[];

  Object? playlistError;
  MusicUserPlaylists? playlists;
  final List<MusicUserPlaylistQuery> playlistQueries =
      <MusicUserPlaylistQuery>[];

  @override
  Future<MusicHistoryPage> userHistory(MusicUserHistoryQuery query) async {
    historyQueries.add(query);
    final Object? error = historyError;
    if (error != null) throw error;
    if (historyPages.isEmpty) {
      throw StateError('FakeUserLibraryApi: 未配置 historyPages');
    }
    return historyPages.removeAt(0);
  }

  @override
  Future<MusicPage<MusicPurchasedAlbum>> userPurchasedAlbums(
    MusicUserPagedQuery query,
  ) async {
    purchasedAlbumQueries.add(query);
    final Object? error = purchasedAlbumsError;
    if (error != null) throw error;
    if (purchasedAlbumPages.isEmpty) {
      throw StateError('FakeUserLibraryApi: 未配置 purchasedAlbumPages');
    }
    return purchasedAlbumPages.removeAt(0);
  }

  @override
  Future<MusicPage<MusicPurchasedSong>> userPurchasedSongs(
    MusicUserPagedQuery query,
  ) async {
    purchasedSongQueries.add(query);
    final Object? error = purchasedSongsError;
    if (error != null) throw error;
    if (purchasedSongPages.isEmpty) {
      throw StateError('FakeUserLibraryApi: 未配置 purchasedSongPages');
    }
    return purchasedSongPages.removeAt(0);
  }

  @override
  Future<MusicUserPlaylists> userPlaylist(MusicUserPlaylistQuery query) async {
    playlistQueries.add(query);
    final Object? error = playlistError;
    if (error != null) throw error;
    final MusicUserPlaylists? data = playlists;
    if (data == null) throw StateError('FakeUserLibraryApi: 未配置 playlists');
    return data;
  }

  // ── 偏好（L3）：调用记录 + 可注入失败 ─────────────────────────────────
  MusicPreferences? preference;
  Object? preferenceError;
  int preferenceCalls = 0;

  final List<MusicPreferenceUpdateQuery> preferenceUpdateQueries =
      <MusicPreferenceUpdateQuery>[];
  Object? preferenceUpdateError;

  /// userPreferenceUpdate 回执的 updated（false 用于失败提示分支）。
  bool preferenceUpdateResult = true;

  @override
  Future<MusicPreferences> userPreference() async {
    preferenceCalls++;
    final Object? error = preferenceError;
    if (error != null) throw error;
    final MusicPreferences? data = preference;
    if (data == null) {
      throw StateError('FakeUserLibraryApi: 未配置 preference');
    }
    return data;
  }

  @override
  Future<MusicPreferenceAcknowledgement> userPreferenceUpdate(
    MusicPreferenceUpdateQuery query,
  ) async {
    preferenceUpdateQueries.add(query);
    final Object? error = preferenceUpdateError;
    if (error != null) throw error;
    return MusicPreferenceAcknowledgement(updated: preferenceUpdateResult);
  }

  @override
  Future<MusicVerifyAcknowledgement> verifyUserInfo(
    MusicVerifyUserInfoQuery query,
  ) => throw UnimplementedError();
}

/// 播放 UI 替身：只记录 playSong 的入参，不渲染。
class FakePlayerUi implements MusicPlayerUi {
  final List<MusicSong> played = <MusicSong>[];
  final List<Duration> startAts = <Duration>[];

  @override
  Future<void> playSong(
    MusicSong song, {
    Duration startAt = Duration.zero,
  }) async {
    played.add(song);
    startAts.add(startAt);
  }

  @override
  Widget? buildMiniPlayer(BuildContext context) => null;

  @override
  Widget buildPlayerPage(BuildContext context) => const SizedBox.shrink();

  @override
  void dispose() {}
}

/// 认证失败（匿名/未登录）的统一入口——kind 对齐 KugouApiException 词表。
KugouApiException authenticationError() =>
    const KugouApiException('authentication', '请先登录');

// ── L3：偏好模型工厂 / 选图替身 ───────────────────────────────────────────

/// 偏好快照工厂（权重字段默认为空表；单个测试按需覆盖）。
MusicPreferences fakePreferences({
  String? recommendationMode = '0',
  String? gender = '',
  String? age = '',
  MusicWeightPreference? languages,
  MusicWeightPreference? styles,
  MusicWeightPreference? recommendation,
}) {
  MusicWeightPreference empty() => const MusicWeightPreference(
    encoded: '',
    weights: <String, double>{},
    raw: '',
  );
  return MusicPreferences(
    recommendationMode: recommendationMode,
    gender: gender,
    age: age,
    languages: languages ?? empty(),
    styles: styles ?? empty(),
    recommendation: recommendation ?? empty(),
  );
}

/// 最小 PNG 字节：完整 8 字节魔数 + 若干填充（校验/上传只看魔数与长度）。
Uint8List fakePngBytes({int extra = 16}) => Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  ...List<int>.filled(extra, 0x41),
]);

/// 头像选图替身：返回预置字节（null 模拟用户取消），绝不触碰 file_picker 插件。
class FakeProfileImagePicker implements MusicProfileImagePicker {
  FakeProfileImagePicker(this.next);

  /// 下一次 pickImage 的返回值（测试中途可改写）。
  Uint8List? next;
  int calls = 0;

  @override
  Future<Uint8List?> pickImage() async {
    calls++;
    return next;
  }
}
