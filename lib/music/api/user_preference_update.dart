/// 偏好写入端点——EchoMusicNext `crates/echo-api/src/module/
/// user_preference_update.rs` 的翻译（docs/architecture.md §4.3）。
///
/// 差量字符串补丁：只带上显式给出的字段（空串也是有效值——实测「不变模式」
/// 的写入回执是 `data=""`）；一个字段都没给 → input。
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/user_preference.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/user_library_models.dart';

/// 偏好写入请求（user_preference_update.rs `Query`；六个字段均可选）。
class MusicPreferenceUpdateQuery {
  const MusicPreferenceUpdateQuery({
    this.recommendationMode,
    this.gender,
    this.age,
    this.languages,
    this.styles,
    this.recommendation,
  });

  /// 推荐模式（wire `mode`）。
  final String? recommendationMode;
  final String? gender;
  final String? age;

  /// 语言权重（wire `lang`）。
  final String? languages;

  /// 曲风权重（wire `style`）。
  final String? styles;

  /// 推荐语种权重（wire `song_lang`）。
  final String? recommendation;

  /// 差量字段表（user_preference_update.rs `fields`）：键按 wire 命名，
  /// 只保留显式给出的字段；全空 → input（偏好没有变化）。
  Map<String, String> fields() {
    final fields = <String, String?>{
      'mode': recommendationMode,
      'gender': gender,
      'age': age,
      'lang': languages,
      'style': styles,
      'song_lang': recommendation,
    }..removeWhere((_, value) => value == null);
    if (fields.isEmpty) {
      throw const KugouApiException('input', '偏好没有变化');
    }
    return Map<String, String>.from(fields);
  }
}

/// POST /userpreferservice/v1/update_user_conf（preference 协议；需要账号）。
Future<MusicPreferenceAcknowledgement> fetchUserPreferenceUpdate(
  MusicSession session,
  MusicPreferenceUpdateQuery query, {
  String? seed,
  Random? random,
  DateTime Function()? now,
}) async {
  // Rust：fields(q) 在 send 之前求值——空字段先于账号检查报 input；
  // require_account 在 preference_protocol::send 内部（共享实现）。
  final fields = query.fields();
  final identity = await session.ensureDevice();
  final bytes = await kugouSendPreferenceProtocol(
    session.client,
    identity,
    fields: fields,
    seed: seed,
    random: random,
    now: now,
  );
  return _convertAcknowledgement(bytes);
}

/// wire 解析（user_preference_update.rs `convert`：AckEnvelope + success）。
MusicPreferenceAcknowledgement _convertAcknowledgement(Uint8List bytes) {
  final envelope = decodeEnvelope(bytes);
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '偏好写入');
  return const MusicPreferenceAcknowledgement(updated: true);
}
