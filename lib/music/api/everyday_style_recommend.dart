/// 风格推荐端点——EchoMusicNext
/// `crates/echo-api/src/module/everyday_style_recommend.rs` 的翻译。
library;

import 'dart:typed_data';

import 'package:mimao/music/api/everyday_recommend.dart';
import 'package:mimao/music/api/session.dart';
import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_client.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/discovery_models.dart';

/// 风格推荐输入（everyday_style_recommend.rs `Query`）。
class EverydayStyleRecommendQuery {
  const EverydayStyleRecommendQuery({this.tagIds = const <String>[]});

  final List<String> tagIds;

  void validate() {
    // > 128 个，或任一为空/超 32 字节/含非 ASCII 字母数字 → input（上游一致）；
    // 非纯 ASCII 标签必然命中字母数字校验，Dart String.length 与字节数对
    // ASCII 等价。
    if (tagIds.length > 128) {
      throw const KugouApiException('input', '风格标签无效');
    }
    for (final tag in tagIds) {
      if (tag.isEmpty || tag.length > 32 || !_asciiAlnum.hasMatch(tag)) {
        throw const KugouApiException('input', '风格标签无效');
      }
    }
  }

  static final RegExp _asciiAlnum = RegExp(r'^[0-9a-zA-Z]+$');
}

/// POST /everydayrec.service/everyday_style_recommend（网关；无 x-router；
/// tagids 走 query，请求体固定 `{}`——platform 参数不改变空请求体）。
Future<MusicStyleRecommendations> fetchEverydayStyleRecommend(
  MusicSession session,
  EverydayStyleRecommendQuery query,
) async {
  query.validate();
  final identity = await session.ensureDevice();
  final response = await session.client.sendEndpoint(
    identity,
    KugouEndpoint(
      origin: KugouOrigin.gateway,
      path: '/everydayrec.service/everyday_style_recommend',
      method: 'POST',
      params: <String, String>{'tagids': query.tagIds.join(',')},
      body: encodeJsonBody(const <String, Object?>{}),
    ),
  );
  return _convertEverydayStyleRecommend(response.bytes);
}

/// wire 解析（everyday_style_recommend.rs `convert`）。
MusicStyleRecommendations _convertEverydayStyleRecommend(Uint8List bytes) {
  final envelope = decodeDiscoveryEnvelope(bytes);
  ensureBusinessSuccess(envelope.status, envelope.errorCode, context: '风格推荐');
  // Envelope<Value> 的 data 缺省为 Null，Data 解析失败 → decode（上游一致）。
  final data = wireMap(envelope.data);
  if (data == null) {
    throw const KugouApiException('decode', '风格推荐响应 data 不是 object');
  }
  return MusicStyleRecommendations(
    songs: discoveryRecommendationSongs(data['song_list']),
    groups: _tagGroups(wireList(data['tag_info'], 'tag_info')),
  );
}

/// `Vec<Group>`（list 语义：元素非 object → decode）。
List<MusicStyleTagGroup> _tagGroups(List<Object?> groups) {
  final result = <MusicStyleTagGroup>[];
  for (final raw in groups) {
    final group = wireMap(raw);
    if (group == null) {
      throw const KugouApiException('decode', '风格标签组不是 object');
    }
    result.add(
      MusicStyleTagGroup(
        name: wireText(group['name']),
        child: _tags(wireList(group['child'], 'child')),
      ),
    );
  }
  return result;
}

/// `Vec<Tag>`（list 语义：元素非 object → decode）。
List<MusicStyleTag> _tags(List<Object?> tags) {
  final result = <MusicStyleTag>[];
  for (final raw in tags) {
    final tag = wireMap(raw);
    if (tag == null) {
      throw const KugouApiException('decode', '风格标签不是 object');
    }
    // wire 键 `default` → selected（serde rename）。
    result.add(
      MusicStyleTag(
        id: wireText(tag['id']),
        name: wireText(tag['name']),
        selected: discoveryOptionalUnsigned32(tag['default']),
      ),
    );
  }
  return result;
}
