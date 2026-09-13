import 'package:flutter/foundation.dart';

import '../core/viewing_geometry.dart';
import 'orientation.dart';

/// 1試行ぶんの刺激パラメータ（仕様書 3.1）。
///
/// λ は**視角（分）を一次表現**にしている。論理px への換算は [ViewingGeometry] だけが行う。
/// 未決事項A が確定しても、このクラスは変更しなくて済む（仕様書 0-A）。
@immutable
class GaborParams {
  const GaborParams({
    required this.contrast,
    required this.wavelengthArcmin,
    required this.orientation,
  }) : assert(contrast >= 0 && contrast <= 1),
       assert(wavelengthArcmin > 0);

  /// C: マイケルソンコントラスト。ステアケースが動かす（仕様書 4.3、上下限 1%〜60%）。
  final double contrast;

  /// λ: 波長を視角の分で表したもの。σ も同値（仕様書 3.1）。
  final double wavelengthArcmin;

  /// θ: 縞の向き。
  final GaborOrientation orientation;

  /// 初期の空間周波数帯（仕様書 5.4）。ここで飽和したら 13 cpd に移る。
  static const double defaultCyclesPerDegree = 6.5;

  /// 初期の λ（視角の分）。6.5 cpd 相当。
  static const double defaultWavelengthArcmin = 60.0 / defaultCyclesPerDegree;

  /// 空間周波数（cycles per degree）。仕様書 5.4 のシーズン設計で使う単位。
  double get cyclesPerDegree =>
      ViewingGeometry.cyclesPerDegreeFromArcmin(wavelengthArcmin);

  /// λ を論理px に落とす。σ も同値。
  double lambdaLogicalPixels(ViewingGeometry geometry) =>
      geometry.logicalPixelsFromArcmin(wavelengthArcmin);

  /// 描画サイズ = 6σ（仕様書 3.1）。
  double patchDiameterLogicalPixels(ViewingGeometry geometry) =>
      6 * lambdaLogicalPixels(geometry);

  GaborParams copyWith({
    double? contrast,
    double? wavelengthArcmin,
    GaborOrientation? orientation,
  }) => GaborParams(
    contrast: contrast ?? this.contrast,
    wavelengthArcmin: wavelengthArcmin ?? this.wavelengthArcmin,
    orientation: orientation ?? this.orientation,
  );

  /// C = 0 の一様な中間グレー。固視点表示中やブランク中に使う。
  GaborParams get blank => copyWith(contrast: 0);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GaborParams &&
          other.contrast == contrast &&
          other.wavelengthArcmin == wavelengthArcmin &&
          other.orientation == orientation;

  @override
  int get hashCode => Object.hash(contrast, wavelengthArcmin, orientation);

  @override
  String toString() =>
      'GaborParams(C: ${(contrast * 100).toStringAsFixed(2)}%, '
      'λ: ${wavelengthArcmin.toStringAsFixed(2)}′ '
      '(${cyclesPerDegree.toStringAsFixed(2)} cpd), '
      'θ: ${orientation.degrees}°)';
}
