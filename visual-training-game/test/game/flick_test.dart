import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:visual_training_game/game/flick.dart';
import 'package:visual_training_game/stimulus/orientation.dart';

void main() {
  group('仕様書 4.1 の回答方向テーブル', () {
    // 画面座標は y が下向き。
    const Offset up = Offset(0, -1);
    const Offset down = Offset(0, 1);
    const Offset left = Offset(-1, 0);
    const Offset right = Offset(1, 0);
    const Offset upRight = Offset(1, -1);
    const Offset downLeft = Offset(-1, 1);
    const Offset upLeft = Offset(-1, -1);
    const Offset downRight = Offset(1, 1);

    void expectAnswer(Offset direction, GaborOrientation expected) {
      // 閾値を確実に超える長さにする。
      final FlickResponse? response = FlickJudge.evaluate(direction * 100);
      expect(response, isNotNull, reason: '$direction');
      expect(response!.answer, expected, reason: '$direction');
    }

    test('0°（縦縞）は 上 または 下', () {
      expectAnswer(up, GaborOrientation.deg0);
      expectAnswer(down, GaborOrientation.deg0);
    });

    test('90°（横縞）は 左 または 右', () {
      expectAnswer(left, GaborOrientation.deg90);
      expectAnswer(right, GaborOrientation.deg90);
    });

    test('45° は 右上 または 左下', () {
      expectAnswer(upRight, GaborOrientation.deg45);
      expectAnswer(downLeft, GaborOrientation.deg45);
    });

    test('135° は 左上 または 右下', () {
      expectAnswer(upLeft, GaborOrientation.deg135);
      expectAnswer(downRight, GaborOrientation.deg135);
    });

    test('反対方向のフリックは同じ回答になる', () {
      for (final Offset direction in <Offset>[
        up,
        left,
        upRight,
        upLeft,
        const Offset(0.3, -0.9),
      ]) {
        final FlickResponse? a = FlickJudge.evaluate(direction * 100);
        final FlickResponse? b = FlickJudge.evaluate(direction * -100);
        expect(a!.answer, b!.answer, reason: '$direction');
      }
    });
  });

  group('縞の向きとフリックの整合', () {
    test('各向きの stripeAxis 方向にフリックすると、その向きが正解になる', () {
      // GaborOrientation.stripeAxis は刺激側の定義、FlickJudge は回答側の定義。
      // この2つが食い違うと、正答率が測れているようで実は測れていない状態になる。
      for (final GaborOrientation orientation in GaborOrientation.values) {
        for (final double sign in <double>[1, -1]) {
          final Offset flick = orientation.stripeAxis * 100 * sign;
          final FlickResponse? response = FlickJudge.evaluate(flick);
          expect(
            response!.isCorrectFor(orientation),
            isTrue,
            reason: '${orientation.degrees}° (sign $sign)',
          );
        }
      }
    });

    test('隣の向きへのフリックは不正解になる', () {
      for (final GaborOrientation stimulus in GaborOrientation.values) {
        for (final GaborOrientation other in GaborOrientation.values) {
          if (other == stimulus) continue;
          final FlickResponse? response = FlickJudge.evaluate(
            other.stripeAxis * 100,
          );
          expect(
            response!.isCorrectFor(stimulus),
            isFalse,
            reason: '刺激 ${stimulus.degrees}° に ${other.degrees}° 方向',
          );
        }
      }
    });
  });

  group('閾値', () {
    test('初期値は 24論理px', () {
      expect(FlickJudge.defaultThresholdLogicalPixels, 24.0);
    });

    test('閾値未満は回答なし', () {
      expect(FlickJudge.evaluate(const Offset(0, -23.9)), isNull);
      expect(FlickJudge.evaluate(Offset.zero), isNull);
    });

    test('閾値ちょうどは回答として扱う', () {
      expect(FlickJudge.evaluate(const Offset(0, -24)), isNotNull);
    });

    test('閾値は差し替えられる（実機で調整するため）', () {
      expect(FlickJudge.evaluate(const Offset(0, -10), threshold: 8), isNotNull);
      expect(FlickJudge.evaluate(const Offset(0, -10), threshold: 40), isNull);
    });
  });

  group('軸角度', () {
    test('値域は [0, 180)', () {
      final math.Random random = math.Random(3);
      for (int i = 0; i < 2000; i++) {
        final Offset delta = Offset(
          random.nextDouble() * 400 - 200,
          random.nextDouble() * 400 - 200,
        );
        if (delta.distance < FlickJudge.defaultThresholdLogicalPixels) continue;
        final double axis = FlickJudge.axisDegreesOf(delta);
        expect(axis, greaterThanOrEqualTo(0));
        expect(axis, lessThan(180));
      }
    });

    test('丸める前の連続値を保持する（ログ用）', () {
      // 20° は deg0 と deg45 の間。丸めると 0° になるが、生の角度も残す。
      final double radians = 20 * math.pi / 180;
      final Offset flick =
          Offset(-math.sin(radians), math.cos(radians)) * 100;
      final FlickResponse response = FlickJudge.evaluate(flick)!;
      expect(response.axisDegrees, closeTo(20, 0.01));
      expect(response.answer, GaborOrientation.deg0);
      expect(response.ambiguityDegrees, closeTo(20, 0.01));
    });

    test('境界（22.5°）付近では迷いの大きさが最大になる', () {
      final double radians = 22.5 * math.pi / 180;
      final Offset flick =
          Offset(-math.sin(radians), math.cos(radians)) * 100;
      final FlickResponse response = FlickJudge.evaluate(flick)!;
      expect(response.ambiguityDegrees, closeTo(22.5, 0.01));
    });

    test('どの角度でも迷いの大きさは 22.5° を超えない', () {
      for (int degrees = 0; degrees < 180; degrees++) {
        final double radians = degrees * math.pi / 180;
        final Offset flick =
            Offset(-math.sin(radians), math.cos(radians)) * 100;
        expect(
          FlickJudge.evaluate(flick)!.ambiguityDegrees,
          lessThanOrEqualTo(22.5 + 1e-9),
          reason: '$degrees°',
        );
      }
    });
  });

  group('チャンスレベル', () {
    test('ランダムなフリックの正答率はおよそ 25%', () {
      // 2択だと勘で 50% 当たってしまうため4択にしている（仕様書 4.1）。
      final math.Random random = math.Random(2024);
      const GaborOrientation stimulus = GaborOrientation.deg45;
      int correct = 0;
      const int trials = 40000;
      for (int i = 0; i < trials; i++) {
        final double angle = random.nextDouble() * 2 * math.pi;
        final Offset flick =
            Offset(math.cos(angle), math.sin(angle)) * 100;
        if (FlickJudge.evaluate(flick)!.isCorrectFor(stimulus)) correct++;
      }
      expect(correct / trials, closeTo(0.25, 0.01));
    });
  });
}
