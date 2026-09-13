import 'package:flutter/material.dart';

import 'stimulus/gabor_shader.dart';
import 'ui/dev_menu_screen.dart';
import 'ui/palette.dart';

/// アプリのルート。
///
/// [GaborShader] はプロセスに1つだけ持ち、uniform を差し替えて使い回す。
/// 画面ごとに読み込むと提示タイミングが揺れる。
class VisualTrainingApp extends StatefulWidget {
  const VisualTrainingApp({super.key});

  @override
  State<VisualTrainingApp> createState() => _VisualTrainingAppState();
}

class _VisualTrainingAppState extends State<VisualTrainingApp> {
  GaborShader? _shader;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
      final GaborShader shader = await GaborShader.load();
      if (!mounted) {
        shader.dispose();
        return;
      }
      setState(() => _shader = shader);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '見る力を試すゲーム',
    theme: Palette.theme(),
    home: Builder(
      builder: (BuildContext context) {
        final Object? error = _error;
        if (error != null) {
          return _ShaderLoadFailure(error: error);
        }
        final GaborShader? shader = _shader;
        if (shader == null) {
          return const ColoredBox(
            color: Palette.midGray,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return DevMenuScreen(shader: shader);
      },
    ),
  );
}

class _ShaderLoadFailure extends StatelessWidget {
  const _ShaderLoadFailure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'シェーダーの読み込みに失敗した。\n'
          'pubspec.yaml の shaders に gabor.frag が登録されているか確認すること。\n\n'
          '$error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Palette.textOnMidGray),
        ),
      ),
    ),
  );
}
