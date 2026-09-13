import 'dart:math' as math;
import 'dart:ui' show Offset;

/// ガボールの向き（仕様書 4.1）。
///
/// チャンスレベルを 25% にするため必ず4択にする。2択だと勘で 50% 当たってしまい、
/// ステアケースが「見えているか」ではなく「運」を測ることになる。
enum GaborOrientation {
  /// 縦縞。
  deg0(0),

  /// 右上〜左下に縞が走る。
  deg45(45),

  /// 横縞。
  deg90(90),

  /// 左上〜右下に縞が走る。
  deg135(135);

  const GaborOrientation(this.degrees);

  /// 格子の向き θ（度）。シェーダーの `uThetaRad` に渡す前にラジアンへ変換する。
  final int degrees;

  double get radians => degrees * math.pi / 180.0;

  /// 画面座標（y が下向き）における**縞が走る向き**の単位ベクトル。
  ///
  /// 輝度が変化する軸は (cosθ, sinθ)。縞はそれに直交するので (-sinθ, cosθ)。
  /// 軸なので反対向きも同じ意味を持つ（仕様書 4.1「反対方向も正解扱い」）。
  ///
  /// | 向き | このベクトル | 正解フリック方向 |
  /// |---|---|---|
  /// | 0°   | (0, 1)            | 上 または 下 |
  /// | 45°  | (-0.71, 0.71)     | 右上 または 左下 |
  /// | 90°  | (-1, 0)           | 左 または 右 |
  /// | 135° | (-0.71, -0.71)    | 左上 または 右下 |
  Offset get stripeAxis => Offset(-math.sin(radians), math.cos(radians));

  /// 一様分布から1つ選ぶ。
  static GaborOrientation random(math.Random random) =>
      values[random.nextInt(values.length)];
}
