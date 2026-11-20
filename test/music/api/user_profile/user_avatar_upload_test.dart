/// 头像图片上传端点测试（user_avatar_upload.rs）：
/// base64/魔数分支、multipart 装配（边界避让）、上传回执解码。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimao/music/api/user_avatar_upload.dart';
import 'package:mimao/music/client/kugou_crypto.dart';
import 'package:mimao/music/client/kugou_error.dart';

import '../capture_adapter.dart';
import 'fake_session.dart';

const String kBoundary = 'EchoMusicAvatarBoundary';

const List<int> kPngMagic = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

Future<void> upload(
  CaptureAdapter adapter,
  Uint8List image, {
  String date = '20260101',
}) {
  final session = fakeSession(fixedClient(adapter), accountIdentity());
  return fetchUserAvatarUpload(
    session,
    imageBase64: base64.encode(image),
    localDate: date,
  );
}

void main() {
  late CaptureAdapter adapter;

  setUp(() {
    adapter = CaptureAdapter(
      jsonBytes('{"IsSuccess":true,"FileName":["avatar_file.png"]}'),
    );
  });

  test('匿名 → authentication，不发起请求', () async {
    final session = fakeSession(fixedClient(adapter), anonymousIdentity());
    await expectLater(
      fetchUserAvatarUpload(
        session,
        imageBase64: base64.encode(kPngMagic),
        localDate: '20260101',
      ),
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

  test('base64 非法（URL-safe 字母表/长度不齐）→ input 图片数据无效', () async {
    final session = fakeSession(fixedClient(adapter), accountIdentity());
    for (final bad in <String>['-_-_-', 'iVBORw0KGgo', 'a=b']) {
      await expectLater(
        fetchUserAvatarUpload(session, imageBase64: bad, localDate: '20260101'),
        throwsA(
          isA<KugouApiException>()
              .having((e) => e.kind, 'kind', 'input')
              .having((e) => e.message, 'message', '图片数据无效'),
        ),
        reason: '非法 base64：$bad',
      );
    }
    expect(adapter.requests, isEmpty);
  });

  test('空图片 → input 8MB 文案；base64 超长在解码前拒绝', () async {
    final session = fakeSession(fixedClient(adapter), accountIdentity());
    await expectLater(
      fetchUserAvatarUpload(session, imageBase64: '', localDate: '20260101'),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'input')
            .having((e) => e.message, 'message', '头像图片不能超过 8 MB'),
      ),
    );
    // LIMIT.div_ceil(3)*4 = 11184812：超限先拒，不解码。
    await expectLater(
      fetchUserAvatarUpload(
        session,
        imageBase64: 'A' * 11184813,
        localDate: '20260101',
      ),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'input')
            .having((e) => e.message, 'message', '头像图片不能超过 8 MB'),
      ),
    );
    // 解码后 > 8MB 原始字节同样拒绝。
    await expectLater(
      upload(
        adapter,
        Uint8List.fromList(<int>[
          ...kPngMagic,
          ...List<int>.filled(8 * 1024 * 1024, 0x41),
        ]),
      ),
      throwsA(
        isA<KugouApiException>().having(
          (e) => e.message,
          'message',
          '头像图片不能超过 8 MB',
        ),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('魔数拒绝：非图片字节 → input 请选择 JPEG、PNG 或 GIF 图片', () async {
    await expectLater(
      upload(adapter, Uint8List.fromList(utf8.encode('plain text'))),
      throwsA(
        isA<KugouApiException>()
            .having((e) => e.kind, 'kind', 'input')
            .having((e) => e.message, 'message', '请选择 JPEG、PNG 或 GIF 图片'),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('本地日期非法 → input 图片上传日期无效', () async {
    await expectLater(
      upload(adapter, Uint8List.fromList(kPngMagic), date: '20260230'),
      throwsA(
        isA<KugouApiException>().having(
          (e) => e.message,
          'message',
          '图片上传日期无效',
        ),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('multipart 装配：固定主机/type·md5·file 三段/图片字节原样嵌入', () async {
    final image = Uint8List.fromList(<int>[...kPngMagic, 1, 2, 3]);
    await upload(adapter, image);

    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.path, 'http://imgphp.kugou.com/imageupload/post.php');
    // 图片不含边界：不追加 x。
    expect(
      request.headers['Content-Type'],
      'multipart/form-data; boundary=$kBoundary',
    );
    // 裸传输：无身份/签名/路由头。
    expect(request.headers.containsKey('x-router'), isFalse);
    expect(request.headers.containsKey('dfid'), isFalse);
    expect(request.headers.containsKey('mid'), isFalse);

    final body = request.data! as Uint8List;
    final head = utf8.encode(
      '--$kBoundary\r\n'
      'Content-Disposition: form-data; name="type"\r\n\r\n'
      'kugouicon\r\n'
      '--$kBoundary\r\n'
      'Content-Disposition: form-data; name="md5"\r\n\r\n'
      '${kugouImageChecksum('20260101')}\r\n'
      '--$kBoundary\r\n'
      'Content-Disposition: form-data; name="file"; filename="avatar.png"\r\n'
      'Content-Type: image/png\r\n\r\n',
    );
    final tail = utf8.encode('\r\n--$kBoundary--\r\n');
    expect(body.length, head.length + image.length + tail.length);
    expect(body.sublist(0, head.length), head);
    expect(body.sublist(head.length, head.length + image.length), image);
    expect(body.sublist(body.length - tail.length), tail);
  });

  test('jpg/gif 变体：魔数 → 扩展名与 MIME', () async {
    const gif87 = <int>[0x47, 0x49, 0x46, 0x38, 0x37, 0x61];
    const gif89 = <int>[0x47, 0x49, 0x46, 0x38, 0x39, 0x61];
    for (final (magic, name, mime) in const <(List<int>, String, String)>[
      (<int>[0xFF, 0xD8, 0xFF], 'jpg', 'image/jpeg'),
      (gif87, 'gif', 'image/gif'),
      (gif89, 'gif', 'image/gif'),
    ]) {
      final image = Uint8List.fromList(magic);
      await upload(adapter, image);
      final request = adapter.requests.last;
      expect(
        request.headers['Content-Type'],
        'multipart/form-data; boundary=$kBoundary',
      );
      expect(
        bytesContain(
          request.data! as List<int>,
          utf8.encode('filename="avatar.$name"'),
        ),
        isTrue,
      );
      expect(
        bytesContain(
          request.data! as List<int>,
          utf8.encode('Content-Type: $mime'),
        ),
        isTrue,
      );
    }
  });

  test('边界避让：图片包含基础边界 → 逐次追加 x', () async {
    final image = Uint8List.fromList(<int>[
      ...kPngMagic,
      ...utf8.encode('$kBoundary tail'),
    ]);
    await upload(adapter, image);
    final request = adapter.requests.single;
    expect(
      request.headers['Content-Type'],
      'multipart/form-data; boundary=${kBoundary}x',
    );
    final body = request.data! as Uint8List;
    expect(bytesContain(body, utf8.encode('--${kBoundary}x\r\n')), isTrue);
    expect(
      bytesContain(body, utf8.encode('\r\n--${kBoundary}x--\r\n')),
      isTrue,
    );
    // 新边界不在图片字节里（避让成功）。
    expect(bytesContain(body, utf8.encode('${kBoundary}x tail')), isFalse);
  });

  test('回执解码：首个非空 FileName → file_name；数字/字符串布尔宽容', () async {
    for (final success in const <Object?>[true, 'true', 1, '1']) {
      adapter.bytes = jsonBytes(
        '{"IsSuccess":$success,"FileName":["first.png","second.png"]}',
      );
      final session = fakeSession(fixedClient(adapter), accountIdentity());
      final upload = await fetchUserAvatarUpload(
        session,
        imageBase64: base64.encode(kPngMagic),
        localDate: '20260101',
      );
      expect(upload.fileName, 'first.png', reason: 'success=$success');
    }
  });

  test('回执失败/缺文件名/非文本项 → 对应异常', () async {
    Future<void> expectBody(String body, String kind) async {
      adapter.bytes = jsonBytes(body);
      final session = fakeSession(fixedClient(adapter), accountIdentity());
      await expectLater(
        fetchUserAvatarUpload(
          session,
          imageBase64: base64.encode(kPngMagic),
          localDate: '20260101',
        ),
        throwsA(isA<KugouApiException>().having((e) => e.kind, 'kind', kind)),
        reason: body,
      );
    }

    await expectBody('{"IsSuccess":false,"FileName":["a.png"]}', 'business');
    await expectBody('{"FileName":["a.png"]}', 'decode');
    await expectBody('{"IsSuccess":true,"FileName":[]}', 'decode');
    await expectBody('{"IsSuccess":true,"FileName":[""]}', 'decode');
    await expectBody('{"IsSuccess":true,"FileName":[{"a":1}]}', 'decode');
    // 登录过期仍按传输层语义映射（UploadWire 没有信封字段）。
    await expectBody(
      '{"IsSuccess":false,"error_code":20018}',
      'authentication',
    );
  });
}
