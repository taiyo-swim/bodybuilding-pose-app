import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 1ビートの発生。
@immutable
class BeatEvent {
  const BeatEvent({
    required this.index,
    required this.intended,
    required this.actual,
  });

  /// 0 始まりのビート番号。
  final int index;

  /// 本来このビートが来るはずだった時刻（クロック開始からの経過）。
  final Duration intended;

  /// 実際に検出した vsync の時刻。
  final Duration actual;

  /// 検出の遅れ（ms）。vsync 刻みで検出するので、最大でも1フレームぶん遅れる。
  double get detectionErrorMs =>
      (actual - intended).inMicroseconds / Duration.microsecondsPerMillisecond;

  /// 小節の頭か（4拍子の1拍目）。アクセント音を鳴らす判定に使う。
  bool get isDownbeat => index % 4 == 0;

  @override
  String toString() =>
      'BeatEvent(#$index, err: ${detectionErrorMs.toStringAsFixed(2)}ms)';
}

/// BPM 固定のビートクロック（仕様書 2.1 / 4.2）。
///
/// **BPM は 120 固定で、曲ごとに変えない。** 譜面データの構造が単純になり、
/// AI 生成側の指定も安定する（仕様書 2.1）。
///
/// 音楽はメトロノーム兼ペースメーカーであって、採点対象ではない（仕様書 4.2）。
/// タイミング精度を採点すると「見えていないのに勘で押す」方が高得点になり、
/// 訓練として壊れる。
///
/// Phase 1 ではこのクロックが master で、クリック音をこちらから鳴らす。
/// BGM が入る Phase 2 以降は、3分のセッションで音とクロックが離れていかないよう、
/// 再生位置に追従させる必要がある（[syncToAudioPosition] を参照）。
class BeatClock {
  BeatClock({required TickerProvider vsync, this.bpm = fixedBpm})
    : assert(bpm > 0) {
    _ticker = vsync.createTicker(_onTick);
  }

  /// 仕様書 2.1 で固定された BPM。
  static const int fixedBpm = 120;

  final int bpm;

  late final Ticker _ticker;
  final StreamController<BeatEvent> _beats =
      StreamController<BeatEvent>.broadcast();
  final ValueNotifier<double> _phase = ValueNotifier<double>(0);

  int _lastBeatIndex = -1;
  Duration _elapsed = Duration.zero;
  Duration _offset = Duration.zero;

  /// 1ビートの長さ。BPM120 なら 500ms。
  int get beatPeriodMicros => (60 * Duration.microsecondsPerSecond) ~/ bpm;

  Duration get beatPeriod => Duration(microseconds: beatPeriodMicros);

  /// ビートの発生。
  Stream<BeatEvent> get beats => _beats.stream;

  /// 現在のビート内の位相（0.0〜1.0）。固視点の脈打ちに使う。
  ValueListenable<double> get phase => _phase;

  /// 直近のビート番号。開始前は -1。
  int get beatIndex => _lastBeatIndex;

  /// クロック開始からの経過時間。
  Duration get elapsed => _elapsed;

  bool get isRunning => _ticker.isActive;

  void start() {
    if (_ticker.isActive) return;
    _lastBeatIndex = -1;
    _offset = Duration.zero;
    _ticker.start();
  }

  void stop() {
    if (!_ticker.isActive) return;
    _ticker.stop();
  }

  /// 次のビートを待つ。
  Future<BeatEvent> waitForNextBeat() => _beats.stream.first;

  /// [count] 拍ぶん待つ。
  Future<BeatEvent> waitForBeats(int count) {
    assert(count >= 1);
    return _beats.stream.take(count).last;
  }

  /// BGM の再生位置にクロックを合わせる。
  ///
  /// TODO(Phase 2): BGM が入ったら、曲の再生位置を master にしてここで補正する。
  /// vsync クロックと音の再生速度はわずかに違うので、3分のセッションでは
  /// 補正しないと数十ms ずれる。Phase 1 はクリック音をこちらから鳴らすため不要。
  void syncToAudioPosition(Duration audioPosition) {
    _offset = _elapsed - audioPosition;
  }

  /// [syncToAudioPosition] で入った補正量。
  Duration get audioSyncOffset => _offset;

  void _onTick(Duration timestamp) {
    _elapsed = timestamp;
    final int micros = timestamp.inMicroseconds;
    final int index = micros ~/ beatPeriodMicros;

    _phase.value = (micros % beatPeriodMicros) / beatPeriodMicros;

    if (index <= _lastBeatIndex) return;

    // フレーム落ちで複数ビートをまたいだ場合、最後の1つだけ出す。
    // 取りこぼしたビートに合わせて刺激をまとめて出しても意味がない。
    _lastBeatIndex = index;
    _beats.add(
      BeatEvent(
        index: index,
        intended: Duration(microseconds: index * beatPeriodMicros),
        actual: timestamp,
      ),
    );
  }

  void dispose() {
    _ticker.dispose();
    _phase.dispose();
    unawaited(_beats.close());
  }
}
