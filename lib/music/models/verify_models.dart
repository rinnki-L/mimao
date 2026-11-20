/// 验证挑战配置模型——EchoMusicNext `crates/echo-api/src/domain.rs`
/// `VerificationConfiguration` 的翻译（由 get_verify_info 端点装配）。
///
/// 会话标识只留在内存里，不落盘、不进日志（上游 domain.rs 注释同款约束）。
library;

/// 验证挑战配置（domain.rs `VerificationConfiguration`）。
class MusicVerificationConfiguration {
  const MusicVerificationConfiguration({
    required this.provider,
    required this.vendor,
    required this.appId,
    required this.displayMessage,
    required this.verificationType,
    required this.availableTypes,
    required this.businessId,
    required this.sessionId,
    required this.partnerStatus,
    required this.protocolFlag,
  });

  /// 挑战类别（get_verify_info.rs provider 映射）：`sms` / `real_name` /
  /// `bind_phone` / `login` / `account_risk` / `tencent`（url 以
  /// `KGCodeTX|` 开头）/ `unsupported`。
  final String provider;

  /// 供应商（get_verify_info.rs vendor 映射，取自 url `|` 前缀的大写形式）：
  /// `TX` / `GT` / `KG` / `KG2` / `SM` / `YD` / 其余 `UNKNOWN`。
  final String vendor;

  /// wire `txappid`（scalar，缺省 ''）。
  final String appId;

  /// wire `show.msg`（缺省 ''）。客户端动作与短信挑战不需要 sessionid、
  /// business 或 vde——缺省字段保留为 null，不臆造（get_verify_info.rs 注释）。
  final String displayMessage;

  /// wire `v_type`（必填标量）。
  final int verificationType;

  /// wire `v_type_list`（list 宽容：null / 空 object → 空表）。
  final List<int> availableTypes;

  /// wire `business`（optional：缺省/非法值 → null）。
  final int? businessId;

  /// wire `sessionid`（optional：缺省/非法值 → null）。
  final String? sessionId;

  /// wire `partnerid_map`（String → i64；伙伴状态原样保留）。
  final Map<String, int> partnerStatus;

  /// wire `vde`（optional：保留观察到的协议位，不推断未文档化的含义——
  /// domain.rs `protocol_flag` 注释）。
  final int? protocolFlag;

  Map<String, Object?> toJson() => <String, Object?>{
    'provider': provider,
    'vendor': vendor,
    'appId': appId,
    'displayMessage': displayMessage,
    'verificationType': verificationType,
    'availableTypes': availableTypes,
    'businessId': businessId,
    'sessionId': sessionId,
    'partnerStatus': partnerStatus,
    'protocolFlag': protocolFlag,
  };

  factory MusicVerificationConfiguration.fromJson(Map<String, Object?> json) =>
      MusicVerificationConfiguration(
        provider: '${json['provider'] ?? ''}',
        vendor: '${json['vendor'] ?? ''}',
        appId: '${json['appId'] ?? ''}',
        displayMessage: '${json['displayMessage'] ?? ''}',
        verificationType: (json['verificationType'] as num?)?.toInt() ?? 0,
        availableTypes: <int>[
          for (final raw
              in (json['availableTypes'] as List<Object?>? ??
                  const <Object?>[]))
            (raw as num?)?.toInt() ?? 0,
        ],
        businessId: (json['businessId'] as num?)?.toInt(),
        sessionId: json['sessionId'] == null ? null : '${json['sessionId']}',
        partnerStatus: <String, int>{
          for (final entry in Map<String, Object?>.from(
            json['partnerStatus']! as Map,
          ).entries)
            entry.key: (entry.value as num?)?.toInt() ?? 0,
        },
        protocolFlag: (json['protocolFlag'] as num?)?.toInt(),
      );
}
