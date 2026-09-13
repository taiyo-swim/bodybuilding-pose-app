import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// ディザリングの**原理と振幅の選択**を検証する（仕様書 3.2）。
///
/// 注意: これは `shaders/gabor.frag` そのものの検証ではない。GLSL は実機でしか走らない。
/// ここで確かめるのは「なぜ振幅を ±1 LSB の TPDF にしたのか」という設計判断であり、
/// 見え方の確認は実機での目視が必要（仕様書 11-2 / 12）。
///
/// `gabor.frag` の tpdfNoise を変える場合は、このテストの前提も見直すこと。
void main() {
  const int levels = 255; // 8bit

  double quantize(double v) => (v * levels).roundToDouble() / levels;

  group('8bit 量子化の問題（ディザなし）', () {
    test('コントラスト3%では使える階調が ±4 しかない', () {
      // 仕様書 3.2 の主張そのもの。
      // 中間グレー付近の振幅は 0.5 * C = 0.015 → 0.015 * 255 = 3.8 階調。
      const double contrast = 0.03;
      final double amplitudeInLevels = 0.5 * contrast * levels;
      expect(amplitudeInLevels, closeTo(3.8, 0.05));
    });

    test('正弦波が階段状になり、1周期でわずかな段数しか出ない', () {
      const double contrast = 0.03;
      final Set<double> distinct = <double>{};
      for (int i = 0; i < 2000; i++) {
        final double phase = 2 * math.pi * i / 2000;
        distinct.add(quantize(128 / 255 + 0.5 * contrast * math.sin(phase)));
      }
      // ±3.8 階調なので 8〜9 段。これが「量子化の輪郭」の正体。
      expect(distinct.length, lessThanOrEqualTo(9));
    });

    test('量子化誤差は最大 0.5 LSB の決定的なバイアスとして残る', () {
      double worst = 0;
      for (int i = 0; i < 1000; i++) {
        final double v = 0.4 + 0.2 * i / 1000;
        worst = math.max(worst, (quantize(v) - v).abs() * levels);
      }
      expect(worst, greaterThan(0.45));
    });
  });

  group('TPDF ディザ（振幅 ±1 LSB）', () {
    /// 独立な一様乱数2つの和 - 1 → 三角分布 [-1, 1]。
    double tpdf(math.Random random) =>
        random.nextDouble() + random.nextDouble() - 1.0;

    test('値域は [-1, 1]、平均は 0', () {
      final math.Random random = math.Random(7);
      double sum = 0;
      double lo = 1, hi = -1;
      const int n = 200000;
      for (int i = 0; i < n; i++) {
        final double v = tpdf(random);
        sum += v;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
      expect(lo, greaterThanOrEqualTo(-1.0));
      expect(hi, lessThanOrEqualTo(1.0));
      expect(sum / n, closeTo(0, 0.01));
    });

    test('量子化後の期待値が元の値と一致する（決定的なバイアスが消える）', () {
      // これがディザを入れる理由。誤差がバイアスではなくノイズに変わるので、
      // 空間的に平均すると本来の輝度が復元される。
      final math.Random random = math.Random(42);
      const int samples = 60000;
      for (final double v in <double>[
        128 / 255,
        128 / 255 + 0.0007, // 1/255 の 1/5 という、単体では表現できない差
        128 / 255 - 0.0031,
        0.5013,
      ]) {
        double sum = 0;
        for (int i = 0; i < samples; i++) {
          sum += quantize(v + tpdf(random) / levels);
        }
        final double meanErrorInLevels = (sum / samples - v).abs() * levels;
        expect(
          meanErrorInLevels,
          lessThan(0.02),
          reason: 'v = $v の平均誤差が大きすぎる',
        );
      }
    });

    test('ディザなしでは同じ入力で誤差が残り続ける', () {
      // 上のテストとの対比。平均しても誤差が消えないことを示す。
      const double v = 128 / 255 + 0.0007;
      final double errorInLevels = (quantize(v) - v).abs() * levels;
      expect(errorInLevels, greaterThan(0.15));
    });

    test('加算されるノイズ自体は 8bit で ±1 階調に収まる', () {
      // 過大なノイズは刺激より目立つマスクになる。振幅を上げてはいけない。
      final math.Random random = math.Random(99);
      for (int i = 0; i < 10000; i++) {
        expect(tpdf(random).abs(), lessThanOrEqualTo(1.0));
      }
    });
  });
}
