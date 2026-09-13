#version 460 core

// ガボールパッチ = 正弦波格子 × ガウス窓（仕様書 3.1）
//
//   luminance(x, y) = 0.5 + 0.5 * C * exp(-(x² + y²) / (2σ²)) * sin(2π * xr / λ)
//     xr = x·cos(θ) + y·sin(θ)
//     σ  = λ
//     描画サイズ = 6σ
//
// このシェーダーは刺激だけでなく、固視点表示中やブランク中の背景も描く。
// 背景と刺激を同じ1枚で塗ることで、パッチと周囲の間に継ぎ目が出ない。
// C = 0 を渡せば一様な中間グレーになる。
//
// ---------------------------------------------------------------------------
// 座標系について
//
// FlutterFragCoord() の y は下向き。この向きのまま xr を計算すると、
//   θ=0   → 縦縞（輝度が x 方向に変化する）
//   θ=90  → 横縞
//   θ=45  → 変調軸が右下方向、縞は右上〜左下に走る
//   θ=135 → 縞は左上〜右下に走る
// となり、仕様書 4.1 の回答方向テーブルとそのまま一致する。
// ---------------------------------------------------------------------------
//
// TODO(要確認): ガンマの扱いが仕様書に書かれていない。
// 現状はフォーミュラをそのまま 8bit sRGB のコード値として出力している（仕様書 3.1 の字義通り）。
// 表示装置のガンマ（概ね 2.2）を考慮すると、コード値上の C と網膜上の輝度コントラストは一致しない。
// 低コントラスト条件の数値を対外的に「コントラスト3%」と呼ぶなら、
// 線形化して計算するか、C の定義を「コード値上の変調」と明記するかを決める必要がある。
// 決定するまでこのファイルを変更しないこと（仕様書 12）。

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;         // 描画領域のサイズ（論理px）
uniform float uContrast;    // C: マイケルソンコントラスト 0..1
uniform float uLambdaPx;    // λ: 波長（論理px）。σ も同値
uniform float uThetaRad;    // θ: 向き（ラジアン）
uniform float uRadiusSigma; // 描画半径をσの倍数で指定。3.0 で「描画サイズ = 6σ」

out vec4 fragColor;

const float kPi = 3.1415926535897932;

// 背景は中間グレー sRGB 128（仕様書 3.1）。
// 仕様書の式の定数項は 0.5 だが、0.5 と 128/255 では 0.4/255 ずれる。
// パッチの平均輝度を周囲と厳密に一致させるほうが重要なので、両方 128/255 に揃える。
const float kMidGray = 128.0 / 255.0;

void main() {
    // パッチの表示位置は常に画面中央固定（仕様書 3.1）。移動させない。
    vec2 p = FlutterFragCoord().xy - uSize * 0.5;

    float sigma = uLambdaPx; // σ = λ（仕様書 3.1）

    // 描画サイズ = 6σ。半径 3σ の外側は完全に背景と同値にする。
    // exp(-3²/2) ≈ 0.0111 なので、C = 0.6（上限）でも切り落とす段差は
    // 0.5 * 0.6 * 0.0111 ≈ 0.0033 → 8bit で 0.85 階調。1階調に満たないため視認されない。
    float r = length(p);
    float cutoff = step(r, uRadiusSigma * sigma);

    float xr = p.x * cos(uThetaRad) + p.y * sin(uThetaRad);
    float envelope = exp(-dot(p, p) / (2.0 * sigma * sigma)) * cutoff;
    float grating = sin(2.0 * kPi * xr / uLambdaPx);

    float lum = kMidGray + 0.5 * uContrast * envelope * grating;

    fragColor = vec4(vec3(clamp(lum, 0.0, 1.0)), 1.0);
}
