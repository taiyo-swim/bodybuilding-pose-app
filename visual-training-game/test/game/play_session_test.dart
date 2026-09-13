import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_training_game/core/viewing_geometry.dart';
import 'package:visual_training_game/data/database.dart';
import 'package:visual_training_game/data/session_recorder.dart';
import 'package:visual_training_game/game/beat_clock.dart';
import 'package:visual_training_game/game/flick.dart';
import 'package:visual_training_game/game/play_session.dart';
import 'package:visual_training_game/game/staircase.dart';
import 'package:visual_training_game/stimulus/frame_presenter.dart';
import 'package:visual_training_game/stimulus/orientation.dart';

const Duration _frame = Duration(microseconds: 16667);
const ViewingGeometry _geometry = ViewingGeometry(logicalPixelsPerInch: 160);

/// どう回答するか。
enum _Answering { correct, wrong, none }

void main() {
  late BeatClock clock;
  late FramePresenter presenter;

  Future<void> pumpHarness(WidgetTester tester) async {
    await tester.pumpWidget(
      _Harness(
        onReady: (BeatClock c, FramePresenter p) {
          clock = c;
          presenter = p;
        },
      ),
    );
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    presenter.start();
    clock.start();
    await tester.pump(_frame); // 拍 0 を消化する
  }

  /// セッションが終わるまでフレームを送る。
  ///
  /// 回答受付に入ったら [answering] に従って1回だけフリックを送る。
  /// [maxFrames] は保険。フレーム数を決め打ちにすると、
  /// タイミングを少し変えただけでテストがハングする。
  Future<void> runUntilFinished(
    WidgetTester tester,
    PlaySession session, {
    _Answering answering = _Answering.correct,
    int maxFrames = 900,
  }) async {
    bool answeredThisTrial = false;
    for (int i = 0; i < maxFrames && session.isRunning; i++) {
      await tester.pump(_frame);
      if (!session.isAcceptingResponse) {
        answeredThisTrial = false;
        continue;
      }
      if (answeredThisTrial || answering == _Answering.none) continue;

      final GaborOrientation shown = session.currentParams!.orientation;
      final GaborOrientation answer = answering == _Answering.correct
          ? shown
          : GaborOrientation.values[(shown.index + 1) % 4];
      session.submitResponse(FlickJudge.evaluate(answer.stripeAxis * 100)!);
      answeredThisTrial = true;
    }
    expect(
      session.isRunning,
      isFalse,
      reason: '$maxFrames フレーム以内にセッションが終わらなかった',
    );
  }

  testWidgets('1試行は3拍で、4秒のセッションで3試行回る', (WidgetTester tester) async {
    // 拍 1 が固視点、拍 2 が提示と回答受付、拍 3 が締切。次の固視点は拍 4。
    // BPM120 なので 1試行 1.5秒。次の固視点の拍まで待ってから残り時間を見るので、
    // 4秒のセッションでは拍 1 / 4 / 7 の3試行が回る。
    await pumpHarness(tester);
    final PlaySession session = PlaySession(
      clock: clock,
      presenter: presenter,
      geometry: _geometry,
      seed: 1,
      sessionDuration: const Duration(seconds: 4),
    );
    addTearDown(session.dispose);

    final Future<void> running = session.run();
    await runUntilFinished(tester, session);
    await running;

    expect(PlaySession.beatsPerTrial, 3);
    expect(session.trialCount, 3);
    expect(session.phase, TrialPhase.finished);
    expect(session.isRunning, isFalse);
  });

  testWidgets('コアループの順序は 固視点 → 提示 → 回答 → フィードバック', (
    WidgetTester tester,
  ) async {
    await pumpHarness(tester);
    final PlaySession session = PlaySession(
      clock: clock,
      presenter: presenter,
      geometry: _geometry,
      seed: 2,
      sessionDuration: const Duration(milliseconds: 2200),
    );
    addTearDown(session.dispose);

    final List<TrialPhase> phases = <TrialPhase>[];
    session.addListener(() => phases.add(session.phase));

    final Future<void> running = session.run();
    await runUntilFinished(tester, session);
    await running;

    expect(phases.take(4), <TrialPhase>[
      TrialPhase.fixation,
      TrialPhase.stimulus,
      TrialPhase.response,
      TrialPhase.feedback,
    ]);
  });

  testWidgets('全問正解ならコンボが伸び、スコアが入る', (WidgetTester tester) async {
    await pumpHarness(tester);
    final PlaySession session = PlaySession(
      clock: clock,
      presenter: presenter,
      geometry: _geometry,
      seed: 3,
      sessionDuration: const Duration(seconds: 4),
    );
    addTearDown(session.dispose);

    final Future<void> running = session.run();
    await runUntilFinished(tester, session);
    await running;

    expect(session.correctCount, session.trialCount);
    expect(session.combo, session.trialCount);
    expect(session.bestCombo, session.trialCount);
    expect(session.score, greaterThan(0));
    expect(session.lastOutcome?.correct, isTrue);
  });

  testWidgets('3連続正解でコントラストが難化する（仕様書 4.3）', (WidgetTester tester) async {
    await pumpHarness(tester);
    final Staircase staircase = Staircase(initialContrast: 0.30);
    final PlaySession session = PlaySession(
      clock: clock,
      presenter: presenter,
      geometry: _geometry,
      seed: 4,
      staircase: staircase,
      sessionDuration: const Duration(seconds: 4),
    );
    addTearDown(session.dispose);

    final Future<void> running = session.run();
    await runUntilFinished(tester, session);
    await running;

    expect(session.trialCount, 3);
    expect(staircase.contrast, closeTo(0.30 * Staircase.stepFactor, 1e-12));
  });

  testWidgets('無回答は不正解になり、コンボが切れる', (WidgetTester tester) async {
    // 回答受付はビート丸ごと。過ぎたら不正解（仕様書 4.2）。
    await pumpHarness(tester);
    final PlaySession session = PlaySession(
      clock: clock,
      presenter: presenter,
      geometry: _geometry,
      seed: 5,
      sessionDuration: const Duration(seconds: 4),
    );
    addTearDown(session.dispose);

    final Future<void> running = session.run();
    await runUntilFinished(tester, session, answering: _Answering.none);
    await running;

    expect(session.trialCount, greaterThan(0));
    expect(session.correctCount, 0);
    expect(session.combo, 0);
    expect(session.score, 0);
    expect(session.lastOutcome?.isTimeout, isTrue);
  });

  testWidgets('誤答でコンボが 0 に戻る', (WidgetTester tester) async {
    await pumpHarness(tester);
    final PlaySession session = PlaySession(
      clock: clock,
      presenter: presenter,
      geometry: _geometry,
      seed: 6,
      sessionDuration: const Duration(seconds: 4),
    );
    addTearDown(session.dispose);

    final Future<void> running = session.run();
    await runUntilFinished(tester, session, answering: _Answering.wrong);
    await running;

    expect(session.correctCount, 0);
    expect(session.combo, 0);
    expect(session.lastOutcome?.isTimeout, isFalse);
    expect(session.lastOutcome?.correct, isFalse);
  });

  testWidgets('受付ウィンドウ外のフリックは無視する', (WidgetTester tester) async {
    await pumpHarness(tester);
    final PlaySession session = PlaySession(
      clock: clock,
      presenter: presenter,
      geometry: _geometry,
      seed: 7,
      sessionDuration: const Duration(milliseconds: 2200),
    );
    addTearDown(session.dispose);

    final Future<void> running = session.run();

    // 固視点の間にフリックしても回答にならない。
    for (int i = 0; i < 900 && session.isRunning; i++) {
      await tester.pump(_frame);
      if (session.phase == TrialPhase.fixation) {
        session.submitResponse(
          FlickJudge.evaluate(GaborOrientation.deg0.stripeAxis * 100)!,
        );
      }
    }
    await running;

    expect(session.correctCount, 0);
    expect(session.lastOutcome?.isTimeout, isTrue);
  });

  testWidgets('stop() でループを抜ける', (WidgetTester tester) async {
    await pumpHarness(tester);
    final PlaySession session = PlaySession(
      clock: clock,
      presenter: presenter,
      geometry: _geometry,
      seed: 8,
      sessionDuration: const Duration(minutes: 3),
    );
    addTearDown(session.dispose);

    final Future<void> running = session.run();
    for (int i = 0; i < 60; i++) {
      await tester.pump(_frame);
    }
    expect(session.isRunning, isTrue);

    session.stop();
    // 停止してもフレームは送り続ける。提示中だった場合、
    // 残りのフレームを描かないと present() が解決しない。
    // isRunning は stop() の時点で false になるので、ここでは条件にできない。
    for (int i = 0; i < 60; i++) {
      await tester.pump(_frame);
    }
    await running;

    expect(session.isRunning, isFalse);
    expect(session.phase, TrialPhase.finished);
  });

  testWidgets('試行ログが DB に残る', (WidgetTester tester) async {
    await pumpHarness(tester);
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final PlaySession session = await PlaySession.begin(
      clock: clock,
      presenter: presenter,
      geometry: _geometry,
      recorder: SessionRecorder(db),
      seed: 999,
      deviceBrightness: 0.7,
      sessionDuration: const Duration(seconds: 4),
    );
    addTearDown(session.dispose);

    final Future<void> running = session.run();
    await runUntilFinished(tester, session);
    await running;

    final List<SessionRow> sessions = await db.recentSessions();
    expect(sessions, hasLength(1));
    expect(sessions.single.seed, 999);
    expect(sessions.single.nTrials, session.trialCount);
    expect(sessions.single.score, session.score);
    // 閾値は未決事項B が決まるまで書かない。
    expect(sessions.single.thresholdContrast, isNull);

    final List<TrialRow> trials = await db.trialsOf(sessions.single.id);
    expect(trials, hasLength(session.trialCount));
    for (final TrialRow trial in trials) {
      expect(trial.correct, isTrue);
      expect(trial.rtMs, isNotNull);
      // 150ms 目標 → 60Hz なら 9フレーム。実測は ±1フレーム以内であること。
      expect(trial.framesRequested, 9);
      expect(trial.msActual, closeTo(150, 16.7));
      expect(trial.refreshHz, closeTo(60, 1));
    }
  });

  testWidgets('同じシードなら同じ刺激列になる（仕様書 6 のデイリー用）', (
    WidgetTester tester,
  ) async {
    Future<List<GaborOrientation>> orientationsFor(int seed) async {
      final PlaySession session = PlaySession(
        clock: clock,
        presenter: presenter,
        geometry: _geometry,
        seed: seed,
        sessionDuration: const Duration(seconds: 4),
      );
      final List<GaborOrientation> seen = <GaborOrientation>[];
      session.addListener(() {
        if (session.phase == TrialPhase.stimulus) {
          seen.add(session.currentParams!.orientation);
        }
      });
      final Future<void> running = session.run();
      await runUntilFinished(tester, session);
      await running;
      session.dispose();
      return seen;
    }

    await pumpHarness(tester);
    final List<GaborOrientation> first = await orientationsFor(42);
    final List<GaborOrientation> second = await orientationsFor(42);
    final List<GaborOrientation> other = await orientationsFor(43);

    expect(first, isNotEmpty);
    expect(second, first);
    expect(other, isNot(first));
  });
}

class _Harness extends StatefulWidget {
  const _Harness({required this.onReady});

  final void Function(BeatClock, FramePresenter) onReady;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> with TickerProviderStateMixin {
  late final BeatClock _clock = BeatClock(vsync: this);
  late final FramePresenter _presenter = FramePresenter(vsync: this);

  @override
  void initState() {
    super.initState();
    widget.onReady(_clock, _presenter);
  }

  @override
  void dispose() {
    _clock.stop();
    _clock.dispose();
    _presenter.stop();
    _presenter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _presenter,
    builder: (BuildContext context, Widget? child) => const SizedBox.expand(),
  );
}
