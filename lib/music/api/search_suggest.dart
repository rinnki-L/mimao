/// 搜索建议端点——EchoMusicNext `crates/echo-api/src/module/search_suggest.rs`
/// 的翻译（docs/architecture.md §4.3：`music/api/` ← module，一端点一文件）。
///
/// 分组是带类型的展示字段；SingerShortcut/Shortcuts 快捷扩展未建模、原样
/// 保留（上游注释：导航语义确立前不并入分组）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/search_models.dart';

/// 搜索建议的输入（search_suggest.rs `Query`；四个限额默认各 10）。
class MusicSearchSuggestQuery {
  const MusicSearchSuggestQuery({
    required this.keyword,
    this.albumLimit = 10,
    this.correctionLimit = 10,
    this.mvLimit = 10,
    this.musicLimit = 10,
  });

  final String keyword;

  /// 四类建议条数，合法区间都是 1..=100（Rust `default_limit` = 10）。
  final int albumLimit;
  final int correctionLimit;
  final int mvLimit;
  final int musicLimit;

  void validate() {
    if (keyword.trim().isEmpty ||
        _invalidLimit(albumLimit) ||
        _invalidLimit(correctionLimit) ||
        _invalidLimit(mvLimit) ||
        _invalidLimit(musicLimit)) {
      throw const KugouApiException('input', '搜索建议参数无效');
    }
  }

  static bool _invalidLimit(int limit) => limit < 1 || limit > 100;
}

/// GET /v2/getSearchTip（网关 + x-router=searchtip.kugou.com）。
Future<MusicSearchSuggestions> fetchSearchSuggest(
  MusicSession session,
  MusicSearchSuggestQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/v2/getSearchTip',
      router: 'searchtip.kugou.com',
      method: 'GET',
      params: <String, String>{
        'keyword': query.keyword,
        'AlbumTipCount': query.albumLimit.toString(),
        'CorrectTipCount': query.correctionLimit.toString(),
        'MVTipCount': query.mvLimit.toString(),
        'MusicTipCount': query.musicLimit.toString(),
        'radiotip': '1',
      },
    ),
  );
  return _convertSearchSuggest(response.bytes);
}

/// wire 解析（search_suggest.rs `convert`）。
///
/// 信封是本端点自有结构：根上除了 status/error_code/data（分组列表），还有
/// SingerShortcut/Shortcuts 两个未建模扩展键——所以不走共享三件套，根对象
/// 自行解码（[_decodeSuggestRoot] 含 request.rs `decode_envelope` 的回退链）。
MusicSearchSuggestions _convertSearchSuggest(Uint8List bytes) {
  final root = _decodeSuggestRoot(bytes);
  ensureBusinessSuccess(
    requiredScalarInt(root['status'], 'status'),
    requiredScalarInt(root['error_code'], 'error_code'),
    context: '搜索建议',
  );
  return MusicSearchSuggestions(
    groups: wireList(root['data'], 'data').map(_convertSuggestGroup).toList(),
    // optional<Value> 永不失败：null/缺省 → null，其余原样保留。
    singerShortcutExtension: root['SingerShortcut'],
    shortcutsExtension: root['Shortcuts'],
  );
}

/// 根对象解码 + 回退链。
Map<String, Object?> _decodeSuggestRoot(Uint8List bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  final root = wireMap(decoded);
  if (root == null) {
    throw const KugouApiException('decode', '搜索建议响应信封不是 JSON object');
  }
  try {
    // request.rs decode 前置：根上 error_code=20018 → authentication。
    if (optionalInt(root['error_code']) ==
        kugouErrorCodeAuthenticationExpired) {
      throw const KugouApiException('authentication', '登录已过期，请重新登录酷狗账号');
    }
    // status/error_code 是必填标量（Wire 无 default）。
    requiredScalarInt(root['error_code'], 'error_code');
    requiredScalarInt(root['status'], 'status');
  } on KugouApiException catch (error) {
    if (error.kind != 'decode') rethrow;
    // decode_envelope 回退链：payload 解码失败时，根上有非 0 error_code 或
    // status==0 → business(code)；否则维持原 decode 失败。
    final code = optionalInt(root['error_code']);
    final rejected = optionalInt(root['status']) == 0;
    if ((code != null && code != 0) || rejected) {
      throw KugouApiException('business', '音乐服务返回失败（搜索建议）', code: code ?? 0);
    }
    rethrow;
  }
  return root;
}

MusicSuggestionGroup _convertSuggestGroup(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '搜索建议分组项不是 object');
  }
  return MusicSuggestionGroup(
    title: wireText(wire['LableName']),
    reportedCount: optionalInt(wire['RecordCount']),
    items: wireList(
      wire['RecordDatas'],
      'RecordDatas',
    ).map(_convertSuggestion).toList(),
  );
}

MusicSearchSuggestion _convertSuggestion(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '搜索建议条目不是 object');
  }
  return MusicSearchSuggestion(
    text: wireText(wire['HintInfo']),
    matches: optionalInt(wire['MatchCount']),
    heat: optionalInt(wire['Hot']),
    source: wireText(wire['Use']),
    subtitle: wireText(wire['subtitle']),
    tags: _suggestTags(wire['tags']),
    jump: _suggestJump(wire['jump']),
  );
}

/// `optional<Vec<String>>`：缺省/null → null；文本+数字项 → 字符串表；
/// bool 项或非数组 → 整体 null（Rust optional 的宽容：失败回 None，不抛）。
List<String>? _suggestTags(Object? value) {
  if (value == null || value is! List) return null;
  final tags = <String>[];
  for (final item in value) {
    final text = optionalText(item);
    if (text == null) return null;
    tags.add(text);
  }
  return tags;
}

/// `optional<Jump>`：缺省/null/非 object → null；object 内字段按 text/optional。
MusicSuggestJump? _suggestJump(Object? value) {
  final wire = wireMap(value);
  if (wire == null) return null;
  return MusicSuggestJump(
    kind: wireText(wire['type']),
    id: optionalInt(wire['id']),
    url: wireText(wire['url']),
  );
}
