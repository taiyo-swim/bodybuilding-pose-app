import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visual_training_game/core/viewing_geometry.dart';
import 'package:visual_training_game/data/database.dart';
import 'package:visual_training_game/data/session_recorder.dart';
import 'package:visual_training_game/data/tables.dart';
import 'package:visual_training_game/game/flick.dart';
import 'package:visual_training_game/stimulus/frame_presenter.dart';
import 'package:visual_training_game/stimulus/gabor_params.dart';
import 'package:visual_training_game/stimulus/orientation.dart';

const ViewingGeometry _geometry = ViewingGeometry(logicalPixelsPerInch: 160);

const PresentationMeasurement _measurement = PresentationMeasurement(
  targetMs: 50,
  framesRequested: 3,
  framesShown: 3,
  measuredMs: 50.1,
  refreshHz: 59.94,
);

GaborParams _params({
  double contrast = 0.05,
  GaborOrientation orientation = GaborOrientation.deg45,
}) => GaborParams(
  contrast: contrast,
  wavelengthArcmin: GaborParams.defaultWavelengthArcmin,
  orientation: orientation,
);

void main() {
  late AppDatabase db;
  late SessionRecorder recorder;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    recorder = SessionRecorder(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> beginSession() => recorder.begin(
    mode: SessionMode.game,
    seed: 12345,
    geometry: _geometry,
    deviceBrightness: 0.8,
  );

  group('セッション', () {
    test('開始すると行が1件でき、視距離とppiも残る', () async {
      final String id = await beginSession();
      final List<SessionRow> rows = await db.recentSessions();

      expect(rows, hasLength(1));
      final SessionRow row = rows.single;
      expect(row.id, id);
      expect(row.mode, SessionMode.game);
      expect(row.seed, 12345);
      expect(row.deviceBrightness, 0.8);
      // 未決事項A が確定したとき、過去ログを読み直せるように残している。
      expect(row.logicalPixelsPerInch, 160);
      expect(row.viewingDistanceCm, 40);
    });

    test('閾値は書かない（未決事項B）', () async {
      await beginSession();
      await recorder.end(score: 100);
      final SessionRow row = (await db.recentSessions()).single;
      expect(row.thresholdContrast, isNull);
    });

    test('測定モードは作れない（未決事項B）', () async {
      expect(
        () => recorder.begin(
          mode: SessionMode.measure,
          seed: 1,
          geometry: _geometry,
        ),
        throwsUnimplementedError,
      );
    });

    test('二重に開始できない', () async {
      await beginSession();
      expect(beginSession, throwsStateError);
    });

    test('開始前に試行を記録しようとすると失敗する', () {
      expect(
        () => recorder.recordTrial(
          params: _params(),
          geometry: _geometry,
          measurement: _measurement,
          response: null,
          rtMs: null,
        ),
        throwsStateError,
      );
    });

    test('終了時に試行数とスコアを書き戻す', () async {
      await beginSession();
      for (int i = 0; i < 5; i++) {
        await recorder.recordTrial(
          params: _params(),
          geometry: _geometry,
          measurement: _measurement,
          response: FlickJudge.evaluate(
            GaborOrientation.deg45.stripeAxis * 100,
          ),
          rtMs: 400,
        );
      }
      await recorder.end(score: 1234);

      final SessionRow row = (await db.recentSessions()).single;
      expect(row.nTrials, 5);
      expect(row.score, 1234);
      expect(recorder.isActive, isFalse);
    });
  });

  group('試行ログ', () {
    test('提示条件と実測値をそのまま残す', () async {
      final String id = await beginSession();
      await recorder.recordTrial(
        params: _params(contrast: 0.031, orientation: GaborOrientation.deg135),
        geometry: _geometry,
        measurement: _measurement,
        response: FlickJudge.evaluate(GaborOrientation.deg135.stripeAxis * 100),
        rtMs: 382,
      );

      final TrialRow row = (await db.trialsOf(id)).single;
      expect(row.contrast, 0.031);
      expect(row.orientationDeg, 135);
      expect(row.framesRequested, 3);
      // フレーム数 × 公称フレーム時間ではなく、実測値が入っていること（仕様書 3.3）。
      expect(row.msActual, 50.1);
      expect(row.refreshHz, 59.94);
      expect(row.correct, isTrue);
      expect(row.rtMs, 382);
      expect(row.maskType, MaskType.none);
      expect(row.flankerDistanceLambda, isNull);
      expect(row.isiMs, isNull);
    });

    test('λ を論理px と視角の両方で残す', () async {
      // 未決事項A が確定したとき、どちらか一方しかないと読み直せない。
      final String id = await beginSession();
      await recorder.recordTrial(
        params: _params(),
        geometry: _geometry,
        measurement: _measurement,
        response: null,
        rtMs: null,
      );

      final TrialRow row = (await db.trialsOf(id)).single;
      expect(row.lambdaArcmin, closeTo(60 / 6.5, 1e-9));
      expect(
        row.lambdaPx,
        closeTo(_geometry.logicalPixelsFromArcmin(60 / 6.5), 1e-9),
      );
    });

    test('丸める前の回答角度を残す', () async {
      final String id = await beginSession();
      final FlickResponse response = FlickJudge.evaluate(
        const Offset(-34, 94), // 20° 付近
      )!;
      await recorder.recordTrial(
        params: _params(orientation: GaborOrientation.deg0),
        geometry: _geometry,
        measurement: _measurement,
        response: response,
        rtMs: 300,
      );

      final TrialRow row = (await db.trialsOf(id)).single;
      expect(row.responseDeg, closeTo(response.axisDegrees, 1e-9));
      expect(row.responseDeg, isNot(closeTo(0, 1)));
      expect(row.correct, isTrue);
    });

    test('無回答は不正解として、回答角度と反応時間は null で残す', () async {
      // 受付ウィンドウを過ぎたもの（仕様書 4.2）。
      final String id = await beginSession();
      await recorder.recordTrial(
        params: _params(),
        geometry: _geometry,
        measurement: _measurement,
        response: null,
        rtMs: null,
      );

      final TrialRow row = (await db.trialsOf(id)).single;
      expect(row.correct, isFalse);
      expect(row.responseDeg, isNull);
      expect(row.rtMs, isNull);
    });

    test('誤答を正しく不正解として残す', () async {
      final String id = await beginSession();
      await recorder.recordTrial(
        params: _params(orientation: GaborOrientation.deg0),
        geometry: _geometry,
        measurement: _measurement,
        response: FlickJudge.evaluate(GaborOrientation.deg90.stripeAxis * 100),
        rtMs: 250,
      );

      final TrialRow row = (await db.trialsOf(id)).single;
      expect(row.correct, isFalse);
      expect(row.orientationDeg, 0);
    });

    test('全件残る（集計で潰さない）', () async {
      final String id = await beginSession();
      for (int i = 0; i < 180; i++) {
        await recorder.recordTrial(
          params: _params(contrast: 0.01 + i * 0.001),
          geometry: _geometry,
          measurement: _measurement,
          response: null,
          rtMs: null,
        );
      }
      final List<TrialRow> rows = await db.trialsOf(id);
      expect(rows, hasLength(180));
      expect(rows.first.contrast, closeTo(0.01, 1e-9));
      expect(rows.last.contrast, closeTo(0.01 + 179 * 0.001, 1e-9));
    });

    test('累計試行数を数えられる（経験値レベルの材料）', () async {
      await beginSession();
      for (int i = 0; i < 7; i++) {
        await recorder.recordTrial(
          params: _params(),
          geometry: _geometry,
          measurement: _measurement,
          response: null,
          rtMs: null,
        );
      }
      await recorder.end(score: 0);
      expect(await db.totalTrialCount(), 7);
    });

    test('セッションを消すと試行ログも消える', () async {
      final String id = await beginSession();
      await recorder.recordTrial(
        params: _params(),
        geometry: _geometry,
        measurement: _measurement,
        response: null,
        rtMs: null,
      );
      await recorder.end(score: 0);

      await (db.delete(db.sessions)
            ..where(($SessionsTable t) => t.id.equals(id)))
          .go();
      expect(await db.trialsOf(id), isEmpty);
    });
  });
}
