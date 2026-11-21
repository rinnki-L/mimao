// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与 music/pages 其它文件同款说明。
/// 音乐偏好页（L3）：userPreference 读取 + userPreferenceUpdate 差量写入。
///
/// 六个字段（mode/gender/age/lang/style/song_lang）都是字符串；lang/style/
/// song_lang 是权重型偏好——能解出 weights 时按「标签: 权重」chips 展示并
/// 行编辑，解不出时展示原始文本（不丢远端值），连文本都没有的只读展示。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:mimao/music/api/user_library_api.dart';
import 'package:mimao/music/models/user_library_models.dart';

/// 单个权重编辑行：「标签 + 权重」两个输入框。
class _WeightRow {
  _WeightRow({required String label, required String weight})
    : label = TextEditingController(text: label),
      weight = TextEditingController(text: weight);

  final TextEditingController label;
  final TextEditingController weight;

  void dispose() {
    label.dispose();
    weight.dispose();
  }
}

/// 单个权重字段的编辑状态。
///
/// - 远端值解得出 weights → 行编辑（标签+权重），保存时排序后序列化回
///   紧凑 JSON（与端点 BTreeMap 键序约定一致）；
/// - 远端值是字符串但解不出 weights → 原始文本编辑（提交原样字符串，
///   便于修正坏值）；
/// - 连文本都没有（数字/布尔等）→ 只读展示，不参与提交。
class _WeightField {
  _WeightField({
    required this.wireKey,
    required this.title,
    required this.initial,
  }) {
    final Map<String, double>? weights = initial.weights;
    if (weights != null) {
      // 按 key 排序展示，行序稳定（远端 BTreeMap 键序）。
      final List<String> keys = weights.keys.toList()..sort();
      for (final String key in keys) {
        rows.add(_WeightRow(label: key, weight: formatWeight(weights[key]!)));
      }
    } else {
      rawText.text = initial.encoded ?? '';
    }
  }

  /// wire 字段名（lang/style/song_lang），仅用于测试定位 key。
  final String wireKey;
  final String title;
  final MusicWeightPreference initial;

  final List<_WeightRow> rows = <_WeightRow>[];

  /// 原始文本编辑器（仅 editableByText 时展示；始终持有便于 dispose）。
  final TextEditingController rawText = TextEditingController();

  bool get editableByRows => initial.weights != null;

  bool get editableByText => initial.weights == null && initial.encoded != null;

  void dispose() {
    for (final _WeightRow row in rows) {
      row.dispose();
    }
    rawText.dispose();
  }
}

/// 权重展示/序列化共用格式：整值不带小数点（2.0 → '2'），其余原样。
String formatWeight(double value) =>
    value == value.roundToDouble() ? value.toInt().toString() : '$value';

/// 行编辑结果序列化为紧凑 JSON：key 排序（上游 BTreeMap 键序）、整值不带
/// 小数点。服务端按 JSON 数字解析，整数与浮点等价。
String serializeWeights(Map<String, double> weights) {
  final List<String> keys = weights.keys.toList()..sort();
  return jsonEncode(<String, Object?>{
    for (final String key in keys)
      key: weights[key]! == weights[key]!.roundToDouble()
          ? weights[key]!.toInt()
          : weights[key]!,
  });
}

/// 音乐偏好页。进入即 `library.userPreference()` 装载；保存只提交相对
/// 初始快照有改动的字段，无改动就地提示、不发请求。
class MusicPreferencePage extends StatefulWidget {
  const MusicPreferencePage({super.key, required this.library});

  final MusicUserLibraryApi library;

  @override
  State<MusicPreferencePage> createState() => _MusicPreferencePageState();
}

class _MusicPreferencePageState extends State<MusicPreferencePage> {
  bool _loading = true;
  Object? _error;

  MusicPreferences? _initial;
  late final TextEditingController _mode = TextEditingController();
  late final TextEditingController _gender = TextEditingController();
  late final TextEditingController _age = TextEditingController();
  List<_WeightField> _weights = <_WeightField>[];

  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _mode.dispose();
    _gender.dispose();
    _age.dispose();
    for (final _WeightField field in _weights) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await widget.library.userPreference();
      if (!mounted) return;
      setState(() {
        _applyPreferences(prefs);
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _applyPreferences(MusicPreferences prefs) {
    for (final _WeightField field in _weights) {
      field.dispose();
    }
    _mode.text = prefs.recommendationMode ?? '';
    _gender.text = prefs.gender ?? '';
    _age.text = prefs.age ?? '';
    _weights = <_WeightField>[
      _WeightField(wireKey: 'lang', title: '语言偏好', initial: prefs.languages),
      _WeightField(wireKey: 'style', title: '曲风偏好', initial: prefs.styles),
      _WeightField(
        wireKey: 'song_lang',
        title: '推荐语种',
        initial: prefs.recommendation,
      ),
    ];
    _initial = prefs;
  }

  /// 文本字段的差量：与初始值相同 → null（不下发）；否则提交文本
  /// （空串是合法值——端点语义为「清除/重置」）。
  String? _textDiff(TextEditingController controller, String? initial) {
    final String text = controller.text.trim();
    return text == (initial ?? '') ? null : text;
  }

  /// 行编辑 → `Map<String, double>`；空标签行跳过；权重不是数字 → null。
  Map<String, double>? _collectRows(_WeightField field) {
    final map = <String, double>{};
    for (final _WeightRow row in field.rows) {
      final String label = row.label.text.trim();
      if (label.isEmpty) continue;
      final double? weight = double.tryParse(row.weight.text.trim());
      if (weight == null) return null;
      map[label] = weight;
    }
    return map;
  }

  // ── 保存 ─────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final MusicPreferences? initial = _initial;
    if (initial == null || _saving) return;

    final String? mode = _textDiff(_mode, initial.recommendationMode);
    final String? gender = _textDiff(_gender, initial.gender);
    final String? age = _textDiff(_age, initial.age);
    final List<String?> weightFields = <String?>[
      _weightDiff(_weights[0]),
      _weightDiff(_weights[1]),
      _weightDiff(_weights[2]),
    ];
    if (weightFields.contains(_kInvalidWeight)) {
      setState(() {
        _saveError = '权重必须是数字（可为负数或小数）';
      });
      return;
    }

    final bool hasChange =
        mode != null ||
        gender != null ||
        age != null ||
        weightFields.any((String? value) => value != null);
    if (!hasChange) {
      setState(() => _saveError = '偏好没有变化');
      return;
    }

    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final result = await widget.library.userPreferenceUpdate(
        MusicPreferenceUpdateQuery(
          recommendationMode: mode,
          gender: gender,
          age: age,
          languages: weightFields[0],
          styles: weightFields[1],
          recommendation: weightFields[2],
        ),
      );
      if (!mounted) return;
      // 端点成功即 updated=true；false 按失败处理（页内提示，不退出）。
      if (!result.updated) {
        setState(() {
          _saving = false;
          _saveError = '保存失败，请稍后重试';
        });
        return;
      }
      Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = '保存失败：$error';
      });
    }
  }

  /// 权重字段的差量：无效值返回哨兵 [kInvalidWeight]；未改动返回 null。
  String? _weightDiff(_WeightField field) {
    if (field.editableByRows) {
      final Map<String, double>? map = _collectRows(field);
      if (map == null) return _kInvalidWeight;
      // 与远端解出的 weights 逐值比对（double 相等），序列化格式差异
      // （'2' vs '2.0'）不构成「改动」。
      if (mapEquals(map, field.initial.weights)) return null;
      return serializeWeights(map);
    }
    if (field.editableByText) {
      final String text = field.rawText.text;
      return text == field.initial.encoded ? null : text;
    }
    return null;
  }

  static const String _kInvalidWeight = '__invalid__';

  // ── 组装 ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('音乐偏好')),
      body: _loading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('$_error', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text('基础偏好', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                TextFormField(
                  key: const ValueKey<String>('pref-mode'),
                  controller: _mode,
                  decoration: const InputDecoration(
                    labelText: '推荐模式',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey<String>('pref-gender'),
                  controller: _gender,
                  decoration: const InputDecoration(
                    labelText: '性别',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey<String>('pref-age'),
                  controller: _age,
                  decoration: const InputDecoration(
                    labelText: '年龄',
                    border: OutlineInputBorder(),
                  ),
                ),
                for (final _WeightField field in _weights) ...<Widget>[
                  const SizedBox(height: 20),
                  _buildWeightSection(context, field),
                ],
                if (_saveError != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    _saveError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  key: const ValueKey<String>('pref-save'),
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? '保存中…' : '保存'),
                ),
              ],
            ),
    );
  }

  Widget _buildWeightSection(BuildContext context, _WeightField field) {
    final theme = Theme.of(context);
    return Column(
      key: ValueKey<String>('pref-${field.wireKey}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(field.title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (field.editableByRows)
          // 能解出 weights：远端快照以 chips 展示（「标签: 权重」），
          // 行编辑器负责修改。
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final String key
                  in (field.initial.weights ?? const <String, double>{}).keys
                      .toList()
                    ..sort())
                Chip(
                  label: Text(
                    '$key: ${formatWeight(field.initial.weights![key]!)}',
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          )
        else if (field.editableByText)
          // 解不出 weights 的字符串原值：原始文本直接进输入框（可修正）。
          TextFormField(
            key: ValueKey<String>('pref-${field.wireKey}-raw'),
            controller: field.rawText,
            decoration: InputDecoration(
              labelText: '${field.title}（原始文本）',
              border: const OutlineInputBorder(),
            ),
          )
        else
          // 连文本都没有的远端值：只读展示，绝不静默丢弃。
          Text(
            '原始值：${field.initial.raw ?? '（空）'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (field.editableByRows) ...<Widget>[
          const SizedBox(height: 8),
          for (var index = 0; index < field.rows.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextFormField(
                      key: ValueKey<String>(
                        'pref-${field.wireKey}-label-$index',
                      ),
                      controller: field.rows[index].label,
                      decoration: const InputDecoration(
                        hintText: '标签',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey<String>(
                        'pref-${field.wireKey}-weight-$index',
                      ),
                      controller: field.rows[index].weight,
                      decoration: const InputDecoration(
                        hintText: '权重',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    key: ValueKey<String>(
                      'pref-${field.wireKey}-remove-$index',
                    ),
                    onPressed: () =>
                        setState(() => field.rows.removeAt(index)..dispose()),
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: '移除',
                  ),
                ],
              ),
            ),
          OutlinedButton.icon(
            key: ValueKey<String>('pref-${field.wireKey}-add'),
            onPressed: () => setState(
              () => field.rows.add(_WeightRow(label: '', weight: '')),
            ),
            icon: const Icon(Icons.add),
            label: const Text('添加标签'),
          ),
        ],
      ],
    );
  }
}
