/// 用户资料端点模型——EchoMusicNext `module/user_*.rs` 与 `domain.rs`
/// `Profile` / `ProfileIdentity` 的翻译。
///
/// 只保留资料展示白名单（student/tags、profile、会员、等级）；联系方式与
/// 关联 Provider 的私密字段上游就刻意丢弃，这里同样不收。
library;

/// 学生身份与展示标签（user_info.rs `UserIdentity`）。
class MusicUserIdentityTags {
  const MusicUserIdentityTags({
    required this.studentStatus,
    required this.studentSchool,
    required this.studentExpireTime,
    required this.tags,
  });

  /// 学生状态码（wire `student_status`；非法/缺省 → null）。
  final int? studentStatus;

  /// 学校名（wire `student_school`；text 宽容：非法值 → ''）。
  final String studentSchool;

  /// 认证到期文本（wire `student_expire_time`）。
  final String studentExpireTime;

  /// 展示标签（wire `tags` 拆分去重，保持顺序）。
  final List<String> tags;

  Map<String, Object?> toJson() => <String, Object?>{
    'studentStatus': studentStatus,
    'studentSchool': studentSchool,
    'studentExpireTime': studentExpireTime,
    'tags': List<String>.of(tags),
  };

  factory MusicUserIdentityTags.fromJson(Map<String, Object?> json) =>
      MusicUserIdentityTags(
        studentStatus: (json['studentStatus'] as num?)?.toInt(),
        studentSchool: '${json['studentSchool'] ?? ''}',
        studentExpireTime: '${json['studentExpireTime'] ?? ''}',
        tags: <String>[
          for (final raw
              in (json['tags'] as List<Object?>? ?? const <Object?>[]))
            '${raw ?? ''}',
        ],
      );
}

/// 认证身份事实（domain.rs `ProfileIdentity`）——独立于展示文案的原始码。
class MusicUserProfileIdentity {
  const MusicUserProfileIdentity({
    required this.actorCode,
    required this.businessCode,
    required this.starCode,
    required this.singerCode,
    required this.legacyStarCode,
    required this.talentBits,
    required this.actor,
    required this.business,
    required this.star,
    required this.singer,
    required this.authorizations,
    required this.talentAuthorizations,
    required this.singerAuthorizations,
  });

  final int? actorCode;
  final int? businessCode;
  final int? starCode;
  final int? singerCode;

  /// 旧版星标标志（wire `is_star`，可为负数——i32）。
  final int? legacyStarCode;

  /// 快手达人位标志（wire `kq_talent`）。
  final int? talentBits;

  final bool actor;
  final bool business;
  final bool star;

  /// 新旧两个歌手标志任一为 1（user_detail.rs `singer`）。
  final bool singer;

  final List<String> authorizations;
  final List<String> talentAuthorizations;
  final List<String> singerAuthorizations;

  Map<String, Object?> toJson() => <String, Object?>{
    'actorCode': actorCode,
    'businessCode': businessCode,
    'starCode': starCode,
    'singerCode': singerCode,
    'legacyStarCode': legacyStarCode,
    'talentBits': talentBits,
    'actor': actor,
    'business': business,
    'star': star,
    'singer': singer,
    'authorizations': List<String>.of(authorizations),
    'talentAuthorizations': List<String>.of(talentAuthorizations),
    'singerAuthorizations': List<String>.of(singerAuthorizations),
  };

  factory MusicUserProfileIdentity.fromJson(Map<String, Object?> json) =>
      MusicUserProfileIdentity(
        actorCode: (json['actorCode'] as num?)?.toInt(),
        businessCode: (json['businessCode'] as num?)?.toInt(),
        starCode: (json['starCode'] as num?)?.toInt(),
        singerCode: (json['singerCode'] as num?)?.toInt(),
        legacyStarCode: (json['legacyStarCode'] as num?)?.toInt(),
        talentBits: (json['talentBits'] as num?)?.toInt(),
        actor: json['actor'] == true,
        business: json['business'] == true,
        star: json['star'] == true,
        singer: json['singer'] == true,
        authorizations: _stringList(json['authorizations']),
        talentAuthorizations: _stringList(json['talentAuthorizations']),
        singerAuthorizations: _stringList(json['singerAuthorizations']),
      );

  static List<String> _stringList(Object? raw) => <String>[
    for (final item in (raw as List<Object?>? ?? const <Object?>[]))
      '${item ?? ''}',
  ];
}

/// 个人主页资料（domain.rs `Profile`；user_detail.rs `convert`）。
class MusicUserProfile {
  const MusicUserProfile({
    required this.id,
    required this.nickname,
    required this.avatarUrl,
    required this.gender,
    required this.vipType,
    required this.follows,
    required this.fans,
    required this.biography,
    required this.friends,
    required this.grade,
    required this.listeningMinutes,
    required this.visitors,
    required this.registeredAtSeconds,
    required this.province,
    required this.city,
    required this.ipLocation,
    required this.birthday,
    required this.identity,
  });

  /// 账号 id（来自调用方身份快照，不是响应字段）。
  final int id;

  final String nickname;
  final String avatarUrl;
  final int? gender;
  final int? vipType;
  final int? follows;
  final int? fans;
  final String biography;
  final int? friends;

  /// 听歌等级（wire `p_grade`）。
  final int? grade;

  /// 累计听歌分钟（wire `duration`）。
  final int? listeningMinutes;
  final int? visitors;

  /// 注册时间（秒；wire `rtime`）。
  final int? registeredAtSeconds;

  /// 可编辑的省份/城市偏好。
  final String province;
  final String city;

  /// IP 属地展示文本（wire `loc`，与可编辑省市无关）。
  final String ipLocation;
  final String birthday;
  final MusicUserProfileIdentity identity;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'nickname': nickname,
    'avatarUrl': avatarUrl,
    'gender': gender,
    'vipType': vipType,
    'follows': follows,
    'fans': fans,
    'biography': biography,
    'friends': friends,
    'grade': grade,
    'listeningMinutes': listeningMinutes,
    'visitors': visitors,
    'registeredAtSeconds': registeredAtSeconds,
    'province': province,
    'city': city,
    'ipLocation': ipLocation,
    'birthday': birthday,
    'identity': identity.toJson(),
  };

  factory MusicUserProfile.fromJson(Map<String, Object?> json) =>
      MusicUserProfile(
        id: (json['id'] as num?)?.toInt() ?? 0,
        nickname: '${json['nickname'] ?? ''}',
        avatarUrl: '${json['avatarUrl'] ?? ''}',
        gender: (json['gender'] as num?)?.toInt(),
        vipType: (json['vipType'] as num?)?.toInt(),
        follows: (json['follows'] as num?)?.toInt(),
        fans: (json['fans'] as num?)?.toInt(),
        biography: '${json['biography'] ?? ''}',
        friends: (json['friends'] as num?)?.toInt(),
        grade: (json['grade'] as num?)?.toInt(),
        listeningMinutes: (json['listeningMinutes'] as num?)?.toInt(),
        visitors: (json['visitors'] as num?)?.toInt(),
        registeredAtSeconds: (json['registeredAtSeconds'] as num?)?.toInt(),
        province: '${json['province'] ?? ''}',
        city: '${json['city'] ?? ''}',
        ipLocation: '${json['ipLocation'] ?? ''}',
        birthday: '${json['birthday'] ?? ''}',
        identity: MusicUserProfileIdentity.fromJson(
          Map<String, Object?>.from(json['identity']! as Map),
        ),
      );
}

/// 资料更新回执（user_update.rs `Acknowledgement`；成功即 updated=true）。
class MusicUserUpdateResult {
  const MusicUserUpdateResult({required this.updated});

  final bool updated;

  Map<String, Object?> toJson() => <String, Object?>{'updated': updated};

  factory MusicUserUpdateResult.fromJson(Map<String, Object?> json) =>
      MusicUserUpdateResult(updated: json['updated'] == true);
}

/// 头像引用提交结果（user_update_avatar.rs `AvatarUpdate`）。
class MusicUserAvatarUpdate {
  const MusicUserAvatarUpdate({
    required this.avatarUrl,
    required this.reviewPending,
  });

  /// 固定 CDN 形态：`http://c1.kgimg.com/v2/kugouicon/<file>`。
  final String avatarUrl;

  /// 审核回执（error_code=34236）：已提交但未发布。
  final bool reviewPending;

  Map<String, Object?> toJson() => <String, Object?>{
    'avatarUrl': avatarUrl,
    'reviewPending': reviewPending,
  };

  factory MusicUserAvatarUpdate.fromJson(Map<String, Object?> json) =>
      MusicUserAvatarUpdate(
        avatarUrl: '${json['avatarUrl'] ?? ''}',
        reviewPending: json['reviewPending'] == true,
      );
}

/// 头像图片上传结果（user_avatar_upload.rs `Upload`）。
class MusicUserAvatarUpload {
  const MusicUserAvatarUpload({required this.fileName});

  /// 上传服务返回的文件引用；交给 userUpdateAvatar 提交。
  final String fileName;

  Map<String, Object?> toJson() => <String, Object?>{'fileName': fileName};

  factory MusicUserAvatarUpload.fromJson(Map<String, Object?> json) =>
      MusicUserAvatarUpload(fileName: '${json['fileName'] ?? ''}');
}

/// 联合会员产品（user_vip_detail.rs `MembershipProduct`）。
class MusicUserVipMembershipProduct {
  const MusicUserVipMembershipProduct({
    required this.active,
    required this.activeCode,
    required this.product,
    required this.business,
    required this.beginsAt,
    required this.expiresAt,
  });

  /// wire `is_vip` 的展示布尔（0→false、1→true、其它 → null）。
  final bool? active;

  /// wire `is_vip` 原始码。
  final int? activeCode;
  final String product;
  final String business;

  /// ISO 本地时间文本（无时区，不臆造 UTC）；空值 → null。
  final String? beginsAt;
  final String? expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'active': active,
    'activeCode': activeCode,
    'product': product,
    'business': business,
    'beginsAt': beginsAt,
    'expiresAt': expiresAt,
  };

  factory MusicUserVipMembershipProduct.fromJson(
    Map<String, Object?> json,
  ) => MusicUserVipMembershipProduct(
    active: json['active'] is bool ? json['active'] as bool : null,
    activeCode: (json['activeCode'] as num?)?.toInt(),
    product: '${json['product'] ?? ''}',
    business: '${json['business'] ?? ''}',
    beginsAt: json['beginsAt'] is String ? json['beginsAt'] as String : null,
    expiresAt: json['expiresAt'] is String ? json['expiresAt'] as String : null,
  );
}

/// 联合会员概览（user_vip_detail.rs `Memberships`）。
class MusicUserVipMemberships {
  const MusicUserVipMemberships({
    required this.userId,
    required this.vipTypeCode,
    required this.userTypeCode,
    required this.deluxeBeginsAt,
    required this.superBeginsAt,
    required this.deluxeExpiresAt,
    required this.superExpiresAt,
    required this.products,
  });

  final int? userId;
  final int? vipTypeCode;
  final int? userTypeCode;

  /// 豪华版开始/到期（wire `vip_begin_time` / `vip_end_time`）。
  final String? deluxeBeginsAt;
  final String? deluxeExpiresAt;

  /// 超级会员开始/到期（wire `su_vip_begin_time` / `su_vip_end_time`）。
  final String? superBeginsAt;
  final String? superExpiresAt;

  final List<MusicUserVipMembershipProduct> products;

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'vipTypeCode': vipTypeCode,
    'userTypeCode': userTypeCode,
    'deluxeBeginsAt': deluxeBeginsAt,
    'superBeginsAt': superBeginsAt,
    'deluxeExpiresAt': deluxeExpiresAt,
    'superExpiresAt': superExpiresAt,
    'products': [for (final product in products) product.toJson()],
  };

  factory MusicUserVipMemberships.fromJson(Map<String, Object?> json) =>
      MusicUserVipMemberships(
        userId: (json['userId'] as num?)?.toInt(),
        vipTypeCode: (json['vipTypeCode'] as num?)?.toInt(),
        userTypeCode: (json['userTypeCode'] as num?)?.toInt(),
        deluxeBeginsAt: json['deluxeBeginsAt'] is String
            ? json['deluxeBeginsAt'] as String
            : null,
        superBeginsAt: json['superBeginsAt'] is String
            ? json['superBeginsAt'] as String
            : null,
        deluxeExpiresAt: json['deluxeExpiresAt'] is String
            ? json['deluxeExpiresAt'] as String
            : null,
        superExpiresAt: json['superExpiresAt'] is String
            ? json['superExpiresAt'] as String
            : null,
        products: <MusicUserVipMembershipProduct>[
          for (final raw
              in (json['products'] as List<Object?>? ?? const <Object?>[]))
            MusicUserVipMembershipProduct.fromJson(
              Map<String, Object?>.from(raw! as Map),
            ),
        ],
      );
}

/// 听歌等级与成长值（user_grade_info.rs `ListeningGrade`）。
class MusicUserGradeInfo {
  const MusicUserGradeInfo({
    required this.userId,
    required this.grade,
    required this.listeningSeconds,
    required this.currentPoints,
    required this.gradePoints,
    required this.nextGradePoints,
    required this.nextGrade,
  });

  final int? userId;

  /// 等级（wire `p_grade`）。
  final int? grade;

  /// 累计听歌秒数（wire `d_sec`）。
  final int? listeningSeconds;
  final int? currentPoints;
  final int? gradePoints;
  final int? nextGradePoints;
  final int? nextGrade;

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'grade': grade,
    'listeningSeconds': listeningSeconds,
    'currentPoints': currentPoints,
    'gradePoints': gradePoints,
    'nextGradePoints': nextGradePoints,
    'nextGrade': nextGrade,
  };

  factory MusicUserGradeInfo.fromJson(Map<String, Object?> json) =>
      MusicUserGradeInfo(
        userId: (json['userId'] as num?)?.toInt(),
        grade: (json['grade'] as num?)?.toInt(),
        listeningSeconds: (json['listeningSeconds'] as num?)?.toInt(),
        currentPoints: (json['currentPoints'] as num?)?.toInt(),
        gradePoints: (json['gradePoints'] as num?)?.toInt(),
        nextGradePoints: (json['nextGradePoints'] as num?)?.toInt(),
        nextGrade: (json['nextGrade'] as num?)?.toInt(),
      );
}

/// 批量作者会员查询的单个用户条目
/// （user_batch_union_vipinfo.rs `AuthorProducts`）。
class MusicUserBatchAuthorProducts {
  const MusicUserBatchAuthorProducts({
    required this.userId,
    required this.products,
  });

  /// wire `busi_vip` 的 map key（字符串形态的 id，保留拼写）。
  final String userId;
  final List<MusicUserBatchMembership> products;

  Map<String, Object?> toJson() => <String, Object?>{
    'userId': userId,
    'products': [for (final product in products) product.toJson()],
  };

  factory MusicUserBatchAuthorProducts.fromJson(Map<String, Object?> json) =>
      MusicUserBatchAuthorProducts(
        userId: '${json['userId'] ?? ''}',
        products: <MusicUserBatchMembership>[
          for (final raw
              in (json['products'] as List<Object?>? ?? const <Object?>[]))
            MusicUserBatchMembership.fromJson(
              Map<String, Object?>.from(raw! as Map),
            ),
        ],
      );
}

/// 批量作者会员产品（user_batch_union_vipinfo.rs `Membership`）。
class MusicUserBatchMembership {
  const MusicUserBatchMembership({
    required this.product,
    required this.activeCode,
    required this.active,
    required this.yearCode,
    required this.extension,
  });

  final String product;
  final int? activeCode;
  final bool? active;

  /// 年费标志（wire `y_type`）。
  final int? yearCode;

  /// 未消费的其余字段（wire flatten 捕获，原样保留）。
  final Map<String, Object?> extension;

  Map<String, Object?> toJson() => <String, Object?>{
    'product': product,
    'activeCode': activeCode,
    'active': active,
    'yearCode': yearCode,
    'extension': Map<String, Object?>.of(extension),
  };

  factory MusicUserBatchMembership.fromJson(Map<String, Object?> json) =>
      MusicUserBatchMembership(
        product: '${json['product'] ?? ''}',
        activeCode: (json['activeCode'] as num?)?.toInt(),
        active: json['active'] is bool ? json['active'] as bool : null,
        yearCode: (json['yearCode'] as num?)?.toInt(),
        extension: Map<String, Object?>.from(
          (json['extension'] as Map?) ?? const <String, Object?>{},
        ),
      );
}
