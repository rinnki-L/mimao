/// 用户资料端点组门面——G9 组接口（docs/music-api-expansion.md §4/§5）。
///
/// 组合 8 个资料端点：身份标签、主页资料、资料/头像写、头像上传、联合会员、
/// 听歌等级、批量作者会员。听歌上报（user_listen_report）归 G14，不在本组。
/// 端点协议在各 `<endpoint>.dart` 文件（一端点一文件），本文件只做装配。
library;

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/user_avatar_upload.dart';
import 'package:mimao/music/api/user_batch_union_vipinfo.dart';
import 'package:mimao/music/api/user_detail.dart';
import 'package:mimao/music/api/user_grade_info.dart';
import 'package:mimao/music/api/user_info.dart';
import 'package:mimao/music/api/user_update.dart';
import 'package:mimao/music/api/user_update_avatar.dart';
import 'package:mimao/music/api/user_vip_detail.dart';
import 'package:mimao/music/models/user_models.dart';

/// 用户资料组接口（方法名带组语义，集成时全局唯一）。
abstract interface class MusicUserProfileApi {
  /// 当前账号的学生身份与展示标签。
  Future<MusicUserIdentityTags> userInfo();

  /// 当前账号的主页资料（含认证身份事实）。
  Future<MusicUserProfile> userDetail();

  /// 差量更新资料；返回确认回执。
  Future<MusicUserUpdateResult> userUpdate(MusicUserUpdateQuery query);

  /// 提交一个已上传的头像引用（审核中 → reviewPending）。
  Future<MusicUserAvatarUpdate> userUpdateAvatar(String fileName);

  /// 上传头像图片，返回文件引用（再交给 userUpdateAvatar 提交）。
  Future<MusicUserAvatarUpload> userAvatarUpload({
    required String imageBase64,
    required String localDate,
  });

  /// 当前账号的联合会员概览。
  Future<MusicUserVipMemberships> userVipDetail();

  /// 听歌等级；[userId] 缺省查当前账号（匿名可查其它账号）。
  Future<MusicUserGradeInfo> userGradeInfo(int? userId);

  /// 批量查作者会员产品（1..20 个 id，匿名可查）。
  Future<List<MusicUserBatchAuthorProducts>> userBatchUnionVipinfo(
    List<int> userIds,
  );
}

/// 生产实现：共享会话 + 各端点函数（协议见各文件）。
class KugouUserProfileApi implements MusicUserProfileApi {
  KugouUserProfileApi(this.session);

  final MusicSession session;

  @override
  Future<MusicUserIdentityTags> userInfo() => fetchUserInfo(session);

  @override
  Future<MusicUserProfile> userDetail() => fetchUserDetail(session);

  @override
  Future<MusicUserUpdateResult> userUpdate(MusicUserUpdateQuery query) =>
      fetchUserUpdate(session, query);

  @override
  Future<MusicUserAvatarUpdate> userUpdateAvatar(String fileName) =>
      fetchUserUpdateAvatar(session, fileName);

  @override
  Future<MusicUserAvatarUpload> userAvatarUpload({
    required String imageBase64,
    required String localDate,
  }) => fetchUserAvatarUpload(
    session,
    imageBase64: imageBase64,
    localDate: localDate,
  );

  @override
  Future<MusicUserVipMemberships> userVipDetail() =>
      fetchUserVipDetail(session);

  @override
  Future<MusicUserGradeInfo> userGradeInfo(int? userId) =>
      fetchUserGradeInfo(session, MusicUserGradeQuery(userId: userId));

  @override
  Future<List<MusicUserBatchAuthorProducts>> userBatchUnionVipinfo(
    List<int> userIds,
  ) => fetchUserBatchUnionVipinfo(session, userIds);
}
