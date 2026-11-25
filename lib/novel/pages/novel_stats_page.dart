// ignore_for_file: deprecated_member_use — Flutter 3.50 弃用整个 material.dart，
// 与小说其他页面同款说明。
/// 阅读统计页：概览四卡 + 近 7/30 天柱状图 + 年视图热力图 + 章节维度。
///
/// 数据源是 `NovelStatsApi`（本机聚合视图），图表全部用 CustomPainter 自绘，
/// 不引入图表库：柱状图、日历热力图、章节时长条三种画法都在本文件里，
/// 颜色只从 ColorScheme 取，圆角只用 MimaoRadius 的档位。
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/material.dart';
import 'package:mimao/core/theme.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/pages/novel_widgets.dart';
import 'package:mimao/novel/stats_service.dart';

/// 统计页；[stats] 未注入时显示能力说明（不伪造数字）。
class NovelStatsPage extends StatefulWidget {
  const NovelStatsPage({super.key, this.stats});

  final NovelStatsApi? stats;

  @override
  State<NovelStatsPage> createState() => _NovelStatsPageState();
}

class _NovelStatsPageState extends State<NovelStatsPage> {
  late Future<_StatsData> _future;
  int _rangeDays = 7;
  int _year = DateTime.now().year;
  String? _selectedBookId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_StatsData> _load() async {
    final api = widget.stats;
    if (api == null) return _StatsData.empty();
    final overview = await api.overview();
    final days = await api.timeline();
    final heatmap = await api.heatmapSeconds(year: _year);
    // 书列表按累计时长倒序（时间轴已是逐日倒序，累计后重排）。
    final secondsByBook = <String, int>{};
    final titles = <String, String>{};
    for (final day in days) {
      for (final book in day.books) {
        if (book.bookId.isEmpty || book.seconds <= 0) continue;
        secondsByBook[book.bookId] =
            (secondsByBook[book.bookId] ?? 0) + book.seconds;
        if (book.title.isNotEmpty) titles[book.bookId] = book.title;
      }
    }
    final bookIds = secondsByBook.keys.toList()
      ..sort((a, b) => secondsByBook[b]!.compareTo(secondsByBook[a]!));
    var selected = _selectedBookId;
    if (selected == null || !secondsByBook.containsKey(selected)) {
      selected = bookIds.isEmpty ? null : bookIds.first;
    }
    final chapters = selected == null || selected.isEmpty
        ? const <NovelChapterStats>[]
        : await api.bookChapters(selected);
    final daySeconds = <String, int>{
      for (final day in days) day.day: day.seconds,
    };
    return _StatsData(
      overview: overview,
      daySeconds: daySeconds,
      heatmap: heatmap,
      bookIds: bookIds,
      bookTitles: titles,
      bookSeconds: secondsByBook,
      selectedBookId: selected,
      chapters: chapters,
    );
  }

  void _reload() {
    setState(() {
      _selectedBookId = _selectedBookId;
      _future = _load();
    });
  }

  void _setRange(int days) {
    if (days == _rangeDays) return;
    setState(() {
      _rangeDays = days;
    });
  }

  void _shiftYear(int delta) {
    final next = _year + delta;
    if (next > DateTime.now().year) return;
    setState(() {
      _year = next;
      _future = _load();
    });
  }

  Future<void> _selectBook(String? bookId) async {
    if (bookId == null || bookId == _selectedBookId) return;
    setState(() {
      _selectedBookId = bookId;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('阅读统计'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<_StatsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const NovelLoadingState(label: '正在汇总阅读记录…');
          }
          if (snapshot.hasError) {
            return NovelErrorState(
              message: '统计读取失败：${snapshot.error}',
              onRetry: _reload,
            );
          }
          final data = snapshot.data ?? _StatsData.empty();
          if (data.isEmpty) {
            return const NovelEmptyState(
              icon: Icons.insights_outlined,
              title: '还没有阅读时长记录',
              message: '阅读器在退出或换章时结算时长；读几页再回来看。',
            );
          }
          return NovelPageContent(
            maxWidth: 1100,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: ListView(
              children: <Widget>[
                _OverviewSection(data: data),
                const SizedBox(height: 24),
                NovelSectionHeader(
                  icon: Icons.bar_chart,
                  title: '阅读时长',
                  trailing: SegmentedButton<int>(
                    segments: const <ButtonSegment<int>>[
                      ButtonSegment<int>(value: 7, label: Text('近 7 天')),
                      ButtonSegment<int>(value: 30, label: Text('近 30 天')),
                    ],
                    selected: <int>{_rangeDays},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        _setRange(selection.first),
                  ),
                ),
                const SizedBox(height: 10),
                NovelCard(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: SizedBox(
                    height: 190,
                    child: _BarChart(
                      buckets: novelBarBuckets(
                        data.daySeconds,
                        end: DateTime.now(),
                        count: _rangeDays,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                NovelSectionHeader(
                  icon: Icons.grid_on,
                  title: '阅读热力图',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton(
                        tooltip: '上一年',
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => _shiftYear(-1),
                      ),
                      Text('$_year 年'),
                      IconButton(
                        tooltip: '下一年',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _year >= DateTime.now().year
                            ? null
                            : () => _shiftYear(1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                NovelCard(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: SizedBox(
                    height: 136,
                    child: _Heatmap(year: _year, daySeconds: data.heatmap),
                  ),
                ),
                const SizedBox(height: 24),
                NovelSectionHeader(
                  icon: Icons.menu_book_outlined,
                  title: '章节维度',
                ),
                const SizedBox(height: 10),
                _ChapterSection(data: data, onSelect: _selectBook),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 一次加载的整页数据。
class _StatsData {
  const _StatsData({
    required this.overview,
    required this.daySeconds,
    required this.heatmap,
    required this.bookIds,
    required this.bookTitles,
    required this.bookSeconds,
    required this.selectedBookId,
    required this.chapters,
  });

  factory _StatsData.empty() => const _StatsData(
    overview: NovelStatsOverview(
      totalSeconds: 0,
      booksRead: 0,
      activeDays: 0,
      averageSecondsPerDay: 0,
      currentStreak: 0,
      longestStreak: 0,
      todaySeconds: 0,
    ),
    daySeconds: <String, int>{},
    heatmap: <String, int>{},
    bookIds: <String>[],
    bookTitles: <String, String>{},
    bookSeconds: <String, int>{},
    selectedBookId: null,
    chapters: <NovelChapterStats>[],
  );

  final NovelStatsOverview overview;
  final Map<String, int> daySeconds;
  final Map<String, int> heatmap;
  final List<String> bookIds;
  final Map<String, String> bookTitles;
  final Map<String, int> bookSeconds;
  final String? selectedBookId;
  final List<NovelChapterStats> chapters;

  bool get isEmpty => daySeconds.isEmpty;
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({required this.data});

  final _StatsData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final overview = data.overview;
    final (totalValue, totalUnit) = novelDurationParts(overview.totalSeconds);
    final (avgValue, avgUnit) = novelDurationParts(
      overview.averageSecondsPerDay,
    );
    final cards = <Widget>[
      NovelStatCard(
        icon: Icons.schedule,
        label: '累计时长',
        value: totalValue,
        unit: totalUnit,
      ),
      NovelStatCard(
        icon: Icons.auto_stories_outlined,
        label: '累计本数',
        value: '${overview.booksRead}',
        unit: '本',
      ),
      NovelStatCard(
        icon: Icons.today_outlined,
        label: '日均（活跃日）',
        value: avgValue,
        unit: avgUnit,
      ),
      NovelStatCard(
        icon: Icons.local_fire_department_outlined,
        label: '最长连续',
        value: '${overview.longestStreak}',
        unit: '天',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        NovelSectionHeader(icon: Icons.insights, title: '概览'),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900
                ? 4
                : constraints.maxWidth >= 560
                ? 2
                : 1;
            const gap = 12.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: <Widget>[
                for (final card in cards) SizedBox(width: width, child: card),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          '当前连续 ${overview.currentStreak} 天 · '
          '活跃 ${overview.activeDays} 天 · '
          '今日 ${overview.todaySeconds ~/ 60} 分钟',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 近 N 天柱状图（CustomPainter 自绘：网格 + 柱 + 日期标签）。
class _BarChart extends StatelessWidget {
  const _BarChart({required this.buckets});

  final List<NovelBarBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return CustomPaint(
      size: Size.infinite,
      painter: _BarChartPainter(
        buckets: buckets,
        barColor: cs.primary,
        gridColor: cs.outlineVariant,
        labelStyle: theme.textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
        ),
        valueStyle: theme.textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
        ),
        maxValueStyle: theme.textTheme.labelSmall?.copyWith(color: cs.primary),
      ),
    );
  }
}

class _BarChartPainter extends CustomPainter {
  _BarChartPainter({
    required this.buckets,
    required this.barColor,
    required this.gridColor,
    required this.labelStyle,
    required this.valueStyle,
    required this.maxValueStyle,
  });

  final List<NovelBarBucket> buckets;
  final Color barColor;
  final Color gridColor;
  final TextStyle? labelStyle;
  final TextStyle? valueStyle;
  final TextStyle? maxValueStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (buckets.isEmpty || size.width <= 0 || size.height <= 0) return;
    final labelSize = labelStyle?.fontSize ?? 11;
    final bottomInset = labelSize + 8;
    final topInset = labelSize + 6;
    final chartHeight = size.height - bottomInset - topInset;
    if (chartHeight <= 0) return;

    final maxSeconds = buckets.fold<int>(
      0,
      (best, bucket) => bucket.seconds > best ? bucket.seconds : best,
    );
    final scaleMax = maxSeconds <= 0 ? 1 : maxSeconds;

    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = topInset + chartHeight * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final slot = size.width / buckets.length;
    final barWidth = math.min(slot * 0.56, 32.0);
    final barPaint = Paint()..color = barColor;
    final radius = Radius.circular(MimaoRadii.sm);
    final labelStep = buckets.length <= 7 ? 1 : 5;
    for (var index = 0; index < buckets.length; index++) {
      final bucket = buckets[index];
      final ratio = bucket.seconds / scaleMax;
      final height = chartHeight * ratio;
      final centerX = slot * index + slot / 2;
      final rect = Rect.fromLTWH(
        centerX - barWidth / 2,
        topInset + chartHeight - height,
        barWidth,
        height.clamp(0, chartHeight),
      );
      if (height > 0) {
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), barPaint);
      }
      if (index % labelStep == 0 || index == buckets.length - 1) {
        _paintText(
          canvas,
          _shortDay(bucket.day),
          labelStyle,
          Offset(centerX, size.height - labelSize - 1),
          center: true,
        );
      }
      if (bucket.seconds > 0 && index == _maxIndex()) {
        _paintText(
          canvas,
          _formatSeconds(bucket.seconds),
          maxValueStyle,
          Offset(centerX, rect.top - labelSize - 2),
          center: true,
        );
      }
    }
  }

  int _maxIndex() {
    var best = 0;
    for (var i = 0; i < buckets.length; i++) {
      if (buckets[i].seconds > buckets[best].seconds) best = i;
    }
    return best;
  }

  String _shortDay(String day) {
    // `yyyy-MM-dd` → `M/d`，柱宽有限不放年份。
    final parts = day.split('-');
    if (parts.length != 3) return day;
    return '${int.parse(parts[1])}/${int.parse(parts[2])}';
  }

  String _formatSeconds(int seconds) {
    if (seconds < 3600) return '${(seconds / 60).round()} 分';
    return '${(seconds / 3600).toStringAsFixed(1)} 时';
  }

  void _paintText(
    Canvas canvas,
    String text,
    TextStyle? style,
    Offset at, {
    bool center = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center ? Offset(at.dx - painter.width / 2, at.dy) : at,
    );
  }

  @override
  bool shouldRepaint(_BarChartPainter oldDelegate) =>
      !listEquals(oldDelegate.buckets, buckets) ||
      oldDelegate.barColor != barColor ||
      oldDelegate.gridColor != gridColor;

  @override
  bool shouldRebuildSemantics(covariant CustomPainter oldDelegate) => false;
}

/// 年视图热力图：7 行（周一..周日）× N 列（周），顶部月份、左侧星期。
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.year, required this.daySeconds});

  final int year;
  final Map<String, int> daySeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return CustomPaint(
      size: Size.infinite,
      painter: _HeatmapPainter(
        year: year,
        levels: novelHeatLevels(daySeconds),
        activeColor: cs.primary,
        emptyColor: cs.outlineVariant.withValues(alpha: 0.35),
        labelStyle: theme.textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.year,
    required this.levels,
    required this.activeColor,
    required this.emptyColor,
    required this.labelStyle,
  });

  final int year;

  /// `yyyy-MM-dd` → 1..4 档（0/缺省 = 没读）。
  final Map<String, int> levels;
  final Color activeColor;
  final Color emptyColor;
  final TextStyle? labelStyle;

  static const List<double> _alphas = <double>[0.28, 0.5, 0.74, 1];

  @override
  void paint(Canvas canvas, Size size) {
    final labelSize = labelStyle?.fontSize ?? 11;
    final leftInset = labelSize * 1.6;
    final topInset = labelSize + 6;
    final width = size.width - leftInset;
    final height = size.height - topInset;
    if (width <= 0 || height <= 0) return;

    final first = DateTime(year, 1, 1);
    final last = DateTime(year, 12, 31);
    final daysInYear = last.difference(first).inDays + 1;
    // 周一 = 第 0 行；1 月 1 日可能落在周中。
    final leading = first.weekday - 1;
    final weeks = ((leading + daysInYear) / 7).ceil();
    final cell = math.min(width / weeks, height / 7);
    final gap = math.max(cell * 0.14, 1.0);
    final radius = Radius.circular(math.max(cell * 0.22, 1.5));
    final emptyPaint = Paint()..color = emptyColor;
    final paint = Paint();
    final monthTexts = <int, int>{};

    for (var i = 0; i < daysInYear; i++) {
      final day = first.add(Duration(days: i));
      final slot = leading + i;
      final col = slot ~/ 7;
      final row = slot % 7;
      final rect = Rect.fromLTWH(
        leftInset + col * cell,
        topInset + row * cell,
        cell - gap,
        cell - gap,
      );
      final level = levels[_dayKey(day)] ?? 0;
      if (level <= 0) {
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), emptyPaint);
      } else {
        paint.color = activeColor.withValues(
          alpha: _alphas[(level - 1).clamp(0, _alphas.length - 1)],
        );
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), paint);
      }
      if (day.day <= 7) monthTexts[day.month] = col;
    }

    for (final entry in monthTexts.entries) {
      _paintText(
        canvas,
        '${entry.key}月',
        labelStyle,
        Offset(leftInset + entry.value * cell, 0),
      );
    }
    const weekdayLabels = <int, String>{0: '一', 2: '三', 4: '五', 6: '日'};
    for (final entry in weekdayLabels.entries) {
      _paintText(
        canvas,
        entry.value,
        labelStyle,
        Offset(0, topInset + entry.key * cell),
      );
    }
  }

  String _dayKey(DateTime day) {
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '${day.year}-$month-$date';
  }

  void _paintText(Canvas canvas, String text, TextStyle? style, Offset at) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_HeatmapPainter oldDelegate) =>
      oldDelegate.year != year ||
      oldDelegate.activeColor != activeColor ||
      !mapEquals(oldDelegate.levels, levels);

  @override
  bool shouldRebuildSemantics(covariant CustomPainter oldDelegate) => false;
}

class _ChapterSection extends StatelessWidget {
  const _ChapterSection({required this.data, required this.onSelect});

  final _StatsData data;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (data.bookIds.isEmpty) {
      return NovelCard(
        child: Text(
          '还没有带书名的章节记录。阅读器换章时会按「书 + 章」结算；'
          '只读到旧版记录的话，章节维度要等新记录进来才有。',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    }
    final selected = data.selectedBookId;
    final title = data.bookTitles[selected]?.isNotEmpty == true
        ? data.bookTitles[selected]!
        : (selected?.isEmpty ?? true ? '未知书籍' : selected!);
    final maxSeconds = data.chapters.fold<int>(
      0,
      (best, chapter) => chapter.seconds > best ? chapter.seconds : best,
    );
    return NovelCard(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selected,
              isExpanded: true,
              borderRadius: MimaoShapes.md,
              items: <DropdownMenuItem<String>>[
                for (final bookId in data.bookIds)
                  DropdownMenuItem<String>(
                    value: bookId,
                    child: Text(
                      data.bookTitles[bookId]?.isNotEmpty == true
                          ? data.bookTitles[bookId]!
                          : bookId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: onSelect,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$title · ${_durationText(data.bookSeconds[selected] ?? 0)}'
            ' · ${data.chapters.length} 章',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (data.chapters.isEmpty)
            Text(
              '这本书还没有按章记录。旧版记录只有整本时长，'
              '换章结算从这次更新后才开始累计。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            )
          else
            for (final chapter in data.chapters)
              _ChapterRow(chapter: chapter, maxSeconds: maxSeconds),
        ],
      ),
    );
  }

  String _durationText(int seconds) {
    final (value, unit) = novelDurationParts(seconds);
    return '$value $unit';
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({required this.chapter, required this.maxSeconds});

  final NovelChapterStats chapter;
  final int maxSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    // 章节名经常本身就以「第 N 章」开头（书源目录原文），再拼一次前缀会变成
    // 「第 3 章 · 第 3 章」；[novelChapterLabel] 统一处理这个去重。
    final name = novelChapterLabel(
      chapterIndex: chapter.chapterIndex,
      chapterName: chapter.chapterName,
    );
    final last = chapter.lastReadAt;
    final (value, unit) = novelDurationParts(chapter.seconds);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$value $unit',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (last != null) ...<Widget>[
                const SizedBox(width: 8),
                Text(
                  _lastReadLabel(last),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 6,
            child: CustomPaint(
              size: Size.infinite,
              painter: _ChapterBarPainter(
                ratio: maxSeconds <= 0
                    ? 0
                    : (chapter.seconds / maxSeconds).clamp(0.0, 1.0),
                trackColor: cs.surfaceContainerHighest,
                barColor: cs.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _lastReadLabel(DateTime at) {
    final local = at.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$month-$day';
  }
}

class _ChapterBarPainter extends CustomPainter {
  _ChapterBarPainter({
    required this.ratio,
    required this.trackColor,
    required this.barColor,
  });

  final double ratio;
  final Color trackColor;
  final Color barColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final track = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, radius),
      Paint()..color = trackColor,
    );
    final width = size.width * ratio;
    if (width <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, width, size.height), radius),
      Paint()..color = barColor,
    );
  }

  @override
  bool shouldRepaint(_ChapterBarPainter oldDelegate) =>
      oldDelegate.ratio != ratio ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.barColor != barColor;
}
