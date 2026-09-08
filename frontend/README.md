# frontend

Bodybuilding Pose App のフロントエンド (React 19 + TypeScript + Vite + Tailwind CSS 4 + Three.js)。

通常はリポジトリルートの `./dev.sh` / `./start.sh` から起動する。
このディレクトリ単体で操作する場合は以下を使う。

```bash
npm install       # 依存関係のインストール
npm run dev       # 開発サーバー (http://localhost:5173、/api と /models は :8000 にプロキシ)
npm run build     # 型チェック + 本番ビルド → dist/
npm run lint      # ESLint
```

`npm run dev` はバックエンド (`uvicorn backend.main:app --port 8000`) が
起動していることを前提にしている。

## 構成

| パス | 役割 |
|------|------|
| `src/App.tsx` | ルート状態管理（音源・ルーティン・ポーズ・モデル） |
| `src/components/` | サイドバーの各パネルと3Dビュー・再生バー |
| `src/lib/viewer3d.ts` | Three.js シーン、GLBロード、ボーンアニメーション |
| `src/lib/player.ts` | 音楽再生とポーズ表示の同期 |
| `src/lib/api.ts` | バックエンドAPIクライアント |
| `src/lib/pywebview.ts` | デスクトップ版のネイティブファイル選択ダイアログ連携 |
| `src/lib/poseLabels.ts` | ポーズ名の日本語表示 |

## スタイルの注意点

Tailwind CSS 4 はユーティリティを CSS cascade layer に出力する。
レイヤー外のスタイルはレイヤー内のスタイルより詳細度に関係なく優先されるため、
`src/index.css` のリセット (`* { padding: 0 }` など) は必ず `@layer base` の中に置くこと。
レイヤー外に書くと `p-4` などの余白ユーティリティがすべて無効になる。
