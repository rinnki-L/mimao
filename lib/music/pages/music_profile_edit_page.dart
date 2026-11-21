// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 资料编辑页（L3）：昵称/性别/生日/个性签名/省市 → user_update 差量写入。
///
/// 只依赖 [MusicUserProfileApi]；保存时只提交相对初始资料的改动字段，
/// 校验失败（空昵称/签名超长/生日格式）就地提示，不发起请求。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mimao/music/api/user_profile_api.dart';
import 'package:mimao/music/api/user_update.dart';
import 'package:mimao/music/models/user_models.dart';

/// 个性签名的字符上限（与端点一致：按 UTF-16 码元数计量）。
const int kSignatureMaxLength = 120;

/// 生日字段的格式（`yyyy-MM-dd`，可空——空串语义为清除）。
final RegExp _kBirthdayPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// 资料编辑页。[initial] 为空时自行调 `userDetail()` 装载初始资料
/// （页面自包含）；账号中心已加载时可直接透传省一次请求。
class MusicProfileEditPage extends StatefulWidget {
  const MusicProfileEditPage({super.key, required this.profile, this.initial});

  final MusicUserProfileApi profile;

  /// 初始资料快照（用户中心 `userDetail()` 的结果）。
  final MusicUserProfile? initial;

  @override
  State<MusicProfileEditPage> createState() => _MusicProfileEditPageState();
}

class _MusicProfileEditPageState extends State<MusicProfileEditPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _loading = false;
  Object? _loadError;
  MusicUserProfile? _initial;

  late final TextEditingController _nickname = TextEditingController();
  late final TextEditingController _birthday = TextEditingController();
  late final TextEditingController _signature = TextEditingController();
  late final TextEditingController _province = TextEditingController();
  late final TextEditingController _city = TextEditingController();

  /// 性别选择（0 未知/1 男/2 女；null 表示远端未设置）。
  int? _gender;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final MusicUserProfile? initial = widget.initial;
    if (initial == null) {
      _loading = true;
      unawaited(_load());
    } else {
      _applyInitial(initial);
    }
  }

  @override
  void dispose() {
    _nickname.dispose();
    _birthday.dispose();
    _signature.dispose();
    _province.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final data = await widget.profile.userDetail();
      if (!mounted) return;
      _applyInitial(data);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  void _applyInitial(MusicUserProfile profile) {
    setState(() {
      _initial = profile;
      _loading = false;
      _loadError = null;
      _nickname.text = profile.nickname;
      _birthday.text = profile.birthday;
      _signature.text = profile.biography;
      _province.text = profile.province;
      _city.text = profile.city;
      _gender = profile.gender;
    });
  }

  // ── 就地校验（Form validator；保存时统一触发） ────────────────────────

  String? _validateNickname(String? value) {
    if (value?.trim().isEmpty ?? true) return '昵称不能为空';
    return null;
  }

  String? _validateSignature(String? value) {
    final String text = value ?? '';
    if (text.codeUnits.length > kSignatureMaxLength) {
      return '个性签名最多 $kSignatureMaxLength 个字符';
    }
    return null;
  }

  String? _validateBirthday(String? value) {
    final String text = (value ?? '').trim();
    if (text.isEmpty) return null; // 允许清空（空串语义=清除生日）
    if (!_kBirthdayPattern.hasMatch(text)) return '生日格式应为 yyyy-MM-dd';
    if (DateTime.tryParse(text) == null) return '生日日期无效';
    return null;
  }

  // ── 保存：差量装配 → userUpdate ───────────────────────────────────────

  Future<void> _save() async {
    final MusicUserProfile? initial = _initial;
    if (initial == null || _saving) return;
    if (_formKey.currentState?.validate() != true) return;

    final String nickname = _nickname.text.trim();
    final String birthday = _birthday.text.trim();
    final String signature = _signature.text;
    final String province = _province.text.trim();
    final String city = _city.text.trim();

    // 端点是差量补丁：null=不改；signature/birthday 允许空串（清除）。
    // 省市端点不允许空串——清空输入视为放弃修改，不下发。
    final String? nicknameField = nickname == initial.nickname
        ? null
        : nickname;
    final int? genderField = (_gender == null || _gender == initial.gender)
        ? null
        : _gender;
    final String? birthdayField = birthday == initial.birthday
        ? null
        : birthday;
    final String? signatureField = signature == initial.biography
        ? null
        : signature;
    final String? provinceField =
        (province.isEmpty || province == initial.province) ? null : province;
    final String? cityField = (city.isEmpty || city == initial.city)
        ? null
        : city;

    final bool hasChange =
        nicknameField != null ||
        genderField != null ||
        birthdayField != null ||
        signatureField != null ||
        provinceField != null ||
        cityField != null;
    if (!hasChange) {
      setState(() => _error = '资料没有变化');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.profile.userUpdate(
        MusicUserUpdateQuery(
          nickname: nicknameField,
          gender: genderField,
          birthday: birthdayField,
          signature: signatureField,
          province: provinceField,
          city: cityField,
        ),
      );
      if (!mounted) return;
      // 端点成功即 updated=true；false 按失败处理（防御非典型回执）。
      if (!result.updated) {
        setState(() {
          _saving = false;
          _error = '保存失败，请稍后重试';
        });
        return;
      }
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败：$e';
      });
    }
  }

  // ── 组装 ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('编辑资料')),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _loadError != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('$_loadError', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  TextFormField(
                    key: const ValueKey<String>('profile-nickname'),
                    controller: _nickname,
                    decoration: const InputDecoration(
                      labelText: '昵称',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateNickname,
                  ),
                  const SizedBox(height: 16),
                  Align(
                    key: const ValueKey<String>('profile-gender'),
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<int>(
                      segments: const <ButtonSegment<int>>[
                        ButtonSegment<int>(value: 0, label: Text('未知')),
                        ButtonSegment<int>(value: 1, label: Text('男')),
                        ButtonSegment<int>(value: 2, label: Text('女')),
                      ],
                      selected: <int>{_gender ?? 0},
                      onSelectionChanged: (Set<int> selection) =>
                          setState(() => _gender = selection.first),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey<String>('profile-birthday'),
                    controller: _birthday,
                    decoration: const InputDecoration(
                      labelText: '生日',
                      hintText: 'yyyy-MM-dd',
                      helperText: '留空表示清除生日',
                      border: OutlineInputBorder(),
                    ),
                    validator: _validateBirthday,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey<String>('profile-signature'),
                    controller: _signature,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: '个性签名',
                      helperText: '清空后保存即清除签名',
                      counterText:
                          '${_signature.text.codeUnits.length}/$kSignatureMaxLength',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: _validateSignature,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey<String>('profile-province'),
                    controller: _province,
                    decoration: const InputDecoration(
                      labelText: '省份',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey<String>('profile-city'),
                    controller: _city,
                    decoration: const InputDecoration(
                      labelText: '城市',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const ValueKey<String>('profile-save'),
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '保存中…' : '保存'),
                  ),
                ],
              ),
            ),
    );
  }
}
