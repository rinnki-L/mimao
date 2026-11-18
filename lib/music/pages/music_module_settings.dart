// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 comic 页面同款说明。
/// 音乐模块在全局设置抽屉里的分组（M4 骨架）。
///
/// 只读展示设备身份（不触发联网注册）；酷狗账号登录（二维码）与播放偏好
/// 随后续切片接入。
library;

import 'package:flutter/material.dart';
import 'package:mimao/music/api/music_api.dart';
import 'package:mimao/music/client/kugou_identity.dart';

class MusicModuleSettings extends StatelessWidget {
  const MusicModuleSettings({super.key, required this.api});

  final MusicApi api;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('设备身份', style: theme.textTheme.titleSmall),
        ),
        FutureBuilder<KugouIdentity?>(
          future: api.currentIdentity(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              );
            }
            final identity = snapshot.data;
            if (identity == null) {
              return ListTile(
                leading: const Icon(Icons.devices_other),
                title: const Text('尚未引导设备身份'),
                subtitle: const Text('首次搜索时自动生成并注册'),
              );
            }
            final loggedIn = identity.hasAccount;
            return Column(
              children: <Widget>[
                ListTile(
                  leading: Icon(
                    loggedIn ? Icons.account_circle : Icons.devices_other,
                  ),
                  title: Text(loggedIn ? '酷狗账号已登录' : '匿名设备'),
                  subtitle: Text(
                    loggedIn ? '用户 ID：${identity.userId}' : '未登录（匿名态）',
                  ),
                ),
                _IdentityRow(label: 'GUID', value: identity.guid),
                _IdentityRow(label: 'MID', value: identity.mid),
                _IdentityRow(label: 'DFID', value: identity.dfid),
              ],
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('账号', style: theme.textTheme.titleSmall),
        ),
        ListTile(
          leading: const Icon(Icons.qr_code_2),
          title: const Text('酷狗账号登录（二维码）'),
          subtitle: const Text('登录态 API 客户端切片接入'),
          enabled: false,
          trailing: const Icon(Icons.chevron_right),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            '协议实现对照 EchoMusicNext crates/echo-api 逐函数翻译，'
            '上游酷狗概念版 API 取自 MakcRe/KuGouMusicApi（详见 lib/music/README.md）。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// 脱敏的一行标识（前 8 位 + …）。
class _IdentityRow extends StatelessWidget {
  const _IdentityRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : _mask(value),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  String _mask(String value) {
    if (value.length <= 8) return value;
    return '${value.substring(0, 8)}…（${value.length} 位）';
  }
}
