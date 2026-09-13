import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_training_game/game/flick.dart';
import 'package:visual_training_game/stimulus/orientation.dart';
import 'package:visual_training_game/ui/flick_response_area.dart';

void main() {
  Future<List<FlickResponse>> pumpArea(
    WidgetTester tester, {
    bool enabled = true,
  }) async {
    final List<FlickResponse> responses = <FlickResponse>[];
    await tester.pumpWidget(
      MaterialApp(
        home: FlickResponseArea(
          enabled: enabled,
          onFlick: responses.add,
          child: const SizedBox.expand(),
        ),
      ),
    );
    return responses;
  }

  testWidgets('上フリックを 0°（縦縞）の回答として受け取る', (WidgetTester tester) async {
    final List<FlickResponse> responses = await pumpArea(tester);

    await tester.fling(
      find.byType(FlickResponseArea),
      const Offset(0, -120),
      800,
    );
    await tester.pumpAndSettle();

    expect(responses, hasLength(1));
    expect(responses.single.answer, GaborOrientation.deg0);
  });

  testWidgets('右下フリックを 135° の回答として受け取る', (WidgetTester tester) async {
    final List<FlickResponse> responses = await pumpArea(tester);

    await tester.fling(
      find.byType(FlickResponseArea),
      const Offset(120, 120),
      800,
    );
    await tester.pumpAndSettle();

    expect(responses, hasLength(1));
    expect(responses.single.answer, GaborOrientation.deg135);
  });

  testWidgets('1ジェスチャにつき通知は1回だけ', (WidgetTester tester) async {
    // 閾値を超えた時点で確定させる。その後に指を動かしても回答は変わらない。
    final List<FlickResponse> responses = await pumpArea(tester);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(FlickResponseArea)),
    );
    for (int i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(responses, hasLength(1));
    expect(responses.single.answer, GaborOrientation.deg0);
  });

  testWidgets('閾値に満たない動きでは回答しない', (WidgetTester tester) async {
    final List<FlickResponse> responses = await pumpArea(tester);

    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byType(FlickResponseArea)),
    );
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -8));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(responses, isEmpty);
  });

  testWidgets('受付外のフリックは無視する', (WidgetTester tester) async {
    // 回答受付ウィンドウの外では反応しない（仕様書 4.2）。
    final List<FlickResponse> responses = await pumpArea(tester, enabled: false);

    await tester.fling(
      find.byType(FlickResponseArea),
      const Offset(0, -120),
      800,
    );
    await tester.pumpAndSettle();

    expect(responses, isEmpty);
  });

  testWidgets('続けて2回フリックすれば2回とも受け取る', (WidgetTester tester) async {
    final List<FlickResponse> responses = await pumpArea(tester);

    await tester.fling(
      find.byType(FlickResponseArea),
      const Offset(0, -120),
      800,
    );
    await tester.pumpAndSettle();
    await tester.fling(
      find.byType(FlickResponseArea),
      const Offset(-120, 0),
      800,
    );
    await tester.pumpAndSettle();

    expect(responses, hasLength(2));
    expect(responses[0].answer, GaborOrientation.deg0);
    expect(responses[1].answer, GaborOrientation.deg90);
  });
}
