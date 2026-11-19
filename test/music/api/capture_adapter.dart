/// 捕获型 HttpClientAdapter：离线断言请求装配（路径/头/参数/签名）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class CaptureAdapter implements HttpClientAdapter {
  CaptureAdapter(this.bytes);

  /// 可变：测试中途替换响应体。
  Uint8List bytes;

  final RequestOptions captured = RequestOptions(path: '/');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured
      ..method = options.method
      ..path = options.path
      ..queryParameters = options.queryParameters
      ..headers = options.headers;
    return ResponseBody.fromBytes(bytes, 200);
  }

  @override
  void close({bool force = false}) {}
}

/// 响应体快捷构造。
Uint8List jsonBytes(String json) => Uint8List.fromList(utf8.encode(json));

/// 捕获的 query 统一成字符串表（签名自验用）。
Map<String, String> capturedQuery(RequestOptions options) =>
    options.queryParameters.map((key, value) => MapEntry(key, '$value'));
