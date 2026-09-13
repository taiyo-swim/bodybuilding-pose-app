import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:visual_training_game/stimulus/orientation.dart';

void main() {
  group('GaborOrientation', () {
    test('4択である（チャンスレベル25%）', () {
      expect(GaborOrientation.values.length, 4);
    });

    test('仕様書 4.1 の回答方向テーブルと一致する', () {
      // 画面座標は y が下向き。
      const Map<GaborOrientation, Offset> expected = <GaborOrientation, Offset>{
        // 縦縞 → 上 または 下
        GaborOrientation.deg0: Offset(0, 1),
        // 右上 または 左下
        GaborOrientation.deg45: Offset(-math.sqrt1_2, math.sqrt1_2),
        // 左 または 右
        GaborOrientation.deg90: Offset(-1, 0),
        // 左上 または 右下
        GaborOrientation.deg135: Offset(-math.sqrt1_2, -math.sqrt1_2),
      };

      expected.forEach((GaborOrientation orientation, Offset axis) {
        expect(
          orientation.stripeAxis.dx,
          closeTo(axis.dx, 1e-12),
          reason: '${orientation.degrees}° の dx',
        );
        expect(
          orientation.stripeAxis.dy,
          closeTo(axis.dy, 1e-12),
          reason: '${orientation.degrees}° の dy',
        );
      });
    });

    test('縞の向きは単位ベクトル', () {
      for (final GaborOrientation o in GaborOrientation.values) {
        expect(o.stripeAxis.distance, closeTo(1.0, 1e-12));
      }
    });

    test('縞の向きは輝度変調軸と直交する', () {
      for (final GaborOrientation o in GaborOrientation.values) {
        final Offset modulation = Offset(
          math.cos(o.radians),
          math.sin(o.radians),
        );
        final double dot =
            modulation.dx * o.stripeAxis.dx + modulation.dy * o.stripeAxis.dy;
        expect(dot, closeTo(0, 1e-12), reason: '${o.degrees}°');
      }
    });

    test('random は4つの向きすべてを返しうる', () {
      final math.Random random = math.Random(1234);
      final Set<GaborOrientation> seen = <GaborOrientation>{};
      for (int i = 0; i < 200; i++) {
        seen.add(GaborOrientation.random(random));
      }
      expect(seen, GaborOrientation.values.toSet());
    });
  });
}
