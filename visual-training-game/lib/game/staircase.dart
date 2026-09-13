import 'package:flutter/foundation.dart';

/// ステアケースが1試行で何をしたか。
enum StaircaseStepKind {
  /// 3連続正解で難化した。
  harder,

  /// ミスで易化した。
  easier,

  /// 連続正解が規定に満たず、コントラストは据え置き。
  hold,
}

/// 1試行ぶんの適応の記録。
@immutable
class StaircaseStep {
  const StaircaseStep({
    required this.kind,
    required this.contrastBefore,
    required this.contrastAfter,
    required this.isReversal,
    required this.clamped,
  });

  final StaircaseStepKind kind;
  final double contrastBefore;
  final double contrastAfter;

  /// 難化と易化が切り替わった試行か。
  ///
  /// 反転点は閾値推定の材料になるが、**推定方法そのものは未決**（仕様書 0-B）。
  /// ここでは記録だけしておく。
  final bool isReversal;

  /// 上下限に張り付いてコントラストが実際には動かなかったか。
  ///
  /// 床に張り付き続ける場合、その端末・その被験者にとって
  /// この軸は「マスター済み」として扱う判断材料になる（仕様書 5.4）。
  final bool clamped;

  @override
  String toString() =>
      'StaircaseStep(${kind.name}: '
      '${(contrastBefore * 100).toStringAsFixed(2)}% → '
      '${(contrastAfter * 100).toStringAsFixed(2)}%'
      '${isReversal ? ', reversal' : ''}${clamped ? ', clamped' : ''})';
}

/// 適応的ステアケース（仕様書 4.3）。
///
/// - 3連続正解 → コントラストを 0.85倍（難化）
/// - 1回ミス → コントラストを 1/0.85倍（易化）
/// - 正答率は約79%に収束する
/// - 上下限: 1% 〜 60%
///
/// **この内部難易度はプレイヤーに数値として見せない。**
/// 外に出すのは経験値・ランク・リーグだけ（仕様書 5.1）。
///
/// 79% に収束する理由: 3連続正解で難化、1回ミスで易化なので、
/// 難化と易化が釣り合う点は p³ = 1/2、すなわち p = 0.7937 になる。
class Staircase {
  Staircase({double initialContrast = defaultInitialContrast})
    : _contrast = initialContrast.clamp(minContrast, maxContrast) {
    assert(initialContrast >= minContrast && initialContrast <= maxContrast);
  }

  /// 難化の倍率（仕様書 4.3）。
  static const double stepFactor = 0.85;

  /// 下限。これ以上は難しくしない（仕様書 4.3）。
  static const double minContrast = 0.01;

  /// 上限（仕様書 4.3）。
  static const double maxContrast = 0.60;

  /// 難化に必要な連続正解数。
  static const int correctRunForHarder = 3;

  /// 開始コントラスト。
  ///
  /// 仕様書に指定がないため実装側で決めた値。上限から始めると閾値まで降りるのに
  /// 試行を使いすぎ、低すぎると最初から見えず離脱する。30% はその折衷。
  /// 実データを見て調整する余地がある。
  static const double defaultInitialContrast = 0.30;

  double _contrast;
  int _correctRun = 0;
  int _trialCount = 0;
  int? _lastDirection; // -1: 難化, +1: 易化
  final List<double> _reversalContrasts = <double>[];

  /// 次の試行で使うコントラスト。**UI に数値として出さないこと。**
  double get contrast => _contrast;

  int get trialCount => _trialCount;

  /// 反転点のコントラスト列。
  ///
  /// TODO(未決): 閾値推定の方法と試行数が未決のため、ここから閾値は計算しない
  /// （仕様書 0-B）。40試行で十分か、反転点の平均を取るか、
  /// 心理測定関数をフィットするかが決まってから実装する。
  List<double> get reversalContrasts => List<double>.unmodifiable(_reversalContrasts);

  int get reversalCount => _reversalContrasts.length;

  /// 下限に張り付いているか。この軸をこれ以上難化させられない（仕様書 5.4）。
  bool get isAtFloor => _contrast <= minContrast;

  /// 上限に張り付いているか。
  bool get isAtCeiling => _contrast >= maxContrast;

  /// 1試行の結果を反映し、次のコントラストを決める。
  StaircaseStep record({required bool correct}) {
    _trialCount++;
    final double before = _contrast;

    final StaircaseStepKind kind;
    final int? direction;

    if (correct) {
      _correctRun++;
      if (_correctRun >= correctRunForHarder) {
        _correctRun = 0;
        kind = StaircaseStepKind.harder;
        direction = -1;
        _contrast = before * stepFactor;
      } else {
        kind = StaircaseStepKind.hold;
        direction = null;
      }
    } else {
      _correctRun = 0;
      kind = StaircaseStepKind.easier;
      direction = 1;
      _contrast = before / stepFactor;
    }

    _contrast = _contrast.clamp(minContrast, maxContrast);

    bool isReversal = false;
    if (direction != null) {
      final int? last = _lastDirection;
      if (last != null && last != direction) {
        isReversal = true;
        // 反転点は「向きが変わる直前のコントラスト」を採る。
        _reversalContrasts.add(before);
      }
      _lastDirection = direction;
    }

    return StaircaseStep(
      kind: kind,
      contrastBefore: before,
      contrastAfter: _contrast,
      isReversal: isReversal,
      clamped: direction != null && _contrast == before,
    );
  }

  /// セッションをまたいで続きから始めるためのリセット。
  void resetTo(double contrast) {
    _contrast = contrast.clamp(minContrast, maxContrast);
    _correctRun = 0;
    _trialCount = 0;
    _lastDirection = null;
    _reversalContrasts.clear();
  }

  @override
  String toString() =>
      'Staircase(C: ${(_contrast * 100).toStringAsFixed(2)}%, '
      'trials: $_trialCount, reversals: $reversalCount)';
}
