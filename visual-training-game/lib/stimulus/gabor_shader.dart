import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/viewing_geometry.dart';
import 'gabor_params.dart';

/// `shaders/gabor.frag` のラッパー。
///
/// ガボール生成は GPU で数行で済む。CPU 描画では提示フレーム数に間に合わない（仕様書 2）。
///
/// [ui.FragmentShader] は1つ作って uniform を差し替えて使い回す。
/// 毎フレーム生成すると GC 圧が上がり、提示タイミングが揺れる。
class GaborShader {
  GaborShader._(this._shader);

  static const String assetKey = 'shaders/gabor.frag';

  /// 描画半径をσの何倍にするか。3.0 で「描画サイズ = 6σ」（仕様書 3.1）。
  static const double radiusSigma = 3.0;

  final ui.FragmentShader _shader;

  bool _disposed = false;

  static Future<GaborShader> load() async {
    final ui.FragmentProgram program = await ui.FragmentProgram.fromAsset(
      assetKey,
    );
    return GaborShader._(program.fragmentShader());
  }

  /// uniform を更新して塗り用のシェーダーを返す。
  ///
  /// インデックスは `gabor.frag` の uniform 宣言順に対応する。
  /// 宣言を足す・並べ替える場合は必ずここも直すこと。
  ui.FragmentShader configure({
    required Size size,
    required GaborParams params,
    required ViewingGeometry geometry,
  }) {
    assert(!_disposed, 'disposed した GaborShader は使えない');
    final double lambdaPx = params.lambdaLogicalPixels(geometry);
    return configureRaw(
      size: size,
      contrast: params.contrast,
      lambdaLogicalPixels: lambdaPx,
      thetaRadians: params.orientation.radians,
    );
  }

  /// 論理px を直接指定する下位 API。換算済みの値を渡すこと。
  ui.FragmentShader configureRaw({
    required Size size,
    required double contrast,
    required double lambdaLogicalPixels,
    required double thetaRadians,
  }) {
    assert(!_disposed, 'disposed した GaborShader は使えない');
    assert(lambdaLogicalPixels > 0, 'λ が 0 以下ではゼロ除算になる');
    _shader
      ..setFloat(0, size.width) // uSize.x
      ..setFloat(1, size.height) // uSize.y
      ..setFloat(2, contrast) // uContrast
      ..setFloat(3, lambdaLogicalPixels) // uLambdaPx
      ..setFloat(4, thetaRadians) // uThetaRad
      ..setFloat(5, radiusSigma); // uRadiusSigma
    return _shader;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _shader.dispose();
  }
}
