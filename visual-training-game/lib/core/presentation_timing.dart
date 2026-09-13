import 'package:flutter/foundation.dart';

import 'refresh_rate.dart';

/// 提示時間の管理（仕様書 3.3）。
///
/// **提示時間をミリ秒で指定してはいけない。内部表現は必ずフレーム数にする。**
///
/// - 60Hz 端末: 1フレーム = 16.7ms → 最短提示は2フレーム（約33ms）
/// - 120Hz 端末: 同じ「2フレーム」でも 16.7ms になってしまう
///
/// そのため、端末のリフレッシュレートから**目標msに最も近いフレーム数**へ変換する。
@immutable
class PresentationPlan {
  const PresentationPlan({
    required this.targetMs,
    required this.frames,
    required this.refreshRate,
    required this.clampedToFloor,
  });

  /// 難易度が指示した目標提示時間（ms）。
  final double targetMs;

  /// 実際に描くフレーム数。これが提示時間の内部表現。
  final int frames;

  final RefreshRate refreshRate;

  /// 目標が端末の最短提示を下回ったため、フレーム数の下限に丸めたか。
  ///
  /// true のとき、その端末では「処理速度」軸をこれ以上難化させられない。
  /// 仕様書 5.4 の「物理的限界を超えて難化させないこと」の判定に使う。
  final bool clampedToFloor;

  /// フレーム数から計算した公称の提示時間（ms）。
  ///
  /// 試行ログに残す `ms_actual` はこれではなく、実際のフレームタイムスタンプから
  /// 測った値を使う（仕様書 3.3「推定値ではなく実測を残すこと」）。
  double get nominalMs => frames * refreshRate.frameMs;

  /// 目標との差をフレーム数で表したもの。
  double get errorInFrames => (nominalMs - targetMs) / refreshRate.frameMs;

  @override
  String toString() =>
      'PresentationPlan(target: ${targetMs.toStringAsFixed(1)}ms → '
      '$frames frames = ${nominalMs.toStringAsFixed(1)}ms '
      '@ $refreshRate${clampedToFloor ? ' [floor]' : ''})';
}

/// 提示時間の段階（仕様書 3.3）。難化するほど短くなる。
const List<double> kPresentationStagesMs = <double>[150, 100, 66, 50, 33];

/// 1フレームだけの提示は表示装置側で落ちることがあるため、常に2フレーム以上にする。
///
/// 仕様書 3.3 が 60Hz の最短提示を「2フレーム（約33ms）」としているのに合わせる。
const int kMinimumPresentationFrames = 2;

/// 目標ms を、そのリフレッシュレートで最も近いフレーム数に変換する。
PresentationPlan planPresentation({
  required double targetMs,
  required RefreshRate refreshRate,
  int minimumFrames = kMinimumPresentationFrames,
}) {
  assert(targetMs > 0);
  assert(minimumFrames >= 1);

  final int ideal = (targetMs / refreshRate.frameMs).round();
  final int frames = ideal < minimumFrames ? minimumFrames : ideal;

  return PresentationPlan(
    targetMs: targetMs,
    frames: frames,
    refreshRate: refreshRate,
    clampedToFloor: ideal < minimumFrames,
  );
}

/// その端末でこの目標提示時間を出せるか。
///
/// 出せない軸は「マスター済み」として封じ、別の軸に移す（仕様書 5.4）。
bool canPresent({
  required double targetMs,
  required RefreshRate refreshRate,
  int minimumFrames = kMinimumPresentationFrames,
}) => !planPresentation(
  targetMs: targetMs,
  refreshRate: refreshRate,
  minimumFrames: minimumFrames,
).clampedToFloor;

/// その端末で到達できる最短の提示時間（ms）。
double shortestPresentableMs({
  required RefreshRate refreshRate,
  int minimumFrames = kMinimumPresentationFrames,
}) => minimumFrames * refreshRate.frameMs;
