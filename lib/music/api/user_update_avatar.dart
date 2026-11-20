/// 头像引用提交端点——EchoMusicNext
/// `crates/echo-api/src/module/user_update_avatar.rs` 的翻译
/// （docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 只提交一个已上传的头像引用（上传本身在 user_avatar_upload）；不做图片
/// 处理、不关心账号状态。审核回执 34236 表示「已提交待发布」，不是失败。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/user_update.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/user_models.dart';

/// 审核中回执码（user_update_avatar.rs `convert`：error_code == 34236）。
const int kugouErrorCodeAvatarReviewPending = 34236;

/// 提交头像引用（user_update_avatar.rs `execute`）。
Future<MusicUserAvatarUpdate> fetchUserUpdateAvatar(
  MusicSession session,
  String fileName,
) async {
  // 上游单条件校验：非空、≤256 字节、字符集 [A-Za-z0-9_.-]。
  // 字符集限 ASCII，合法名下字节长与码元数一致。
  if (fileName.isEmpty ||
      fileName.length > 256 ||
      !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(fileName)) {
    throw const KugouApiException('input', '头像文件引用无效');
  }
  final identity = await session.ensureDevice();
  final bytes = await submitUserFields(session, identity, <String, String>{
    'photo': fileName,
  });
  return _convertAvatarUpdate(bytes, fileName);
}

/// wire 解析（user_update_avatar.rs `convert`）。
MusicUserAvatarUpdate _convertAvatarUpdate(Uint8List bytes, String file) {
  final envelope = decodeEnvelope(bytes);
  // 审核回执=已提交，不必然已发布；只有非审核码才走通用成功判定。
  final reviewPending = envelope.errorCode == kugouErrorCodeAvatarReviewPending;
  if (!reviewPending) {
    ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '头像更新');
  }
  return MusicUserAvatarUpdate(
    avatarUrl: 'http://c1.kgimg.com/v2/kugouicon/$file',
    reviewPending: reviewPending,
  );
}
