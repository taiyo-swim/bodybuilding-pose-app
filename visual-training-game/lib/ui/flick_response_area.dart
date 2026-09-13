import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../game/flick.dart';

/// 画面全体でフリックを受ける領域（仕様書 4.1）。
///
/// 閾値を超えた時点で即座に通知する。指を離すまで待たない。
/// 速く答えるとスコア倍率が上がる設計なので（仕様書 4.2）、
/// 回答が確定した瞬間が反応時間の測定点になる。
///
/// 反応時間の記録は呼び出し側が [onFlick] の中で行う。
/// コールバックはジェスチャイベントと同じフレームで同期的に呼ばれる。
class FlickResponseArea extends StatefulWidget {
  const FlickResponseArea({
    required this.onFlick,
    required this.child,
    this.enabled = true,
    this.threshold = FlickJudge.defaultThresholdLogicalPixels,
    super.key,
  });

  /// 閾値を超えたフリックを検出したときに呼ばれる。1ジェスチャにつき1回だけ。
  final ValueChanged<FlickResponse> onFlick;

  /// 回答受付中か。受付外のフリックは無視する（仕様書 4.2 の受付ウィンドウ）。
  final bool enabled;

  /// フリック距離の閾値（論理px）。
  final double threshold;

  final Widget child;

  @override
  State<FlickResponseArea> createState() => _FlickResponseAreaState();
}

class _FlickResponseAreaState extends State<FlickResponseArea> {
  Offset _accumulated = Offset.zero;
  bool _reportedThisGesture = false;

  void _onPanStart(DragStartDetails details) {
    _accumulated = Offset.zero;
    _reportedThisGesture = false;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!widget.enabled || _reportedThisGesture) return;

    _accumulated += details.delta;
    final FlickResponse? response = FlickJudge.evaluate(
      _accumulated,
      threshold: widget.threshold,
    );
    if (response == null) return;

    _reportedThisGesture = true;
    widget.onFlick(response);
  }

  void _onPanEnd(DragEndDetails details) {
    _accumulated = Offset.zero;
  }

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: <Type, GestureRecognizerFactory<GestureRecognizer>>{
      // 縦横どちらのフリックも取りたいので PanGestureRecognizer を使う。
      // 既定の PanGestureRecognizer はスクロール可能な祖先とアリーナを争うが、
      // プレイ画面にスクロールは置かないので問題にならない。
      PanGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
            PanGestureRecognizer.new,
            (PanGestureRecognizer instance) {
              instance
                ..onStart = _onPanStart
                ..onUpdate = _onPanUpdate
                ..onEnd = _onPanEnd
                // 親指1本の短いフリックを拾うため、勝ち抜け条件を緩める。
                ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
            },
          ),
    },
    child: widget.child,
  );
}
