/// 设备注册端点——EchoMusicNext `crates/echo-api/src/module/register_dev.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 用途：首次使用时把 dfid='-' 的匿名设备升级为真 dfid（/register/dev
/// 的应答**即使 status=1 也可能不带身份**——绝不杜撰标识符或把无身份当作
/// 注册成功，沿用上游注释的铁律）。
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/client/kugou_identity.dart';

/// 注册成功后服务端分配的设备身份。
class RegisteredDevice {
  const RegisteredDevice({required this.dfid});

  final String dfid;
}

/// 注册函数签名（music_api.dart 里的可注入缝）。
typedef RegisterDeviceFn =
    Future<RegisteredDevice> Function(
      KugouClient client,
      KugouIdentity identity,
    );

/// 固定设备档案（register_dev.rs `DeviceProfile::new`）——字段顺序在加密与
/// 签名前必须保持，黄金向量按字节对拍（test/music/api/）。
Map<String, Object?> kugouDeviceProfile(String guid) => <String, Object?>{
  'availableRamSize': 4983533568,
  'availableRomSize': 48114719,
  'availableSDSize': 48114717,
  'basebandVer': '',
  'batteryLevel': 100,
  'batteryStatus': 3,
  'brand': 'Redmi',
  'buildSerial': 'unknown',
  'device': 'marble',
  'imei': guid,
  'imsi': '',
  'manufacturer': 'Xiaomi',
  'uuid': guid,
  'accelerometer': false,
  'accelerometerValue': '',
  'gravity': false,
  'gravityValue': '',
  'gyroscope': false,
  'gyroscopeValue': '',
  'light': false,
  'lightValue': '',
  'magnetic': false,
  'magneticValue': '',
  'orientation': false,
  'orientationValue': '',
  'pressure': false,
  'pressureValue': '',
  'step_counter': false,
  'step_counterValue': '',
  'temperature': false,
  'temperatureValue': '',
};

/// 注册设备（匿名身份；`seed`/`random` 仅供测试注入）。
Future<RegisteredDevice> registerDevice(
  KugouClient client,
  KugouIdentity identity, {
  String? seed,
  Random? random,
}) async {
  if (identity.guid.isEmpty) {
    throw const KugouApiException('input', '设备 GUID 无效');
  }
  final anonymous = identity.withoutAccount();
  final envelope = seed == null
      ? KugouRegistrationEnvelope.registration(
          kugouDeviceProfile(anonymous.guid),
          userId: 0,
          token: '',
          random: random,
        )
      : KugouRegistrationEnvelope.withSeed(
          kugouDeviceProfile(anonymous.guid),
          seed: seed,
          userId: 0,
          token: '',
        );

  final response = await client.sendEndpoint(
    anonymous,
    KugouEndpoint(
      origin: KugouOrigin.registration,
      path: '/risk/v3/r_register_dev',
      method: 'POST',
      params: <String, String>{
        'part': '1',
        'platid': '1',
        'p': envelope.portrait,
      },
      body: envelope.base64Body(),
      headers: const <(String, String)>[
        ('Content-Type', 'application/x-www-form-urlencoded'),
        ('Accept', 'application/json, text/plain, */*'),
        ('kg-rc', '1'),
        ('kg-thash', '5d816a0'),
        ('kg-rec', '1'),
        ('kg-rf', 'B9EDA08A64250DEFFBCADDEE00F8F25F'),
      ],
    ),
  );

  // 传输本身就是加密二进制，与 MIME 标签无关（上游注释）。
  final plain = envelope.decryptResponse(response.bytes);
  return _convertRegisteredDevice(plain);
}

/// wire 解析（register_dev.rs `convert`）。
RegisteredDevice _convertRegisteredDevice(Uint8List bytes) {
  // 解密后的 JSON 仍按信封语义判定；这里不走 decodeBusinessEnvelope——
  // 空数组/缺 dfid 的「未分配」必须是专属 kind，不能并进 business。
  final envelope = decodeEnvelope(bytes);
  if (envelope.status != 1 || envelope.errorCode != 0) {
    throw KugouApiException(
      'business',
      '设备注册失败（status=${envelope.status}）',
      code: envelope.errorCode,
    );
  }
  final data = envelope.data;
  if (data is List && data.isEmpty) {
    throw const KugouApiException(
      'device_registration_unassigned',
      '设备服务未返回设备身份',
    );
  }
  if (data is! Map) {
    throw const KugouApiException('decode', '设备注册响应 data 不是 object');
  }
  if (!data.containsKey('dfid')) {
    throw const KugouApiException(
      'device_registration_unassigned',
      '设备服务未返回设备身份',
    );
  }
  final dfid = wireText(data['dfid']);
  if (dfid.isEmpty || dfid == '-' || dfid.length > 512) {
    throw const KugouApiException('authentication', '服务未返回有效登录凭证');
  }
  return RegisteredDevice(dfid: dfid);
}
