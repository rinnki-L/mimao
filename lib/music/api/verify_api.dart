/// 验证端点组接口——captcha_sent / get_verify_info 的组装面
/// （规格第 4 节：每组产出 `Music<Group>Api` 接口 + `Kugou<Group>Api` 实现）。
library;

import 'package:mimao/music/api/captcha_sent.dart';
import 'package:mimao/music/api/get_verify_info.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/models/verify_models.dart';

/// 验证挑战端点组（captcha_sent.rs / get_verify_info.rs）。
abstract interface class MusicVerifyApi {
  /// 发送短信验证码——设备级匿名请求，与当前登录态无关；成功返回 true，
  /// 失败以 KugouApiException 收口。
  Future<bool> captchaSent(MusicCaptchaSentQuery query);

  /// 取验证挑战配置（provider/vendor/会话字段；事件无效 → input，
  /// 业务失败 → business）。
  Future<MusicVerificationConfiguration> getVerifyInfo(
    MusicVerifyInfoQuery query,
  );
}

/// 酷狗实现：委托给组内端点函数（一端点一文件的翻译层）。
class KugouVerifyApi implements MusicVerifyApi {
  KugouVerifyApi(this.session);

  final MusicSession session;

  @override
  Future<bool> captchaSent(MusicCaptchaSentQuery query) =>
      fetchCaptchaSent(session, query);

  @override
  Future<MusicVerificationConfiguration> getVerifyInfo(
    MusicVerifyInfoQuery query,
  ) => fetchVerifyInfo(session, query);
}
