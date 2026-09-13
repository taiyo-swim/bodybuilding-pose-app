import 'package:flutter_test/flutter_test.dart';
import 'package:visual_training_game/core/presentation_timing.dart';
import 'package:visual_training_game/core/refresh_rate.dart';

void main() {
  const RefreshRate hz60 = RefreshRate(60);
  const RefreshRate hz90 = RefreshRate(90);
  const RefreshRate hz120 = RefreshRate(120);

  group('提示時間の段階', () {
    test('仕様書 3.3 の段階どおり', () {
      expect(kPresentationStagesMs, <double>[150, 100, 66, 50, 33]);
    });

    test('難化するほど短くなる', () {
      for (int i = 1; i < kPresentationStagesMs.length; i++) {
        expect(
          kPresentationStagesMs[i],
          lessThan(kPresentationStagesMs[i - 1]),
        );
      }
    });
  });

  group('planPresentation', () {
    test('60Hz: 1フレーム16.7ms として最も近いフレーム数に変換する', () {
      const List<(double, int)> expected = <(double, int)>[
        (150, 9),
        (100, 6),
        (66, 4),
        (50, 3),
        (33, 2),
      ];
      for (final (double targetMs, int frames) in expected) {
        final PresentationPlan plan = planPresentation(
          targetMs: targetMs,
          refreshRate: hz60,
        );
        expect(plan.frames, frames, reason: '${targetMs}ms @60Hz');
      }
    });

    test('120Hz: 同じ目標msでもフレーム数は倍になる', () {
      // 仕様書 3.3 が警告している「同じ2フレームでも16.7msになってしまう」の回避。
      const List<(double, int)> expected = <(double, int)>[
        (150, 18),
        (100, 12),
        (66, 8),
        (50, 6),
        (33, 4),
      ];
      for (final (double targetMs, int frames) in expected) {
        final PresentationPlan plan = planPresentation(
          targetMs: targetMs,
          refreshRate: hz120,
        );
        expect(plan.frames, frames, reason: '${targetMs}ms @120Hz');
      }
    });

    test('リフレッシュレートが変わっても公称提示時間は目標の±1フレーム以内', () {
      // Phase 1 の完了条件（仕様書 11）と同じ基準。
      for (final RefreshRate rate in <RefreshRate>[hz60, hz90, hz120]) {
        for (final double targetMs in kPresentationStagesMs) {
          final PresentationPlan plan = planPresentation(
            targetMs: targetMs,
            refreshRate: rate,
          );
          expect(
            plan.errorInFrames.abs(),
            lessThanOrEqualTo(1.0),
            reason: '${targetMs}ms @ $rate',
          );
        }
      }
    });

    test('90Hz のように割り切れない場合も最も近いフレーム数を選ぶ', () {
      // 1フレーム = 11.111ms。150ms は 13.5 フレーム → 14 フレーム = 155.6ms。
      final PresentationPlan plan = planPresentation(
        targetMs: 150,
        refreshRate: hz90,
      );
      expect(plan.frames, 14);
      expect(plan.nominalMs, closeTo(155.6, 0.1));
      expect(plan.errorInFrames.abs(), lessThanOrEqualTo(0.5));
    });

    test('最短提示を下回る目標は下限に丸め、それを明示する', () {
      // 60Hz で 10ms は物理的に出せない。
      final PresentationPlan plan = planPresentation(
        targetMs: 10,
        refreshRate: hz60,
      );
      expect(plan.frames, kMinimumPresentationFrames);
      expect(plan.clampedToFloor, isTrue);
    });

    test('段階どおりの目標では下限に張り付かない', () {
      for (final RefreshRate rate in <RefreshRate>[hz60, hz90, hz120]) {
        for (final double targetMs in kPresentationStagesMs) {
          expect(
            planPresentation(targetMs: targetMs, refreshRate: rate)
                .clampedToFloor,
            isFalse,
            reason: '${targetMs}ms @ $rate',
          );
        }
      }
    });
  });

  group('物理的限界の判定（仕様書 5.4）', () {
    test('60Hz では 33ms が到達可能な最短', () {
      expect(shortestPresentableMs(refreshRate: hz60), closeTo(33.3, 0.1));
      expect(canPresent(targetMs: 33, refreshRate: hz60), isTrue);
      expect(canPresent(targetMs: 16, refreshRate: hz60), isFalse);
    });

    test('120Hz なら 16.7ms まで出せる', () {
      expect(shortestPresentableMs(refreshRate: hz120), closeTo(16.7, 0.1));
      expect(canPresent(targetMs: 20, refreshRate: hz120), isTrue);
    });
  });

  group('RefreshRate', () {
    test('フレーム時間を返す', () {
      expect(hz60.frameMs, closeTo(16.667, 0.001));
      expect(hz120.frameMs, closeTo(8.333, 0.001));
    });

    test('フォールバックは 60Hz で、出所が分かるようになっている', () {
      expect(RefreshRate.fallback.hz, 60);
      expect(RefreshRate.fallback.source, RefreshRateSource.fallback);
    });
  });

  group('RefreshRateProbe', () {
    test('フレーム間隔の中央値からリフレッシュレートを実測する', () {
      final RefreshRateProbe probe = RefreshRateProbe();
      for (int i = 0; i <= 60; i++) {
        probe.addFrameTimestamp(Duration(microseconds: i * 16667));
      }
      final RefreshRate? estimate = probe.estimate();
      expect(estimate, isNotNull);
      expect(estimate!.hz, closeTo(60, 0.1));
      expect(estimate.source, RefreshRateSource.measured);
    });

    test('標本が足りないうちは null を返す', () {
      final RefreshRateProbe probe = RefreshRateProbe();
      probe.addFrameTimestamp(Duration.zero);
      probe.addFrameTimestamp(const Duration(microseconds: 16667));
      expect(probe.estimate(), isNull);
    });

    test('取りこぼした長い間隔は中央値を壊さない', () {
      final RefreshRateProbe probe = RefreshRateProbe();
      int micros = 0;
      for (int i = 0; i < 60; i++) {
        // 10フレームに1回、アプリが止まったような長い間隔を混ぜる。
        micros += (i % 10 == 0) ? 500000 : 8333;
        probe.addFrameTimestamp(Duration(microseconds: micros));
      }
      expect(probe.estimate()!.hz, closeTo(120, 1));
    });
  });
}
