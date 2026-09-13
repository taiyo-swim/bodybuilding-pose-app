import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_training_game/core/presentation_timing.dart';
import 'package:visual_training_game/core/refresh_rate.dart';
import 'package:visual_training_game/stimulus/frame_presenter.dart';

/// テストのフレーム間隔。`tester.pump(_frame)` 1回で1フレーム進む。
const Duration _frame = Duration(microseconds: 16667);
const RefreshRate _hz60 = RefreshRate(60);

void main() {
  /// 表示側の再構築を記録する計測用ハーネス。
  ///
  /// 返るリストには「[FramePresenter] が表示側に通知したタイミングの可視状態」が
  /// 順に入る。毎フレームの状態ではない点に注意（提示中は通知しない設計のため）。
  Future<(FramePresenter, List<bool>)> pumpHarness(WidgetTester tester) async {
    late FramePresenter presenter;
    final List<bool> rebuilds = <bool>[];
    await tester.pumpWidget(
      _Harness(
        onReady: (FramePresenter p) => presenter = p,
        onBuild: rebuilds.add,
      ),
    );
    return (presenter, rebuilds);
  }

  testWidgets('要求したフレーム数だけ刺激を描き、実測msを返す', (WidgetTester tester) async {
    final (FramePresenter presenter, List<bool> _) = await pumpHarness(tester);
    presenter.start();

    final PresentationPlan plan = planPresentation(
      targetMs: 50,
      refreshRate: _hz60,
    );
    expect(plan.frames, 3);

    final Future<PresentationMeasurement> pending = presenter.present(plan);

    // 3フレーム提示 + 消すための1フレーム。
    for (int i = 0; i < 4; i++) {
      await tester.pump(_frame);
    }

    final PresentationMeasurement m = await pending;
    expect(m.framesRequested, 3);
    expect(m.framesShown, 3);
    expect(m.droppedFrames, isFalse);
    // 3フレーム × 16.667ms = 50.0ms
    expect(m.measuredMs, closeTo(50.0, 0.1));
    expect(m.withinOneFrame, isTrue);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('提示の前後だけ表示を切り替え、提示中は再構築しない', (WidgetTester tester) async {
    // 提示中に毎フレーム再構築すると、その負荷自体が提示タイミングを揺らす。
    // 表示の切り替えは「出す」「消す」の2回だけであるべき。
    final (FramePresenter presenter, List<bool> rebuilds) = await pumpHarness(
      tester,
    );
    presenter.start();

    final Future<PresentationMeasurement> pending = presenter.present(
      planPresentation(targetMs: 150, refreshRate: _hz60), // 9フレーム
    );
    rebuilds.clear();
    for (int i = 0; i < 12; i++) {
      await tester.pump(_frame);
    }
    await pending;

    expect(rebuilds, <bool>[true, false]);
    expect(presenter.isStimulusVisible, isFalse);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('最短提示は2フレーム（60Hz で約33ms）', (WidgetTester tester) async {
    final (FramePresenter presenter, List<bool> _) = await pumpHarness(tester);
    presenter.start();

    final Future<PresentationMeasurement> pending = presenter.present(
      planPresentation(targetMs: 33, refreshRate: _hz60),
    );
    for (int i = 0; i < 3; i++) {
      await tester.pump(_frame);
    }

    final PresentationMeasurement m = await pending;
    expect(m.framesShown, 2);
    expect(m.measuredMs, closeTo(33.3, 0.1));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'フレームが遅れたら ms_actual にそのまま現れる（推定値ではない）',
    (WidgetTester tester) async {
      // 仕様書 3.3「推定値ではなく実測を残すこと」。
      // フレーム数 × 公称フレーム時間で計算していたら、この遅延は見えなくなる。
      final (FramePresenter presenter, List<bool> _) = await pumpHarness(
        tester,
      );
      presenter.start();

      final Future<PresentationMeasurement> pending = presenter.present(
        planPresentation(targetMs: 50, refreshRate: _hz60),
      );

      await tester.pump(_frame); // 1フレーム目（提示開始）
      await tester.pump(_frame); // 2フレーム目
      await tester.pump(const Duration(milliseconds: 100)); // 描画が詰まった
      await tester.pump(_frame); // 消すフレーム

      final PresentationMeasurement m = await pending;
      expect(m.framesShown, 3);
      // 16.667 + 100 + 16.667 = 133.3ms。目標 50ms から大きく外れている。
      expect(m.measuredMs, closeTo(133.3, 0.5));
      expect(m.withinOneFrame, isFalse);
      expect(m.errorInFrames, greaterThan(4));

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('連続した提示が互いに干渉しない', (WidgetTester tester) async {
    final (FramePresenter presenter, List<bool> _) = await pumpHarness(tester);
    presenter.start();

    for (int trial = 0; trial < 3; trial++) {
      final Future<PresentationMeasurement> pending = presenter.present(
        planPresentation(targetMs: 33, refreshRate: _hz60),
      );
      for (int i = 0; i < 3; i++) {
        await tester.pump(_frame);
      }
      final PresentationMeasurement m = await pending;
      expect(m.framesShown, 2, reason: '試行 $trial');
      expect(m.measuredMs, closeTo(33.3, 0.1), reason: '試行 $trial');

      // 試行間のブランク。
      for (int i = 0; i < 10; i++) {
        await tester.pump(_frame);
      }
    }

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('リフレッシュレートを実測して記録する', (WidgetTester tester) async {
    final (FramePresenter presenter, List<bool> _) = await pumpHarness(tester);
    presenter.start();

    for (int i = 0; i < 60; i++) {
      await tester.pump(_frame);
    }
    expect(presenter.refreshRate.hz, closeTo(60, 0.5));
    expect(presenter.refreshRate.source, RefreshRateSource.measured);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('破棄されたら提示待ちはエラーで終わる', (WidgetTester tester) async {
    final (FramePresenter presenter, List<bool> _) = await pumpHarness(tester);
    presenter.start();

    final Future<PresentationMeasurement> pending = presenter.present(
      planPresentation(targetMs: 150, refreshRate: _hz60),
    );
    // 破棄より先にエラーハンドラを繋いでおく。
    // 繋ぐ前に completeError されると未処理の非同期エラーとして扱われる。
    final Future<void> expectation = expectLater(pending, throwsStateError);

    await tester.pump(_frame);
    await tester.pumpWidget(const SizedBox());

    await expectation;
  });
}

class _Harness extends StatefulWidget {
  const _Harness({required this.onReady, required this.onBuild});

  final void Function(FramePresenter) onReady;
  final void Function(bool visible) onBuild;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness>
    with SingleTickerProviderStateMixin {
  late final FramePresenter _presenter = FramePresenter(vsync: this);

  @override
  void initState() {
    super.initState();
    widget.onReady(_presenter);
  }

  @override
  void dispose() {
    _presenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _presenter,
    builder: (BuildContext context, Widget? child) {
      widget.onBuild(_presenter.isStimulusVisible);
      return const SizedBox.expand();
    },
  );
}
