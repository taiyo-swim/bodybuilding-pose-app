import 'dart:async';

import 'package:flutter/material.dart';

import '../audio/metronome.dart';
import '../game/beat_clock.dart';
import 'palette.dart';

/// 開発者向け: 音とビートのずれを実機で計測する画面（仕様書 11-6）。
///
/// アプリ内で自動的に測れるのは**ソフトウェア側の遅れだけ**で、
/// 端末のオーディオ出力バッファぶんの遅れは測れない。
///
/// 音響的な遅延を出す手順:
/// 1. この画面を開き、拍頭で白い円が光ることを確認する
/// 2. **別の端末**でこの画面を録画する（60fps 以上が望ましい）
/// 3. 録画の波形で「クリック音の立ち上がり」と「円が光るフレーム」の差を読む
/// 4. その差が音響的な遅延。`Metronome` を先に鳴らして打ち消す
///
/// 画面に出している統計は、その測定の前提になるばらつきの確認用。
/// ばらつきが大きい端末では、そもそも音をペースメーカーとして使えない。
class BeatSyncCheckScreen extends StatefulWidget {
  const BeatSyncCheckScreen({super.key});

  @override
  State<BeatSyncCheckScreen> createState() => _BeatSyncCheckScreenState();
}

class _BeatSyncCheckScreenState extends State<BeatSyncCheckScreen>
    with SingleTickerProviderStateMixin {
  late final BeatClock _clock = BeatClock(vsync: this);
  final Metronome _metronome = Metronome();
  late final MetronomeDriver _driver = MetronomeDriver(
    clock: _clock,
    metronome: _metronome,
  );

  StreamSubscription<BeatEvent>? _subscription;
  final List<double> _detectionErrorsMs = <double>[];
  BeatEvent? _lastBeat;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _metronome.load();
      if (!mounted) return;
      _clock.start();
      _driver.start();
      _subscription = _clock.beats.listen((BeatEvent beat) {
        if (!mounted) return;
        setState(() {
          _lastBeat = beat;
          _detectionErrorsMs.add(beat.detectionErrorMs);
          if (_detectionErrorsMs.length > 240) _detectionErrorsMs.removeAt(0);
        });
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_driver.stop());
    _clock.stop();
    _clock.dispose();
    unawaited(_metronome.dispose());
    super.dispose();
  }

  double? get _meanDetectionErrorMs => _detectionErrorsMs.isEmpty
      ? null
      : _detectionErrorsMs.reduce((double a, double b) => a + b) /
            _detectionErrorsMs.length;

  double? get _maxDetectionErrorMs => _detectionErrorsMs.isEmpty
      ? null
      : _detectionErrorsMs.reduce((double a, double b) => a > b ? a : b);

  @override
  Widget build(BuildContext context) {
    final Object? error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('音ズレ計測')),
      body: SafeArea(
        child: error != null
            ? Center(child: Text('メトロノームを読み込めなかった。\n$error'))
            : Column(
                children: <Widget>[
                  Expanded(child: Center(child: _BeatFlash(clock: _clock))),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _Stat(
                          label: 'BPM',
                          value: '${_clock.bpm}（固定）',
                        ),
                        _Stat(
                          label: '拍',
                          value: '${(_lastBeat?.index ?? -1) + 1}',
                        ),
                        _Stat(
                          label: 'ビート検出の遅れ',
                          value: _formatPair(
                            _meanDetectionErrorMs,
                            _maxDetectionErrorMs,
                          ),
                        ),
                        _Stat(
                          label: '発音命令の遅れ',
                          value: _formatPair(
                            _driver.log.meanMs,
                            _driver.log.maxMs,
                          ),
                        ),
                        _Stat(
                          label: '発音命令のばらつき',
                          value: _driver.log.standardDeviationMs == null
                              ? '—'
                              : '${_driver.log.standardDeviationMs!.toStringAsFixed(2)} ms (SD)',
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'ここに出ているのはソフトウェア側の遅れだけ。'
                          '音響的な遅延は、別の端末でこの画面を録画し、'
                          'クリック音の立ち上がりと円が光るフレームの差を読んで求めること。',
                          style: TextStyle(
                            color: Palette.subtleTextOnMidGray,
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  static String _formatPair(double? mean, double? max) =>
      mean == null || max == null
      ? '—'
      : '平均 ${mean.toStringAsFixed(2)} ms / 最大 ${max.toStringAsFixed(2)} ms';
}

/// 拍頭で光る円。外部録画で音と映像の差を読むための基準になる。
class _BeatFlash extends StatelessWidget {
  const _BeatFlash({required this.clock});

  final BeatClock clock;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ValueListenableBuilder<double>(
      valueListenable: clock.phase,
      builder: (BuildContext context, double phase, Widget? child) {
        // 拍頭から 1/8 拍だけ白く光らせる。BPM120 なら 62.5ms。
        final bool lit = phase < 0.125;
        return Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: lit ? Colors.white : Palette.midGray,
            border: Border.all(color: Palette.subtleTextOnMidGray),
          ),
        );
      },
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: <Widget>[
        SizedBox(
          width: 150,
          child: Text(
            label,
            style: const TextStyle(
              color: Palette.subtleTextOnMidGray,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 12)),
        ),
      ],
    ),
  );
}
