/// 捕获型 HttpClientAdapter：离线断言请求装配（路径/头/参数/签名/请求体）。
///
/// 端点扩容后一个测试常需要「多次请求不同响应」（登录流程、分页链路），
/// 因此支持按请求序号取 [responses]/[responseStatusCodes]；未配置的序号
/// 回退到 [bytes]/[statusCode]。所有请求的装配快照都留在 [requests]。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 一次请求的可读快照（RequestOptions 会被 dio 复用/回收，不能直接留引用）。
class CapturedRequest {
  const CapturedRequest({
    required this.method,
    required this.path,
    required this.queryParameters,
    required this.headers,
    required this.data,
  });

  final String method;
  final String path;
  final Map<String, Object?> queryParameters;
  final Map<String, Object?> headers;
  final Object? data;

  Map<String, String> get query =>
      queryParameters.map((key, value) => MapEntry(key, '$value'));

  /// 请求体的文本形式（`Uint8List` / `List<int>` / `String`）。
  String get bodyText {
    final body = data;
    if (body == null) return '';
    if (body is String) return body;
    if (body is Uint8List) return utf8.decode(body);
    if (body is List<int>) return utf8.decode(body);
    return '$body';
  }
}

class CaptureAdapter implements HttpClientAdapter {
  CaptureAdapter(this.bytes);

  /// 可变：测试中途替换默认响应体。
  Uint8List bytes;

  /// 默认 HTTP 状态码。
  int statusCode = 200;

  /// 按请求序号返回的响应体；长度不足的序号回退到 [bytes]。
  final List<Uint8List> responses = <Uint8List>[];

  /// 按请求序号返回的 HTTP 状态码；长度不足的序号回退到 [statusCode]。
  final List<int> responseStatusCodes = <int>[];

  /// 全部请求快照（按发生顺序）。
  final List<CapturedRequest> requests = <CapturedRequest>[];

  /// 最近一次请求（兼容既有测试的读取方式）。
  final RequestOptions captured = RequestOptions(path: '/');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(
      CapturedRequest(
        method: options.method,
        path: options.path,
        queryParameters: Map<String, Object?>.from(options.queryParameters),
        headers: Map<String, Object?>.from(options.headers),
        data: options.data,
      ),
    );
    captured
      ..method = options.method
      ..path = options.path
      ..queryParameters = options.queryParameters
      ..headers = options.headers
      ..data = options.data;
    final index = requests.length - 1;
    final body = index < responses.length ? responses[index] : bytes;
    final status = index < responseStatusCodes.length
        ? responseStatusCodes[index]
        : statusCode;
    return ResponseBody.fromBytes(body, status);
  }

  @override
  void close({bool force = false}) {}
}

/// 响应体快捷构造。
Uint8List jsonBytes(String json) => Uint8List.fromList(utf8.encode(json));

/// 捕获的 query 统一成字符串表（签名自验用）。
Map<String, String> capturedQuery(RequestOptions options) =>
    options.queryParameters.map((key, value) => MapEntry(key, '$value'));
