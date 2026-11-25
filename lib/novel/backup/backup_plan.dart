/// 恢复合并规划：把「本机快照」与「远端文档」比成一张可预览、可执行的计划。
///
/// **这一层是纯函数**：不碰 IO、不碰 drift，喂两个 [NovelBackupDocument] 就出
/// [NovelBackupPlan]。预览页显示的计数与真正执行的操作来自同一个 plan，
/// 不存在"预览算一遍、执行再算一遍"的漂移。
///
/// 合并口径（与需求一一对应）：
/// - **进度**：按 `(bookId, sourceKey)`；章号大者胜，同章取时间更新者，全同取本地。
///   确定性规则，不进冲突列表。
/// - **收藏**：并集（恢复从不删本地收藏）；同书两侧的分组/系列/备注不同 → 冲突。
/// - **分组/系列**：名称取并集，同名复用，不做第二套 id。
/// - **书签/划线**：按锚点自然键并集去重；同键内容不同 → 冲突。
/// - **阅读时长**：按 `(deviceId,bookId,chapterIndex,day)` 取 max（重复导入幂等），
///   各设备各自成行、互不覆盖。
/// - **设置**：分「跨设备共享」与「设备本地」两档——共享项远端赢，本地项本地赢。
/// - **墓碑**：较新的删除记录压过较旧的行，避免删掉的书签被合并复活。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:mimao/novel/backup/backup_document.dart';
import 'package:mimao/novel/library_api.dart';
import 'package:mimao/novel/models/novel_models.dart';
import 'package:mimao/novel/reader/novel_locator.dart';
import 'package:mimao/novel/source/novel_source_model.dart';

/// 计划里的一条操作落在哪张"逻辑表"上。
enum NovelBackupTarget {
  progress('阅读进度'),
  collect('收藏'),
  series('系列'),
  bookmark('书签'),
  marking('划线'),
  readRecord('阅读时长'),
  tombstone('删除记录'),
  source('书源'),
  searchKeyword('搜索历史'),
  pref('设置');

  const NovelBackupTarget(this.label);

  final String label;
}

enum NovelBackupAction { insert, update, delete }

/// 一条可自动执行的操作。payload 一律是「存档 JSON」，执行层据此落库。
class NovelBackupOp {
  const NovelBackupOp({
    required this.target,
    required this.action,
    required this.key,
    this.payload = const <String, Object?>{},
    this.label = '',
  });

  final NovelBackupTarget target;
  final NovelBackupAction action;
  final String key;
  final Map<String, Object?> payload;

  /// 展示用的一句话（"《三体》 · 第 12 章"）。
  final String label;

  String get id => '${target.name}:${action.name}:$key';

  @override
  String toString() =>
      'NovelBackupOp(${target.name}.${action.name}, $key, $label)';
}

/// 一条需要用户拍板的冲突。
///
/// 默认取本地（`localOp` 为 null 表示"本地保持不动"）；用户勾选远端后改执行
/// [remoteOp]。
class NovelBackupConflict {
  const NovelBackupConflict({
    required this.target,
    required this.key,
    required this.title,
    required this.detail,
    required this.localText,
    required this.remoteText,
    required this.remoteOp,
    this.localOp,
  });

  final NovelBackupTarget target;

  /// 合并键；[NovelBackupPlan.resolveConflicts] 用它认领选择结果。
  final String key;

  /// 冲突标题（书名 / 规则名）。
  final String title;

  /// 冲突字段说明（"分组不同"）。
  final String detail;

  final String localText;
  final String remoteText;

  /// 用户选远端时执行的操作。
  final NovelBackupOp remoteOp;

  /// 用户选本地时执行的操作；null = 保持本地不动。
  final NovelBackupOp? localOp;

  String get id => '${target.name}:$key';
}

/// 预览页顶部的四个数字。
class NovelBackupCounts {
  const NovelBackupCounts({
    this.added = 0,
    this.updated = 0,
    this.removed = 0,
    this.conflicts = 0,
    this.unchanged = 0,
    this.skipped = 0,
  });

  final int added;
  final int updated;
  final int removed;
  final int conflicts;

  /// 两侧已一致，无需动作。
  final int unchanged;

  /// 刻意跳过（例如远端进度对应的书本地没有、墓碑压过）。
  final int skipped;

  /// 计划里真正要执行的操作数（含已消解的冲突）。
  int get total => added + updated + removed;

  bool get isNoop => total == 0 && conflicts == 0;

  /// 一句人话，预览页与 toast 共用。
  String get summary {
    final parts = <String>['新增 $added', '更新 $updated'];
    if (removed > 0) parts.add('删除 $removed');
    parts.add('冲突 $conflicts');
    return parts.join(' · ');
  }

  NovelBackupCounts operator +(NovelBackupCounts other) => NovelBackupCounts(
    added: added + other.added,
    updated: updated + other.updated,
    removed: removed + other.removed,
    conflicts: conflicts + other.conflicts,
    unchanged: unchanged + other.unchanged,
    skipped: skipped + other.skipped,
  );
}

/// 分类明细（预览页按"维度"列一行）。
class NovelBackupTargetCounts {
  const NovelBackupTargetCounts({
    required this.target,
    required this.added,
    required this.updated,
    required this.removed,
    required this.conflicts,
  });

  final NovelBackupTarget target;
  final int added;
  final int updated;
  final int removed;
  final int conflicts;

  bool get isEmpty =>
      added == 0 && updated == 0 && removed == 0 && conflicts == 0;

  String get text {
    final parts = <String>[];
    if (added > 0) parts.add('新增 $added');
    if (updated > 0) parts.add('更新 $updated');
    if (removed > 0) parts.add('删除 $removed');
    if (conflicts > 0) parts.add('冲突 $conflicts');
    return parts.join(' · ');
  }
}

/// 恢复计划。
class NovelBackupPlan {
  const NovelBackupPlan({
    required this.ops,
    this.conflicts = const <NovelBackupConflict>[],
    this.unchanged = 0,
    this.skipped = 0,
  });

  static const NovelBackupPlan empty = NovelBackupPlan(ops: <NovelBackupOp>[]);

  final List<NovelBackupOp> ops;
  final List<NovelBackupConflict> conflicts;
  final int unchanged;
  final int skipped;

  NovelBackupCounts get counts => NovelBackupCounts(
    added: ops.where((op) => op.action == NovelBackupAction.insert).length,
    updated: ops.where((op) => op.action == NovelBackupAction.update).length,
    removed: ops.where((op) => op.action == NovelBackupAction.delete).length,
    conflicts: conflicts.length,
    unchanged: unchanged,
    skipped: skipped,
  );

  List<NovelBackupTargetCounts> get byTarget {
    final added = <NovelBackupTarget, int>{};
    final updated = <NovelBackupTarget, int>{};
    final removed = <NovelBackupTarget, int>{};
    final conflicted = <NovelBackupTarget, int>{};
    for (final op in ops) {
      final bucket = switch (op.action) {
        NovelBackupAction.insert => added,
        NovelBackupAction.update => updated,
        NovelBackupAction.delete => removed,
      };
      bucket[op.target] = (bucket[op.target] ?? 0) + 1;
    }
    for (final conflict in conflicts) {
      conflicted[conflict.target] = (conflicted[conflict.target] ?? 0) + 1;
    }
    return <NovelBackupTargetCounts>[
      for (final target in NovelBackupTarget.values)
        NovelBackupTargetCounts(
          target: target,
          added: added[target] ?? 0,
          updated: updated[target] ?? 0,
          removed: removed[target] ?? 0,
          conflicts: conflicted[target] ?? 0,
        ),
    ].where((row) => !row.isEmpty).toList(growable: false);
  }

  /// 把冲突按用户选择展开成可执行计划。
  ///
  /// [useRemote] 键是 [NovelBackupConflict.id]；true = 用远端，缺省 = 用本地。
  NovelBackupPlan resolveConflicts(Map<String, bool> useRemote) {
    final resolved = <NovelBackupOp>[...ops];
    for (final conflict in conflicts) {
      final pickRemote = useRemote[conflict.id] ?? false;
      if (pickRemote) {
        resolved.add(conflict.remoteOp);
      } else if (conflict.localOp != null) {
        resolved.add(conflict.localOp!);
      }
    }
    return NovelBackupPlan(
      ops: List<NovelBackupOp>.unmodifiable(resolved),
      conflicts: const <NovelBackupConflict>[],
      unchanged: unchanged,
      skipped: skipped,
    );
  }
}

/// 墓碑保留期：超过就把删除记录本身也丢掉（否则只会无边增长）。
const Duration novelBackupTombstoneRetention = Duration(days: 90);

/// 丢掉过期墓碑（写入/合并前都过一遍）。
List<NovelBackupTombstone> pruneNovelTombstones(
  Iterable<NovelBackupTombstone> tombstones, {
  required DateTime now,
}) {
  final cutoff = now.subtract(novelBackupTombstoneRetention);
  return <NovelBackupTombstone>[
    for (final item in tombstones)
      if (item.deletedAt.isAfter(cutoff)) item,
  ];
}

/// 跨设备共享的设置键：这些项按"远端赢"合并（换台设备也想看到同样的排版）。
const Set<String> novelBackupSharedPrefKeys = <String>{
  novelPrefReaderSettings,
  novelPrefReaderFontSize,
  novelPrefReaderBookSettings,
};

/// 设备本地设置键：这些项按"本地赢"合并（各设备的窗口尺寸、布局、目标不必一致）。
const Set<String> novelBackupDevicePrefKeys = <String>{
  novelPrefGoalMinutes,
  novelPrefShelfLayout,
  novelPrefShelfColumns,
  novelPrefShelfSort,
  novelPrefShelfView,
  novelPrefShelfOrder,
  novelPrefHomeModules,
};

/// 永远不进备份的键（凭据、设备身份）。写快照时也要挡住，别指望只在读侧过滤。
const Set<String> novelBackupNeverExportedPrefKeys = <String>{
  'webdav_url',
  'webdav_user',
  'webdav_password',
  'webdav_encrypt',
  'webdav_auto_mode',
  'webdav_last_auto_at',
  'webdav_last_auto_result',
  'webdav_progress_auto',
  'webdav_device_name',
  'device_id',
};

/// 生成本地 → 远端的恢复计划。
///
/// [localDeviceId] 只用于给远端 v1 文档（没有设备维度）与新建行打上本机标记。
NovelBackupPlan planNovelRestore({
  required NovelBackupDocument local,
  required NovelBackupDocument remote,
  String localDeviceId = '',
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final ops = <NovelBackupOp>[];
  final conflicts = <NovelBackupConflict>[];
  var unchanged = 0;
  var skipped = 0;

  void insert(
    NovelBackupTarget target,
    String key,
    Map<String, Object?> payload, {
    String label = '',
  }) {
    ops.add(
      NovelBackupOp(
        target: target,
        action: NovelBackupAction.insert,
        key: key,
        payload: payload,
        label: label,
      ),
    );
  }

  void update(
    NovelBackupTarget target,
    String key,
    Map<String, Object?> payload, {
    String label = '',
  }) {
    ops.add(
      NovelBackupOp(
        target: target,
        action: NovelBackupAction.update,
        key: key,
        payload: payload,
        label: label,
      ),
    );
  }

  void remove(
    NovelBackupTarget target,
    String key,
    Map<String, Object?> payload,
  ) {
    ops.add(
      NovelBackupOp(
        target: target,
        action: NovelBackupAction.delete,
        key: key,
        payload: payload,
      ),
    );
  }

  final localTombstones = <String, NovelBackupTombstone>{
    for (final item in local.tombstones) item.id: item,
  };
  final remoteTombstones = <String, NovelBackupTombstone>{
    for (final item in remote.tombstones) item.id: item,
  };

  bool isTombstoned(
    Map<String, NovelBackupTombstone> tombstones,
    String kind,
    String key,
    DateTime stamp,
  ) {
    final tombstone = tombstones['$kind|$key'];
    if (tombstone == null) return false;
    return !stamp.isAfter(tombstone.deletedAt);
  }

  // ── 收藏 / 系列 ────────────────────────────────────────────────────────
  final localCollects = _indexCollects(local.collects);
  for (final item in remote.collects) {
    final key = item.key;
    final existing =
        localCollects.exact[key] ?? _fallbackCollect(localCollects, item);
    if (existing == null) {
      insert(
        NovelBackupTarget.collect,
        key,
        item.toJson(),
        label: item.book.title,
      );
      continue;
    }
    final merged = _mergeCollectFields(existing, item);
    if (merged.conflicts.isNotEmpty) {
      conflicts.add(
        NovelBackupConflict(
          target: NovelBackupTarget.collect,
          key: key,
          title: item.book.title,
          detail: merged.conflicts.join(' / '),
          localText: _describeCollect(existing),
          remoteText: _describeCollect(item),
          remoteOp: NovelBackupOp(
            target: NovelBackupTarget.collect,
            action: NovelBackupAction.update,
            key: key,
            payload: merged.remote.toJson(),
            label: item.book.title,
          ),
          localOp: merged.localChanged
              ? NovelBackupOp(
                  target: NovelBackupTarget.collect,
                  action: NovelBackupAction.update,
                  key: key,
                  payload: merged.local.toJson(),
                  label: item.book.title,
                )
              : null,
        ),
      );
      continue;
    }
    if (merged.localChanged) {
      update(
        NovelBackupTarget.collect,
        key,
        merged.local.toJson(),
        label: item.book.title,
      );
    } else {
      unchanged++;
    }
  }

  final localSeries = <String>{for (final item in local.series) item.name};
  for (final item in remote.series) {
    if (localSeries.add(item.name)) {
      insert(
        NovelBackupTarget.series,
        item.key,
        item.toJson(),
        label: item.name,
      );
    } else {
      unchanged++;
    }
  }

  // ── 阅读历史 / 进度 ────────────────────────────────────────────────────
  //
  // 历史行是进度的唯一权威；`progress` 段是它的投影（进度专用包含它）。
  final localHistory = <String, NovelBackupHistory>{
    for (final item in local.histories) item.book.id: item,
  };
  final localProgress = <String, NovelBackupProgress>{
    for (final item in local.progress) item.key: item,
  };
  final remoteProgress = _collectRemoteProgress(remote);
  for (final entry in remoteProgress.entries) {
    final bookId = entry.key;
    final incoming = entry.value;
    final localHistoryRow = localHistory[bookId];
    final localProgressRow = _findProgress(
      localProgress,
      bookId,
      incoming.sourceKey,
    );
    final localChapter = math.max(
      localHistoryRow?.chapterIndex ?? 0,
      localProgressRow?.chapterIndex ?? 0,
    );
    final localLocator = localProgressRow?.locator;
    final localStamp = _newest([
      localHistoryRow?.openedAt,
      localProgressRow?.updatedAt,
    ]);

    final remoteChapter = incoming.chapterIndex;
    final remoteStamp = incoming.updatedAt;
    final knownLocally =
        localHistoryRow != null ||
        localProgressRow != null ||
        local.collects.any((collect) => collect.book.id == bookId);
    if (!knownLocally) {
      // 本地没有这本书：只同步进度不造幽灵条目（与上游 downloadAllBookProgress 一致）。
      skipped++;
      continue;
    }
    if (remoteChapter > localChapter) {
      update(
        NovelBackupTarget.progress,
        bookId,
        _progressPayload(
          incoming,
          book: localHistoryRow?.book,
          readCount: localHistoryRow?.readCount ?? 1,
          chapterCount: math.max(
            incoming.chapterCount,
            localHistoryRow?.chapterCount ?? 0,
          ),
        ),
        label: '${localHistoryRow?.book.title ?? bookId} · 第 $remoteChapter 章',
      );
      continue;
    }
    if (remoteChapter == localChapter &&
        remoteChapter > 0 &&
        _isAfter(remoteStamp, localStamp)) {
      update(
        NovelBackupTarget.progress,
        bookId,
        _progressPayload(
          incoming,
          book: localHistoryRow?.book,
          readCount: localHistoryRow?.readCount ?? 1,
          chapterCount: math.max(
            incoming.chapterCount,
            localHistoryRow?.chapterCount ?? 0,
          ),
          keepLocator: incoming.locator ?? localLocator,
        ),
        label: '${localHistoryRow?.book.title ?? bookId} · 第 $remoteChapter 章',
      );
      continue;
    }
    // 本地完全没有这本书的进度（连章号都没有）→ 新建一条。
    // 注意判据必须是「本地章号为 0」而不是「本地没有历史行」：进度专用包里
    // histories 段是空的，只看历史行会把本地 30 章误判成"没读过"，反而被远端
    // 的旧章号覆盖——那是"同步不覆盖本地更新的记录"最不能破的一条。
    if (localChapter <= 0 && remoteChapter > 0) {
      insert(
        NovelBackupTarget.progress,
        bookId,
        _progressPayload(incoming),
        label: '${incoming.bookId} · 第 $remoteChapter 章',
      );
      continue;
    }
    unchanged++;
  }

  // ── 书签 / 划线 ────────────────────────────────────────────────────────
  final localBookmarks = <String, NovelBackupBookmark>{
    for (final item in local.bookmarks) item.key: item,
  };
  for (final item in remote.bookmarks) {
    final key = item.key;
    if (isTombstoned(
      localTombstones,
      novelTombstoneBookmark,
      key,
      item.createdAt,
    )) {
      skipped++;
      continue;
    }
    final existing = localBookmarks[key];
    if (existing == null) {
      insert(
        NovelBackupTarget.bookmark,
        key,
        item.toJson(),
        label: item.chapterName.isEmpty ? item.bookTitle : item.chapterName,
      );
      continue;
    }
    if (existing.excerpt != item.excerpt) {
      conflicts.add(
        NovelBackupConflict(
          target: NovelBackupTarget.bookmark,
          key: key,
          title: existing.bookTitle.isEmpty
              ? existing.bookId
              : existing.bookTitle,
          detail: '同位置书签的摘录不同',
          localText: _ellipsis(existing.excerpt),
          remoteText: _ellipsis(item.excerpt),
          remoteOp: NovelBackupOp(
            target: NovelBackupTarget.bookmark,
            action: NovelBackupAction.update,
            key: key,
            payload: item.toJson(),
          ),
        ),
      );
      continue;
    }
    unchanged++;
  }

  final localMarkings = <String, NovelBackupMarking>{
    for (final item in local.markings) item.key: item,
  };
  for (final item in remote.markings) {
    final key = item.key;
    if (isTombstoned(
      localTombstones,
      novelTombstoneMarking,
      key,
      item.updatedAt,
    )) {
      skipped++;
      continue;
    }
    final existing = localMarkings[key];
    if (existing == null) {
      insert(
        NovelBackupTarget.marking,
        key,
        item.toJson(),
        label: item.chapterName.isEmpty ? item.bookTitle : item.chapterName,
      );
      continue;
    }
    if (existing.contentSignature != item.contentSignature) {
      conflicts.add(
        NovelBackupConflict(
          target: NovelBackupTarget.marking,
          key: key,
          title: existing.bookTitle.isEmpty
              ? existing.bookId
              : existing.bookTitle,
          detail: existing.note != item.note ? '同一处划线的笔记不同' : '同一处划线的样式不同',
          localText: _describeMarking(existing),
          remoteText: _describeMarking(item),
          remoteOp: NovelBackupOp(
            target: NovelBackupTarget.marking,
            action: NovelBackupAction.update,
            key: key,
            payload: item.toJson(),
          ),
        ),
      );
      continue;
    }
    unchanged++;
  }

  // 远端墓碑压过本地较旧的行：删本地副本，否则对侧的删除永远传播不过来。
  for (final tombstone in remoteTombstones.values) {
    if (localTombstones[tombstone.id] != null) {
      unchanged++;
      continue;
    }
    if (tombstone.kind == novelTombstoneBookmark) {
      final row = localBookmarks[tombstone.key];
      if (row == null || row.createdAt.isAfter(tombstone.deletedAt)) {
        skipped++;
        continue;
      }
      remove(NovelBackupTarget.tombstone, tombstone.id, <String, Object?>{
        'kind': tombstone.kind,
        'key': tombstone.key,
        'localKey': row.key,
      });
      continue;
    }
    final row = localMarkings[tombstone.key];
    if (row == null || row.updatedAt.isAfter(tombstone.deletedAt)) {
      skipped++;
      continue;
    }
    remove(NovelBackupTarget.tombstone, tombstone.id, <String, Object?>{
      'kind': tombstone.kind,
      'key': tombstone.key,
      'localKey': row.key,
    });
  }
  for (final tombstone in pruneNovelTombstones(
    remoteTombstones.values,
    now: at,
  )) {
    if (localTombstones.containsKey(tombstone.id)) continue;
    insert(
      NovelBackupTarget.tombstone,
      tombstone.id,
      tombstone.toJson(),
      label: tombstone.kind,
    );
  }

  // ── 阅读时长 ───────────────────────────────────────────────────────────
  final localRecords = <String, NovelBackupReadRecord>{
    for (final item in local.readRecords) item.key: item,
  };
  for (final item in remote.readRecords) {
    final existing = localRecords[item.key];
    if (existing == null) {
      insert(
        NovelBackupTarget.readRecord,
        item.key,
        item.toJson(),
        label: item.day,
      );
      continue;
    }
    final seconds = math.max(existing.seconds, item.seconds);
    final firstReadAt = existing.firstReadAt.isBefore(item.firstReadAt)
        ? existing.firstReadAt
        : item.firstReadAt;
    final lastReadAt = existing.lastReadAt.isAfter(item.lastReadAt)
        ? existing.lastReadAt
        : item.lastReadAt;
    if (seconds == existing.seconds &&
        firstReadAt == existing.firstReadAt &&
        lastReadAt == existing.lastReadAt) {
      unchanged++;
      continue;
    }
    update(
      NovelBackupTarget.readRecord,
      item.key,
      item
          .copyWith(
            seconds: seconds,
            firstReadAt: firstReadAt,
            lastReadAt: lastReadAt,
          )
          .toJson(),
      label: item.day,
    );
  }

  // ── 书源 ───────────────────────────────────────────────────────────────
  final localSources = <String, NovelBackupSourceEntry>{};
  for (final source in local.sources) {
    localSources[source.key] = NovelBackupSourceEntry(source);
  }
  for (final source in remote.sources) {
    final existing = localSources[source.key];
    if (existing == null) {
      insert(
        NovelBackupTarget.source,
        source.key,
        source.toJson(),
        label: source.name,
      );
      continue;
    }
    if (existing.signature != NovelBackupSourceEntry(source).signature) {
      // 同一 key 内容不同：本地可能是用户改过的，默认保本地，让用户选。
      conflicts.add(
        NovelBackupConflict(
          target: NovelBackupTarget.source,
          key: source.key,
          title: source.name,
          detail: '同 key 书源内容不同',
          localText: '本地版本',
          remoteText: '远端版本',
          remoteOp: NovelBackupOp(
            target: NovelBackupTarget.source,
            action: NovelBackupAction.update,
            key: source.key,
            payload: source.toJson(),
            label: source.name,
          ),
        ),
      );
      continue;
    }
    unchanged++;
  }

  // ── 搜索历史 ───────────────────────────────────────────────────────────
  final localKeywords = <String>{...local.searchKeywords};
  for (final keyword in remote.searchKeywords) {
    if (localKeywords.add(keyword)) {
      insert(NovelBackupTarget.searchKeyword, keyword, <String, Object?>{
        'keyword': keyword,
      }, label: keyword);
    } else {
      unchanged++;
    }
  }

  // ── 设置 ───────────────────────────────────────────────────────────────
  for (final entry in remote.prefs.entries) {
    if (novelBackupNeverExportedPrefKeys.contains(entry.key)) continue;
    final localValue = local.prefs[entry.key];
    if (localValue == entry.value) {
      unchanged++;
      continue;
    }
    final shared = novelBackupSharedPrefKeys.contains(entry.key);
    final deviceLocal = novelBackupDevicePrefKeys.contains(entry.key);
    if (deviceLocal && localValue != null) {
      // 设备本地项：本地已有值就保本地（换台设备不该改我的窗口布局）。
      unchanged++;
      continue;
    }
    if (!shared && !deviceLocal && localValue != null) {
      // 未知键：保守，本地已有值就保本地。
      unchanged++;
      continue;
    }
    final perBookSettings = entry.key == novelPrefReaderBookSettings;
    final value = perBookSettings
        ? _mergeReaderBookSettings(localValue, entry.value)
        : entry.value;
    if (value == (localValue ?? '')) {
      unchanged++;
      continue;
    }
    update(NovelBackupTarget.pref, entry.key, <String, Object?>{
      'key': entry.key,
      'value': value,
    }, label: entry.key);
  }

  return NovelBackupPlan(
    ops: List<NovelBackupOp>.unmodifiable(ops),
    conflicts: List<NovelBackupConflict>.unmodifiable(conflicts),
    unchanged: unchanged,
    skipped: skipped,
  );
}

/// 合并后的收藏：`local` 是要落库的版本，`remote` 是"全选远端"的版本。
class _CollectMerge {
  const _CollectMerge({
    required this.local,
    required this.remote,
    required this.conflicts,
    required this.localChanged,
  });

  final NovelBackupCollect local;
  final NovelBackupCollect remote;
  final List<String> conflicts;

  /// 本地这一侧是否需要写回（远端补了空字段）。
  final bool localChanged;
}

_CollectMerge _mergeCollectFields(
  NovelBackupCollect local,
  NovelBackupCollect remote,
) {
  final conflicts = <String>[];
  var changed = false;
  String? group = local.groupName;
  String? series = local.seriesName;
  var note = local.note;

  void mergeField({
    required String label,
    required String? localValue,
    required String? remoteValue,
    required void Function(String? value) assign,
  }) {
    final l = (localValue ?? '').trim();
    final r = (remoteValue ?? '').trim();
    if (r.isEmpty) return;
    if (l.isEmpty) {
      assign(remoteValue);
      changed = true;
      return;
    }
    if (l != r) conflicts.add('$label不同');
  }

  mergeField(
    label: '分组',
    localValue: local.groupName,
    remoteValue: remote.groupName,
    assign: (value) => group = value,
  );
  mergeField(
    label: '系列',
    localValue: local.seriesName,
    remoteValue: remote.seriesName,
    assign: (value) => series = value,
  );
  mergeField(
    label: '备注',
    localValue: local.note,
    remoteValue: remote.note,
    assign: (value) => note = value ?? '',
  );

  final mergedLocal = NovelBackupCollect(
    book: local.book,
    groupName: group,
    note: note,
    seriesName: series,
    chapterIndex: local.chapterIndex,
    chapterCount: local.chapterCount,
    updatedAt: local.updatedAt,
  );
  final mergedRemote = NovelBackupCollect(
    book: remote.book,
    groupName: remote.groupName,
    note: remote.note,
    seriesName: remote.seriesName,
    chapterIndex: remote.chapterIndex,
    chapterCount: remote.chapterCount,
    updatedAt: remote.updatedAt,
  );
  return _CollectMerge(
    local: mergedLocal,
    remote: mergedRemote,
    conflicts: conflicts,
    localChanged: changed,
  );
}

class _CollectIndex {
  const _CollectIndex(this.exact);

  final Map<String, NovelBackupCollect> exact;
}

_CollectIndex _indexCollects(Iterable<NovelBackupCollect> collects) =>
    _CollectIndex(<String, NovelBackupCollect>{
      for (final item in collects) item.key: item,
    });

/// 老数据只知道 bookId：sourceKey 为空时按 bookId 兜底匹配，避免重复入架。
NovelBackupCollect? _fallbackCollect(
  _CollectIndex index,
  NovelBackupCollect item,
) {
  if (item.book.sourceKey.isEmpty) {
    for (final entry in index.exact.values) {
      if (entry.book.id == item.book.id) return entry;
    }
    return null;
  }
  final legacy = index.exact[item.book.id];
  return legacy;
}

NovelBackupProgress? _findProgress(
  Map<String, NovelBackupProgress> index,
  String bookId,
  String sourceKey,
) {
  final exact = index[novelBackupBookKey(bookId, sourceKey)];
  if (exact != null) return exact;
  if (sourceKey.isNotEmpty) {
    // 本机只有 bookId 键（老数据）：仍然认作同一本。
    final legacy = index[bookId];
    if (legacy != null && legacy.sourceKey.isEmpty) return legacy;
  }
  for (final entry in index.values) {
    if (entry.bookId == bookId) return entry;
  }
  return null;
}

/// 把远端三种载体（progress / histories / collects）统一成「每本一行进度」。
Map<String, NovelBackupProgress> _collectRemoteProgress(
  NovelBackupDocument remote,
) {
  final result = <String, NovelBackupProgress>{};
  void put(NovelBackupProgress incoming) {
    final existing = result[incoming.bookId];
    if (existing == null ||
        incoming.chapterIndex > existing.chapterIndex ||
        (incoming.chapterIndex == existing.chapterIndex &&
            _isAfter(incoming.updatedAt, existing.updatedAt))) {
      result[incoming.bookId] = incoming;
    } else if (incoming.locator != null && existing.locator == null) {
      result[incoming.bookId] = existing.copyWith(locator: incoming.locator);
    }
  }

  for (final item in remote.progress) {
    put(item);
  }
  for (final item in remote.histories) {
    put(
      NovelBackupProgress(
        bookId: item.book.id,
        sourceKey: item.book.sourceKey,
        chapterIndex: item.chapterIndex,
        chapterCount: item.chapterCount,
        readCount: item.readCount,
        updatedAt: item.openedAt,
      ),
    );
  }
  for (final item in remote.collects) {
    if (item.chapterIndex <= 0) continue;
    put(
      NovelBackupProgress(
        bookId: item.book.id,
        sourceKey: item.book.sourceKey,
        chapterIndex: item.chapterIndex,
        chapterCount: item.chapterCount,
        updatedAt: item.updatedAt,
      ),
    );
  }
  return result;
}

Map<String, Object?> _progressPayload(
  NovelBackupProgress incoming, {
  NovelSummary? book,
  int readCount = 1,
  int? chapterCount,
  NovelLocator? keepLocator,
}) {
  final payload = <String, Object?>{
    'bookId': incoming.bookId,
    'chapterIndex': incoming.chapterIndex,
    'chapterCount': chapterCount ?? incoming.chapterCount,
    'readCount': math.max(readCount, incoming.readCount),
  };
  if (book != null) payload['book'] = book.toJson();
  final locator = keepLocator ?? incoming.locator;
  if (locator != null) payload['locator'] = locator.toJson();
  if (incoming.sourceKey.isNotEmpty) payload['sourceKey'] = incoming.sourceKey;
  if (incoming.updatedAt != null) {
    payload['updatedAt'] = incoming.updatedAt!.toIso8601String();
  }
  return payload;
}

/// `novel_pref.reader_book_settings` 是「每书覆盖」的一整张表，按 bookId 并集，
/// 冲突时本地优先（各设备的覆盖都是用户自己在一台机器上做的调整）。
String _mergeReaderBookSettings(String? localRaw, String? remoteRaw) {
  final localMap = _decodeMap(localRaw);
  final remoteMap = _decodeMap(remoteRaw);
  if (remoteMap.isEmpty) return localRaw ?? '';
  if (localMap.isEmpty) return remoteRaw ?? '';
  final merged = <String, Object?>{...remoteMap, ...localMap};
  return _encodeMap(merged);
}

Map<String, Object?> _decodeMap(String? raw) {
  if (raw == null || raw.trim().isEmpty) return <String, Object?>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, Object?>.from(decoded);
  } on Object {
    // 坏数据当空。
  }
  return <String, Object?>{};
}

String _encodeMap(Map<String, Object?> value) => jsonEncode(value);

bool _isAfter(DateTime? left, DateTime? right) {
  if (left == null) return false;
  if (right == null) return true;
  return left.isAfter(right);
}

DateTime? _newest(List<DateTime?> values) {
  DateTime? result;
  for (final value in values) {
    if (value == null) continue;
    if (result == null || value.isAfter(result)) result = value;
  }
  return result;
}

String _describeCollect(NovelBackupCollect item) {
  final parts = <String>[
    if ((item.groupName ?? '').isNotEmpty) '分组：${item.groupName}',
    if ((item.seriesName ?? '').isNotEmpty) '系列：${item.seriesName}',
    if (item.note.isNotEmpty) '备注：${_ellipsis(item.note)}',
  ];
  return parts.isEmpty ? '（无分组/系列/备注）' : parts.join(' · ');
}

String _describeMarking(NovelBackupMarking item) {
  final parts = <String>[
    if (item.note.isNotEmpty) '笔记：${_ellipsis(item.note)}',
    '样式：${_describeMarkingStyle(item.styleJson)}',
  ];
  return parts.join(' · ');
}

String _describeMarkingStyle(String styleJson) {
  try {
    final decoded = jsonDecode(styleJson);
    if (decoded is Map) {
      final decoration = '${decoded['decoration'] ?? 'background'}';
      final color = decoded['color'];
      if (color is num) {
        final hex = color
            .toInt()
            .toRadixString(16)
            .padLeft(8, '0')
            .toUpperCase();
        return '$decoration #$hex';
      }
      return decoration;
    }
  } on Object {
    // 坏样式按原样描述。
  }
  return '默认';
}

/// 书源内容签名：同 key 不同内容才算冲突。
class NovelBackupSourceEntry {
  NovelBackupSourceEntry(this.source);

  final NovelBookSource source;

  String get key => source.key;

  String get signature => jsonEncode(source.toJson());
}

/// 上传前的合并：把远端文档并进本地快照，得到"推上去的超集"。
///
/// 与恢复同一套字段规则（并集 + 进度取章号大者/同章取时间新者 + 阅读时长取 max
/// + 墓碑压过较旧的行），**冲突一律本地赢**——上传方是正在操作的这一端。
/// 这里刻意按"并集"实现而不是复用恢复计划：恢复会跳过"本地没有这本书"的进度
/// （不造幽灵条目），但上传不能跳过，否则另一台设备的独有历史会被这次 PUT 抹掉。
NovelBackupDocument mergeNovelBackupDocuments({
  required NovelBackupDocument local,
  required NovelBackupDocument remote,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();

  // 收藏：远端打底、本地覆盖；本地独有的保留。
  final collects = <String, NovelBackupCollect>{
    for (final item in remote.collects) item.key: item,
    for (final item in local.collects) item.key: item,
  };

  // 历史：按 bookId 并，章号/次数取 max，时间取新。
  final histories = <String, NovelBackupHistory>{
    for (final item in remote.histories) item.book.id: item,
  };
  for (final item in local.histories) {
    final other = histories[item.book.id];
    histories[item.book.id] = other == null
        ? item
        : NovelBackupHistory(
            book: item.book.title.isNotEmpty ? item.book : other.book,
            chapterIndex: math.max(item.chapterIndex, other.chapterIndex),
            chapterCount: math.max(item.chapterCount, other.chapterCount),
            readCount: math.max(item.readCount, other.readCount),
            openedAt: _isAfter(item.openedAt, other.openedAt)
                ? item.openedAt
                : other.openedAt,
          );
  }

  // 进度：章号大者胜、同章取时间新者。
  final progress = <String, NovelBackupProgress>{};
  for (final item in <NovelBackupProgress>[
    ...remote.progress,
    ...local.progress,
  ]) {
    final existing = progress[item.bookId];
    if (existing == null) {
      progress[item.bookId] = item;
      continue;
    }
    final takeIncoming =
        item.chapterIndex > existing.chapterIndex ||
        (item.chapterIndex == existing.chapterIndex &&
            _isAfter(item.updatedAt, existing.updatedAt));
    progress[item.bookId] = takeIncoming
        ? item.copyWith(
            chapterCount: math.max(item.chapterCount, existing.chapterCount),
            readCount: math.max(item.readCount, existing.readCount),
          )
        : existing.copyWith(
            chapterCount: math.max(item.chapterCount, existing.chapterCount),
            readCount: math.max(item.readCount, existing.readCount),
            locator: existing.locator ?? item.locator,
          );
  }

  final series = <String, NovelBackupSeries>{
    for (final item in remote.series) item.name: item,
    for (final item in local.series) item.name: item,
  };

  final bookmarks = <String, NovelBackupBookmark>{
    for (final item in remote.bookmarks) item.key: item,
    for (final item in local.bookmarks) item.key: item,
  };
  final markings = <String, NovelBackupMarking>{
    for (final item in remote.markings) item.key: item,
    for (final item in local.markings) item.key: item,
  };

  // 墓碑：同键取最新一次删除。
  final tombstones = <String, NovelBackupTombstone>{
    for (final item in remote.tombstones) item.id: item,
  };
  for (final item in local.tombstones) {
    final other = tombstones[item.id];
    if (other == null || item.deletedAt.isAfter(other.deletedAt)) {
      tombstones[item.id] = item;
    }
  }
  // 被删过的行不进超集，否则下一次恢复又把它复活。
  for (final tombstone in tombstones.values) {
    if (tombstone.kind == novelTombstoneBookmark) {
      final row = bookmarks[tombstone.key];
      if (row != null && !row.createdAt.isAfter(tombstone.deletedAt)) {
        bookmarks.remove(tombstone.key);
      }
    } else {
      final row = markings[tombstone.key];
      if (row != null && !row.updatedAt.isAfter(tombstone.deletedAt)) {
        markings.remove(tombstone.key);
      }
    }
  }

  final records = <String, NovelBackupReadRecord>{
    for (final item in remote.readRecords) item.key: item,
  };
  for (final item in local.readRecords) {
    final other = records[item.key];
    records[item.key] = other == null
        ? item
        : item.copyWith(
            seconds: math.max(item.seconds, other.seconds),
            bookTitle: item.bookTitle.isEmpty
                ? other.bookTitle
                : item.bookTitle,
            chapterName: item.chapterName.isEmpty
                ? other.chapterName
                : item.chapterName,
            firstReadAt: item.firstReadAt.isBefore(other.firstReadAt)
                ? item.firstReadAt
                : other.firstReadAt,
            lastReadAt: item.lastReadAt.isAfter(other.lastReadAt)
                ? item.lastReadAt
                : other.lastReadAt,
          );
  }

  final sources = <String, NovelBookSource>{
    for (final item in remote.sources) item.key: item,
    for (final item in local.sources) item.key: item,
  };
  final keywords = <String>{...remote.searchKeywords, ...local.searchKeywords};

  final prefs = <String, String>{
    for (final entry in remote.prefs.entries)
      if (!novelBackupNeverExportedPrefKeys.contains(entry.key))
        entry.key: entry.value,
    for (final entry in local.prefs.entries)
      if (!novelBackupNeverExportedPrefKeys.contains(entry.key))
        entry.key: entry.value,
  };

  return NovelBackupDocument(
    collects: collects.values.toList(growable: false),
    histories: histories.values.toList(growable: false),
    searchKeywords: keywords.toList(growable: false),
    sources: sources.values.toList(growable: false),
    prefs: prefs,
    exportedAt: local.exportedAt,
    deviceId: local.deviceId,
    deviceName: local.deviceName,
    progress: progress.values.toList(growable: false),
    series: series.values.toList(growable: false),
    bookmarks: bookmarks.values.toList(growable: false),
    markings: markings.values.toList(growable: false),
    readRecords: records.values.toList(growable: false),
    tombstones: pruneNovelTombstones(tombstones.values, now: at),
  );
}

String _ellipsis(String value, {int max = 24}) {
  final text = value.replaceAll('\n', ' ').trim();
  return text.length <= max ? text : '${text.substring(0, max)}…';
}
