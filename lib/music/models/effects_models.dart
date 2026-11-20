/// 音效目录模型与 wire 翻译——EchoMusicNext `crates/echo-api/src/util/audio_effect.rs`
/// 的组内翻译（规格 §2：util helper 不放共享层，模型落 `models/effects_models.dart`）。
///
/// `audio_effect.rs` 是 effects_artist / effects_brand_detail / effects_match
/// 共用的目录协议（Sound/CatalogRow/Headphone 行、paging 校验、errcode 信封），
/// 因此行解码辅助集中在本文件；effects_brand 的 Brand 行（模块局部类型）也放
/// 这里，端点文件只负责请求装配。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:mimao/music/api/wire.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/music_models.dart';

/// 音效条目（audio_effect.rs `Effect`）。
class MusicEffect {
  const MusicEffect({
    required this.id,
    required this.name,
    required this.author,
    required this.intro,
    required this.iconUrl,
    required this.labels,
    required this.userCount,
    required this.source,
    required this.soundUrls,
    required this.vpfUrls,
    required this.fileSize,
    required this.unavailableReason,
  });

  /// 音效 id（wire `sound.id`；耳机行同样取嵌套 sound.id，不是 model_id）。
  final int id;
  final String name;
  final String author;
  final String intro;
  final String iconUrl;
  final List<String> labels;
  final int? userCount;

  /// 目录来源标记（Rust `&'static str`）：'artist' / 'headphone'。
  final String source;
  final List<String> soundUrls;
  final List<String> vpfUrls;
  final int? fileSize;

  /// 非空表示该音效当前不可用（上游授权限制 / 耳机音效未解锁）。
  final String? unavailableReason;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'author': author,
    'intro': intro,
    'iconUrl': iconUrl,
    'labels': labels,
    'userCount': userCount,
    'source': source,
    'soundUrls': soundUrls,
    'vpfUrls': vpfUrls,
    'fileSize': fileSize,
    'unavailableReason': unavailableReason,
  };
}

/// 耳机品牌（effects_brand.rs `Brand`）。
class MusicEarphoneBrand {
  const MusicEarphoneBrand({
    required this.id,
    required this.name,
    required this.iconUrl,
    required this.modelCount,
  });

  final int id;
  final String name;
  final String iconUrl;
  final int? modelCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'iconUrl': iconUrl,
    'modelCount': modelCount,
  };
}

/// 音效分页校验（audio_effect.rs `paging`）：页码/页大小从 1 起，页大小 ≤ 50。
void validateEffectsPaging(int page, int pageSize) {
  // Rust 入参是 u32：0/负值在反序列化层就被拒；Dart 用同一类 input 错误表达。
  if (page <= 0 || pageSize <= 0 || pageSize > 50) {
    throw const KugouApiException('input', '音效分页无效');
  }
}

/// response.rs `optional<u32/u64>` 的无符号域：负数在 Rust `from_value` 失败
/// → None；共享层 `optionalInt` 不查范围，effects 组统一用本函数补齐。
int? effectsOptionalUnsigned(Object? value) {
  final parsed = optionalInt(value);
  if (parsed == null || parsed < 0) return null;
  return parsed;
}

/// effects 目录信封（response.rs `ErrcodeEnvelope` + audio_effect.rs
/// `CatalogWire`）：status/errcode 已过业务判定；root 供端点读取 total 等
/// 兄弟字段，data 是 `root['data']` 的别名。
class MusicEffectsEnvelope {
  const MusicEffectsEnvelope(this.status, this.errcode, this.root);

  final int status;
  final int errcode;
  final Map<String, Object?> root;

  Object? get data => root['data'];
}

/// effects 信封解码——request.rs `decode` + `decode_envelope("errcode")` +
/// `success` 的组合语义（wire.dart 的 [decodeEnvelopeWithFields] 只覆盖
/// error_code 系信封，这里的 msg 过期探测、errcode 恢复分支逐条对齐上游）：
///
/// 1. `authentication_expiration`（request.rs）：宽松探测 `error_code`=20018
///    或 `msg` 含「登录已过期」→ authentication（先于结构解码；effects 信封
///    本身用 errcode，通常不触发）；
/// 2. 结构解码：status（u32）/errcode（i64）必填 scalar，缺失/越界 → 失败；
/// 3. `decode_envelope` 恢复：结构失败时 errcode 非零或 status==0 → business；
/// 4. `request::success`：status==1 且 errcode==0，否则 business(errcode)。
MusicEffectsEnvelope decodeEffectsEnvelope(Uint8List bytes) {
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object {
    throw const KugouApiException('decode', '响应不是合法 JSON');
  }
  final root = wireMap(decoded);

  if (root != null) {
    final code = optionalInt(root['error_code']);
    final msg = root['msg'];
    final expired = msg is String && msg.contains('登录已过期');
    if (code == kugouErrorCodeAuthenticationExpired || expired) {
      throw KugouApiException('authentication', '账号认证无效，请重新登录', code: code);
    }
  }

  var status = 0;
  var errcode = 0;
  var structDecoded = false;
  if (root != null) {
    try {
      final parsedStatus = requiredScalarInt(root['status'], 'status');
      // u32 域：越界在 Rust from_value::<u32> 失败 → 走恢复分支。
      if (parsedStatus >= 0 && parsedStatus <= 0xFFFFFFFF) {
        status = parsedStatus;
        errcode = requiredScalarInt(root['errcode'], 'errcode');
        structDecoded = true;
      }
    } on KugouApiException {
      // 落到 decode_envelope 恢复分支（码值读取与上游同样宽松）。
    }
  }
  if (!structDecoded) {
    final code = optionalInt(root?['errcode']);
    final rejected = root != null && optionalInt(root['status']) == 0;
    if ((code != null && code != 0) || rejected) {
      throw KugouApiException('business', '音乐服务返回失败（音效目录）', code: code ?? 0);
    }
    throw const KugouApiException('decode', '音效目录响应缺少必填信封字段');
  }
  ensureBusinessSuccess(status, errcode, context: '音效目录');
  return MusicEffectsEnvelope(status, errcode, root!);
}

/// audio_effect.rs `urls`：备用列表在前、主地址在后；http 升级 https；只保留
/// 无用户信息的 https 地址；按最终字符串去重、保序；解析失败跳过。
List<String> _effectUrls(List<String> backups, String primary) {
  final out = <String>[];
  for (final raw in <String>[...backups, primary]) {
    final uri = Uri.tryParse(raw);
    if (uri == null) continue;
    if (uri.scheme != 'http' && uri.scheme != 'https') continue;
    if (uri.userInfo.isNotEmpty) continue;
    final value = uri.scheme == 'http'
        ? uri.replace(scheme: 'https').toString()
        : uri.toString();
    if (!out.contains(value)) out.add(value);
  }
  return out;
}

/// response.rs `list<String>`：元素经 ResponseValue 字符串解码（数字 → 文本；
/// bool/object → decode 失败，不静默丢弃）。
List<String> _textList(Object? value, String field) {
  final items = wireList(value, field);
  final result = <String>[];
  for (final item in items) {
    final text = optionalText(item);
    if (text == null) {
      throw KugouApiException('decode', '响应字段 $field 含非法文本项');
    }
    result.add(text);
  }
  return result;
}

/// audio_effect.rs `base(sound, source)`：Sound 行的公共投影（作者/简介/封面
/// 等 CatalogRow 字段留给 [convertEffectsCatalogPage] 填充）。
MusicEffect _soundBaseToEffect(Map<String, Object?> sound, String source) {
  final id = requiredScalarInt(sound['id'], 'id');
  final privilege = effectsOptionalUnsigned(sound['privilege']);
  return MusicEffect(
    id: id,
    name: wireText(sound['name']),
    author: '',
    intro: '',
    iconUrl: '',
    labels: const <String>[],
    userCount: null,
    source: source,
    soundUrls: _effectUrls(
      _textList(sound['sound_bk'], 'sound_bk'),
      wireText(sound['sound']),
    ),
    vpfUrls: _effectUrls(
      _textList(sound['vpf_bk'], 'vpf_bk'),
      wireText(sound['vpf']),
    ),
    fileSize: null,
    unavailableReason: privilege != null && privilege > 0
        ? '此音效需要上游授权，暂不支持下载'
        : null,
  );
}

/// audio_effect.rs `catalog_page`（effects_artist.rs `convert` 调用，source=
/// 'artist'）：CatalogWire 信封 + total + data 列表逐行 catalog()。
MusicPage<MusicEffect> convertEffectsCatalogPage(
  Uint8List bytes,
  int page,
  int size,
  String source,
) {
  final envelope = decodeEffectsEnvelope(bytes);
  // CatalogWire.data 走 `list`：缺失/null/空 object → 空表（不失败）。
  final rows = wireList(envelope.root['data'], 'data');
  final items = rows.map((row) => _catalogRowToEffect(row, source)).toList();
  return MusicPage<MusicEffect>(
    page: page,
    pageSize: size,
    total: effectsOptionalUnsigned(envelope.root['total']),
    items: items,
  );
}

/// audio_effect.rs `CatalogRow`（flatten Sound + 行字段）→ `catalog(row, source)`。
MusicEffect _catalogRowToEffect(Object? raw, String source) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '音效条目不是 object');
  }
  final effect = _soundBaseToEffect(wire, source);
  final singerPrivilege = effectsOptionalUnsigned(wire['singer_privilege']);
  return MusicEffect(
    id: effect.id,
    name: effect.name,
    author: wireText(wire['author']),
    intro: wireText(wire['intro']),
    iconUrl: coverUrl(wireText(wire['icon_url'])),
    labels: _textList(wire['label'], 'label'),
    userCount: effectsOptionalUnsigned(wire['user_count']),
    source: effect.source,
    soundUrls: effect.soundUrls,
    vpfUrls: effect.vpfUrls,
    fileSize: effectsOptionalUnsigned(wire['filesize']),
    // catalog()：singer_privilege > 0 时覆写 unavailable_reason（两条消息
    // 文案相同，与上游的「先 base 后覆写」等价）。
    unavailableReason:
        (effect.unavailableReason != null ||
            (singerPrivilege != null && singerPrivilege > 0))
        ? '此音效需要上游授权，暂不支持下载'
        : null,
  );
}

/// audio_effect.rs `Headphone` wire → `headphone(row)` 的宽容入口：
/// - model/model_icon/is_unlocked 宽容（text/optional，非法 → 缺省）；
/// - sound 严格（必填 object，id 必填 scalar）。
/// 任一严格失败 → null（不抛）：
/// - effects_match 的 common 走 response.rs `optional`，失败吞成 None；
/// - effects_brand_detail 的 list 元素是严格解码，调用方把 null 升级成 decode。
MusicEffect? effectsHeadphoneFromWire(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) return null;
  Map<String, Object?> sound;
  int id;
  try {
    sound = requiredWireMap(wire['sound'], 'sound');
    id = requiredScalarInt(sound['id'], 'id');
  } on KugouApiException {
    return null;
  }
  final privilege = effectsOptionalUnsigned(sound['privilege']);
  final isUnlocked = effectsOptionalUnsigned(wire['is_unlocked']);
  // headphone()：先 base（privilege 授权限制），再按 is_unlocked != 1 覆写。
  final unavailableReason = isUnlocked != null && isUnlocked != 1
      ? '此耳机音效尚未解锁'
      : privilege != null && privilege > 0
      ? '此音效需要上游授权，暂不支持下载'
      : null;
  return MusicEffect(
    id: id,
    // e.name = row.model（覆盖 sound.name；sound.name 不透出）。
    name: wireText(wire['model']),
    author: '',
    intro: '针对对应耳机型号调校，请选择与你的设备一致的型号。',
    iconUrl: coverUrl(wireText(wire['model_icon'])),
    labels: const <String>[],
    userCount: null,
    source: 'headphone',
    soundUrls: _effectUrls(
      _textList(sound['sound_bk'], 'sound_bk'),
      wireText(sound['sound']),
    ),
    vpfUrls: _effectUrls(
      _textList(sound['vpf_bk'], 'vpf_bk'),
      wireText(sound['vpf']),
    ),
    fileSize: null,
    unavailableReason: unavailableReason,
  );
}

/// effects_brand.rs `convert`：ErrcodeEnvelope 信封 + data.list 逐行 Brand。
/// data 本身必填 object（缺 data/非 object → decode；上游 from_value::<Data>）。
MusicPage<MusicEarphoneBrand> convertEffectsBrandPage(
  Uint8List bytes,
  int page,
  int size,
) {
  final envelope = decodeEffectsEnvelope(bytes);
  final data = requiredWireMap(envelope.data, 'data');
  final items = wireList(data['list'], 'list').map(_brandRowToBrand).toList();
  return MusicPage<MusicEarphoneBrand>(
    page: page,
    pageSize: size,
    total: effectsOptionalUnsigned(data['total']),
    items: items,
  );
}

/// effects_brand.rs `BrandWire` → `Brand`（brand_id 必填 scalar）。
MusicEarphoneBrand _brandRowToBrand(Object? raw) {
  final wire = wireMap(raw);
  if (wire == null) {
    throw const KugouApiException('decode', '品牌条目不是 object');
  }
  return MusicEarphoneBrand(
    id: requiredScalarInt(wire['brand_id'], 'brand_id'),
    name: wireText(wire['brand']),
    iconUrl: coverUrl(wireText(wire['logo'])),
    modelCount: effectsOptionalUnsigned(wire['model_count']),
  );
}
