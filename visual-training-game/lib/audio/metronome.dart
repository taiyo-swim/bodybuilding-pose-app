import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../game/beat_clock.dart';

/// クリック音のメトロノーム（仕様書 2.1 / 11-6）。
///
/// BGM が未完成の間はこれで開発を進めてよい。音声同期の検証もこれで実施できる。
///
/// 1つの [AudioPlayer] を鳴らし直すと前の音が切れるので、プレイヤーを数個持ち回す。
/// BPM120 では 500ms 間隔だが、クリック自体は 25ms なので2〜3個あれば足りる。
class Metronome {
  Metronome({this.poolSize = 3}) : assert(poolSize >= 2);

  static const String clickAsset = 'assets/audio/metronome/click.wav';
  static const String accentAsset = 'assets/audio/metronome/click_accent.wav';

  final int poolSize;

  final List<AudioPlayer> _clickPool = <AudioPlayer>[];
  final List<AudioPlayer> _accentPool = <AudioPlayer>[];
  int _clickCursor = 0;
  int _accentCursor = 0;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// 音源を先読みする。ビートが始まる前に必ず呼ぶこと。
  ///
  /// 鳴らす直前に読み込むと、最初の数拍が遅れる。
  Future<void> load() async {
    if (_loaded) return;
    await Future.wait(<Future<void>>[
      _fill(_clickPool, clickAsset),
      _fill(_accentPool, accentAsset),
    ]);
    _loaded = true;
  }

  Future<void> _fill(List<AudioPlayer> pool, String asset) async {
    for (int i = 0; i < poolSize; i++) {
      final AudioPlayer player = AudioPlayer();
      await player.setAsset(asset);
      pool.add(player);
    }
  }

  /// 1拍鳴らす。呼び出しをブロックしない。
  ///
  /// 戻り値は「再生命令を出し終えるまで」の Future であって、
  /// 実際に音が出るまでではない。出力遅延は [MetronomeDispatchLog] を参照。
  Future<void> tick({required bool accent}) {
    if (!_loaded) {
      throw StateError('load() を呼んでから tick() すること');
    }
    final List<AudioPlayer> pool = accent ? _accentPool : _clickPool;
    final int index = accent
        ? (_accentCursor = (_accentCursor + 1) % pool.length)
        : (_clickCursor = (_clickCursor + 1) % pool.length);
    final AudioPlayer player = pool[index];
    return player.seek(Duration.zero).then((_) => player.play());
  }

  Future<void> dispose() async {
    await Future.wait(<Future<void>>[
      for (final AudioPlayer player in <AudioPlayer>[
        ..._clickPool,
        ..._accentPool,
      ])
        player.dispose(),
    ]);
    _clickPool.clear();
    _accentPool.clear();
    _loaded = false;
  }
}

/// メトロノームの発音命令がどれだけ遅れて出せたかの記録（仕様書 11-6）。
///
/// **これは音響的な出力遅延ではない。** 測れるのは
/// 「ビートを検出してから再生命令を出し終えるまで」であって、
/// 端末のオーディオ出力バッファぶんの遅れは含まれない。
///
/// 仕様書 11-6 が求める「音声とビートのずれ」を実機で出すには、
/// 別の端末で録音して画面の点滅と波形を突き合わせるなど、外部の測定が要る。
/// ここで出せるのは、その測定の前提になるソフトウェア側のばらつきだけ。
class MetronomeDispatchLog {
  MetronomeDispatchLog({this.capacity = 240});

  final int capacity;
  final List<double> _samplesMs = <double>[];

  int get sampleCount => _samplesMs.length;

  /// 1拍ぶんの記録を足す。
  ///
  /// [beat] のビート検出時刻から、再生命令が返るまでの経過を [dispatchedAfter] に渡す。
  void add(BeatEvent beat, Duration dispatchedAfter) {
    final double totalMs =
        beat.detectionErrorMs +
        dispatchedAfter.inMicroseconds / Duration.microsecondsPerMillisecond;
    _samplesMs.add(totalMs);
    if (_samplesMs.length > capacity) {
      _samplesMs.removeAt(0);
    }
  }

  /// 平均遅れ（ms）。
  double? get meanMs => _samplesMs.isEmpty
      ? null
      : _samplesMs.reduce((double a, double b) => a + b) / _samplesMs.length;

  /// 最大遅れ（ms）。
  double? get maxMs => _samplesMs.isEmpty
      ? null
      : _samplesMs.reduce((double a, double b) => a > b ? a : b);

  /// ばらつき（標準偏差、ms）。
  ///
  /// 一定の遅れは [Metronome] を先に鳴らすことで打ち消せるが、
  /// ばらつきは打ち消せない。こちらが大きいほど、音がペースメーカーとして使えない。
  double? get standardDeviationMs {
    if (_samplesMs.length < 2) return null;
    final double mean = meanMs!;
    final double variance =
        _samplesMs
            .map((double v) => (v - mean) * (v - mean))
            .reduce((double a, double b) => a + b) /
        (_samplesMs.length - 1);
    return variance <= 0 ? 0 : math.sqrt(variance);
  }

  List<double> get samples => List<double>.unmodifiable(_samplesMs);

  void clear() => _samplesMs.clear();
}

/// [Metronome] を [BeatClock] に繋ぎ、遅れを記録する。
class MetronomeDriver {
  MetronomeDriver({
    required this.clock,
    required this.metronome,
    MetronomeDispatchLog? log,
  }) : log = log ?? MetronomeDispatchLog();

  final BeatClock clock;
  final Metronome metronome;
  final MetronomeDispatchLog log;

  StreamSubscription<BeatEvent>? _subscription;

  bool get isRunning => _subscription != null;

  void start() {
    _subscription ??= clock.beats.listen(_onBeat);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  void _onBeat(BeatEvent beat) {
    final Stopwatch stopwatch = Stopwatch()..start();
    unawaited(
      metronome.tick(accent: beat.isDownbeat).then((_) {
        stopwatch.stop();
        log.add(beat, stopwatch.elapsed);
      }).catchError((Object error, StackTrace stack) {
        // 音が出なくてもゲームは続ける。ペースメーカーであって採点対象ではない。
        debugPrint('メトロノームの再生に失敗: $error');
      }),
    );
  }
}
