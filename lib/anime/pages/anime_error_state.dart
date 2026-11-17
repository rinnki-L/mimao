// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 但 Kazumi/Venera 上游镜像全部用它；为保持类型一致与 patch 可重放，M1 继续用。
import 'package:flutter/material.dart';

/// 番剧页统一的「加载失败 + 重试」占位。
///
/// 搜索 / 时间表 / 详情三页的错误态结构完全一致，仅提示文案不同；
/// 文案由各页按原样传入，避免三份重复实现。
class AnimeRetryErrorState extends StatelessWidget {
  const AnimeRetryErrorState({
    super.key,
    required this.message,
    required this.onRetry,
  });

  /// 展示给用户的失败原因（各页保留原有措辞）。
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 56, color: cs.error),
          const SizedBox(height: 12),
          Text(message),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
