import 'package:drift/drift.dart';

/// セッションの種別（仕様書 8）。
enum SessionMode {
  /// 通常のゲーム。BGM とコンボがある。
  game,

  /// 週1回のコンディション測定（仕様書 7）。BGM もコンボもなし。
  ///
  /// TODO(未決): 閾値推定の方法と試行数が未決のため未実装（仕様書 0-B）。
  /// 決まるまでこのモードのセッションを作らない。
  measure,
}

/// 後続マスクの種別（仕様書 4 / 5.2「時間分解能」）。
enum MaskType {
  /// マスクなし。Phase 1 はこれだけ。
  none,

  /// 後続マスク。時間分解能の軸で使う。Phase 3 で解放する。
  backward,
}

/// 難易度の6軸（仕様書 5.2）。
enum DifficultyAxis {
  /// コントラスト感度。C を小さく。
  contrastSensitivity,

  /// 処理速度。提示フレーム数を少なく。
  processingSpeed,

  /// 解像力。λ を高周波へ。
  resolution,

  /// 側抑制耐性。フランカー距離 4λ → 1.5λ。
  lateralInhibition,

  /// 時間分解能。後続マスクの ISI 150ms → 60ms。
  temporalResolution,

  /// 持続力。試行数 / BPM を多く・速く。
  endurance,
}

/// セッション（仕様書 8）。
@DataClassName('SessionRow')
class Sessions extends Table {
  TextColumn get id => text()();
  DateTimeColumn get startedAt => dateTime()();
  TextColumn get mode => textEnum<SessionMode>()();

  /// BGM のトラックID。メトロノームで進めている間は null（仕様書 2.1）。
  TextColumn get trackId => text().nullable()();

  /// 刺激列を再現するためのシード。
  ///
  /// デイリーチャレンジではサーバーが配布する（仕様書 6）。Phase 1 はローカル生成。
  IntColumn get seed => integer()();

  IntColumn get nTrials => integer().withDefault(const Constant(0))();
  IntColumn get score => integer().withDefault(const Constant(0))();

  /// このセッションの閾値。
  ///
  /// TODO(未決): 推定方法と試行数が未決のため、常に null のまま（仕様書 0-B）。
  /// カラムだけ先に用意して、決まったら埋める。
  RealColumn get thresholdContrast => real().nullable()();

  /// プレイ中に固定した画面輝度（0.0〜1.0、仕様書 3.4）。
  ///
  /// 自動調光が効いていると実効コントラストが毎回変わり、測定値が無意味になる。
  /// 固定できなかった端末では null になり、その場合このセッションの
  /// コントラスト測定値は比較に使えない。
  RealColumn get deviceBrightness => real().nullable()();

  // --- ここから下は仕様書 8 の一覧にないが、後から解析し直すために必要な列 ---
  //
  // 未決事項A（刺激の物理サイズ）が確定すると、論理px と視角の対応が変わる。
  // そのとき、当時どの前提で提示したかが残っていないと、
  // 過去ログを新しい基準で読み直せなくなる（仕様書 8「全件残す」の趣旨）。

  /// 提示時に使った 1インチあたりの論理px 数。
  RealColumn get logicalPixelsPerInch => real()();

  /// 提示時に仮定した視距離（cm）。暫定方針では 40。
  RealColumn get viewingDistanceCm => real()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// 試行ログ（仕様書 8）。
///
/// **全件残す。** 集計値だけ保存すると、後から解析方法を変えられなくなる。
@DataClassName('TrialRow')
class Trials extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get ts => dateTime()();

  /// 提示したコントラスト（ステアケースの内部難易度）。
  RealColumn get contrast => real()();

  /// 提示した λ（論理px）。
  RealColumn get lambdaPx => real()();

  /// 提示した λ（視角の分）。
  ///
  /// 仕様書 8 の一覧にないが、λ の一次表現は視角なので（仕様書 0-A）、
  /// これを残さないと端末をまたいだ比較ができない。
  RealColumn get lambdaArcmin => real()();

  /// 提示した向き（度）。0 / 45 / 90 / 135。
  IntColumn get orientationDeg => integer()();

  /// 要求した提示フレーム数。提示時間の内部表現（仕様書 3.3）。
  IntColumn get framesRequested => integer()();

  /// **実測**の提示時間（ms）。
  ///
  /// フレーム数 × 公称フレーム時間ではない。
  /// 仕様書 3.3「推定値ではなく実測を残すこと」。
  RealColumn get msActual => real()();

  /// 実測のリフレッシュレート。
  RealColumn get refreshHz => real()();

  /// 後続マスクの種別。Phase 1 は常に none。
  TextColumn get maskType => textEnum<MaskType>()();

  /// フランカー距離（λ の倍数）。側抑制耐性の軸。Phase 1 では null。
  RealColumn get flankerDistanceLambda => real().nullable()();

  /// マスクまでの ISI（ms）。時間分解能の軸。Phase 1 では null。
  RealColumn get isiMs => real().nullable()();

  /// 回答の軸角度（度、[0, 180)）。4択に丸める前の連続値。
  ///
  /// 無回答なら null。
  RealColumn get responseDeg => real().nullable()();

  /// 正誤。無回答は不正解として扱う（仕様書 4.2 の受付ウィンドウを過ぎたもの）。
  BoolColumn get correct => boolean()();

  /// 反応時間（ms）。刺激の提示開始から回答確定まで。無回答なら null。
  IntColumn get rtMs => integer().nullable()();
}

/// 6軸プロフィール（仕様書 5.2 / 8）。
///
/// TODO(未決): 値の出どころである週次測定が未決事項B に依存するため、
/// Phase 1 では書き込まない。レーダーチャートは Phase 2（仕様書 11-12）。
@DataClassName('ProfileAxisRow')
class ProfileAxes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get axisName => textEnum<DifficultyAxis>()();
  RealColumn get value => real()();
  DateTimeColumn get measuredAt => dateTime()();
}
