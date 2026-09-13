import 'package:flutter/foundation.dart';
import 'package:screen_brightness/screen_brightness.dart';

/// プレイ中の画面輝度を固定する（仕様書 3.4）。
///
/// 自動調光が効いていると実効コントラストが毎回変わり、測定値が無意味になる。
/// 終了時には必ず元に戻す。戻し忘れるとユーザーの端末設定を壊す。
///
/// 固定できなかった端末では [lockedBrightness] が null になる。
/// その場合、そのセッションのコントラスト測定値は他と比較できない。
/// 値は試行ログのセッション行に残して、後から除外できるようにする。
class BrightnessLock {
  BrightnessLock({ScreenBrightness? screenBrightness})
    : _brightness = screenBrightness ?? ScreenBrightness();

  /// プレイ中に固定する輝度。
  ///
  /// 最大にすると眼精疲労を招き、端末も発熱する。中間より少し明るい程度にする。
  /// TODO: 実機で中間グレーの見え方を確認して調整する。
  static const double playBrightness = 0.7;

  final ScreenBrightness _brightness;

  double? _lockedBrightness;
  bool _locked = false;

  /// 実際に固定できた輝度。固定できなかったときは null。
  double? get lockedBrightness => _lockedBrightness;

  bool get isLocked => _locked;

  /// 輝度を固定する。失敗しても例外は投げない（ゲームは続行できるべき）。
  Future<void> lock({double brightness = playBrightness}) async {
    if (_locked) return;
    try {
      await _brightness.setApplicationScreenBrightness(brightness);
      _lockedBrightness = brightness;
      _locked = true;
    } catch (error) {
      // 端末やOSの制限で設定できないことがある。
      // 測定値が比較できないことだけ記録して続行する。
      _lockedBrightness = null;
      _locked = false;
      debugPrint('画面輝度を固定できなかった: $error');
    }
  }

  /// 元の輝度に戻す。
  Future<void> release() async {
    if (!_locked) return;
    try {
      await _brightness.resetApplicationScreenBrightness();
    } catch (error) {
      debugPrint('画面輝度を戻せなかった: $error');
    } finally {
      _locked = false;
      _lockedBrightness = null;
    }
  }
}
