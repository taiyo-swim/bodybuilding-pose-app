import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_training_game/game/beat_clock.dart';

const Duration _frame = Duration(microseconds: 16667);

void main() {
  /// クロックを用意する。
  ///
  /// 後片付けは addTearDown に登録する。テスト本体が途中で失敗しても
  /// Ticker が動いたまま残らないようにするため。
  Future<BeatClock> pumpClock(WidgetTester tester, {int bpm = 120}) async {
    late BeatClock clock;
    await tester.pumpWidget(
      _ClockHarness(bpm: bpm, onReady: (BeatClock c) => clock = c),
    );
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    return clock;
  }

  Future<List<BeatEvent>> collect(
    WidgetTester tester,
    BeatClock clock,
    int frames,
  ) async {
    final List<BeatEvent> beats = <BeatEvent>[];
    final StreamSubscription<BeatEvent> sub = clock.beats.listen(beats.add);
    addTearDown(sub.cancel);
    clock.start();
    for (int i = 0; i < frames; i++) {
      await tester.pump(_frame);
    }
    return beats;
  }

  testWidgets('BPM は 120 固定（仕様書 2.1）', (WidgetTester tester) async {
    final BeatClock clock = await pumpClock(tester);
    expect(BeatClock.fixedBpm, 120);
    expect(clock.bpm, 120);
    expect(clock.beatPeriod, const Duration(milliseconds: 500));
  });

  testWidgets('最初の拍は即座に出て、以後 500ms ごとに出る', (WidgetTester tester) async {
    final BeatClock clock = await pumpClock(tester);
    // 90フレーム = 1.5秒。拍 0（開始直後）と 1、2 が出る。
    final List<BeatEvent> beats = await collect(tester, clock, 91);
    expect(beats.map((BeatEvent b) => b.index), <int>[0, 1, 2, 3]);
  });

  testWidgets('拍の間隔は 500ms', (WidgetTester tester) async {
    final BeatClock clock = await pumpClock(tester);
    final List<BeatEvent> beats = await collect(tester, clock, 120);
    expect(beats.length, greaterThanOrEqualTo(4));
    for (int i = 1; i < beats.length; i++) {
      final int deltaMs =
          (beats[i].intended - beats[i - 1].intended).inMilliseconds;
      expect(deltaMs, 500);
    }
  });

  testWidgets('検出の遅れは1フレーム以内', (WidgetTester tester) async {
    // vsync 刻みでしか検出できないので、最大でも1フレームぶん遅れる。
    final BeatClock clock = await pumpClock(tester);
    final List<BeatEvent> beats = await collect(tester, clock, 120);

    expect(beats, isNotEmpty);
    for (final BeatEvent beat in beats) {
      expect(beat.detectionErrorMs, greaterThanOrEqualTo(0));
      expect(beat.detectionErrorMs, lessThan(16.7), reason: '${beat.index}拍目');
    }
  });

  testWidgets('位相は 0 から 1 の間を進み、拍をまたぐと巻き戻る', (WidgetTester tester) async {
    final BeatClock clock = await pumpClock(tester);
    clock.start();

    final List<double> phases = <double>[];
    for (int i = 0; i < 60; i++) {
      await tester.pump(_frame);
      phases.add(clock.phase.value);
    }

    expect(phases, everyElement(greaterThanOrEqualTo(0)));
    expect(phases, everyElement(lessThan(1)));
    expect(phases[10], greaterThan(phases[5]));
    // 30フレームで1拍。29→31 のどこかで巻き戻る。
    expect(phases[31], lessThan(phases[28]));
  });

  testWidgets('4拍ごとに小節の頭になる', (WidgetTester tester) async {
    final BeatClock clock = await pumpClock(tester);
    final List<BeatEvent> beats = await collect(tester, clock, 271);

    final List<int> downbeats = beats
        .where((BeatEvent b) => b.isDownbeat)
        .map((BeatEvent b) => b.index)
        .toList();
    expect(downbeats, <int>[0, 4, 8]);
  });

  testWidgets('フレームが大きく飛んでも、拍をまとめて出さない', (WidgetTester tester) async {
    // 取りこぼした拍に合わせて刺激をまとめて出しても意味がない。
    final BeatClock clock = await pumpClock(tester);
    final List<BeatEvent> beats = <BeatEvent>[];
    final StreamSubscription<BeatEvent> sub = clock.beats.listen(beats.add);
    addTearDown(sub.cancel);
    clock.start();

    await tester.pump(_frame); // 拍 0
    await tester.pump(const Duration(milliseconds: 2000)); // 4拍ぶん飛ぶ
    await tester.pump(_frame);

    expect(beats.map((BeatEvent b) => b.index), <int>[0, 4]);
  });

  testWidgets('waitForNextBeat が次の拍で解決する', (WidgetTester tester) async {
    final BeatClock clock = await pumpClock(tester);
    clock.start();
    await tester.pump(_frame); // 拍 0 を消化する

    BeatEvent? received;
    unawaited(clock.waitForNextBeat().then((BeatEvent b) => received = b));

    for (int i = 0; i < 25; i++) {
      await tester.pump(_frame);
    }
    expect(received, isNull, reason: 'まだ次の拍が来ていない');

    for (int i = 0; i < 8; i++) {
      await tester.pump(_frame);
    }
    expect(received?.index, 1);
  });
}

class _ClockHarness extends StatefulWidget {
  const _ClockHarness({required this.onReady, required this.bpm});

  final void Function(BeatClock) onReady;
  final int bpm;

  @override
  State<_ClockHarness> createState() => _ClockHarnessState();
}

class _ClockHarnessState extends State<_ClockHarness>
    with SingleTickerProviderStateMixin {
  late final BeatClock _clock = BeatClock(vsync: this, bpm: widget.bpm);

  @override
  void initState() {
    super.initState();
    widget.onReady(_clock);
  }

  @override
  void dispose() {
    _clock.stop();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
