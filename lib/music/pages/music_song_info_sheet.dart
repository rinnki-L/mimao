// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与音乐模块页同款说明。
/// 歌曲资料面板（L6）：权益（privilege_lite）/ 资料（krm_audio）/
/// 歌手图片（images_audio）三个独立查询分区 + 写真全屏预览。
///
/// 只认 [MusicPlaybackExtApi] 接口，不 import 网络实现；三个分区各自
/// loading/error/重试/空隐藏，互不阻塞。宿主未接线（`ext == null`）时
/// [showMusicSongInfoSheet] 什么都不弹——查询能力由集成者显式传入。
library;

import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/music/api/images_audio.dart';
import 'package:mimao/music/api/krm_audio.dart';
import 'package:mimao/music/api/playback_ext_api.dart';
import 'package:mimao/music/api/privilege_lite.dart';
import 'package:mimao/music/models/music_models.dart';
import 'package:mimao/music/models/playback_ext_models.dart';

/// 资源 hash 预检（与 privilege_lite / images_audio 的入参校验一致：32 位
/// ASCII 十六进制）。页面用它决定「要不要发起查询」——空/非法 hash 直接
/// 隐藏对应分区，而不是等接口抛输入错误。
bool isValidResourceHash(String hash) {
  if (hash.length != 32) return false;
  for (final code in hash.codeUnits) {
    final isDigit = code >= 0x30 && code <= 0x39;
    final isUpperHex = code >= 0x41 && code <= 0x46;
    final isLowerHex = code >= 0x61 && code <= 0x66;
    if (!isDigit && !isUpperHex && !isLowerHex) return false;
  }
  return true;
}

/// images_audio 的外层分组（资源 → 歌手）拍平成一张写真列表：跨歌手、
/// 跨图片类别收集，只保留有 https 地址的条目，保持服务端返回顺序。
List<MusicPortrait> flattenAuthorImages(List<List<MusicAuthorImages>> groups) =>
    <MusicPortrait>[
      for (final group in groups)
        for (final artist in group)
          for (final portraits in artist.images.values)
            for (final portrait in portraits)
              if ((portrait.url ?? '').isNotEmpty) portrait,
    ];

/// 打开歌曲资料面板。`ext == null` 表示宿主未接线查询能力：不弹面板
///（调用方也应据此省略长按回调；面板只认注入的接口）。
Future<void> showMusicSongInfoSheet(
  BuildContext context, {
  required MusicSong song,
  MusicPlaybackExtApi? ext,
}) async {
  if (ext == null) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => MusicSongInfoSheet(song: song, ext: ext),
  );
}

/// 歌曲资料面板：头部基础信息 + 权益/资料/歌手图片三个独立分区。
class MusicSongInfoSheet extends StatefulWidget {
  const MusicSongInfoSheet({super.key, required this.song, required this.ext});

  final MusicSong song;
  final MusicPlaybackExtApi ext;

  @override
  State<MusicSongInfoSheet> createState() => _MusicSongInfoSheetState();
}

class _MusicSongInfoSheetState extends State<MusicSongInfoSheet> {
  // ── 权益（privilegeLite，单曲 hash + albumId）──
  MusicResourcePrivileges? _privilege;
  Object? _privilegeError;
  bool _privilegeLoading = false;

  // ── 资料（krmAudio，album_audio_id = song.audioId；为空不查）──
  MusicSongInformation? _information;
  Object? _infoError;
  bool _infoLoading = false;

  // ── 歌手图片（imagesAudio，hash + filename=歌名）──
  List<MusicPortrait> _portraits = const <MusicPortrait>[];
  Object? _portraitError;
  bool _portraitLoading = false;

  @override
  void initState() {
    super.initState();
    // hash 非法时权益/图片没有可查的资源，直接不发起请求（分区隐藏）。
    if (isValidResourceHash(widget.song.hash)) {
      _loadPrivilege();
      _loadPortraits();
    }
    _loadInfo();
  }

  Future<void> _loadPrivilege() async {
    setState(() {
      _privilegeLoading = true;
      _privilegeError = null;
    });
    try {
      final rows = await widget.ext.privilegeLite(
        PrivilegeLiteQuery(
          resources: <PrivilegeLiteResource>[
            PrivilegeLiteResource(
              hash: widget.song.hash,
              albumId: int.tryParse(widget.song.albumId),
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() {
        _privilege = rows.isEmpty ? null : rows.first;
        _privilegeLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _privilegeError = error;
        _privilegeLoading = false;
      });
    }
  }

  /// 资料查询：`song.audioId` 缺省/非法时不查（规格：为空不查，分区隐藏）。
  Future<void> _loadInfo() async {
    final audioId = widget.song.audioId;
    if (audioId == null || audioId <= 0) return;
    setState(() {
      _infoLoading = true;
      _infoError = null;
    });
    try {
      final presentations = await widget.ext.krmAudio(
        KrmAudioQuery(albumAudioIds: <int>[audioId]),
      );
      if (!mounted) return;
      // 单 id 查询：优先按 album_audio_id 精确匹配，缺行时回退首行。
      MusicSongInformation? information;
      for (final presentation in presentations) {
        if (presentation.id == '$audioId') {
          information = presentation.information;
          break;
        }
      }
      information ??= presentations.isEmpty
          ? null
          : presentations.first.information;
      setState(() {
        _information = information;
        _infoLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _infoError = error;
        _infoLoading = false;
      });
    }
  }

  Future<void> _loadPortraits() async {
    setState(() {
      _portraitLoading = true;
      _portraitError = null;
    });
    try {
      final groups = await widget.ext.imagesAudio(
        ImagesAudioQuery(
          resources: <ImagesAudioResource>[
            ImagesAudioResource(
              hash: widget.song.hash,
              filename: widget.song.title,
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() {
        _portraits = flattenAuthorImages(groups);
        _portraitLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _portraitError = error;
        _portraitLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final song = widget.song;
    final subtitle = <String>[
      if (song.artistText.isNotEmpty) song.artistText,
      if (song.albumTitle.isNotEmpty) song.albumTitle,
    ].join(' · ');
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    song.title.isEmpty ? '未知歌曲' : song.title,
                    style: theme.textTheme.titleLarge,
                  ),
                  if (subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: <Widget>[
                  _privilegeSection(),
                  _infoSection(),
                  _portraitSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 三个分区：同一套「loading / error+重试 / 内容 / 空隐藏」骨架 ──

  Widget _privilegeSection() {
    final privilege = _privilege;
    return _sectionCard(
      title: '权益',
      loading: _privilegeLoading,
      error: _privilegeError,
      onRetry: _loadPrivilege,
      // 空响应整段隐藏；resourceError 是事实（规格要求展示），不算「空」。
      hasContent: privilege != null,
      content: privilege == null
          ? const SizedBox.shrink()
          : _privilegeBody(privilege),
    );
  }

  Widget _infoSection() {
    final information = _information;
    return _sectionCard(
      title: '资料',
      loading: _infoLoading,
      error: _infoError,
      onRetry: _loadInfo,
      hasContent: _infoHasContent,
      content: information == null
          ? const SizedBox.shrink()
          : _infoBody(information),
    );
  }

  /// 资料段是否值得展示：词曲/语言/发行/BPM 全空时整段隐藏。
  bool get _infoHasContent {
    final information = _information;
    if (information == null) return false;
    return (information.lyricist?.isNotEmpty ?? false) ||
        (information.composer?.isNotEmpty ?? false) ||
        (information.language?.isNotEmpty ?? false) ||
        (information.publishedAt?.isNotEmpty ?? false) ||
        (information.albumPublishedAt?.isNotEmpty ?? false) ||
        information.bpm != null;
  }

  Widget _portraitSection() {
    return _sectionCard(
      title: '歌手图片',
      loading: _portraitLoading,
      error: _portraitError,
      onRetry: _loadPortraits,
      hasContent: _portraits.isNotEmpty,
      content: MusicPortraitStrip(portraits: _portraits),
    );
  }

  /// 分区卡骨架：空数据且无错误 → 整段隐藏（零尺寸，不留卡片间距）。
  Widget _sectionCard({
    required String title,
    required bool loading,
    required Object? error,
    required VoidCallback onRetry,
    required bool hasContent,
    required Widget content,
  }) {
    if (!loading && error == null && !hasContent) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final Widget body;
    if (loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (error != null) {
      body = Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '$error',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      );
    } else {
      body = content;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              body,
            ],
          ),
        ),
      ),
    );
  }

  // ── 权益内容：主档位 / 可用音质 / 预览区间 / 资源异常 ──
  // 权益字段只是目录事实（上游注释：status=0 也可能带授权地址），不推断
  // 「可播/免费/VIP」结论，原样展示码值与文本。

  Widget _privilegeBody(MusicResourcePrivileges privilege) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final preview = privilege.preview;
    // 局部可空变量各自判空，区间行只在起止毫秒齐备时展示。
    final startMs = preview?.startMs;
    final endMs = preview?.endMs;
    final hasResourceError =
        (privilege.resourceError ?? 0) != 0 ||
        privilege.resourceMessage.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _kvRow(theme, '主档位', _variantText(privilege.primary)),
        if (privilege.variants.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            '可用音质',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: <Widget>[
              for (final variant in privilege.variants)
                _variantChip(theme, variant),
            ],
          ),
        ],
        if (startMs != null && endMs != null) ...<Widget>[
          const SizedBox(height: 8),
          _kvRow(theme, '预览区间', '${_formatMs(startMs)} – ${_formatMs(endMs)}'),
        ],
        if (hasResourceError) ...<Widget>[
          const SizedBox(height: 8),
          _kvRow(
            theme,
            '资源异常',
            privilege.resourceMessage.isEmpty
                ? '错误码 ${privilege.resourceError}'
                : privilege.resourceMessage,
            valueColor: scheme.error,
          ),
        ],
      ],
    );
  }

  /// 档位展示串：音质 · 码率 · 扩展名；全空时给「未知」占位。
  String _variantText(MusicQualityVariant variant) {
    final parts = <String>[
      if (variant.quality.isNotEmpty) variant.quality,
      if (variant.bitRateBps != null && variant.bitRateBps! > 0)
        '${variant.bitRateBps! ~/ 1000}kbps',
      if (variant.extension.isNotEmpty) variant.extension,
    ];
    return parts.isEmpty ? '未知' : parts.join(' · ');
  }

  Widget _variantChip(ThemeData theme, MusicQualityVariant variant) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: MimaoShapes.pill,
      ),
      child: Text(_variantText(variant), style: theme.textTheme.labelSmall),
    );
  }

  // ── 资料内容：作词 / 作曲 / 语言 / 发行时间 / BPM（空字段隐藏）──

  Widget _infoBody(MusicSongInformation information) {
    final theme = Theme.of(context);
    final publishedAt = (information.publishedAt?.isNotEmpty ?? false)
        ? information.publishedAt!
        : (information.albumPublishedAt ?? '');
    final bpm = information.bpm;
    final rows = <Widget>[
      if (information.lyricist?.isNotEmpty ?? false)
        _kvRow(theme, '作词', information.lyricist!),
      if (information.composer?.isNotEmpty ?? false)
        _kvRow(theme, '作曲', information.composer!),
      if (information.language?.isNotEmpty ?? false)
        _kvRow(theme, '语言', information.language!),
      if (publishedAt.isNotEmpty) _kvRow(theme, '发行时间', publishedAt),
      if (bpm != null) _kvRow(theme, 'BPM', _formatBpm(bpm)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final (index, row) in rows.indexed) ...<Widget>[
          if (index > 0) const SizedBox(height: 6),
          row,
        ],
      ],
    );
  }

  // ── 通用小件 ──

  Widget _kvRow(
    ThemeData theme,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(color: valueColor),
          ),
        ),
      ],
    );
  }

  /// 毫秒 → m:ss（预览区间展示用）。
  String _formatMs(int ms) {
    final seconds = ms ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  /// BPM 展示：整数不带小数点，其余保留 1 位。
  String _formatBpm(double bpm) =>
      bpm == bpm.roundToDouble() ? '${bpm.toInt()}' : bpm.toStringAsFixed(1);
}

/// 横向写真缩略图条：点击任一张全屏预览。纯展示组件——加载/错误/空隐藏
/// 由调用方处理（资料面板与歌手页「歌手写真」分区共用）。
class MusicPortraitStrip extends StatelessWidget {
  const MusicPortraitStrip({
    super.key,
    required this.portraits,
    this.thumbSize = 72,
  });

  final List<MusicPortrait> portraits;
  final double thumbSize;

  @override
  Widget build(BuildContext context) {
    final usable = <MusicPortrait>[
      for (final portrait in portraits)
        if ((portrait.url ?? '').isNotEmpty) portrait,
    ];
    if (usable.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: thumbSize,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: usable.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => _PortraitThumb(
          key: Key('music-portrait-thumb-$index'),
          portrait: usable[index],
          size: thumbSize,
        ),
      ),
    );
  }
}

/// 单张写真缩略图（r10）；图片加载/失败回退静态占位（与封面同款，避免
/// 测试里动画不 settle）。
class _PortraitThumb extends StatelessWidget {
  const _PortraitThumb({super.key, required this.portrait, required this.size});

  final MusicPortrait portrait;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = portrait.url ?? '';
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: MimaoShapes.sm,
      ),
      child: Icon(Icons.image_outlined, color: scheme.primary),
    );
    if (url.isEmpty) return fallback;
    return InkWell(
      borderRadius: MimaoShapes.sm,
      onTap: () => showMusicPortraitPreview(context, portrait),
      child: ClipRRect(
        borderRadius: MimaoShapes.sm,
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : fallback,
        ),
      ),
    );
  }
}

/// 全屏预览一张写真：标题用文件名（缺省「歌手图片」），可缩放查看，
/// 「关闭」退出。无可用地址时不弹（调用方自然不触发）。
void showMusicPortraitPreview(BuildContext context, MusicPortrait portrait) {
  final url = portrait.url ?? '';
  if (url.isEmpty) return;
  final caption = (portrait.filename?.isNotEmpty ?? false)
      ? portrait.filename!
      : '歌手图片';
  showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(caption),
      content: SizedBox(
        width: 320,
        height: 320,
        child: InteractiveViewer(
          maxScale: 4,
          child: Center(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.image_not_supported, size: 48),
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const SizedBox(width: 48, height: 48),
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
