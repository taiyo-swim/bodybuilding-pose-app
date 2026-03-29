# CLAUDE.md — Bodybuilding Pose App

## プロジェクト概要

音楽をアップロードし、BPM・エネルギー解析に基づいたボディビルフリーポーズルーティンを
自動生成して3Dアニメーションで表示するデスクトップ/Webアプリ。

---

## アーキテクチャ

```
Browser / pywebview
    │
    ├── Frontend (React 19 + TypeScript + Three.js)
    │       src/lib/viewer3d.ts   ← 3D描画・ボーンアニメーション
    │       src/lib/player.ts     ← 音楽×ポーズ同期
    │       src/lib/api.ts        ← REST APIクライアント
    │
    └── Backend (FastAPI + uvicorn, port 8000)
            audio_analyzer.py    ← librosa 音楽解析
            pose_extractor.py    ← MediaPipe ポーズ抽出
            routine_generator.py ← ルーティン生成ロジック
            database.py          ← SQLite CRUD
```

---

## 環境

- **OS**: macOS (Apple Silicon)
- **Python**: 3.11 (Homebrew) — 仮想環境 `venv/`
- **Node.js**: 18+
- **仮想環境**: `source venv/bin/activate` で有効化

---

## よく使うコマンド

```bash
# 開発サーバー起動（バックエンド + Vite dev server）
./dev.sh

# 本番ビルド & サーバー起動
./start.sh

# デスクトップアプリ起動（pywebview）
python app.py

# フロントエンドビルドのみ
cd frontend && npm run build

# ポーズ学習スクリプト
python train_poses.py            # training_videos/ を一括処理
python train_poses.py --list     # DB確認
python train_poses.py --clear    # DBリセット
```

---

## 重要なファイルと責務

### バックエンド

| ファイル | 責務 |
|---------|------|
| `backend/main.py` | 全APIエンドポイント。`/api/audio/upload`, `/api/routine/generate`, `/api/poses` など |
| `backend/audio_analyzer.py` | librosa でBPM・ビートタイム・エネルギーカーブを抽出 |
| `backend/routine_generator.py` | エネルギー連動ポーズ選択、ビートタイミングでスイッチタイムを生成 |
| `backend/database.py` | `poses` / `routines` テーブルのSQLite操作 |
| `backend/pose_extractor.py` | MediaPipe で動画から代表フレームのキーポイント抽出 |
| `train_poses.py` | 開発者向け: 動画→MediaPipe→DB一括登録スクリプト |

### フロントエンド

| ファイル | 責務 |
|---------|------|
| `frontend/src/App.tsx` | ルート状態管理（audio, routine, player, viewer の橋渡し） |
| `frontend/src/lib/viewer3d.ts` | Three.js シーン、GLBロード、ボーントランジション |
| `frontend/src/lib/player.ts` | Web Audio再生、ルーティン時刻→ポーズ同期、ビート検出 |
| `frontend/src/lib/api.ts` | fetch ラッパー。全エンドポイントの型付きAPIクライアント |
| `frontend/src/types.ts` | `AudioAnalysis`, `Pose`, `Routine`, `PoseEntry` などの共通型 |

---

## 3Dアニメーション実装詳細（viewer3d.ts）

### Mixamo ボーン座標系

- ボーン名は `mixamorig:BoneName` または `mixamorig1_BoneName` 形式で格納される
- `findBone()` でプレフィックスを除去してベース名でも検索可能
- `bonesByBaseName` マップを使ってO(1)で検索

### Euler角の規則

`POSE_ROTATIONS` のエントリは `[X, Y, Z]` ラジアン、`'XYZ'` 順で適用。

| ボーン | X | Y | Z |
|--------|---|---|---|
| LeftArm | ひねり | 前後・内外回旋 | 上下（+で上） |
| RightArm | ひねり | 前後・内外回旋 | 下上（-で上） |
| Hips | - | 体の向き（π=後ろ向き） | - |

### トランジションの仕組み

1. `applyPredefinedPose()` 呼び出し時に全ボーンの現在回転をキャプチャ（`transitionSource`）
2. 全ボーンのターゲット回転をセット（`targetRotations`）。定義外ボーンはバインドポーズに戻す
3. `transitionProgress` を 0 にリセット
4. `animate()` ループ内で 0.8秒かけて `easeInOut` 補間
5. 完了後はターゲット回転を毎フレーム維持（ドリフト防止）

### 定義済みポーズ一覧（POSE_ROTATIONS）

```
front_double_bicep  front_lat_spread  most_muscular
side_chest          rear_lat_spread   side_tricep
abdominal_thigh     rear_double_bicep
hands_on_hips       vacuum            side_lat_spread  front_relaxed
```

---

## ポーズ選択ロジック（routine_generator.py）

1. DBにポーズが登録されている場合: エネルギーレベル±0.3 の候補から選択
2. DBが空の場合: `DEFAULT_POSES` リスト（ビルトイン12ポーズ）にフォールバック
3. 連続して同じポーズが続かないよう制御
4. BPM別スイッチ間隔: <110→4拍、110〜140→8拍、140+→12拍

---

## 制約事項

- 全ライブラリ無料・OSSのみ
- 外部有料API・クラウドサービスは使用しない
- ローカルで完結（インターネット不要で動作）
- 動画ソース: スマートフォン撮影または手持ち動画（YouTube等は使用しない）

---

## .gitignore すべきもの

```
venv/
frontend/node_modules/
frontend/dist/
uploads/
poses_db/
models/
__pycache__/
*.pyc
.DS_Store
```

---

## 今後の課題

- ポーズ回転値のチューニング（実機での視覚確認が必要）
- ポーズホールド時間の手動調整機能
- 複数3Dモデルの切り替えUI
