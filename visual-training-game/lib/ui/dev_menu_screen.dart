import 'package:flutter/material.dart';

import '../stimulus/gabor_shader.dart';
import 'dither_check_screen.dart';
import 'palette.dart';

/// 開発用のメニュー。
///
/// 仕様書 9 の「ホーム」画面ではない。Phase 1 の間、実機確認が必要な画面へ
/// 素早く飛ぶための入口として置いている。Phase 2 でホーム画面に置き換える。
class DevMenuScreen extends StatelessWidget {
  const DevMenuScreen({required this.shader, super.key});

  final GaborShader shader;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('開発メニュー（Phase 1）')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Text(
            'モデルは画面を見られない。ここに並ぶ画面は人間が実機で確認し、'
            '結果をコミットメッセージに残すこと（仕様書 12）。',
            style: TextStyle(
              color: Palette.subtleTextOnMidGray,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          _MenuTile(
            title: 'ディザリング確認',
            subtitle: 'コントラスト 1〜5% が段々にならず滑らかに見えるか（仕様書 3.2 / 11-2）',
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => DitherCheckScreen(shader: shader),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: Palette.midGray,
    elevation: 0,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: Palette.subtleTextOnMidGray, width: 0.5),
      borderRadius: BorderRadius.circular(8),
    ),
    child: ListTile(
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: Palette.subtleTextOnMidGray,
          fontSize: 12,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Palette.textOnMidGray),
      onTap: onTap,
    ),
  );
}
