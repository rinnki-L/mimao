/// 验证码发送端点——EchoMusicNext `crates/echo-api/src/module/captcha_sent.rs`
/// 的逐函数翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 设备级发码端点：**只保留 mid**，清空 userid/token/t1 且 dfid 置 "-"——
/// 带着当前账号凭证发码反而会污染服务端会话（上游 `execute` 注释原样保留）。
/// 手机号合法性沿用 `login_cellphone::valid_mobile` 的口径。
library;

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

/// 发码输入（captcha_sent.rs `Query`：只有 mobile）。
class MusicCaptchaSentQuery {
  const MusicCaptchaSentQuery({required this.mobile});

  final String mobile;

  void validate() {
    if (!validMobile(mobile)) {
      throw const KugouApiException('input', '请输入正确的手机号码');
    }
  }
}

/// 手机号校验（login_cellphone.rs `valid_mobile`：11 位、1 开头、全 ASCII 数字）。
///
/// Rust 侧先按字节判长度再判数字；全数字串的字节数与字符数一致，非 ASCII
/// 字符会被数字判定拒绝，两个口径等价。
bool validMobile(String mobile) {
  if (mobile.length != 11 || !mobile.startsWith('1')) {
    return false;
  }
  for (final unit in mobile.codeUnits) {
    if (unit < 0x30 || unit > 0x39) {
      return false;
    }
  }
  return true;
}

/// POST /v7/send_mobile_code（网关 + x-router=login.user.kugou.com）。
///
/// 成功即 `{"sent":true}`（上游 convert 的输出 JSON）；Dart 层直接返回
/// `true`——失败路径全部以异常收口，没有 `false` 分支。
Future<bool> fetchCaptchaSent(
  MusicSession session,
  MusicCaptchaSentQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  // Send MID only, without current account credentials or device DFID.
  // （captcha_sent.rs execute：只克隆保留 mid，其余账号/设备字段剥离。）
  final anonymous = KugouIdentity(
    userId: 0,
    token: '',
    t1: '',
    mid: identity.mid,
    dfid: '-',
    uuid: identity.uuid,
    guid: identity.guid,
    mac: identity.mac,
    deviceName: identity.deviceName,
    renderFingerprint: identity.renderFingerprint,
  );
  final response = await session.client.sendEndpoint(
    anonymous,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v7/send_mobile_code',
      router: 'login.user.kugou.com',
      method: 'POST',
      // serde_json 默认 BTreeMap：键按字典序编码（签名覆盖 body 字节）。
      body: encodeJsonBody(<String, Object?>{
        'businessid': 5,
        'mobile': query.mobile,
        'plat': 3,
      }),
    ),
  );
  // AckEnvelope：status/error_code 必填标量；成功判定 request::success
  // （status==1 且 error_code==0，失败已由 decodeBusinessEnvelope 抛 business）。
  decodeBusinessEnvelope(response.bytes, context: '验证码发送');
  return true;
}
