/// 组门面测试：MusicUserProfileApi 的 8 个方法各自落到正确端点。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/user_profile_api.dart';
import 'package:mimao/music/api/user_update.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

void main() {
  late CaptureAdapter adapter;
  late KugouUserProfileApi api;

  setUp(() {
    adapter = CaptureAdapter(jsonBytes('{}'));
    api = KugouUserProfileApi(
      fakeSession(fixedClient(adapter), accountIdentity()),
    );
  });

  test('接口委托：8 个方法 → 各自端点路径', () async {
    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":{}}');
    await api.userInfo();
    expect(
      adapter.requests.last.path,
      'https://gateway.kugou.com/v1/get_my_userinfo',
    );

    await api.userDetail();
    expect(
      adapter.requests.last.path,
      'https://gateway.kugou.com/v3/get_my_info',
    );

    await api.userUpdate(const MusicUserUpdateQuery(nickname: '昵称'));
    expect(
      adapter.requests.last.path,
      'https://gateway.kugou.com/v1/update_userinfo',
    );

    await api.userUpdateAvatar('a.png');
    expect(
      adapter.requests.last.path,
      'https://gateway.kugou.com/v1/update_userinfo',
    );

    // 上传回执没有信封字段，单独给根对象形态的响应。
    adapter.bytes = jsonBytes('{"IsSuccess":true,"FileName":["a.png"]}');
    await api.userAvatarUpload(
      imageBase64: 'iVBORw0KGgo=',
      localDate: '20260101',
    );
    expect(
      adapter.requests.last.path,
      'http://imgphp.kugou.com/imageupload/post.php',
    );

    adapter.bytes = jsonBytes('{"status":1,"error_code":0,"data":{}}');
    await api.userVipDetail();
    expect(
      adapter.requests.last.path,
      'https://kugouvip.kugou.com/v1/get_union_vip',
    );

    await api.userGradeInfo(null);
    expect(
      adapter.requests.last.path,
      'https://gateway.kugou.com/v2/get_grade_info',
    );

    await api.userBatchUnionVipinfo(const <int>[1]);
    expect(
      adapter.requests.last.path,
      'https://kugouvip.kugou.com/v2/batch_union_vipinfo',
    );
  });
}
