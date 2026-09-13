import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'database.g.dart';

/// ローカルの試行ログ（仕様書 8）。
///
/// KVS ではなく SQLite にするのは、試行ログを**全件**保持するため。
/// 集計値だけ保存すると、後から解析方法を変えられなくなる。
@DriftDatabase(tables: <Type>[Sessions, Trials, ProfileAxes])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'visual_training'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (OpeningDetails details) async {
      // SQLite は既定で外部キー制約を無効にする。有効にしないと、
      // セッションを消しても試行ログが孤児として残り続ける。
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// セッションを開始し、その id を返す。
  Future<void> startSession(SessionsCompanion session) =>
      into(sessions).insert(session);

  /// 1試行ぶんのログを追加する。
  Future<int> logTrial(TrialsCompanion trial) => into(trials).insert(trial);

  /// セッション終了時の集計を書き戻す。
  ///
  /// [thresholdContrast] は未決事項B が決まるまで常に null（仕様書 0-B）。
  Future<void> finishSession({
    required String sessionId,
    required int nTrials,
    required int score,
  }) =>
      (update(sessions)..where(($SessionsTable t) => t.id.equals(sessionId)))
          .write(
            SessionsCompanion(
              nTrials: Value<int>(nTrials),
              score: Value<int>(score),
            ),
          );

  Future<List<TrialRow>> trialsOf(String sessionId) =>
      (select(trials)
            ..where(($TrialsTable t) => t.sessionId.equals(sessionId))
            ..orderBy(<OrderClauseGenerator<$TrialsTable>>[
              ($TrialsTable t) => OrderingTerm.asc(t.id),
            ]))
          .get();

  Future<List<SessionRow>> recentSessions({int limit = 30}) =>
      (select(sessions)
            ..orderBy(<OrderClauseGenerator<$SessionsTable>>[
              ($SessionsTable t) => OrderingTerm.desc(t.startedAt),
            ])
            ..limit(limit))
          .get();

  /// 試行の総数。経験値レベルの計算に使う（仕様書 5.1「累計試行数」）。
  Future<int> totalTrialCount() async {
    final Expression<int> count = trials.id.count();
    final TypedResult row =
        await (selectOnly(trials)
              ..addColumns(<Expression<Object>>[count]))
            .getSingle();
    return row.read(count) ?? 0;
  }
}
