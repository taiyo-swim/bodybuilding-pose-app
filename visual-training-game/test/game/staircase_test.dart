import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:visual_training_game/game/staircase.dart';

/// 理想的な観察者の心理測定関数。
///
/// ワイブル関数に 4択のチャンスレベル 0.25 を足したもの。
/// [threshold] はチャンスレベルと100%の中間に達するコントラスト。
double _probabilityCorrect(double contrast, {required double threshold}) {
  const double guess = 0.25;
  const double beta = 3.0; // 傾き。知覚実験で使われる典型値
  final double weibull = 1 - math.exp(-math.pow(contrast / threshold, beta));
  return guess + (1 - guess) * weibull;
}

void main() {
  group('仕様書 4.3 の規則', () {
    test('倍率と上下限が仕様どおり', () {
      expect(Staircase.stepFactor, 0.85);
      expect(Staircase.minContrast, 0.01);
      expect(Staircase.maxContrast, 0.60);
      expect(Staircase.correctRunForHarder, 3);
    });

    test('3連続正解でコントラストが 0.85倍になる', () {
      final Staircase staircase = Staircase(initialContrast: 0.20);

      expect(staircase.record(correct: true).kind, StaircaseStepKind.hold);
      expect(staircase.contrast, 0.20);
      expect(staircase.record(correct: true).kind, StaircaseStepKind.hold);
      expect(staircase.contrast, 0.20);

      final StaircaseStep third = staircase.record(correct: true);
      expect(third.kind, StaircaseStepKind.harder);
      expect(staircase.contrast, closeTo(0.20 * 0.85, 1e-12));
    });

    test('1回ミスで 1/0.85倍になる', () {
      final Staircase staircase = Staircase(initialContrast: 0.20);
      final StaircaseStep step = staircase.record(correct: false);
      expect(step.kind, StaircaseStepKind.easier);
      expect(staircase.contrast, closeTo(0.20 / 0.85, 1e-12));
    });

    test('ミスは連続正解のカウントを崩す', () {
      final Staircase staircase = Staircase(initialContrast: 0.20);
      staircase.record(correct: true);
      staircase.record(correct: true);
      staircase.record(correct: false); // ここでリセット
      final double afterMiss = staircase.contrast;

      staircase.record(correct: true);
      staircase.record(correct: true);
      expect(staircase.contrast, afterMiss, reason: 'まだ難化してはいけない');
      staircase.record(correct: true);
      expect(staircase.contrast, closeTo(afterMiss * 0.85, 1e-12));
    });

    test('難化のたびに連続正解のカウントは振り出しに戻る', () {
      final Staircase staircase = Staircase(initialContrast: 0.30);
      for (int i = 0; i < 6; i++) {
        staircase.record(correct: true);
      }
      // 6連続正解 = 難化2回。
      expect(staircase.contrast, closeTo(0.30 * 0.85 * 0.85, 1e-12));
    });
  });

  group('上下限（仕様書 4.3）', () {
    test('1% を下回らない', () {
      final Staircase staircase = Staircase(initialContrast: 0.02);
      for (int i = 0; i < 300; i++) {
        staircase.record(correct: true);
      }
      expect(staircase.contrast, Staircase.minContrast);
      expect(staircase.isAtFloor, isTrue);
    });

    test('60% を上回らない', () {
      final Staircase staircase = Staircase(initialContrast: 0.30);
      for (int i = 0; i < 300; i++) {
        staircase.record(correct: false);
      }
      expect(staircase.contrast, Staircase.maxContrast);
      expect(staircase.isAtCeiling, isTrue);
    });

    test('張り付いている試行は clamped として記録される', () {
      // これ以上難化できない状態を、仕様書 5.4 の「マスター済み」判定に使う。
      final Staircase staircase = Staircase(initialContrast: 0.01);
      staircase.record(correct: true);
      staircase.record(correct: true);
      final StaircaseStep step = staircase.record(correct: true);
      expect(step.kind, StaircaseStepKind.harder);
      expect(step.clamped, isTrue);
      expect(staircase.contrast, Staircase.minContrast);
    });
  });

  group('反転点', () {
    test('難化と易化が切り替わった試行を記録する', () {
      final Staircase staircase = Staircase(initialContrast: 0.30);
      // 難化（1回目の向き決定）
      staircase.record(correct: true);
      staircase.record(correct: true);
      expect(staircase.record(correct: true).isReversal, isFalse);
      // 易化 → 向きが変わるので反転
      expect(staircase.record(correct: false).isReversal, isTrue);
      // 続けて易化 → 反転ではない
      expect(staircase.record(correct: false).isReversal, isFalse);
      expect(staircase.reversalCount, 1);
    });

    test('据え置きの試行では向きは変わらない', () {
      final Staircase staircase = Staircase(initialContrast: 0.30);
      staircase.record(correct: false); // 易化
      final StaircaseStep hold = staircase.record(correct: true);
      expect(hold.kind, StaircaseStepKind.hold);
      expect(hold.isReversal, isFalse);
      expect(staircase.reversalCount, 0);
    });

    test('反転点は記録するが、閾値は計算しない（未決事項B）', () {
      // 閾値推定の方法と試行数が決まるまで、ここから推定値を出してはいけない。
      final Staircase staircase = Staircase(initialContrast: 0.30);
      final math.Random random = math.Random(11);
      for (int i = 0; i < 200; i++) {
        staircase.record(correct: random.nextDouble() < 0.79);
      }
      expect(staircase.reversalContrasts, isNotEmpty);
      // 公開しているのは反転点の列だけで、閾値を返す API は存在しない。
      expect(staircase.reversalContrasts, isA<List<double>>());
    });
  });

  group('正答率の収束（仕様書 4.3）', () {
    test('理想観察者に対する正答率が 79% 付近に収まる', () {
      for (final double threshold in <double>[0.03, 0.06, 0.12]) {
        final math.Random random = math.Random(threshold.hashCode ^ 0x5eed);
        final Staircase staircase = Staircase(initialContrast: 0.30);

        const int warmup = 500;
        const int measured = 8000;
        int correctCount = 0;

        for (int i = 0; i < warmup + measured; i++) {
          final bool correct =
              random.nextDouble() <
              _probabilityCorrect(staircase.contrast, threshold: threshold);
          if (i >= warmup && correct) correctCount++;
          staircase.record(correct: correct);
        }

        final double rate = correctCount / measured;
        expect(
          rate,
          closeTo(0.7937, 0.03),
          reason: '閾値 $threshold での正答率が 79% から外れている',
        );
      }
    });

    test('コントラストが観察者の閾値付近に落ち着く', () {
      const double threshold = 0.05;
      final math.Random random = math.Random(4242);
      final Staircase staircase = Staircase(initialContrast: 0.30);

      const int warmup = 500;
      const int measured = 4000;
      double sum = 0;

      for (int i = 0; i < warmup + measured; i++) {
        if (i >= warmup) sum += staircase.contrast;
        final bool correct =
            random.nextDouble() <
            _probabilityCorrect(staircase.contrast, threshold: threshold);
        staircase.record(correct: correct);
      }

      final double meanContrast = sum / measured;
      // p = 0.7937 となるコントラストを解析的に求めて比較する。
      // 0.25 + 0.75*(1 - exp(-(c/t)^3)) = 0.7937 → c = t * (-ln(1-0.7249))^(1/3)
      final double expected =
          threshold * math.pow(-math.log(1 - 0.7249), 1 / 3).toDouble();
      expect(meanContrast, closeTo(expected, expected * 0.25));
    });

    test('上限に張り付く観察者では難化が起きない', () {
      // 何も見えない観察者（常にチャンスレベル以下）。
      final Staircase staircase = Staircase(initialContrast: 0.30);
      for (int i = 0; i < 100; i++) {
        staircase.record(correct: false);
      }
      expect(staircase.contrast, Staircase.maxContrast);
    });
  });

  group('resetTo', () {
    test('状態を初期化する', () {
      final Staircase staircase = Staircase(initialContrast: 0.30);
      for (int i = 0; i < 20; i++) {
        staircase.record(correct: i.isEven);
      }
      staircase.resetTo(0.15);
      expect(staircase.contrast, 0.15);
      expect(staircase.trialCount, 0);
      expect(staircase.reversalCount, 0);
    });

    test('範囲外の値は上下限に丸める', () {
      final Staircase staircase = Staircase()..resetTo(0.9);
      expect(staircase.contrast, Staircase.maxContrast);
      staircase.resetTo(0.001);
      expect(staircase.contrast, Staircase.minContrast);
    });
  });
}
