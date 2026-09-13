import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../core/viewing_geometry.dart';
import '../game/flick.dart';
import '../stimulus/frame_presenter.dart';
import '../stimulus/gabor_params.dart';
import 'database.dart';
import 'tables.dart';

/// ドメインの値を試行ログの行に落とす（仕様書 8）。
///
/// マッピングをここ1箇所に集めておく。各画面がバラバラに行を組み立てると、
/// 「この列に何が入っているか」がコードを追わないと分からなくなる。
class SessionRecorder {
  SessionRecorder(this._db);

  final AppDatabase _db;

  String? _sessionId;
  int _trialCount = 0;

  String get sessionId {
    final String? id = _sessionId;
    if (id == null) {
      throw StateError('begin() を呼んでいない');
    }
    return id;
  }

  bool get isActive => _sessionId != null;

  int get trialCount => _trialCount;

  /// セッションを開始する。
  ///
  /// [deviceBrightness] は固定した画面輝度（仕様書 3.4）。固定できなかった端末では
  /// null を渡す。null のセッションのコントラスト測定値は比較に使えない。
  Future<String> begin({
    required SessionMode mode,
    required int seed,
    required ViewingGeometry geometry,
    DateTime? startedAt,
    String? trackId,
    double? deviceBrightness,
  }) async {
    if (_sessionId != null) {
      throw StateError('セッションが既に開始している');
    }
    if (mode == SessionMode.measure) {
      // 閾値推定の方法と試行数が未決のため、測定モードは作らせない（仕様書 0-B）。
      throw UnimplementedError(
        'コンディション測定モードは未決事項B が決まるまで実装しない（仕様書 0-B）',
      );
    }

    final DateTime now = startedAt ?? DateTime.now();
    final String id = _generateSessionId(now);

    await _db.startSession(
      SessionsCompanion.insert(
        id: id,
        startedAt: now,
        mode: mode,
        seed: seed,
        trackId: Value<String?>(trackId),
        deviceBrightness: Value<double?>(deviceBrightness),
        logicalPixelsPerInch: geometry.logicalPixelsPerInch,
        viewingDistanceCm: geometry.viewingDistanceCm,
      ),
    );

    _sessionId = id;
    _trialCount = 0;
    return id;
  }

  /// 1試行ぶんを記録する。
  ///
  /// [response] が null なら無回答。仕様書 4.2 の受付ウィンドウを過ぎたものは
  /// 不正解として扱う。
  Future<void> recordTrial({
    required GaborParams params,
    required ViewingGeometry geometry,
    required PresentationMeasurement measurement,
    required FlickResponse? response,
    required int? rtMs,
    DateTime? at,
  }) async {
    final bool correct = response?.isCorrectFor(params.orientation) ?? false;

    await _db.logTrial(
      TrialsCompanion.insert(
        sessionId: sessionId,
        ts: at ?? DateTime.now(),
        contrast: params.contrast,
        lambdaPx: params.lambdaLogicalPixels(geometry),
        lambdaArcmin: params.wavelengthArcmin,
        orientationDeg: params.orientation.degrees,
        framesRequested: measurement.framesRequested,
        msActual: measurement.measuredMs,
        refreshHz: measurement.refreshHz,
        // Phase 1 ではマスクもフランカーも使わない（仕様書 5.3 の解放スケジュール）。
        maskType: MaskType.none,
        responseDeg: Value<double?>(response?.axisDegrees),
        correct: correct,
        rtMs: Value<int?>(rtMs),
      ),
    );

    _trialCount++;
  }

  /// セッションを終了して集計を書き戻す。
  ///
  /// `threshold_contrast` は書かない。推定方法が未決のため（仕様書 0-B）。
  Future<void> end({required int score}) async {
    final String id = sessionId;
    await _db.finishSession(
      sessionId: id,
      nTrials: _trialCount,
      score: score,
    );
    _sessionId = null;
  }

  static final math.Random _random = math.Random();

  static String _generateSessionId(DateTime at) {
    final String time = at.microsecondsSinceEpoch.toRadixString(36);
    final String salt = _random.nextInt(1 << 32).toRadixString(36);
    return '$time-$salt';
  }
}
