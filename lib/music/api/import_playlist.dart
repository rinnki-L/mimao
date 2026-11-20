/// 歌单导入端点——EchoMusicNext `crates/echo-api/src/module/import_playlist.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 导入分享链接/截图两个阶段与任务结果。资产服务（assetservice）的信封用
/// `errcode` 字段、pubsongs 的明细用 `error_code`；任务行里的 id 是字符串、
/// 回执与结果里是数字——都按 `optional` 宽容解析。
///
/// 传输走 `request_import`（sendEndpoint clearDefaults: true）：URL 只保留
/// 六个设备/应用字段 + signature，账号凭证放在 JSON body 里。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/playlist_models.dart';

/// 导入动作查询（import_playlist.rs `Query` 的六个 snake_case 分支）。
sealed class MusicImportQuery {
  const MusicImportQuery();
}

/// 分享链接导入（Query::Link）。
class MusicImportLinkQuery extends MusicImportQuery {
  const MusicImportLinkQuery(this.url);

  final String url;
}

/// 截图提交（Query::SubmitImage）。
class MusicImportSubmitImageQuery extends MusicImportQuery {
  const MusicImportSubmitImageQuery({
    required this.taskSn,
    required this.imageBase64,
  });

  final String taskSn;
  final String imageBase64;
}

/// 截图落库到目标歌单（Query::Screenshot）。
class MusicImportScreenshotQuery extends MusicImportQuery {
  const MusicImportScreenshotQuery({
    required this.taskSn,
    required this.cloudListId,
    required this.title,
  });

  final String taskSn;
  final int cloudListId;
  final String title;
}

/// 任务状态批量查询（Query::Status）。
class MusicImportStatusQuery extends MusicImportQuery {
  const MusicImportStatusQuery(this.taskIds);

  final List<int> taskIds;
}

/// 导入明细分页（Query::Result）。
class MusicImportResultQuery extends MusicImportQuery {
  const MusicImportResultQuery({
    required this.cloudListId,
    required this.page,
    required this.pageSize,
  });

  final int cloudListId;
  final int page;
  final int pageSize;
}

/// 任务计数（Query::Count）。
class MusicImportCountQuery extends MusicImportQuery {
  const MusicImportCountQuery();
}

/// POST <动作路径>（网关，无 router；request_import = clearDefaults）。
Future<MusicImportOutcome> fetchImportPlaylist(
  MusicSession session,
  MusicImportQuery query,
) async {
  final identity = await session.ensureDevice();
  // 上游 execute：账号前置校验先于动作级 input 校验。
  requireMusicAccount(identity);
  final body = <String, Object?>{
    'userid': identity.userId.toString(),
    'token': identity.token,
  };
  String path;
  switch (query) {
    case MusicImportLinkQuery(:final url):
      // Rust String::len 是字节数；分享链接必须含 https://。
      if (utf8.encode(url).length > 8192 || !url.contains('https://')) {
        throw const KugouApiException('input', '请输入歌单分享链接');
      }
      body['source'] = 3;
      body['task_type'] = 0;
      body['url'] = url;
      path = '/assetservice/import/v1/add_task';
    case MusicImportSubmitImageQuery(:final taskSn, :final imageBase64):
      // base64 字母表是 ASCII：字符数即字节数（14MB 上限按上游 14 * 1024 * 1024）。
      if (taskSn.isEmpty ||
          utf8.encode(taskSn).length > 128 ||
          imageBase64.isEmpty ||
          imageBase64.length > 14 * 1024 * 1024) {
        throw const KugouApiException('input', '截图数据无效');
      }
      body['task_sn'] = taskSn;
      body['img_base64'] = imageBase64;
      path = '/assetservice/import/v1/submit_img';
    case MusicImportScreenshotQuery(
      :final taskSn,
      :final cloudListId,
      :final title,
    ):
      if (taskSn.isEmpty ||
          utf8.encode(taskSn).length > 128 ||
          cloudListId == 0 ||
          title.trim().isEmpty ||
          utf8.encode(title).length > 1024) {
        throw const KugouApiException('input', '请选择或创建目标歌单');
      }
      body['source'] = 3;
      body['task_type'] = 1;
      body['task_sn'] = taskSn;
      body['listid'] = cloudListId;
      body['list_name'] = title;
      path = '/assetservice/import/v1/add_task';
    case MusicImportStatusQuery(:final taskIds):
      if (taskIds.isEmpty || taskIds.length > 100 || taskIds.contains(0)) {
        throw const KugouApiException('input', '导入任务标识无效');
      }
      body['ids'] = taskIds;
      path = '/assetservice/import/v1/query_task_status';
    case MusicImportResultQuery(
      :final cloudListId,
      :final page,
      :final pageSize,
    ):
      if (cloudListId == 0 || page < 1 || pageSize < 1 || pageSize > 100) {
        throw const KugouApiException('input', '导入明细分页无效');
      }
      // 明细接口的 listid 是字符串（与 add_task 的数字相反）。
      body['listid'] = cloudListId.toString();
      body['page'] = page;
      body['pagesize'] = pageSize;
      body['show_missed'] = 1;
      path = '/pubsongs/v1/query_task';
    case MusicImportCountQuery():
      body['classify'] = 1;
      path = '/assetservice/import/v1/task_count';
  }
  // request::unix_seconds（与传输层的 clienttime 同源）。
  final unixSeconds =
      (session.client.now?.call() ?? DateTime.now()).millisecondsSinceEpoch ~/
      1000;
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: path,
      method: 'POST',
      params: <String, String>{
        'appid': '3116',
        'clientver': '11440',
        'clienttime': unixSeconds.toString(),
        'mid': identity.mid,
        'uuid': '-',
        'dfid': identity.dfid,
      },
      body: encodeJsonBody(body),
    ),
    clearDefaults: true,
  );
  return switch (query) {
    MusicImportLinkQuery() || MusicImportScreenshotQuery() =>
      MusicImportCreatedOutcome(convertImportCreated(response.bytes)),
    MusicImportSubmitImageQuery() => convertImportUpload(response.bytes),
    MusicImportStatusQuery() => MusicImportStatusOutcome(
      convertImportStatus(response.bytes),
    ),
    MusicImportResultQuery(:final page, :final pageSize) =>
      MusicImportResultOutcome(
        convertImportResult(response.bytes, page: page, pageSize: pageSize),
      ),
    MusicImportCountQuery() => convertImportCount(response.bytes),
  };
}

/// 根对象解码：request::decode 的 20018/过期文本判定先于结构解析。
Object? _decodeJson(Uint8List bytes) {
  try {
    return jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
}

/// request.rs `authentication_expiration`：认 raw error_code=20018 或
/// msg 含「登录已过期」（code 随 error_code 透传）。
void _ensureNotExpired(Object? decoded) {
  if (decoded is! Map) return;
  final code = optionalInt(decoded['error_code']);
  final message = decoded['msg'];
  if (code == kugouErrorCodeAuthenticationExpired ||
      (message is String && message.contains('登录已过期'))) {
    throw KugouApiException('authentication', '账号认证无效，请重新登录', code: code);
  }
}

/// AssetWire（import_playlist.rs `asset`）：status/errcode 必填标量。
WireEnvelope _asset(Uint8List bytes) {
  final decoded = _decodeJson(bytes);
  _ensureNotExpired(decoded);
  if (decoded is! Map) {
    throw const KugouApiException('decode', '响应信封不是 JSON object');
  }
  final status = requiredScalarInt(decoded['status'], 'status');
  final errcode = requiredScalarInt(decoded['errcode'], 'errcode');
  ensureBusinessSuccess(status, errcode, context: '导入任务');
  return WireEnvelope(status, errcode, decoded['data']);
}

/// convert_created：add_task 的任务回执（data 必须是 object）。
MusicImportTask convertImportCreated(Uint8List bytes) {
  final data = _asset(bytes).data;
  final map = requiredWireMap(data, '导入任务回执 data');
  return MusicImportTask(
    taskId: optionalInt(map['id']),
    userId: optionalInt(map['userid']),
    cloudListId: optionalInt(map['listid']),
    source: optionalInt(map['source']),
    taskType: optionalInt(map['task_type']),
    status: optionalInt(map['status']),
    title: '',
    message: '',
  );
}

/// convert_status：query_task_status 的任务行列表（data null → 空）。
List<MusicImportTask> convertImportStatus(Uint8List bytes) {
  final data = _asset(bytes).data;
  if (data == null) return const <MusicImportTask>[];
  if (data is! List) {
    throw const KugouApiException('decode', '导入任务状态 data 不是数组');
  }
  return <MusicImportTask>[for (final row in data) _convertStatusRow(row)];
}

MusicImportTask _convertStatusRow(Object? raw) {
  final map = wireMap(raw);
  if (map == null) {
    throw const KugouApiException('decode', '导入任务状态行不是 object');
  }
  return MusicImportTask(
    taskId: optionalInt(map['id']),
    userId: optionalInt(map['userid']),
    cloudListId: optionalInt(map['listid']),
    source: optionalInt(map['source']),
    taskType: optionalInt(map['type']),
    status: optionalInt(map['status']),
    title: wireText(map['name']),
    total: optionalInt(map['songs_num']),
    matched: optionalInt(map['matched_num']),
    imported: optionalInt(map['imported_num']),
    missed: optionalInt(map['missed_num']),
    message: wireText(map['msg']),
  );
}

/// convert_upload：submit_img 只回字符串确认，上游折叠成 {"uploaded":true}。
MusicImportUploadedOutcome convertImportUpload(Uint8List bytes) {
  _asset(bytes);
  return const MusicImportUploadedOutcome();
}

/// convert_result：pubsongs 明细信封（error_code 字段）+ ResultData。
/// page/pageSize 回显请求实参（wire data 里没有这两个字段）。
MusicImportResult convertImportResult(
  Uint8List bytes, {
  required int page,
  required int pageSize,
}) {
  final decoded = _decodeJson(bytes);
  _ensureNotExpired(decoded);
  if (decoded is! Map) {
    throw const KugouApiException('decode', '响应信封不是 JSON object');
  }
  final status = requiredScalarInt(decoded['status'], 'status');
  final errorCode = requiredScalarInt(decoded['error_code'], 'error_code');
  ensureBusinessSuccess(status, errorCode, context: '导入明细');
  final data = requiredWireMap(decoded['data'], '导入明细 data');
  return MusicImportResult(
    task: MusicImportTask(
      taskId: optionalInt(data['id']),
      userId: optionalInt(data['userid']),
      cloudListId: optionalInt(data['listid']),
      source: optionalInt(data['source']),
      status: optionalInt(data['status']),
      title: wireText(data['name']),
      total: optionalInt(data['songs_num']),
      imported: optionalInt(data['imported_num']),
      missed: optionalInt(data['missed_num']),
      message: '',
    ),
    missedTracks: <MusicMissedTrack>[
      for (final row in wireList(data['missed'], 'missed'))
        _convertMissedRow(row),
    ],
    page: page,
    pageSize: pageSize,
  );
}

MusicMissedTrack _convertMissedRow(Object? raw) {
  final map = wireMap(raw);
  if (map == null) {
    throw const KugouApiException('decode', '导入明细缺失行不是 object');
  }
  return MusicMissedTrack(
    title: wireText(map['audio_name']),
    artist: wireText(map['author_name']),
    album: wireText(map['album_name']),
    reason: wireText(map['reason']),
  );
}

/// convert_count：task_count 的 userid/count/fail_count。
MusicImportCountOutcome convertImportCount(Uint8List bytes) {
  final data = _asset(bytes).data;
  final map = requiredWireMap(data, '导入统计 data');
  return MusicImportCountOutcome(
    userId: optionalInt(map['userid']),
    count: optionalInt(map['count']),
    failedCount: optionalInt(map['fail_count']),
  );
}
