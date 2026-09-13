import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/presentation_timing.dart';
import '../core/viewing_geometry.dart';
import '../data/session_recorder.dart';
import '../data/tables.dart';
import '../stimulus/frame_presenter.dart';
import '../stimulus/gabor_params.dart';
import '../stimulus/orientation.dart';
import 'beat_clock.dart';
import 'flick.dart';
import 'staircase.dart';

/// 1試行の中のどこにいるか（仕様書 4 のコアループ）。
enum TrialPhase {
  /// セッション開始前。
  idle,

  /// 固視点。ビートに同期して脈打つ。
  fixation,

  /// ガボール提示中。
  stimulus,

  /// 回答受付中。
  response,

  /// 正誤フィードバック。
  feedback,

  /// セッション終了。
  finished,
}

/// 直前の試行の結果。フィードバック表示に使う。
@immutable
class TrialOutcome {
  const TrialOutcome({
    required this.correct,
    required this.stimulus,
    required this.response,
    required this.rtMs,
    required this.scoreGained,
  });

  final bool correct;
  final GaborOrientation stimulus;

  /// 無回答なら null。
  final FlickResponse? response;

  /// 反応時間（ms）。無回答なら null。
  final int? rtMs;

  final int scoreGained;

  bool get isTimeout => response == null;
}

/// コアループ（仕様書 4）。
///
/// ```
/// 固視点（ビートに同期して脈打つ） 約450ms
///   ↓
/// ガボールを N フレーム提示
///   ↓
/// （マスク条件のとき）ISI → 後続マスク        ← Phase 1 では無し
///   ↓
/// 回答受付: 縞の軸方向へのフリック
///   ↓
/// 正誤フィードバック → 次のビートへ
/// ```
///
/// **タイミング精度は採点しない**（仕様書 4.2）。判定は正誤のみで、
/// 音楽はメトロノーム兼ペースメーカーとして使う。
class PlaySession extends ChangeNotifier {
  PlaySession({
    required this.clock,
    required this.presenter,
    required this.geometry,
    required this.seed,
    this.recorder,
    Staircase? staircase,
    this.sessionDuration = defaultSessionDuration,
    this.targetPresentationMs = defaultTargetPresentationMs,
    this.wavelengthArcmin = GaborParams.defaultWavelengthArcmin,
  }) : _random = math.Random(seed),
       staircase = staircase ?? Staircase();

  /// 1セッションは3分で強制終了（仕様書 7）。「もっとやりたい」で終わらせる。
  static const Duration defaultSessionDuration = Duration(minutes: 3);

  /// 1試行が占めるビート数。
  ///
  /// 仕様書 4 のコアループ図から導いた値であって、仕様書に数値の指定はない。
  /// 固視点で1拍、提示と回答受付で1拍（仕様書 4.2「回答受付はビート丸ごと」）、
  /// フィードバックで1拍。BPM120 なら 1試行 1.5秒、3分で約120試行になる。
  static const int beatsPerTrial = 3;

  /// Phase 1 の提示時間。
  ///
  /// 処理速度の軸は「コントラスト8%を安定通過」で解放されるため（仕様書 5.3）、
  /// それまでは最も易しい段階に固定する。
  static const double defaultTargetPresentationMs = 150;

  /// 正解1回の基礎点。仕様書に指定がないので実装側で決めた値。
  static const int baseScorePerCorrect = 100;

  /// 速度ボーナスの最大倍率。
  ///
  /// 速く答えるとスコア倍率が上がる（仕様書 4.2）。**精度ボーナスではない。**
  /// タイミングを採点対象にすると「見えていないのに勘で押す」方が高得点になる。
  static const double maxSpeedMultiplier = 2.0;

  /// コンボ1つあたりの倍率の伸び。
  static const double comboMultiplierStep = 0.02;

  /// コンボ倍率の上限に達するコンボ数。
  static const int comboMultiplierCap = 50;

  final BeatClock clock;
  final FramePresenter presenter;
  final ViewingGeometry geometry;
  final SessionRecorder? recorder;

  /// 刺激列を再現するためのシード。デイリーチャレンジではサーバーが配る（仕様書 6）。
  final int seed;

  final math.Random _random;

  /// 内部難易度。**UI に数値として出さないこと**（仕様書 4.3 / 5.1）。
  final Staircase staircase;

  final Duration sessionDuration;
  final double targetPresentationMs;
  final double wavelengthArcmin;

  TrialPhase _phase = TrialPhase.idle;
  GaborParams? _currentParams;
  TrialOutcome? _lastOutcome;
  Completer<FlickResponse>? _responseCompleter;
  Completer<void>? _stopSignal;
  bool _running = false;
  int _trialCount = 0;
  int _correctCount = 0;
  int _combo = 0;
  int _bestCombo = 0;
  int _score = 0;

  TrialPhase get phase => _phase;

  /// 今提示している（またはこれから提示する）刺激。
  GaborParams? get currentParams => _currentParams;

  TrialOutcome? get lastOutcome => _lastOutcome;

  bool get isAcceptingResponse => _phase == TrialPhase.response;

  bool get isRunning => _running;

  int get trialCount => _trialCount;

  int get correctCount => _correctCount;

  int get combo => _combo;

  int get bestCombo => _bestCombo;

  int get score => _score;

  /// コンボに応じた音のレイヤー数（0〜3）。
  ///
  /// コンボが繋がると音のレイヤーが増え、ミスで抜ける（仕様書 4.2）。
  /// TODO(Phase 2): BGM のステムが揃ったらここを実際のミキサーに繋ぐ。
  /// メトロノームで進めている間は表示にしか使わない（仕様書 2.1）。
  int get comboLayer => switch (_combo) {
    < 5 => 0,
    < 15 => 1,
    < 30 => 2,
    _ => 3,
  };

  /// セッションを回す。[sessionDuration] 経過で自ら止まる。
  Future<void> run() async {
    if (_running) throw StateError('セッションが既に走っている');
    _running = true;
    _stopSignal = Completer<void>();

    final Duration deadline = clock.elapsed + sessionDuration;

    try {
      BeatEvent? fixationBeat = await _awaitBeatOrStop(clock.beatIndex + 1);

      while (_running && fixationBeat != null && clock.elapsed < deadline) {
        await _runTrial(fixationBeat);
        if (!_running) break;
        fixationBeat = await _awaitBeatOrStop(
          fixationBeat.index + beatsPerTrial,
        );
      }
    } finally {
      _running = false;
      _responseCompleter = null;
      _setPhase(TrialPhase.finished);
      await recorder?.end(score: _score);
    }
  }

  /// セッションを途中で止める。
  ///
  /// ビート待ちを起こしてループを抜けさせる。これをしないと、
  /// クロックを止めた場合に待ち続けたままになる。
  void stop() {
    _running = false;
    final Completer<void>? signal = _stopSignal;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  /// 回答が来た。受付中でなければ無視する。
  void submitResponse(FlickResponse response) {
    if (!isAcceptingResponse) return;
    final Completer<FlickResponse>? completer = _responseCompleter;
    if (completer == null || completer.isCompleted) return;
    completer.complete(response);
  }

  Future<void> _runTrial(BeatEvent fixationBeat) async {
    // --- 固視点 ---
    _setPhase(TrialPhase.fixation);
    _lastOutcome = null;

    final GaborParams params = GaborParams(
      contrast: staircase.contrast,
      wavelengthArcmin: wavelengthArcmin,
      orientation: GaborOrientation.random(_random),
    );
    _currentParams = params;

    // --- 提示 ---
    if (await _awaitBeatOrStop(fixationBeat.index + 1) == null) return;

    _setPhase(TrialPhase.stimulus);
    final PresentationPlan plan = planPresentation(
      targetMs: targetPresentationMs,
      refreshRate: presenter.refreshRate,
    );
    final PresentationMeasurement measurement;
    try {
      measurement = await presenter.present(plan);
    } catch (error) {
      // 提示中に FramePresenter が止められた（画面を離れたなど）。
      // 中断した試行は記録しない。中途半端な ms_actual を残すほうが害になる。
      if (!_running) return;
      rethrow;
    }
    if (!_running) return;

    // --- 回答受付（ビート丸ごと、仕様書 4.2）---
    final Stopwatch stopwatch = Stopwatch()..start();
    final Completer<FlickResponse> completer = Completer<FlickResponse>();
    _responseCompleter = completer;
    _setPhase(TrialPhase.response);

    final Future<BeatEvent?> deadline = _awaitBeatOrStop(
      fixationBeat.index + 2,
    );
    final Object? first = await Future.any(<Future<Object?>>[
      completer.future,
      deadline,
    ]);

    final FlickResponse? response = first is FlickResponse ? first : null;
    final int? rtMs = response == null ? null : stopwatch.elapsedMilliseconds;
    stopwatch.stop();
    _responseCompleter = null;

    // --- フィードバック ---
    final bool correct = response?.isCorrectFor(params.orientation) ?? false;
    final int gained = _applyOutcome(correct: correct, rtMs: rtMs);

    _lastOutcome = TrialOutcome(
      correct: correct,
      stimulus: params.orientation,
      response: response,
      rtMs: rtMs,
      scoreGained: gained,
    );
    _trialCount++;
    _setPhase(TrialPhase.feedback);

    staircase.record(correct: correct);

    await recorder?.recordTrial(
      params: params,
      geometry: geometry,
      measurement: measurement,
      response: response,
      rtMs: rtMs,
    );

    // 回答が早かった場合、締切のビートまで待ってから次に進む。
    // 待たないと試行の間隔がばらつき、ペースメーカーとして機能しなくなる。
    await deadline;
  }

  int _applyOutcome({required bool correct, required int? rtMs}) {
    if (!correct) {
      _combo = 0;
      return 0;
    }

    _correctCount++;
    _combo++;
    if (_combo > _bestCombo) _bestCombo = _combo;

    final double speedMultiplier = _speedMultiplier(rtMs);
    final double comboMultiplier =
        1 +
        comboMultiplierStep * math.min(_combo, comboMultiplierCap);
    final int gained =
        (baseScorePerCorrect * speedMultiplier * comboMultiplier).round();
    _score += gained;
    return gained;
  }

  /// 速度ボーナス（仕様書 4.2）。受付ウィンドウのどこで答えたかで決まる。
  double _speedMultiplier(int? rtMs) {
    if (rtMs == null) return 1.0;
    final double windowMs = clock.beatPeriod.inMicroseconds /
        Duration.microsecondsPerMillisecond;
    final double remaining = (1 - rtMs / windowMs).clamp(0.0, 1.0);
    return 1.0 + (maxSpeedMultiplier - 1.0) * remaining;
  }

  /// [index] 以降のビートを待つ。[stop] が呼ばれたら null を返す。
  Future<BeatEvent?> _awaitBeatOrStop(int index) async {
    final Completer<void>? signal = _stopSignal;
    final Future<BeatEvent> beat = _beatAtLeast(index);
    if (signal == null) return beat;

    final Object? result = await Future.any(<Future<Object?>>[
      beat,
      signal.future,
    ]);
    return result is BeatEvent ? result : null;
  }

  Future<BeatEvent> _beatAtLeast(int index) {
    if (clock.beatIndex >= index) {
      // フレーム落ちや DB 書き込みの遅れで既に過ぎている。次のビートに乗り直す。
      return clock.waitForNextBeat();
    }
    return clock.beats.firstWhere((BeatEvent beat) => beat.index >= index);
  }

  void _setPhase(TrialPhase phase) {
    if (_phase == phase) return;
    _phase = phase;
    notifyListeners();
  }

  /// セッションを開始し、記録も始める。
  static Future<PlaySession> begin({
    required BeatClock clock,
    required FramePresenter presenter,
    required ViewingGeometry geometry,
    SessionRecorder? recorder,
    int? seed,
    double? deviceBrightness,
    Duration? sessionDuration,
  }) async {
    final int effectiveSeed =
        seed ?? DateTime.now().microsecondsSinceEpoch & 0x7fffffff;

    await recorder?.begin(
      mode: SessionMode.game,
      seed: effectiveSeed,
      geometry: geometry,
      deviceBrightness: deviceBrightness,
    );

    return PlaySession(
      clock: clock,
      presenter: presenter,
      geometry: geometry,
      seed: effectiveSeed,
      recorder: recorder,
      sessionDuration: sessionDuration ?? defaultSessionDuration,
    );
  }
}
