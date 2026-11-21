// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 安全验证页（L5）：按事件号查询验证挑战配置，并可提交验证码完成验证。
///
/// - 查询：`verify.getVerifyInfo(MusicVerifyInfoQuery(eventId))`，展示
///   provider/vendor/提示文案/可用验证方式（v_type 列表）；
/// - 提交：`searchExt.sideDt(MusicSideDtQuery(eventId, verifyType, proof))`。
///   sidedt 只接受 23（普通验证）与 32（短信/验证码验证）——挑战的
///   `verificationType == 32` 时提交 32，否则按普通验证提交 23；
/// - `searchExt == null` 时只展示挑战信息（提交能力未接线）。
///
/// 错误一律收口成页内文案 / SnackBar，不向 Flutter 抛未捕获异常。
library;

import 'package:flutter/material.dart';
import 'package:mimao/music/api/get_verify_info.dart';
import 'package:mimao/music/api/search_ext_api.dart';
import 'package:mimao/music/api/sidedt.dart';
import 'package:mimao/music/api/verify_api.dart';
import 'package:mimao/music/client/kugou_error.dart';
import 'package:mimao/music/models/verify_models.dart';

/// 安全验证页。
class MusicSecurityVerifyPage extends StatefulWidget {
  const MusicSecurityVerifyPage({
    super.key,
    required this.verify,
    this.searchExt,
  });

  final MusicVerifyApi verify;

  /// sidedt 提交通道；null 时只展示挑战信息。
  final MusicSearchExtApi? searchExt;

  @override
  State<MusicSecurityVerifyPage> createState() =>
      _MusicSecurityVerifyPageState();
}

class _MusicSecurityVerifyPageState extends State<MusicSecurityVerifyPage> {
  final TextEditingController _eventId = TextEditingController();
  final TextEditingController _proof = TextEditingController();

  bool _loading = false;
  bool _submitting = false;
  MusicVerificationConfiguration? _config;

  /// 查询失败的页内提示。
  String? _error;

  /// 提交结果提示（成功/失败都留在页内，便于重试）。
  String? _submitResult;

  @override
  void dispose() {
    _eventId.dispose();
    _proof.dispose();
    super.dispose();
  }

  Future<void> _query() async {
    final eventId = _eventId.text.trim();
    if (eventId.isEmpty) {
      setState(() => _error = '请输入验证事件号');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _config = null;
      _submitResult = null;
    });
    try {
      final config = await widget.verify.getVerifyInfo(
        MusicVerifyInfoQuery(eventId: eventId),
      );
      if (!mounted) return;
      setState(() {
        _config = config;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _messageOf(error);
      });
    }
  }

  /// 提交验证码（sidedt）：verificationType == 32 → 短信验证（32），
  /// 否则按普通验证（23）提交。
  Future<void> _submit() async {
    final searchExt = widget.searchExt;
    if (searchExt == null) return;
    final eventId = _eventId.text.trim();
    final proof = _proof.text.trim();
    if (_config == null) {
      setState(() => _submitResult = '请先查询验证事件');
      return;
    }
    if (proof.isEmpty) {
      setState(() => _submitResult = '请输入验证码');
      return;
    }
    final verifyType = _config!.verificationType == 32 ? 32 : 23;
    setState(() {
      _submitting = true;
      _submitResult = null;
    });
    try {
      final acknowledgement = await searchExt.sideDt(
        MusicSideDtQuery(
          eventId: eventId,
          verifyType: verifyType,
          proof: proof,
        ),
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitResult = acknowledgement.acknowledged
            ? '验证已通过'
            : '验证未通过，请核对验证码后重试';
      });
      if (acknowledgement.acknowledged) _showSnack('验证已通过');
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitResult = _messageOf(error);
      });
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 错误文案：KugouApiException 用服务端中文 message，其它异常给网络兜底话术。
  String _messageOf(Object error) {
    if (error is KugouApiException) {
      final message = error.message.trim();
      if (message.isNotEmpty) return message;
    }
    return '网络异常，请稍后重试';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = _config;
    return Scaffold(
      appBar: AppBar(title: const Text('安全验证')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _eventId,
                  decoration: const InputDecoration(
                    labelText: '验证事件号',
                    hintText: '服务下发的事件号（eventid）',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonal(
                  onPressed: _loading ? null : _query,
                  child: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('查询'),
                ),
              ),
            ],
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              '查询失败：$_error',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (config != null) ...<Widget>[
            const SizedBox(height: 16),
            Text('挑战信息', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            ListTile(
              dense: true,
              leading: const Icon(Icons.shield_outlined),
              title: Text(_providerLabel(config)),
              subtitle: Text(
                '供应商：${config.vendor} · v_type=${config.verificationType}',
              ),
            ),
            if (config.displayMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(
                  config.displayMessage,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            if (config.availableTypes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (final type in config.availableTypes)
                      Chip(label: Text('验证方式 $type')),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            if (widget.searchExt == null)
              Text(
                '验证提交通道未接线，仅展示挑战信息。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else ...<Widget>[
              Text('提交验证码', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _proof,
                decoration: InputDecoration(
                  labelText: '验证码',
                  hintText: '短信或普通验证的验证码',
                  suffixIcon: TextButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('提交'),
                  ),
                ),
              ),
              if (_submitResult != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _submitResult!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _submitResult == '验证已通过'
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  /// provider → 中文类别（映射见 get_verify_info.dart 端点注释）。
  String _providerLabel(MusicVerificationConfiguration config) {
    return switch (config.provider) {
      'sms' => '短信验证',
      'real_name' => '实名认证',
      'bind_phone' => '绑定手机',
      'login' => '登录验证',
      'account_risk' => '账号风控',
      'tencent' => '腾讯验证',
      _ => '验证类别：${config.provider}',
    };
  }
}
