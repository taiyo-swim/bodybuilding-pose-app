import 'dart:math' as math;

/// 視角（分）と論理px の換算。
///
/// **未決事項A の差し替え点はこのファイル1箇所に閉じている**（仕様書 0-A）。
///
/// ピクセルの物理サイズは端末ごとに異なり、視距離も人ごとに違うため、
/// 同じ設定でも網膜上の空間周波数は倍以上ばらつく。
/// v1 の暫定方針は「ppi補正のみ・視距離は40cm固定」。
///
/// 確定するまで、λ を扱うコードは論理px ではなく**視角（分）を一次表現**にすること。
/// 本クラス以外で「論理px の λ」を組み立ててはいけない。
class ViewingGeometry {
  const ViewingGeometry({
    required this.logicalPixelsPerInch,
    this.viewingDistanceCm = defaultViewingDistanceCm,
  }) : assert(logicalPixelsPerInch > 0),
       assert(viewingDistanceCm > 0);

  /// 1インチあたりの**論理**px 数。
  ///
  /// 物理ppi ÷ devicePixelRatio に相当する。物理ppi の取得方法は [DisplayDensity] を参照。
  final double logicalPixelsPerInch;

  /// 視距離（cm）。暫定方針では 40cm 固定（仕様書 0-A）。
  ///
  /// TODO(未決): 未決事項A が「フロントカメラで視距離を推定」に倒れた場合、
  /// ここに実測値が入る。呼び出し側は再構築するだけで済むようにしておくこと。
  final double viewingDistanceCm;

  /// 暫定方針の視距離（仕様書 0-A）。
  static const double defaultViewingDistanceCm = 40.0;

  static const double _cmPerInch = 2.54;

  double get _logicalPixelsPerCm => logicalPixelsPerInch / _cmPerInch;

  /// 論理px 1つが張る視角（分）。
  ///
  /// 1px は視距離に対して十分小さいので、以降の換算は線形近似で扱う。
  /// 6σ のパッチ全体（数百px）でも誤差は 0.1% 未満。
  double get arcminPerLogicalPixel {
    final double sizeCm = 1.0 / _logicalPixelsPerCm;
    final double radians = 2 * math.atan(sizeCm / (2 * viewingDistanceCm));
    return radians * 180 / math.pi * 60;
  }

  /// 視角（分）→ 論理px。
  double logicalPixelsFromArcmin(double arcmin) => arcmin / arcminPerLogicalPixel;

  /// 論理px → 視角（分）。
  double arcminFromLogicalPixels(double logicalPixels) =>
      logicalPixels * arcminPerLogicalPixel;

  /// 空間周波数（cycles per degree）→ 波長（視角の分）。
  ///
  /// 1度 = 60分なので λ[分] = 60 / cpd。仕様書 5.4 の「6.5 cpd」「13 cpd」はこの単位。
  static double arcminFromCyclesPerDegree(double cyclesPerDegree) {
    assert(cyclesPerDegree > 0);
    return 60.0 / cyclesPerDegree;
  }

  /// 波長（視角の分）→ 空間周波数（cycles per degree）。
  static double cyclesPerDegreeFromArcmin(double arcmin) {
    assert(arcmin > 0);
    return 60.0 / arcmin;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewingGeometry &&
          other.logicalPixelsPerInch == logicalPixelsPerInch &&
          other.viewingDistanceCm == viewingDistanceCm;

  @override
  int get hashCode => Object.hash(logicalPixelsPerInch, viewingDistanceCm);

  @override
  String toString() =>
      'ViewingGeometry(lpi: ${logicalPixelsPerInch.toStringAsFixed(1)}, '
      'distance: ${viewingDistanceCm.toStringAsFixed(1)}cm, '
      'arcmin/px: ${arcminPerLogicalPixel.toStringAsFixed(3)})';
}

/// 端末の表示密度を求める。未決事項A の暫定方針（ppi補正のみ）の入力を作る。
abstract final class DisplayDensity {
  /// Android の密度非依存ピクセルの定義（1dp = 1/160 インチ）。
  static const double androidNominalLogicalPixelsPerInch = 160.0;

  /// iOS のポイントの定義（1pt ≈ 1/163 インチ）。
  static const double iosNominalLogicalPixelsPerInch = 163.0;

  /// 実測 ppi が手に入らないときのフォールバック。
  ///
  /// プラットフォームの**公称**密度を返すだけで、実機の物理ppi とは数%〜十数%ずれる。
  /// 例: iPhone の実ppi 460 に対し、公称では 163 × 3 = 489 相当になる。
  ///
  /// TODO(未決): 未決事項A が確定したら、端末ごとの実ppi を引く経路
  /// （機種データベース、またはキャリブレーション結果）に差し替える。
  /// ランキングの公平性はこの値の精度に直結する。
  static double nominalLogicalPixelsPerInch({required bool isIOS}) =>
      isIOS ? iosNominalLogicalPixelsPerInch : androidNominalLogicalPixelsPerInch;
}
