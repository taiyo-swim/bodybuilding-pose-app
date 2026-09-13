import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../audio/metronome.dart';
import '../core/brightness_lock.dart';
import '../core/display_metrics.dart';
import '../core/viewing_geometry.dart';
import '../data/database.dart';
import '../data/session_recorder.dart';
import '../game/beat_clock.dart';
import '../game/play_session.dart';
import '../stimulus/frame_presenter.dart';
import '../stimulus/gabor_params.dart';
import '../stimulus/gabor_shader.dart';
import '../stimulus/gabor_view.dart';
import '../stimulus/orientation.dart';
import 'flick_response_area.dart';
import 'palette.dart';

/// プレイ画面（仕様書 9-2）。
///
/// 画面全体が中間グレーで、刺激も固視点もフィードバックも同じ面の上に描く。
/// 明るいUI要素を置くと目が順応し、実効コントラストが条件ごとに変わる（仕様書 3.1）。
class PlayScreen extends StatefulWidget {
  const PlayScreen({
    required this.shader,
    this.database,
    this.sessionDuration,
    super.key,
  });

  final GaborShader shader;

  /// 試行ログの保存先。null なら記録しない（確認用に短く回すとき）。
  final AppDatabase? database;

  final Duration? sessionDuration;

  @override
  State<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends State<PlayScreen> with TickerProviderStateMixin {
  late final BeatClock _clock = BeatClock(vsync: this);
  late final FramePresenter _presenter = FramePresenter(vsync: this);
  final Metronome _metronome = Metronome();
  final BrightnessLock _brightnessLock = BrightnessLock();
  late final MetronomeDriver _driver = MetronomeDriver(
    clock: _clock,
    metronome: _metronome,
  );

  final ViewingGeometry _geometry = currentViewingGeometry();

  PlaySession? _session;
  Object? _error;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      // 順序が大事。輝度を固定し、音を先読みしてからクロックを回す。
      // 鳴らす直前に読み込むと最初の数拍が遅れる。
      await _brightnessLock.lock();
      await _metronome.load();
      if (!mounted) return;

      _presenter.start();
      _clock.start();
      _driver.start();

      final PlaySession session = await PlaySession.begin(
        clock: _clock,
        presenter: _presenter,
        geometry: _geometry,
        recorder: widget.database == null
            ? null
            : SessionRecorder(widget.database!),
        deviceBrightness: _brightnessLock.lockedBrightness,
        sessionDuration: widget.sessionDuration,
      );
      if (!mounted) {
        session.stop();
        return;
      }
      setState(() => _session = session);

      await session.run();
      if (!mounted) return;
      setState(() => _finished = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _session?.stop();
    _session?.dispose();
    unawaited(_driver.stop());
    _clock.stop();
    _clock.dispose();
    _presenter.stop();
    _presenter.dispose();
    unawaited(_metronome.dispose());
    unawaited(_brightnessLock.release());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Object? error = _error;
    if (error != null) {
      return _MessageScreen(message: 'セッションを開始できなかった。\n\n$error');
    }

    final PlaySession? session = _session;
    if (session == null) {
      return const _MessageScreen(message: '準備中…');
    }

    return Scaffold(
      body: ListenableBuilder(
        listenable: session,
        builder: (BuildContext context, Widget? child) => FlickResponseArea(
          enabled: session.isAcceptingResponse,
          onFlick: session.submitResponse,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _StimulusLayer(
                shader: widget.shader,
                presenter: _presenter,
                geometry: _geometry,
                session: session,
              ),
              if (session.phase == TrialPhase.fixation)
                _FixationPoint(phase: _clock.phase),
              if (session.phase == TrialPhase.feedback)
                _FeedbackLayer(outcome: session.lastOutcome),
              SafeArea(child: _Hud(session: session)),
              if (_finished) _ResultOverlay(session: session),
            ],
          ),
        ),
      ),
    );
  }
}

/// 刺激と背景。提示中だけガボールを描く。
class _StimulusLayer extends StatelessWidget {
  const _StimulusLayer({
    required this.shader,
    required this.presenter,
    required this.geometry,
    required this.session,
  });

  final GaborShader shader;
  final FramePresenter presenter;
  final ViewingGeometry geometry;
  final PlaySession session;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: ListenableBuilder(
      listenable: presenter,
      builder: (BuildContext context, Widget? child) {
        // 試行が始まる前は刺激が決まっていない。C = 0 の一様な中間グレーを描く。
        final GaborParams params =
            session.currentParams ?? _blankParams(session);
        return GaborView(
          shader: shader,
          // 提示中以外も C = 0 にして、背景と同じ一様なグレーにする。
          params: presenter.isStimulusVisible ? params : params.blank,
          geometry: geometry,
          // ノイズパターンは試行ごとに変える。提示中は固定（仕様書 3.2）。
          ditherSeed: session.trialCount.toDouble(),
        );
      },
    ),
  );

  static GaborParams _blankParams(PlaySession session) => GaborParams(
    contrast: 0,
    wavelengthArcmin: session.wavelengthArcmin,
    orientation: GaborOrientation.deg0,
  );
}

/// 固視点。ビートに同期して脈打つ（仕様書 4）。
class _FixationPoint extends StatelessWidget {
  const _FixationPoint({required this.phase});

  final ValueListenable<double> phase;

  /// ビートの終わり際で消す。約450ms 表示した時点で刺激に備える（仕様書 4）。
  static const double fadeOutAt = 0.9;

  @override
  Widget build(BuildContext context) => Center(
    child: RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: phase,
        builder: (BuildContext context, double value, Widget? child) {
          if (value >= fadeOutAt) return const SizedBox.shrink();
          // 拍頭で大きく、拍の終わりに向かって縮む。
          final double pulse = 1 - (value / fadeOutAt);
          return Container(
            width: 8 + 6 * pulse,
            height: 8 + 6 * pulse,
            decoration: const BoxDecoration(
              color: Palette.textOnMidGray,
              shape: BoxShape.circle,
            ),
          );
        },
      ),
    ),
  );
}

/// 正誤フィードバック。
class _FeedbackLayer extends StatelessWidget {
  const _FeedbackLayer({required this.outcome});

  final TrialOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final TrialOutcome? result = outcome;
    if (result == null) return const SizedBox.shrink();
    return Center(
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: result.correct ? Palette.correct : Palette.incorrect,
            width: 3,
          ),
        ),
        child: Icon(
          result.correct
              ? Icons.check
              : (result.isTimeout ? Icons.hourglass_empty : Icons.close),
          color: result.correct ? Palette.correct : Palette.incorrect,
        ),
      ),
    );
  }
}

/// スコアとコンボ。**内部難易度（コントラスト）は出さない**（仕様書 4.3 / 5.1）。
class _Hud extends StatelessWidget {
  const _Hud({required this.session});

  final PlaySession session;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '${session.score}',
          style: const TextStyle(
            color: Palette.textOnMidGray,
            fontSize: 20,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        if (session.combo >= 2)
          Text(
            '${session.combo} COMBO',
            style: const TextStyle(
              color: Palette.subtleTextOnMidGray,
              fontSize: 13,
            ),
          ),
      ],
    ),
  );
}

/// リザルト（仕様書 9-3 の最小版）。
///
/// 閾値と順位は Phase 2 以降。閾値は未決事項B が決まるまで出せない。
class _ResultOverlay extends StatelessWidget {
  const _ResultOverlay({required this.session});

  final PlaySession session;

  @override
  Widget build(BuildContext context) {
    final double accuracy = session.trialCount == 0
        ? 0
        : session.correctCount / session.trialCount;
    return ColoredBox(
      color: Palette.midGray,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('おつかれさま', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 16),
            Text('スコア ${session.score}', style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 8),
            Text(
              '${session.trialCount} 試行 / 正答率 ${(accuracy * 100).toStringAsFixed(0)}% / '
              '最大コンボ ${session.bestCombo}',
              style: const TextStyle(
                color: Palette.subtleTextOnMidGray,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('とじる'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageScreen extends StatelessWidget {
  const _MessageScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Palette.textOnMidGray),
        ),
      ),
    ),
  );
}
