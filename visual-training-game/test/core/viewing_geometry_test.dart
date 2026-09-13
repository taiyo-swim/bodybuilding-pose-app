import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:visual_training_game/core/viewing_geometry.dart';

void main() {
  group('ViewingGeometry', () {
    // Android 公称密度（160 論理px/inch）を 40cm から見た場合。
    // 1論理px = 1/160 inch = 0.15875mm。
    // 2*atan(0.0079375cm / 40cm) = 3.9688e-4 rad = 1.3644 分。
    const ViewingGeometry android160 = ViewingGeometry(
      logicalPixelsPerInch: 160,
    );

    test('1論理pxが張る視角を正しく求める', () {
      expect(android160.arcminPerLogicalPixel, closeTo(1.3644, 0.001));
    });

    test('視距離のデフォルトは暫定方針どおり40cm', () {
      expect(android160.viewingDistanceCm, 40.0);
      expect(ViewingGeometry.defaultViewingDistanceCm, 40.0);
    });

    test('視角 ⇄ 論理px は往復して元に戻る', () {
      for (final double arcmin in <double>[1, 4.6, 9.23, 60]) {
        final double px = android160.logicalPixelsFromArcmin(arcmin);
        expect(android160.arcminFromLogicalPixels(px), closeTo(arcmin, 1e-9));
      }
    });

    test('視距離が2倍になると、同じ論理pxが張る視角はほぼ半分になる', () {
      const ViewingGeometry far = ViewingGeometry(
        logicalPixelsPerInch: 160,
        viewingDistanceCm: 80,
      );
      expect(
        far.arcminPerLogicalPixel,
        closeTo(android160.arcminPerLogicalPixel / 2, 1e-4),
      );
    });

    test('同じ視角を保つには、遠いほど多くの論理pxが要る', () {
      const ViewingGeometry far = ViewingGeometry(
        logicalPixelsPerInch: 160,
        viewingDistanceCm: 80,
      );
      expect(
        far.logicalPixelsFromArcmin(10),
        greaterThan(android160.logicalPixelsFromArcmin(10)),
      );
    });

    test('密度が高いほど1論理pxの視角は小さい', () {
      const ViewingGeometry dense = ViewingGeometry(
        logicalPixelsPerInch: 320,
      );
      expect(
        dense.arcminPerLogicalPixel,
        lessThan(android160.arcminPerLogicalPixel),
      );
    });

    test('cpd ⇄ 視角(分) は 60 を介して変換される', () {
      // 仕様書 5.4 が挙げる 6.5 cpd / 13 cpd。
      expect(
        ViewingGeometry.arcminFromCyclesPerDegree(6.5),
        closeTo(60 / 6.5, 1e-12),
      );
      expect(
        ViewingGeometry.cyclesPerDegreeFromArcmin(
          ViewingGeometry.arcminFromCyclesPerDegree(13),
        ),
        closeTo(13, 1e-12),
      );
    });

    test('線形近似の誤差は 6σ のパッチ全体でも 0.1% 未満', () {
      // λ = 9.23分（6.5 cpd）の 6σ は 6λ。それを厳密な atan と比べる。
      const double arcmin = 60 / 6.5;
      final double px = android160.logicalPixelsFromArcmin(arcmin) * 6;
      final double sizeCm = px / (160 / 2.54);
      final double exactArcmin =
          2 *
          math.atan(sizeCm / (2 * android160.viewingDistanceCm)) *
          180 /
          math.pi *
          60;
      final double linearArcmin = android160.arcminFromLogicalPixels(px);
      expect((linearArcmin - exactArcmin).abs() / exactArcmin, lessThan(0.001));
    });
  });

  group('DisplayDensity', () {
    test('プラットフォームごとの公称密度を返す', () {
      expect(DisplayDensity.nominalLogicalPixelsPerInch(isIOS: true), 163.0);
      expect(DisplayDensity.nominalLogicalPixelsPerInch(isIOS: false), 160.0);
    });
  });
}
