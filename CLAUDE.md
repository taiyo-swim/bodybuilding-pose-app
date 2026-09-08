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
    │       src/lib/pywebview.ts  ← デスクトップ版ネイティブダイアログ連携
    │
    └── Backend (FastAPI + uvicorn, port 8000)
            audio_analyzer.py    ← librosa 音楽解析
            pose_extractor.py    ← MediaPipe ポーズ抽出
            routine_generator.py ← ルーティン生成ロジック
            database.py          ← SQLite CRUD
```

### 時刻の扱い（重要）

ルーティンは曲の一部（トリム区間）だけを使うことがあるため、2つの時間軸が存在する。

| 時間軸 | 意味 | 使う場所 |
|--------|------|---------|
| 曲内時刻 | オーディオファイルの先頭からの秒数 | `audio.currentTime`、`energy_curve` の参照 |
| ルーティン内部時刻 | トリム区間の先頭を0とした秒数 | `pose_sequence[].time`、`beat_times`、UI表示 |

変換は `routineTime = audio.currentTime - trim_start`。
バックエンドは `trim_start` をレスポンスとDBの両方に含めるので、
保存済みルーティンを読み戻しても位置合わせできる。

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

# バックエンドのテスト
pip install -r requirements-dev.txt
pytest

# フロントエンドの型チェック + Lint
cd frontend && npm run build && npm run lint

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
| `tests/` | pytest。DB・ルーティン生成・音楽解析ヘルパー・API層を検証 |

`backend/main.py` の注意点:

- `frontend/dist` が存在しない場合は静的マウントをスキップする
  （`./dev.sh` はViteが配信するため。無条件にマウントするとimport時に落ちる）
- `uploads/` のファイル名は必ず `_safe_upload_path()` を通す（パストラバーサル防止）
- `analyze_audio` / `extract_representative_pose` は例外を422に変換して返す

### フロントエンド

| ファイル | 責務 |
|---------|------|
| `frontend/src/App.tsx` | ルート状態管理（audio, routine, player, viewer の橋渡し） |
| `frontend/src/lib/viewer3d.ts` | Three.js シーン、GLBロード、ボーントランジション |
| `frontend/src/lib/player.ts` | Web Audio再生、ルーティン時刻→ポーズ同期、ビート検出 |
| `frontend/src/lib/api.ts` | fetch ラッパー。全エンドポイントの型付きAPIクライアント |
| `frontend/src/lib/pywebview.ts` | `window.pywebview.api` 経由のネイティブファイル選択 |
| `frontend/src/lib/poseLabels.ts` | ポーズ名（内部ID）→日本語表示名の変換 |
| `frontend/src/types.ts` | `AudioAnalysis`, `Pose`, `Routine`, `PoseEntry` などの共通型 |

### デスクトップ版（pywebview）のファイル選択フロー

ブラウザとデスクトップでファイル入力の経路が異なる。`isDesktop()` で分岐する。

```
ブラウザ      : <input type="file"> → POST /api/audio/upload      （multipart）
デスクトップ  : window.pywebview.api.pick_audio()
                 → Python が uploads/ にコピーしてファイル名を返す
                 → POST /api/audio/analyze?filename=...           （ファイル名のみ）
```

動画は `pick_video` + `/api/video/analyze`、モデルは `pick_model` + `/api/models` を使う。

### CSS の注意点（Tailwind v4）

Tailwind v4 はユーティリティを CSS cascade layer に出力する。
**レイヤー外のスタイルはレイヤー内より詳細度に関係なく優先される**ため、
`src/index.css` のリセット（`* { padding: 0 }` など）は必ず `@layer base` に入れること。
レイヤー外に置くと `p-4` などの余白ユーティリティがすべて無効になり、UIが崩れる。

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

1. `applyPredefinedPose()` 呼び出し時に全ボーン（`POSED_BONES`）の現在回転をキャプチャ（`transitionSource`）
2. 全ボーンのターゲット回転をセット（`targetRotations`）。定義外ボーンはバインドポーズに戻す
3. `transitionProgress` を 0 にリセット
4. `animate()` ループ内で 0.8秒かけて `easeInOut` 補間
5. 完了後はターゲット回転を毎フレーム維持（ドリフト防止）

Spineの呼吸アニメーションは、毎フレーム基準姿勢（ターゲット or バインドポーズ）を
`copy()` してから揺らぎを足す。`rotation.x +=` だけだと累積してドリフトする。

`resetPose()` は単位クォータニオンではなく **バインドポーズ** に戻すこと。
単位回転にすると脚や腰の初期姿勢まで壊れる。

### モデル未ロード時の扱い

- GLBが無い/読み込み前は簡易人型（`showPlaceholder()`）を表示する
- 読み込み中に要求されたポーズは `pendingPose` に保持し、ロード完了後に適用する
- `loadModel()` は旧モデルのジオメトリ/マテリアル/テクスチャを `disposeModel()` で解放する
- `destroy()` は `window` の resize リスナーを**同一関数参照**で解除する
  （`removeEventListener('resize', () => ...)` は別関数なので解除されない）

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
3. 直近2ポーズと重複しないよう制御
4. BPM別スイッチ間隔: <110→4拍、110〜140→8拍、140+→12拍

### タイミング決定（`_switch_times`）

- ビートが十分にある場合はビートに合わせ、無い/少ない場合はBPMから等間隔で生成する
  （ビート検出に失敗した曲でも必ずルーティンができる）
- ルーティンは必ず 0秒 から始める
- `MIN_HOLD`(2秒) 未満の間隔は間引き、`MAX_HOLD`(8秒) を超える間隔は分割する

### エネルギーの参照（`_energy_at`）

`energy_curve` は**曲全体**を16分割したものなので、トリム区間のポーズを選ぶときは
ルーティン内部時刻ではなく **曲内時刻 (`trim_start + t`)** で参照する。
内部時刻で引くと、曲の後半だけを切り出しても曲頭のエネルギーが使われてしまう。
区間の境界では線形補間する。

---

## 制約事項

- 全ライブラリ無料・OSSのみ
- 外部有料API・クラウドサービスは使用しない
- ローカルで完結（インターネット不要で動作）
- 動画ソース: スマートフォン撮影または手持ち動画（YouTube等は使用しない）

---

## データベーススキーマ

```sql
poses(id, name, category, energy_level, keypoints TEXT, created_at)
routines(id, name, audio_file, bpm, duration, pose_sequence TEXT,
         trim_start REAL, beat_times TEXT, created_at)
```

`routines.trim_start` / `beat_times` は保存済みルーティンを再生するために必須。
`init_db()` は `PRAGMA table_info` を見て、旧DBにこれらの列を `ALTER TABLE` で追加する
（マイグレーション処理を消さないこと）。

テスト時は環境変数 `POSE_DB_PATH` でDBの場所を差し替えられる。

---

## .gitignore すべきもの

```
venv/
frontend/node_modules/
frontend/dist/
uploads/
training_videos/
poses_db/
models/
__pycache__/
.pytest_cache/
*.pyc
.DS_Store
```

---

## 今後の課題

- ポーズ回転値のチューニング（実機のMixamoモデルでの視覚確認が必要）
- ポーズホールド時間の手動調整機能（現在はBPMから自動決定のみ）
- ポーズシーケンスの手動並び替え・差し替えUI
- `uploads/` の自動クリーンアップ
