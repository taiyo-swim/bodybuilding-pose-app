import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../core/presentation_timing.dart';
import '../core/refresh_rate.dart';

/// 1回の提示の実測結果。試行ログの `frames_requested` / `ms_actual` / `refresh_hz`
/// はここから作る（仕様書 8）。
@immutable
class PresentationMeasurement {
  const PresentationMeasurement({
    required this.targetMs,
    required this.framesRequested,
    required this.framesShown,
    required this.measuredMs,
    required this.refreshHz,
  });

  final double targetMs;
  final int framesRequested;
  final int framesShown;

  /// **実測**の提示時間（ms）。
  ///
  /// 刺激を出したフレームの vsync タイムスタンプと、それを消したフレームの
  /// タイムスタンプの差。フレーム数 × 公称フレーム時間ではない。
  ///
  /// vsync コールバックの時刻は「フレームの生成開始」であって実際の点灯時刻ではないが、
  /// パイプラインの遅延は一定なので、差分としては正しい値になる。
  final double measuredMs;

  /// 実測のリフレッシュレート。
  final double refreshHz;

  double get frameMs => 1000.0 / refreshHz;

  /// 目標とのずれをフレーム数で表したもの。
  double get errorInFrames => (measuredMs - targetMs) / frameMs;

  /// Phase 1 の完了条件（仕様書 11）。
  ///
  /// 「試行ログの `ms_actual` が目標値の ±1フレーム以内に収まっていること」
  bool get withinOneFrame => errorInFrames.abs() <= 1.0;

  /// 要求したフレーム数だけ実際に描けたか。
  bool get droppedFrames => framesShown != framesRequested;

  @override
  String toString() =>
      'PresentationMeasurement(target: ${targetMs.toStringAsFixed(1)}ms, '
      'frames: $framesShown/$framesRequested, '
      'actual: ${measuredMs.toStringAsFixed(2)}ms, '
      '${refreshHz.toStringAsFixed(1)}Hz, '
      'err: ${errorInFrames.toStringAsFixed(2)} frames)';
}

/// 刺激をフレーム単位で提示する（仕様書 3.3）。
///
/// `Timer` や `Future.delayed` でミリ秒を待つ実装にしてはいけない。
/// タイマーの解像度は vsync に揃わないので、提示が1フレーム伸び縮みする。
///
/// 使い方:
/// ```dart
/// presenter.start();                       // vsync の購読を始める
/// final m = await presenter.present(plan); // plan.frames だけ提示して実測を返す
/// ```
/// 表示側は [isStimulusVisible] を監視して刺激と背景を切り替える。
class FramePresenter extends ChangeNotifier {
  FramePresenter({required TickerProvider vsync, RefreshRateProbe? probe})
    : _probe = probe ?? RefreshRateProbe() {
    _ticker = vsync.createTicker(_onTick);
  }

  late final Ticker _ticker;
  final RefreshRateProbe _probe;

  bool _visible = false;
  _PendingPresentation? _pending;
  int _framesShown = 0;
  Duration? _onset;

  /// 刺激を描くべきか。ウィジェットはこれを見て切り替える。
  bool get isStimulusVisible => _visible;

  /// 提示中か。
  bool get isPresenting => _pending != null;

  /// 実測のリフレッシュレート。標本が溜まるまではプラットフォーム申告値を返す。
  RefreshRate get refreshRate => _probe.estimate() ?? _platformRefreshRate;

  RefreshRate _platformRefreshRate = RefreshRate.fallback;

  /// vsync の購読を始める。リフレッシュレートの実測もここから始まる。
  void start() {
    if (_ticker.isActive) return;
    _platformRefreshRate = RefreshRate.fromPlatform();
    _probe.reset();
    _ticker.start();
  }

  void stop() {
    if (!_ticker.isActive) return;
    _ticker.stop();
    _abortPending(StateError('提示中に FramePresenter が停止した'));
    if (_visible) {
      _visible = false;
      notifyListeners();
    }
  }

  /// [plan] のフレーム数だけ刺激を提示し、実測結果を返す。
  Future<PresentationMeasurement> present(PresentationPlan plan) {
    assert(_ticker.isActive, 'start() を呼んでから present() すること');
    assert(_pending == null, '提示が重なっている');

    final _PendingPresentation pending = _PendingPresentation(plan);
    _pending = pending;
    _framesShown = 0;
    _onset = null;
    return pending.completer.future;
  }

  void _onTick(Duration elapsed) {
    _probe.addFrameTimestamp(elapsed);

    final _PendingPresentation? pending = _pending;
    if (pending == null) return;

    // 1フレーム目: このフレームから刺激を描く。
    if (_framesShown == 0) {
      _visible = true;
      _onset = elapsed;
      _framesShown = 1;
      notifyListeners();
      return;
    }

    // 2フレーム目以降: 既に可視なので再描画は不要。数えるだけ。
    if (_framesShown < pending.plan.frames) {
      _framesShown++;
      return;
    }

    // 規定フレーム数を描き終えた。このフレームで消す。
    // 提示時間は「出したフレームの時刻」から「消したフレームの時刻」までの差。
    final Duration onset = _onset!;
    _visible = false;
    _pending = null;
    notifyListeners();

    pending.completer.complete(
      PresentationMeasurement(
        targetMs: pending.plan.targetMs,
        framesRequested: pending.plan.frames,
        framesShown: _framesShown,
        measuredMs:
            (elapsed - onset).inMicroseconds /
            Duration.microsecondsPerMillisecond,
        refreshHz: refreshRate.hz,
      ),
    );
  }

  void _abortPending(Object error) {
    final _PendingPresentation? pending = _pending;
    if (pending == null) return;
    _pending = null;
    pending.completer.completeError(error);
  }

  @override
  void dispose() {
    _abortPending(StateError('提示中に FramePresenter が破棄された'));
    _ticker.dispose();
    super.dispose();
  }
}

class _PendingPresentation {
  _PendingPresentation(this.plan);

  final PresentationPlan plan;
  final Completer<PresentationMeasurement> completer =
      Completer<PresentationMeasurement>();
}
