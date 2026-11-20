/// KugouAuthApi 组接口测试：登录成功后身份写回（saveIdentity 唯一写入口）+
/// select_account/authorize 不写身份 + 设备端点直通。
///
/// 说明：组接口不暴露测试注入缝（seed/timestamp），因此写回路径用带明文
/// token 兜底的响应验证（login/login_cellphone 的上游语义）；qq/token/openplat
/// Finish 的写回走同一段 `_mergeAccount`，协议层已在各自端点测试覆盖。
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/auth_login_api.dart';
import 'package:mimao/music/api/login.dart';
import 'package:mimao/music/api/login_cellphone.dart';
import 'package:mimao/music/api/login_device_kick.dart';
import 'package:mimao/music/api/login_openplat.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_identity.dart';
import 'package:mimao/music/models/auth_models.dart';

import '../capture_adapter.dart';
import 'test_support.dart';

void main() {
  late CaptureAdapter adapter;
  late KugouClient client;
  late KugouIdentity identity;
  late List<KugouIdentity> saved;
  late KugouAuthApi api;

  setUp(() {
    adapter = CaptureAdapter(
      jsonBytes(
        envelopeJson(
          data: accountWireData(
            // 明文 token 兜底（login/login_cellphone 上游语义；接口层无注入缝）。
            secuParams: '',
            token: 'NEW-TK',
            userId: 99,
            t1: 'NEW-T1',
            nickname: '新昵称',
            pic: 'http://pic/new',
          ),
        ),
      ),
    );
    client = KugouClient(dio: Dio()..httpClientAdapter = adapter);
    identity = fixtureIdentity(userId: 7, token: 'OLD', t1: 'OLDT1');
    saved = <KugouIdentity>[];
    api = KugouAuthApi(fakeSession(client, identity, saved: saved));
  });

  test('login：成功后账号并回身份并落盘（t1/nickname/avatar）', () async {
    final authorization = await api.login(
      const MusicLoginQuery(username: 'user', password: 'pw'),
    );
    expect(authorization.userId, 99);
    expect(authorization.token, 'NEW-TK');
    expect(saved, hasLength(1));
    final savedIdentity = saved.single;
    expect(savedIdentity.userId, 99);
    expect(savedIdentity.token, 'NEW-TK');
    expect(savedIdentity.t1, 'NEW-T1');
    expect(savedIdentity.nickname, '新昵称');
    expect(savedIdentity.avatarUrl, 'http://pic/new');
    // 设备字段保留。
    expect(savedIdentity.mid, identity.mid);
    expect(savedIdentity.dfid, identity.dfid);
    expect(savedIdentity.hasAccount, isTrue);
    expect(savedIdentity.isUsable, isTrue);
  });

  test('loginOpenplat(Authorize)：只换凭证，不写身份', () async {
    adapter.bytes = jsonBytes('{"access_token":"AT","openid":"OID"}');
    final result = await api.loginOpenplat(
      const MusicOpenplatQuery.authorize('CODE'),
    );
    expect(result, isA<MusicProviderAuthorization>());
    expect(saved, isEmpty);
  });

  test('loginCellphone：select_account 不写身份；授权成功写身份', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(
        errorCode: 34175,
        data: <String, Object?>{
          'info_list': <Object?>[
            <String, Object?>{'userid': 1, 'nickname': 'A'},
          ],
        },
      ),
    );
    final select = await api.loginCellphone(
      const MusicCellphoneQuery(mobile: '13800000000', code: '123456'),
    );
    expect(select.selectAccount, isTrue);
    expect(saved, isEmpty);

    adapter.bytes = jsonBytes(
      envelopeJson(
        data: accountWireData(
          secuParams: '',
          token: 'C-TK',
          userId: 66,
          nickname: '手机昵称',
        ),
      ),
    );
    final result = await api.loginCellphone(
      const MusicCellphoneQuery(mobile: '13800000000', code: '123456'),
    );
    expect(result.authorization, isNotNull);
    expect(saved, hasLength(1));
    expect(saved.single.userId, 66);
    expect(saved.single.token, 'C-TK');
    expect(saved.single.nickname, '手机昵称');
  });

  test('loginDevice/loginDeviceKick：直通（不写身份）', () async {
    adapter.bytes = jsonBytes(
      envelopeJson(
        data: <String, Object?>{
          'li': <Object?>[
            <String, Object?>{'mid': 'fixture-mid', 'mt': 'MT'},
          ],
        },
      ),
    );
    final devices = await api.loginDevice();
    expect(devices.single.current, isTrue);

    adapter.bytes = jsonBytes(envelopeJson());
    final kick = await api.loginDeviceKick(
      const MusicDeviceKickQuery(
        targetMid: 'other',
        activeAtSeconds: 100,
        appId: 3116,
        clientVersion: 11440,
      ),
    );
    expect(kick.removed, isTrue);
    expect(saved, isEmpty);
  });
}
