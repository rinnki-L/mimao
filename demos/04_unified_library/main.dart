// ═══════════════════════════════════════════════════════════════
// Demo 04 — 统一收藏/历史库：四种媒体一张表（drift 风格预览）
//
// 回答"统一时间线的数据怎么存"：
//   四种媒体共同的东西（标题/来源/时间）→ 关系列
//   各类型自己的进度结构               → payload JSON 列
//
// 刻意不做完全归一化：起步阶段统一到"能查我的时间线"就够了。
// 等真的需要"按漫画页码筛选"这种需求时，再把 payload 拆成真列——
// 这正是我们说过的原则：先能跑，后抽象。
//
// 为什么不用 Kazumi 的 hive_ce？KV 库做不了"跨类型 + 排序 + 分页"
// 的组合查询；统一库天生是关系查询场景 → SQLite（Venera 同款选择）。
// 模块内部自己的缓存/记录（如 Kazumi 的观看历史）先保持原样，不迁移。
//
// 跑起来需要：drift + drift_flutter + build_runner（drift_dev）。
// 本文件是「读」的 demo：看表怎么设计、查询长什么样。
// ═══════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';

enum MediaType { anime, comic, novel, music }

// ─────────────────────────────────────────────
// 表定义：drift 的写法是"用 Dart 写 SQL 表"，build_runner 生成 DB 类
// ─────────────────────────────────────────────
class MediaEntries extends Table {
  /// 源内唯一键，如 "kazumi:1001" / "venera:sourceA:12345" / "legado:书源id:书id"
  TextColumn get id => text()();

  TextColumn get mediaType => textEnum<MediaType>();

  /// 来自哪个源/规则包 —— 同一作品可以从多个源打开，靠它区分
  TextColumn get sourceName => text()();

  TextColumn get title => text()();

  TextColumn get coverUrl => text().nullable()();

  /// JSON：该类型自己的进度结构，见文末约定
  TextColumn get payload => text()();

  DateTimeColumn get lastOpenedAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  /// 复合主键：同一作品在不同源里是两条记录，时间线里可以都出现
  @override
  Set<Column> get primaryKey => {id, mediaType, sourceName};
}

// ─────────────────────────────────────────────
// payload 约定（各模块自己解释自己，壳不关心内部结构）：
//   anime: {"episode": 12, "positionSec": 843}
//   comic: {"chapter": 45, "page": 3}
//   novel: {"chapter": 102, "progressPct": 32}
//   music: {"playlist": "深夜驾驶", "trackIndex": 7, "positionSec": 95}
// ─────────────────────────────────────────────

// ─────────────────────────────────────────────
// 统一查询长什么样（上面的表经过 build_runner 生成 AppDb 后即可用）：
//
// final db = AppDb();
//
// // ① 我的时间线：最近打开的 50 条，不分类型 —— Demo 01 "我的"页的数据源
// final timeline = await (db.select(db.mediaEntries)
//       ..orderBy([(t) => OrderingTerm.desc(t.lastOpenedAt)])
//       ..limit(50))
//     .get();
//
// // ② 只看在追的番剧
// final anime = await (db.select(db.mediaEntries)
//       ..where((t) => t.mediaType.equals(MediaType.anime.name)))
//     .get();
//
// // ③ 全局搜索框：跨类型模糊搜标题（壳上的一个入口，查所有模块）
// final hits = await (db.select(db.mediaEntries)
//       ..where((t) => t.title.like('%芙莉莲%')))
//     .get();
//
// // ④ 收藏：payload 里放个 "starred": true，或者加一列 boolColumn ——
// //    先用 payload，需要排序筛选时再升格成真列，就是这个设计的伸缩方向
// ─────────────────────────────────────────────
void main() {
  // 这个 demo 没有可运行主体——它是一张"设计图纸"。
  // 表设计评审通过后，它会变成 lib/core/database/ 下的真代码。
  print('Demo 04 是阅读用设计稿，见文件头注释。');
}
