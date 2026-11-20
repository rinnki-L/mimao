/// 头像引用提交端点测试（user_update_avatar.rs）：文件名校验 / 审核回执分支。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/user_update_avatar.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/user_models.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

void main() {
  late CaptureAdapter adapter;

  setUp(() {
    adapter = CaptureAdapter(
      jsonBytes('{"status":1,"error_code":0,"data":""}'),
    );
  });

  Future<MusicUserAvatarUpdate> submit(String fileName) =>
      fetchUserUpdateAvatar(
        fakeSession(fixedClient(adapter), accountIdentity()),
        fileName,
      );

  test('文件名校验：空/超长/非法字符集 → input 头像文件引用无效', () async {
    for (final bad in <String>[
      '',
      'a' * 257,
      'a/b.png',
      '头 像.png',
      'a b.png',
    ]) {
      await expectLater(
        submit(bad),
        throwsA(
          isA<KugouApiException>()
              .having((e) => e.kind, 'kind', 'input')
              .having((e) => e.message, 'message', '头像文件引用无效'),
        ),
        reason: '非法文件名：$bad',
      );
    }
    expect(adapter.requests, isEmpty);
  });

  test('256 字符上界合法；photo 字段进入共享 submit_fields', () async {
    final fileName = 'a' * 256;
    await submit(fileName);
    final request = adapter.requests.single;
    expect(request.path, 'https://gateway.kugou.com/v1/update_userinfo');
    expect(request.headers['x-router'], 'update.user.kugou.com');
    // request_grade 语义：URL 无默认参数、无签名。
    expect(request.query, isEmpty);
    final body = capturedJsonBody(request);
    final data = Map<String, Object?>.from(body['data']! as Map);
    expect(data, <String, Object?>{'photo': fileName});
  });

  test('成功回执：updated 直链 + reviewPending=false', () async {
    final update = await submit('avatar_2026.png');
    expect(
      update.avatarUrl,
      'http://c1.kgimg.com/v2/kugouicon/avatar_2026.png',
    );
    expect(update.reviewPending, isFalse);
  });

  test('审核回执 34236：不算失败，reviewPending=true', () async {
    adapter.bytes = jsonBytes('{"status":0,"error_code":34236,"data":""}');
    final update = await submit('a.png');
    expect(update.reviewPending, isTrue);
    expect(update.avatarUrl, 'http://c1.kgimg.com/v2/kugouicon/a.png');
  });

  test('其它业务失败 → business 带码', () async {
    adapter.bytes = jsonBytes('{"status":0,"error_code":999,"data":""}');
    await expectLater(
      submit('a.png'),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'business')
            .having((e) => e.code, 'code', 999),
      ),
    );
  });

  test('匿名 → authentication，不发起请求', () async {
    final session = fakeSession(fixedClient(adapter), anonymousIdentity());
    await expectLater(
      fetchUserUpdateAvatar(session, 'a.png'),
      throwsA(
        isA<KugouApiException>().having(
          (e) => e.kind,
          'kind',
          'authentication',
        ),
      ),
    );
    expect(adapter.requests, isEmpty);
  });
}
