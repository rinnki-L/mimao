import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// `/tap` 端点：元素树解析目标 + 注入指针事件（debug-only）。
///
/// 两段式设计：
///   1. [resolveTapTargets] 是纯函数（根 Element 进、候选列表出），可单测；
///   2. [dispatchTap] 经 `GestureBinding.handlePointerEvent` 注入 down/up——
///      走 hit-test，**与真实手指同一条通路**（被遮挡时点到的是遮挡者），
///      且全程逻辑像素，天然没有 Win32 层的 DPI 坑。
///
/// 匹配语义（刻意从简）：`key` 对 widget.key 的 toString 包含匹配
/// （`ValueKey('comic-entry')`、`Key('x')` 都能命中）；`text` 对 Text.data
/// 包含匹配（RichText 内嵌 span 不在范围）；两者都给则取交集。
/// 要进详情页就点列表项——与人类同款路径（详见 dev_navigate.dart 的取舍）。
class TapSelector {
  const TapSelector({this.key, this.text, this.index = 0, this.dryRun = false});

  final String? key;
  final String? text;
  final int index;

  /// true 只返回候选不注入事件——agent 先探后点，避免盲点。
  final bool dryRun;

  bool get isEmptySelector => key == null && text == null;

  factory TapSelector.fromJson(Map<String, Object?> json) => TapSelector(
    key: (json['key'] as String?)?.trim(),
    text: (json['text'] as String?)?.trim(),
    index: (json['index'] as num?)?.toInt() ?? 0,
    dryRun: json['dryRun'] == true,
  );
}

/// 一个可点目标：描述 + 全局逻辑坐标中心。
class TapTarget {
  const TapTarget({required this.describe, required this.center});

  final String describe;
  final Offset center;

  Map<String, Object?> toJson() => <String, Object?>{
    'target': describe,
    'center': <Object?>[center.dx, center.dy],
  };
}

/// 从 [root] 深度优先遍历，按选择器收集候选（文档顺序，靠前的先渲染）。
List<TapTarget> resolveTapTargets(Element root, TapSelector selector) {
  final targets = <TapTarget>[];
  void visit(Element element) {
    final widget = element.widget;

    // Offstage 子树不参与（看不见也点不着）。
    if (widget is Offstage && widget.offstage) return;

    var matched = false;
    var describe = widget.runtimeType.toString();

    if (!selector.isEmptySelector) {
      final keyHit =
          selector.key != null &&
          widget.key != null &&
          widget.key.toString().contains(selector.key!);
      final text = widget is Text ? widget.data : null;
      final textHit =
          selector.text != null &&
          text != null &&
          text.contains(selector.text!);
      // 两个条件都给时要求同时命中（交集语义）。
      final keyGivenButMissed = selector.key != null && !keyHit;
      final textGivenButMissed = selector.text != null && !textHit;
      matched = !keyGivenButMissed && !textGivenButMissed;
      if (textHit) describe = '$describe("$text")';
      if (keyHit) describe = '$describe[${widget.key}]';
    } else if (selector.dryRun && widget is Text && widget.data != null) {
      // 空选择器 + dryRun：全部 Text 都算候选（探查页面有什么可点）。
      matched = true;
      describe = '$describe("${widget.data}")';
    }

    if (matched) {
      final renderObject = element.renderObject;
      if (renderObject is RenderBox && renderObject.hasSize) {
        final center = renderObject.localToGlobal(
          renderObject.size.center(Offset.zero),
        );
        if (!center.dx.isNaN && !center.dy.isNaN) {
          targets.add(TapTarget(describe: describe, center: center));
        }
      }
    }

    element.visitChildren(visit);
  }

  visit(root);
  return targets;
}

/// 注入一次点按：down → 50ms → up（给长按/双击之外的手势识别留出窗口）。
/// [onUp] 供测试在 fake-async 下 pump 后断言用。
Future<void> dispatchTap(
  Offset center, {
  Duration gap = const Duration(milliseconds: 50),
}) async {
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(position: center),
  );
  await Future<void>.delayed(gap);
  GestureBinding.instance.handlePointerEvent(PointerUpEvent(position: center));
}

/// /tap 的完整语义：解析 → dryRun 或选第 index 个注入。
/// [root] 生产传 WidgetsBinding.instance.rootElement（测试注入）。
Future<Map<String, Object?>> performTap(
  TapSelector selector, {
  Element? root,
}) async {
  if (selector.isEmptySelector) {
    if (!selector.dryRun) {
      return <String, Object?>{
        'ok': false,
        'error':
            '至少给 key 或 text 一个匹配条件（dryRun 空选择器=列出全部 '
            'Text 目标，用于探查页面）',
      };
    }
    final all = resolveTapTargets(root!, selector);
    return <String, Object?>{
      'ok': true,
      'dryRun': true,
      'count': all.length,
      'candidates': <Object?>[for (final TapTarget t in all) t.toJson()],
    };
  }
  final targets = resolveTapTargets(root!, selector);
  if (selector.dryRun) {
    return <String, Object?>{
      'ok': true,
      'dryRun': true,
      'count': targets.length,
      'candidates': <Object?>[for (final TapTarget t in targets) t.toJson()],
    };
  }
  if (selector.index < 0 || selector.index >= targets.length) {
    return <String, Object?>{
      'ok': false,
      'error':
          '命中 ${targets.length} 个候选，index=${selector.index} 越界'
          '（先 dryRun 看候选列表）',
      'count': targets.length,
    };
  }
  final target = targets[selector.index];
  await dispatchTap(target.center);
  return <String, Object?>{
    'ok': true,
    'tapped': target.describe,
    'center': <Object?>[target.center.dx, target.center.dy],
    'count': targets.length,
  };
}
