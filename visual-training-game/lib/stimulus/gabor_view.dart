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
    super.key,
  });

  final GaborShader shader;
  final GaborParams params;
  final ViewingGeometry geometry;

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: CustomPaint(
      painter: _GaborPainter(
        shader: shader,
        params: params,
        geometry: geometry,
      ),
    ),
  );
}

class _GaborPainter extends CustomPainter {
  const _GaborPainter({
    required this.shader,
    required this.params,
    required this.geometry,
  });

  final GaborShader shader;
  final GaborParams params;
  final ViewingGeometry geometry;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final ui.FragmentShader configured = shader.configure(
      size: size,
      params: params,
      geometry: geometry,
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = configured);
  }

  @override
  bool shouldRepaint(_GaborPainter oldDelegate) =>
      oldDelegate.params != params ||
      oldDelegate.geometry != geometry ||
      !identical(oldDelegate.shader, shader);
}
