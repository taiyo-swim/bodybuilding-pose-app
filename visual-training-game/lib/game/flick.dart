import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../stimulus/orientation.dart';

/// フリック1回ぶんの回答（仕様書 4.1）。
@immutable
class FlickResponse {
  const FlickResponse({
    required this.delta,
    required this.axisDegrees,
    required this.answer,
  });

  /// フリックのベクトル（論理px、y が下向き）。
  final Offset delta;

  /// フリックが示した軸の角度（度）。値域は [0, 180)。
  ///
  /// 4択に丸める前の連続値。試行ログの `response_deg` にはこれを残す。
  /// 丸めた値だけ保存すると、後から「どれくらい迷ったか」を解析できなくなる
  /// （仕様書 8「集計値だけ保存すると、後から解析方法を変えられなくなる」）。
  final double axisDegrees;

  /// 最も近い4択。
  final GaborOrientation answer;

  /// フリックの長さ（論理px）。
  double get distance => delta.distance;

  /// 提示された向きに対して正解か。
  ///
  /// 軸で判定するので反対方向も正解になる（仕様書 4.1）。
  bool isCorrectFor(GaborOrientation stimulus) => answer == stimulus;

  /// 丸める前の角度が、選ばれた4択からどれだけ離れていたか（度、0〜22.5）。
  double get ambiguityDegrees =>
      _axisDistanceDegrees(axisDegrees, answer.degrees.toDouble());

  @override
  String toString() =>
      'FlickResponse(${axisDegrees.toStringAsFixed(1)}° → ${answer.degrees}°, '
      '${distance.toStringAsFixed(1)}px)';
}

/// フリックを4択の向きに判定する（仕様書 4.1）。
///
/// 縞の軸方向にフリックすれば正解。反対方向も正解扱い。
///
/// | 向き | 正解フリック方向 |
/// |---|---|
/// | 0°（縦縞） | 上 または 下 |
/// | 90°（横縞） | 左 または 右 |
/// | 45° | 右上 または 左下 |
/// | 135° | 左上 または 右下 |
abstract final class FlickJudge {
  /// フリック距離の閾値（論理px）。
  ///
  /// 初期値 24。親指1本で操作できることが条件なので、実機で調整する（仕様書 4.1）。
  static const double defaultThresholdLogicalPixels = 24.0;

  /// [delta] を回答に変換する。閾値に満たなければ null（回答なし）。
  static FlickResponse? evaluate(
    Offset delta, {
    double threshold = defaultThresholdLogicalPixels,
  }) {
    if (delta.distance < threshold) return null;

    final double axis = axisDegreesOf(delta);
    return FlickResponse(
      delta: delta,
      axisDegrees: axis,
      answer: nearestOrientation(axis),
    );
  }

  /// フリックベクトルが示す軸の角度（度、[0, 180)）。
  ///
  /// 縞の走る向きは (-sinθ, cosθ)（[GaborOrientation.stripeAxis] 参照）。
  /// フリック (dx, dy) がその向きを指すので、θ = atan2(-dx, dy) で逆算できる。
  static double axisDegreesOf(Offset delta) {
    final double radians = math.atan2(-delta.dx, delta.dy);
    final double degrees = radians * 180 / math.pi;
    // 軸なので 180° 周期。負の値と 180 以上を [0, 180) に畳む。
    return (degrees % 180 + 180) % 180;
  }

  /// 角度に最も近い4択を返す。
  static GaborOrientation nearestOrientation(double axisDegrees) {
    GaborOrientation best = GaborOrientation.deg0;
    double bestDistance = double.infinity;
    for (final GaborOrientation candidate in GaborOrientation.values) {
      final double distance = _axisDistanceDegrees(
        axisDegrees,
        candidate.degrees.toDouble(),
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    return best;
  }
}

/// 2つの角度の距離。180° を法とする軸なので、最大でも 90°。
double _axisDistanceDegrees(double a, double b) {
  final double diff = (a - b).abs() % 180;
  return diff > 90 ? 180 - diff : diff;
}
