/// QQ 扫码创建端点——EchoMusicNext `crates/echo-api/src/module/login_qq_qr_create.rs`
/// 的逐函数翻译。
///
/// 三段 provider 请求（m_authorize HTML → xlogin 跳板取 cookie → ptqrshow
/// 取二维码 PNG），全程 provider 主机白名单 + QQ UA，无酷狗签名/身份。
/// 会话材料（cookie/pt_login_sig/qrsig）只回传给调用方流转，不再外泄。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:mimao/music/api/login_openplat.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/auth_models.dart';

const String _kDecodeCookie = 'Set-Cookie 头无效';
const String _kDecodeSession = '授权页缺少跳转地址';

/// 收集响应的 set-cookie 到会话 jar（login_qq_qr_create.rs `cookies`）：
/// 取 `;` 前的 name=value；无 `=` → decode；空 name 跳过。
///
/// 注意：共享层 `KugouHttpResponse.headers` 对同名多值响应头只保留第一个，
/// 多条 Set-Cookie 的完整采集需要共享层扩展（见交付报告）。
void kugouCollectCookies(Map<String, String> headers, Map<String, String> jar) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() != 'set-cookie') continue;
    final pair = entry.value.split(';').first;
    final separator = pair.indexOf('=');
    if (separator < 0) {
      throw const KugouApiException('decode', _kDecodeCookie);
    }
    final name = pair.substring(0, separator);
    if (name.isNotEmpty) {
      jar[name] = pair.substring(separator + 1);
    }
  }
}

/// jar 序列化（login_qq_qr_create.rs `cookie_string`；BTreeMap 键序）。
String kugouCookieString(Map<String, String> jar) {
  final keys = jar.keys.toList()..sort();
  return <String>[for (final key in keys) '$key=${jar[key]}'].join('; ');
}

/// qrsig → ptqrtoken（login_qq_qr_create.rs `hash33`；u32 wrapping 乘 33）。
int kugouQqHash33(String value) {
  var sum = 0;
  for (final unit in value.codeUnits) {
    sum = (sum * 33 + unit) & 0xFFFFFFFF;
  }
  return sum & 0x7FFFFFFF;
}

/// 授权页 HTML 里的 `src = "..."` 跳转地址（login_qq_qr_create.rs `xlogin`）：
/// 解码 \xHH 转义（必须是 ASCII 字节），并校验 https + xui.ptlogin2.qq.com +
/// /cgi-bin/xlogin。
Uri kugouParseXlogin(Uint8List bytes) {
  final String text;
  try {
    text = utf8.decode(bytes);
  } on Object {
    throw const KugouApiException('decode', _kDecodeSession);
  }
  const marker = 'src = "';
  final start = text.indexOf(marker);
  if (start < 0) {
    throw const KugouApiException('decode', _kDecodeSession);
  }
  final from = start + marker.length;
  final end = text.indexOf('"', from);
  if (end < 0) {
    throw const KugouApiException('decode', _kDecodeSession);
  }
  final buffer = StringBuffer();
  var remaining = text.substring(from, end);
  while (true) {
    final index = remaining.indexOf(r'\x');
    if (index < 0) {
      buffer.write(remaining);
      break;
    }
    buffer.write(remaining.substring(0, index));
    final tail = remaining.substring(index + 2);
    if (tail.length < 2) {
      throw const KugouApiException('decode', _kDecodeSession);
    }
    final byte = int.tryParse(tail.substring(0, 2), radix: 16);
    if (byte == null || byte > 0x7f) {
      throw const KugouApiException('decode', _kDecodeSession);
    }
    buffer.writeCharCode(byte);
    remaining = tail.substring(2);
  }
  final uri = Uri.tryParse(buffer.toString());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'xui.ptlogin2.qq.com' ||
      uri.path != '/cgi-bin/xlogin') {
    throw const KugouApiException('decode', '授权跳转地址无效');
  }
  return uri;
}

/// QQ 扫码创建（login_qq_qr_create.rs `execute`；不需要酷狗身份）。
///
/// `timestampSeconds`/`random` 仅供测试注入。
Future<MusicQqQrSession> fetchLoginQqQrCreate(
  MusicSession session, {
  int? timestampSeconds,
  Random? random,
}) async {
  final seconds =
      timestampSeconds ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final time = '$seconds';
  final sign = md5
      .convert(utf8.encode('fe4a24d80fcf253a00676a808f62c2c6_$time'))
      .toString();
  const appid = kQqLiteAppId;
  const headers = <String, String>{
    'User-Agent': kQqUserAgent,
    'Referer': 'https://xui.ptlogin2.qq.com/',
  };
  final authorize = await kugouProviderRequest(
    session.client,
    method: 'GET',
    url: 'https://openmobile.qq.com/oauth2.0/m_authorize',
    params: <String, String>{
      'cancel_display': '1',
      'sdkp': 'a',
      'display': 'mobile',
      'format': 'json',
      'sign': sign,
      'sdkv': '3.5.11.lite',
      'response_type': 'token',
      'status_os': '11',
      'client_id': appid,
      'switch': '1',
      'status_version': '30',
      'show_download_ui': 'true',
      'pf': 'openmobile_android',
      'scope': 'all',
      'compat_v': '1',
      'status_machine': 'MEIZU+18+Pro',
      'style': 'qr',
      'time': time,
      'redirect_uri': 'auth://tauth.qq.com/',
    },
    headers: headers,
  );
  final xlogin = kugouParseXlogin(authorize.bytes);
  final xloginResponse = await kugouProviderRequest(
    session.client,
    method: 'GET',
    url: xlogin.toString(),
    headers: headers,
  );
  final jar = <String, String>{};
  kugouCollectCookies(xloginResponse.headers, jar);
  final sig = jar['pt_login_sig'];
  if (sig == null || sig.isEmpty) {
    throw const KugouApiException('decode', '授权会话缺少 pt_login_sig');
  }
  final cookie = kugouCookieString(jar);
  final nonce = kugouProviderNonce(random);
  final qr = await kugouProviderRequest(
    session.client,
    method: 'GET',
    url: 'https://xui.ptlogin2.qq.com/ssl/ptqrshow',
    params: <String, String>{
      's': '8',
      'e': '0',
      'appid': '716027609',
      'type': '0',
      't': nonce,
      'daid': '381',
      'pt_3rd_aid': appid,
    },
    headers: <String, String>{
      'User-Agent': kQqUserAgent,
      'Referer': xlogin.toString(),
      'Cookie': cookie,
    },
  );
  kugouCollectCookies(qr.headers, jar);
  final qrsig = jar['qrsig'];
  if (qrsig == null || qrsig.isEmpty) {
    throw const KugouApiException('decode', '二维码会话缺少 qrsig');
  }
  if (!_startsWithPng(qr.bytes)) {
    throw const KugouApiException('decode', '二维码不是 PNG 图片');
  }
  return MusicQqQrSession(
    xloginUrl: xlogin.toString(),
    ptLoginSig: sig,
    ptqrtoken: kugouQqHash33(qrsig),
    qrsig: qrsig,
    cookie: kugouCookieString(jar),
    openloginData: xlogin.query,
    imageDataUrl: 'data:image/png;base64,${base64Encode(qr.bytes)}',
  );
}

/// provider 轮询随机数 `0.<u64>`（login_qq_qr_create.rs / login_qq_qr_check.rs
/// 的 `t`/`r` 参数；`random` 为 null 时用安全随机源）。
String kugouProviderNonce(Random? random) {
  final source = random ?? Random.secure();
  final value =
      (BigInt.from(source.nextInt(1 << 32)) << 32) |
      BigInt.from(source.nextInt(1 << 32));
  return '0.$value';
}

/// PNG 魔数（\x89PNG\r\n\x1a\n）。
bool _startsWithPng(List<int> bytes) {
  const magic = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < magic.length) return false;
  for (var index = 0; index < magic.length; index++) {
    if (bytes[index] != magic[index]) return false;
  }
  return true;
}
