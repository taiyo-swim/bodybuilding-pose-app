import 'package:flutter/material.dart';

import '../core/display_metrics.dart';
import '../core/viewing_geometry.dart';
import '../stimulus/gabor_params.dart';
import '../stimulus/gabor_shader.dart';
import '../stimulus/gabor_view.dart';
import '../stimulus/orientation.dart';
import 'palette.dart';

/// 開発者向け: ディザリングの効きを実機で目視確認する画面（仕様書 11-2）。
///
/// **この確認が済むまで、ディザリングの項目を「完了」にしてはいけない**（仕様書 3.2）。
/// モデルは画面を見られないので、人間がここで確認して結果をコミットメッセージに残す。
///
/// 見るべきもの:
/// - ディザ OFF で、コントラスト 2〜3% の縞が「段々」に見えること（問題の再現）
/// - ディザ ON で、同じ条件の縞が滑らかな濃淡に見えること
/// - ディザ ON でざらつきが刺激より目立たないこと（振幅が過大でないこと）
class DitherCheckScreen extends StatefulWidget {
  const DitherCheckScreen({required this.shader, super.key});

  final GaborShader shader;

  /// 仕様書 3.2 が名指しする検証帯。2〜5% が滑らかに見えることを確認する。
  static const List<double> checkContrasts = <double>[0.01, 0.02, 0.03, 0.05];

  @override
  State<DitherCheckScreen> createState() => _DitherCheckScreenState();
}

class _DitherCheckScreenState extends State<DitherCheckScreen> {
  bool _ditherOn = true;
  double _cyclesPerDegree = GaborParams.defaultCyclesPerDegree;

  @override
  Widget build(BuildContext context) {
    final ViewingGeometry geometry = currentViewingGeometry();
    final double wavelengthArcmin = ViewingGeometry.arcminFromCyclesPerDegree(
      _cyclesPerDegree,
    );
    final double lambdaPx = geometry.logicalPixelsFromArcmin(wavelengthArcmin);
    final double diameterPx = 6 * lambdaPx;

    return Scaffold(
      appBar: AppBar(title: const Text('ディザリング確認')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 24,
                    runSpacing: 24,
                    children: <Widget>[
                      for (final double contrast
                          in DitherCheckScreen.checkContrasts)
                        _PatchTile(
                          shader: widget.shader,
                          geometry: geometry,
                          params: GaborParams(
                            contrast: contrast,
                            wavelengthArcmin: wavelengthArcmin,
                            // 向きは固定。ここで測るのは見えやすさではなく段差の有無。
                            orientation: GaborOrientation.deg45,
                          ),
                          ditherAmplitude: _ditherOn
                              ? GaborShader.defaultDitherAmplitude
                              : 0.0,
                          boxSize: (diameterPx + 24).clamp(96.0, 320.0),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            _Controls(
              ditherOn: _ditherOn,
              onDitherChanged: (bool value) =>
                  setState(() => _ditherOn = value),
              cyclesPerDegree: _cyclesPerDegree,
              onCyclesPerDegreeChanged: (double value) =>
                  setState(() => _cyclesPerDegree = value),
              lambdaPx: lambdaPx,
              diameterPx: diameterPx,
            ),
          ],
        ),
      ),
    );
  }
}

class _PatchTile extends StatelessWidget {
  const _PatchTile({
    required this.shader,
    required this.geometry,
    required this.params,
    required this.ditherAmplitude,
    required this.boxSize,
  });

  final GaborShader shader;
  final ViewingGeometry geometry;
  final GaborParams params;
  final double ditherAmplitude;
  final double boxSize;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      SizedBox(
        width: boxSize,
        height: boxSize,
        child: GaborView(
          shader: shader,
          params: params,
          geometry: geometry,
          ditherAmplitude: ditherAmplitude,
          // タイルごとにパターンをずらし、同じノイズが並んで見えないようにする。
          ditherSeed: params.contrast * 1000,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'C = ${(params.contrast * 100).toStringAsFixed(0)}%',
        style: const TextStyle(
          color: Palette.subtleTextOnMidGray,
          fontSize: 12,
        ),
      ),
    ],
  );
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.ditherOn,
    required this.onDitherChanged,
    required this.cyclesPerDegree,
    required this.onCyclesPerDegreeChanged,
    required this.lambdaPx,
    required this.diameterPx,
  });

  final bool ditherOn;
  final ValueChanged<bool> onDitherChanged;
  final double cyclesPerDegree;
  final ValueChanged<double> onCyclesPerDegreeChanged;
  final double lambdaPx;
  final double diameterPx;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: ditherOn,
          onChanged: onDitherChanged,
          title: const Text('ディザリング'),
          subtitle: Text(
            ditherOn ? '±1/255 の TPDF ノイズを加算中' : 'OFF（比較用。本番では使わない）',
            style: const TextStyle(
              color: Palette.subtleTextOnMidGray,
              fontSize: 12,
            ),
          ),
        ),
        Row(
          children: <Widget>[
            const Text('空間周波数'),
            Expanded(
              child: Slider(
                min: 1,
                max: 16,
                divisions: 30,
                value: cyclesPerDegree,
                label: '${cyclesPerDegree.toStringAsFixed(1)} cpd',
                onChanged: onCyclesPerDegreeChanged,
              ),
            ),
            Text('${cyclesPerDegree.toStringAsFixed(1)} cpd'),
          ],
        ),
        Text(
          'λ = ${lambdaPx.toStringAsFixed(1)} 論理px / '
          '描画サイズ 6σ = ${diameterPx.toStringAsFixed(1)} 論理px\n'
          '視距離 40cm 固定の前提（未決事項A の暫定方針）',
          style: const TextStyle(
            color: Palette.subtleTextOnMidGray,
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}
