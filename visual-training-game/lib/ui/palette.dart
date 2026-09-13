import 'package:flutter/material.dart';

/// 背景は必ず中間グレー。周囲のUIも中間グレーに寄せる（仕様書 3.1）。
///
/// 明るい/暗いUIを画面内に置くと目が順応してしまい、
/// 刺激の実効コントラストが条件ごとに変わる。
abstract final class Palette {
  /// sRGB 128。ガボールの平均輝度と一致させる。
  static const Color midGray = Color(0xFF808080);

  /// 中間グレー上で読める最小限のコントラストの文字色。
  static const Color textOnMidGray = Color(0xFF303030);

  /// 補助的な文字色。
  static const Color subtleTextOnMidGray = Color(0xFF585858);

  /// 正解フィードバック。彩度を抑えて順応への影響を小さくする。
  static const Color correct = Color(0xFF4A7A52);

  /// 不正解フィードバック。
  static const Color incorrect = Color(0xFF8A4A4A);

  static ThemeData theme() {
    final ThemeData base = ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: midGray,
        surface: midGray,
      ),
      useMaterial3: true,
    );
    return base.copyWith(
      scaffoldBackgroundColor: midGray,
      canvasColor: midGray,
      appBarTheme: const AppBarTheme(
        backgroundColor: midGray,
        foregroundColor: textOnMidGray,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: textOnMidGray,
        displayColor: textOnMidGray,
      ),
    );
  }
}
