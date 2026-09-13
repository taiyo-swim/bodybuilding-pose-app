import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/viewing_geometry.dart';
import 'gabor_params.dart';
import 'gabor_shader.dart';

/// 中間グレーの背景と、その中央のガボールを1枚のシェーダーで描く。
///
/// 背景とパッチを別々のウィジェットにすると境界に継ぎ目が出るため、
/// プレイ画面いっぱいをこのシェーダーで塗る（仕様書 3.1「周囲のUIも中間グレーに寄せる」）。
class GaborView extends StatelessWidget {
  const GaborView({
    required this.shader,
    required this.params,
    required this.geometry,
    this.ditherAmplitude = GaborShader.defaultDitherAmplitude,
    this.ditherSeed = 0,
    super.key,
  });

  final GaborShader shader;
  final GaborParams params;
  final ViewingGeometry geometry;

  /// ディザ振幅。1.0 で ±1/255（仕様書 3.2）。0 は検証用の比較条件のみ。
  final double ditherAmplitude;

  /// ノイズパターンのシード。試行ごとに変え、提示中は固定する。
  final double ditherSeed;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: CustomPaint(
      painter: _GaborPainter(
        shader: shader,
        params: params,
        geometry: geometry,
        ditherAmplitude: ditherAmplitude,
        ditherSeed: ditherSeed,
      ),
    ),
  );
}

class _GaborPainter extends CustomPainter {
  const _GaborPainter({
    required this.shader,
    required this.params,
    required this.geometry,
    required this.ditherAmplitude,
    required this.ditherSeed,
  });

  final GaborShader shader;
  final GaborParams params;
  final ViewingGeometry geometry;
  final double ditherAmplitude;
  final double ditherSeed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final ui.FragmentShader configured = shader.configure(
      size: size,
      params: params,
      geometry: geometry,
      ditherAmplitude: ditherAmplitude,
      ditherSeed: ditherSeed,
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = configured);
  }

  @override
  bool shouldRepaint(_GaborPainter oldDelegate) =>
      oldDelegate.params != params ||
      oldDelegate.geometry != geometry ||
      oldDelegate.ditherAmplitude != ditherAmplitude ||
      oldDelegate.ditherSeed != ditherSeed ||
      !identical(oldDelegate.shader, shader);
}
