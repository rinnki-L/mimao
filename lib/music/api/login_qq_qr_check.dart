/// QQ 扫码轮询端点——EchoMusicNext `crates/echo-api/src/module/login_qq_qr_check.rs`
/// 的逐函数翻译。
///
/// 回调文本只按「字符串文法」解析成数据（转义/UTF-16 码元），绝不把 provider
/// 响应当 JS 执行；授权跳转只访问白名单主机，凭证只从 URL/HTML 里取数据。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:mimao/music/api/login_openplat.dart';
import 'package:mimao/music/api/login_qq_qr_create.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/auth_models.dart';

/// 回调参数解析（login_qq_qr_check.rs `callback`）：`ptuiCB('a','b',...)` 的
/// 字符串字段列表；转义支持 \xHH / \uHHHH / \\ / \' / \" / \n \r \t \b \f，
/// 未转义的换行、结尾多余逗号、非逗号分隔、外挂代码都是 decode 失败。
List<String> kugouParseQrCallback(Uint8List bytes) {
  final String text;
  try {
    text = utf8.decode(bytes);
  } on Object {
    throw const KugouApiException('decode', '回调不是合法文本');
  }
  var trimmed = text.trim();
  const prefix = 'ptuiCB(';
  if (!trimmed.startsWith(prefix)) {
    throw const KugouApiException('decode', '回调结构无效');
  }
  var args = trimmed.substring(prefix.length);
  while (args.endsWith(';')) {
    args = args.substring(0, args.length - 1);
  }
  if (!args.endsWith(')')) {
    throw const KugouApiException('decode', '回调结构无效');
  }
  args = args.substring(0, args.length - 1);

  final fields = <String>[];
  final units = <int>[];
  var position = 0;
  bool isWhitespace(int unit) => String.fromCharCode(unit).trim().isEmpty;
  int readHex(int count) {
    var value = 0;
    for (var index = 0; index < count; index++) {
      if (position >= args.length) {
        throw const KugouApiException('decode', '回调转义无效');
      }
      final digit = args.codeUnitAt(position);
      final hex = digit >= 0x30 && digit <= 0x39
          ? digit - 0x30
          : digit >= 0x61 && digit <= 0x66
          ? digit - 0x61 + 10
          : digit >= 0x41 && digit <= 0x46
          ? digit - 0x41 + 10
          : -1;
      if (hex < 0) {
        throw const KugouApiException('decode', '回调转义无效');
      }
      position++;
      value = (value << 4) | hex;
    }
    return value;
  }

  while (position < args.length) {
    while (position < args.length && isWhitespace(args.codeUnitAt(position))) {
      position++;
    }
    if (position >= args.length || args.codeUnitAt(position) != 0x27) {
      throw const KugouApiException('decode', '回调结构无效');
    }
    position++;
    units.clear();
    while (true) {
      if (position >= args.length) {
        throw const KugouApiException('decode', '回调结构无效');
      }
      final unit = args.codeUnitAt(position);
      position++;
      if (unit == 0x27) break; // 字符串结束
      if (unit == 0x5C) {
        // 转义
        if (position >= args.length) {
          throw const KugouApiException('decode', '回调转义无效');
        }
        final escaped = args.codeUnitAt(position);
        position++;
        switch (escaped) {
          case 0x78: // x
            units.add(readHex(2));
          case 0x75: // u
            units.add(readHex(4));
          case 0x5C || 0x27 || 0x22: // \ ' "
            units.add(escaped);
          case 0x6E: // n
            units.add(10);
          case 0x72: // r
            units.add(13);
          case 0x74: // t
            units.add(9);
          case 0x62: // b
            units.add(8);
          case 0x66: // f
            units.add(12);
          default:
            throw const KugouApiException('decode', '回调转义无效');
        }
      } else {
        if (unit == 0x0A || unit == 0x0D) {
          throw const KugouApiException('decode', '回调结构无效');
        }
        units.add(unit);
      }
    }
    fields.add(String.fromCharCodes(units));
    while (position < args.length && isWhitespace(args.codeUnitAt(position))) {
      position++;
    }
    if (position >= args.length) break;
    if (args.codeUnitAt(position) != 0x2C) {
      throw const KugouApiException('decode', '回调结构无效');
    }
    position++;
    if (position >= args.length) {
      throw const KugouApiException('decode', '回调结构无效');
    }
  }
  if (fields.isEmpty) {
    throw const KugouApiException('decode', '回调结构无效');
  }
  return fields;
}

/// 状态映射（login_qq_qr_check.rs `convert`）。
String _convertState(List<String> fields) {
  switch (fields[0]) {
    case '66':
      return MusicQqQrCheckResult.stateWaiting;
    case '65':
      return MusicQqQrCheckResult.stateExpired;
    case '67':
      return MusicQqQrCheckResult.stateScanned;
    case '0':
      return MusicQqQrCheckResult.stateProviderAuthorized;
    default:
      throw const KugouApiException('provider', 'QQ扫码失败，请重新获取二维码');
  }
}

/// 从 URL 的 query 与 fragment 里提取 openid/access_token
/// （login_qq_qr_check.rs `credentials_url`；不跳转、不执行回调 URL）。
MusicProviderAuthorization? kugouQrCredentialsUrl(String urlText) {
  final parsed = Uri.tryParse(urlText);
  if (parsed == null) {
    throw const KugouApiException('decode', '授权地址无效');
  }
  final pairs = <String, String>{};
  void collect(Uri uri) {
    uri.queryParametersAll.forEach((key, values) {
      if (values.isNotEmpty) pairs[key] = values.last;
    });
  }

  collect(parsed);
  final fragment = Uri.tryParse('https://callback.invalid/?${parsed.fragment}');
  if (fragment == null) {
    throw const KugouApiException('decode', '授权地址无效');
  }
  collect(fragment);
  final openid = pairs['openid'];
  final accessToken = pairs['access_token'];
  if (openid != null &&
      accessToken != null &&
      openid.isNotEmpty &&
      accessToken.isNotEmpty) {
    return MusicProviderAuthorization(openid: openid, accessToken: accessToken);
  }
  return null;
}

/// HTML 片段取值（login_qq_qr_check.rs `html_value`）：key 后跳过引号/空白/
/// 冒号/等号，截到第一个分隔符；空值或超长按缺失处理。
String? kugouHtmlValue(String text, String key) {
  final index = text.indexOf(key);
  if (index < 0) return null;
  var tail = text.substring(index + key.length);
  const trimChars = <int>{0x22, 0x27, 0x20, 0x3A, 0x3D};
  while (tail.isNotEmpty && trimChars.contains(tail.codeUnitAt(0))) {
    tail = tail.substring(1);
  }
  const stopChars = <int>{0x26, 0x22, 0x27, 0x20, 0x0A, 0x0D, 0x09};
  var end = 0;
  while (end < tail.length && !stopChars.contains(tail.codeUnitAt(end))) {
    end++;
  }
  final value = tail.substring(0, end);
  if (value.isEmpty || utf8.encode(value).length > 16384) {
    return null;
  }
  return value;
}

/// 大小写不敏感的响应头读取（reqwest HeaderMap 同语义）。
String? kugouHeaderValue(Map<String, String> headers, String name) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) return entry.value;
  }
  return null;
}

/// 授权跳转链（login_qq_qr_check.rs `authorize`）：最多 10 跳；每跳先查
/// URL/fragment 凭证，再校验白名单主机；有 Location 续链，否则从 HTML 取
/// openid/access_token。
Future<MusicProviderAuthorization> _authorize(
  KugouClient client,
  MusicQqQrSession qrSession,
  String initial,
  Map<String, List<String>> pollHeaderValues,
) async {
  const allowedHosts = <String>{
    'xui.ptlogin2.qq.com',
    'ssl.ptlogin2.qq.com',
    'ptlogin2.qq.com',
    'ui.ptlogin2.qq.com',
    'graph.qq.com',
    'connect.qq.com',
    'openmobile.qq.com',
  };
  final jar = <String, String>{};
  for (final pair in qrSession.cookie.split(';')) {
    final trimmed = pair.trim();
    final separator = trimmed.indexOf('=');
    if (separator >= 0) {
      jar[trimmed.substring(0, separator)] = trimmed.substring(separator + 1);
    }
  }
  kugouCollectCookies(pollHeaderValues, jar);
  var urlText = initial;
  if (!urlText.startsWith('http') && !urlText.startsWith('auth:')) {
    urlText = 'https://$urlText';
  }
  final parsed = Uri.tryParse(urlText);
  if (parsed == null) {
    throw const KugouApiException('decode', '授权地址无效');
  }
  var url = parsed;
  for (var hop = 0; hop < 10; hop++) {
    final credentials = kugouQrCredentialsUrl(url.toString());
    if (credentials != null) {
      return credentials;
    }
    if (!allowedHosts.contains(url.host)) {
      throw const KugouApiException('provider', 'QQ授权地址无效');
    }
    final response = await kugouProviderRequest(
      client,
      method: 'GET',
      url: url.toString(),
      headers: <String, String>{
        'User-Agent': kQqUserAgent,
        'Referer': qrSession.xloginUrl,
        'Cookie': kugouCookieString(jar),
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    );
    kugouCollectCookies(response.headerValues, jar);
    final location = kugouHeaderValue(response.headers, 'location');
    if (location != null) {
      url = url.resolve(location);
    } else {
      final String text;
      try {
        text = utf8.decode(response.bytes);
      } on Object {
        throw const KugouApiException('decode', '授权页不是合法文本');
      }
      final openid = kugouHtmlValue(text, 'openid');
      final accessToken = kugouHtmlValue(text, 'access_token');
      if (openid != null && accessToken != null) {
        return MusicProviderAuthorization(
          openid: openid,
          accessToken: accessToken,
        );
      }
      break;
    }
  }
  throw const KugouApiException('provider', 'QQ授权凭证获取失败，请重新扫码');
}

/// QQ 扫码轮询（login_qq_qr_check.rs `execute`；不需要酷狗身份）。
///
/// `random` 仅供测试注入（`r` 参数随机数）。
Future<MusicQqQrCheckResult> fetchLoginQqQrCheck(
  MusicSession session,
  MusicQqQrSession qrSession, {
  Random? random,
}) async {
  if (qrSession.qrsig.isEmpty ||
      qrSession.ptLoginSig.isEmpty ||
      qrSession.cookie.isEmpty ||
      qrSession.openloginData.isEmpty ||
      utf8.encode(qrSession.cookie).length > 32768) {
    throw const KugouApiException('input', 'QQ二维码会话无效');
  }
  final response = await kugouProviderRequest(
    session.client,
    method: 'GET',
    url: 'https://xui.ptlogin2.qq.com/ssl/ptqrlogin',
    params: <String, String>{
      'u1': 'http://connect.qq.com',
      'from_ui': '1',
      'type': '1',
      'ptlang': '2052',
      'ptqrtoken': '${qrSession.ptqrtoken}',
      'daid': '381',
      'aid': '716027609',
      'pt_3rd_aid': kQqLiteAppId,
      'pt_openlogin_data': qrSession.openloginData,
      'device': '2',
      'ptopt': '1',
      'pt_uistyle': '35',
      'jsver': 'v1.36.0',
      'login_sig': qrSession.ptLoginSig,
      'r': kugouProviderNonce(random),
    },
    headers: <String, String>{
      'User-Agent': kQqUserAgent,
      'Referer': qrSession.xloginUrl,
      'Cookie': qrSession.cookie,
    },
  );
  final fields = kugouParseQrCallback(response.bytes);
  final state = _convertState(fields);
  if (state == MusicQqQrCheckResult.stateProviderAuthorized) {
    final redirect = fields.length > 2 ? fields[2] : null;
    if (redirect == null || redirect.isEmpty) {
      throw const KugouApiException('provider', 'QQ授权未返回跳转地址');
    }
    final authorization = await _authorize(
      session.client,
      qrSession,
      redirect,
      response.headerValues,
    );
    return MusicQqQrCheckResult(state: state, authorization: authorization);
  }
  return MusicQqQrCheckResult(state: state);
}
