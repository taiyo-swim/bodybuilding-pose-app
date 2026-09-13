import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 端末のリフレッシュレート。
///
/// 提示時間の内部表現をフレーム数にするため、起動時に取得する（仕様書 3.3）。
@immutable
class RefreshRate {
  const RefreshRate(this.hz, {this.source = RefreshRateSource.platform})
    : assert(hz > 0);

  final double hz;
  final RefreshRateSource source;

  /// 取得に失敗したときのフォールバック。
  ///
  /// 60Hz を仮定するのは安全側ではない（実機が 120Hz なら提示が半分になる）。
  /// [RefreshRateProbe] による実測で必ず補正すること。
  static const RefreshRate fallback = RefreshRate(
    60,
    source: RefreshRateSource.fallback,
  );

  double get frameMs => 1000.0 / hz;

  Duration get framePeriod =>
      Duration(microseconds: (1000000 / hz).round());

  /// プラットフォームから取得する。
  ///
  /// 取得できない、または明らかに異常な値の場合は [fallback] を返す。
  static RefreshRate fromPlatform() {
    try {
      final Iterable<ui.FlutterView> views =
          SchedulerBinding.instance.platformDispatcher.views;
      for (final ui.FlutterView view in views) {
        final double hz = view.display.refreshRate;
        // 一部プラットフォームは 0 や NaN を返す。24Hz 未満・1000Hz 超は異常値とみなす。
        if (hz.isFinite && hz >= 24 && hz <= 1000) {
          return RefreshRate(hz);
        }
      }
    } catch (_) {
      // ビューがまだ無い段階などでは例外になりうる。フォールバックで続行する。
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RefreshRate && other.hz == hz && other.source == source;

  @override
  int get hashCode => Object.hash(hz, source);

  @override
  String toString() =>
      '${hz.toStringAsFixed(2)}Hz (${frameMs.toStringAsFixed(2)}ms/frame, '
      '${source.name})';
}

enum RefreshRateSource {
  /// `Display.refreshRate` から取得した値。
  platform,

  /// 取得に失敗して 60Hz を仮定した値。
  fallback,

  /// フレーム間隔の実測から求めた値。
  measured,
}

/// フレーム間隔を実測してリフレッシュレートを求める。
///
/// プラットフォームの申告値は、可変リフレッシュレートや省電力モードで
/// 実際の描画間隔とずれることがある。試行ログに残す `refresh_hz` は
/// 推定ではなく実測であるべきなので（仕様書 3.3）、常時これを回して補正する。
class RefreshRateProbe {
  RefreshRateProbe({this.windowSize = 120}) : assert(windowSize > 1);

  /// 中央値を取る窓の大きさ（フレーム数）。
  final int windowSize;

  final List<double> _intervalsMs = <double>[];
  Duration? _previous;

  /// 十分な標本が溜まったか。
  bool get hasEnoughSamples => _intervalsMs.length >= windowSize ~/ 4;

  int get sampleCount => _intervalsMs.length;

  /// Ticker のコールバックから毎フレーム呼ぶ。
  void addFrameTimestamp(Duration timestamp) {
    final Duration? previous = _previous;
    _previous = timestamp;
    if (previous == null) return;

    final double deltaMs =
        (timestamp - previous).inMicroseconds / Duration.microsecondsPerMillisecond;
    // 1フレームぶんとして妥当な範囲だけ採る。
    // アプリの一時停止やGCで飛んだ間隔を混ぜると中央値が壊れる。
    if (deltaMs <= 0 || deltaMs > 60) return;

    _intervalsMs.add(deltaMs);
    if (_intervalsMs.length > windowSize) {
      _intervalsMs.removeAt(0);
    }
  }

  /// 実測値。標本が足りなければ null。
  ///
  /// 平均ではなく中央値を使う。取りこぼした1フレームが平均を大きく歪めるため。
  RefreshRate? estimate() {
    if (!hasEnoughSamples) return null;
    final List<double> sorted = List<double>.of(_intervalsMs)..sort();
    final double medianMs = sorted.length.isOdd
        ? sorted[sorted.length ~/ 2]
        : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
    if (medianMs <= 0) return null;
    return RefreshRate(1000.0 / medianMs, source: RefreshRateSource.measured);
  }

  void reset() {
    _intervalsMs.clear();
    _previous = null;
  }
}
