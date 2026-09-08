# Bodybuilding Pose App

音楽をアップロードすると、そのBPM・エネルギーに合わせたボディビルフリーポーズルーティンを自動生成し、Mixamo製3Dキャラクターがリアルタイムにアニメーションするデスクトップ/Webアプリケーション。

---

## 機能概要

- **音楽解析**: librosaでBPM・ビートタイム・エネルギーカーブを抽出
- **トリム機能**: アップロードした曲の任意区間だけでルーティンを作成
- **ルーティン自動生成**: エネルギー連動でポーズを選択し、ビートに合わせてタイミングを決定
- **3Dアニメーション**: Three.js + Mixamo GLBモデルでポーズをスムーズに補間表示
- **モデル切り替え**: 複数のGLBモデルを登録して切り替え可能。モデルが無い場合は簡易人型で動作
- **ルーティン保存**: 生成したルーティンはSQLiteに保存され、一覧から再読み込みできる
- **ポーズライブラリ**: 動画をアップロードしてMediaPipeでキーポイント抽出 → SQLiteに保存
- **デスクトップ連携**: pywebview起動時はネイティブのファイル選択ダイアログを使用
- **開発者向け学習**: `train_poses.py` スクリプトで動画ファイルからポーズを一括登録

---

## 技術スタック

### フロントエンド (`frontend/`)

| カテゴリ | 技術 | バージョン |
|---------|------|-----------|
| フレームワーク | React | 19 |
| 言語 | TypeScript | 5.9 |
| ビルドツール | Vite | 8 |
| スタイリング | Tailwind CSS | 4 |
| 3D描画 | Three.js | 0.183 |

### バックエンド (`backend/`)

| カテゴリ | 技術 | バージョン |
|---------|------|-----------|
| API | FastAPI + uvicorn | 0.115 / 0.34 |
| 音楽解析 | librosa | 0.10 |
| ポーズ推定 | MediaPipe | 0.10 |
| 動画処理 | OpenCV | 4.10 |
| データベース | SQLite (built-in) | - |
| デスクトップ | pywebview | 5.4 |

### 実行環境

- macOS (Apple Silicon 対応)
- Python 3.11 (Homebrew)
- Node.js 18+

---

## ディレクトリ構成

```
bodybuilding-pose-app/
├── app.py                   # pywebview デスクトップ起動エントリポイント
├── dev.sh                   # 開発サーバー起動スクリプト
├── start.sh                 # 本番ビルド & サーバー起動スクリプト
├── train_poses.py           # 開発者向けポーズ学習スクリプト
├── requirements.txt         # Python 依存パッケージ
│
├── backend/
│   ├── main.py              # FastAPI アプリ・全APIエンドポイント定義
│   ├── audio_analyzer.py    # librosa による音楽解析
│   ├── pose_extractor.py    # MediaPipe によるポーズキーポイント抽出
│   ├── routine_generator.py # ポーズルーティン自動生成ロジック
│   └── database.py          # SQLite CRUD操作
│
├── frontend/
│   ├── src/
│   │   ├── App.tsx           # ルートコンポーネント・状態管理
│   │   ├── types.ts          # 共通型定義
│   │   ├── components/
│   │   │   ├── ModelViewer.tsx   # Three.jsキャンバスマウント
│   │   │   ├── AudioPanel.tsx    # 音楽アップロード・トリム・保存済みルーティンUI
│   │   │   ├── PosePanel.tsx     # ポーズライブラリUI
│   │   │   ├── ModelPanel.tsx    # 3Dモデルの追加・切り替えUI
│   │   │   └── PlaybackBar.tsx   # 再生バー・シークUI
│   │   └── lib/
│   │       ├── viewer3d.ts   # Three.js 3D描画・ボーンアニメーション
│   │       ├── player.ts     # 音楽×ポーズ同期プレイヤー
│   │       ├── api.ts        # バックエンドAPIクライアント
│   │       ├── pywebview.ts  # デスクトップ版ネイティブダイアログ連携
│   │       └── poseLabels.ts # ポーズ名の日本語表示
│   ├── package.json
│   └── vite.config.ts
│
├── tests/                   # バックエンドのpytestテスト
│
├── models/                  # Mixamo GLBモデルファイル置き場
├── poses_db/                # SQLiteデータベースファイル
├── training_videos/         # ポーズ学習用動画置き場（train_poses.py が参照）
└── uploads/                 # アップロードされた音楽・動画の一時保存
```

---

## セットアップ

### 1. リポジトリのクローン

```bash
git clone git@github.com:taiyo-swim/bodybuilding-pose-app.git
cd bodybuilding-pose-app
```

### 2. Python 仮想環境のセットアップ

```bash
python3.11 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# テストも実行する場合
pip install -r requirements-dev.txt
```

### 3. フロントエンドの依存関係インストール

```bash
cd frontend
npm install
cd ..
```

### 4. 3Dモデルの配置

[Mixamo](https://www.mixamo.com/) から T-pose キャラクターを GLB 形式でダウンロードし、`models/` フォルダに配置する。ファイル名は任意。

```
models/
└── YourCharacter.glb
```

アプリの **モデルタブ** からアップロードして追加することもできる。複数配置した場合は
モデルタブで切り替えられる。**モデルが1つも無い場合は簡易的な人型が表示され、
ポーズの切り替えタイミングだけ確認できる。**

---

## 起動方法

### 開発モード（ホットリロード）

```bash
source venv/bin/activate
./dev.sh
```

- バックエンド: `http://localhost:8000`
- フロントエンド: `http://localhost:5173`（Vite dev server）

### 本番モード（ビルド済みフロント配信）

```bash
source venv/bin/activate
./start.sh
```

- `http://localhost:8000` でフロントエンドとAPIを一括配信

### デスクトップアプリとして起動（pywebview）

```bash
source venv/bin/activate
python app.py
```

ネイティブウィンドウが開き、ファイル選択ダイアログが使用可能になる。

---

## 使い方

1. **モデルタブ** で3Dモデルを追加する（任意。無い場合は簡易人型で動作する）
2. **音楽タブ** で音楽ファイル（MP3/WAV/FLAC等）をアップロード
3. トリムスライダーでルーティンに使う区間を選択
4. **ルーティン生成** ボタンをクリック → BPMに合わせてポーズシーケンスを自動生成
5. **▶ 再生** ボタン（または `Space` キー）で3Dモデルのアニメーションと音楽を同期再生

生成したルーティンは自動的に保存され、音楽タブの **保存済みルーティン** から再読み込みできる。

### ポーズタブ

動画をアップロードするとMediaPipeでキーポイントを抽出してポーズライブラリに登録される。
一覧のポーズをクリックすると3Dモデルにそのポーズを適用してプレビューでき、`✕` で削除できる。

---

## ポーズの学習（開発者向け）

UIからポーズを登録するのではなく、開発者が動画ファイルを用意してスクリプトで一括学習させる。

### 動画の命名規則

ファイル名（拡張子なし）がポーズ名になる。

| ファイル名 | ポーズ |
|-----------|--------|
| `front_double_bicep.mp4` | フロントダブルバイセップス |
| `front_lat_spread.mp4` | フロントラットスプレッド |
| `most_muscular.mp4` | モストマスキュラー |
| `side_chest.mp4` | サイドチェスト |
| `rear_lat_spread.mp4` | リアラットスプレッド |
| `side_tricep.mp4` | サイドトライセップス |
| `abdominal_thigh.mp4` | アブドミナルアンドサイ |
| `rear_double_bicep.mp4` | リアダブルバイセップス |

### スクリプトの実行

```bash
source venv/bin/activate

# training_videos/ フォルダ内の動画をすべて処理
python train_poses.py

# 単一ファイルをポーズ名指定で登録
python train_poses.py path/to/video.mp4 --name front_double_bicep

# DB内のポーズ一覧を確認
python train_poses.py --list

# DBをリセット（全削除）
python train_poses.py --clear
```

DBにポーズが登録されている場合、ルーティン生成時にそのキーポイントデータが使用される。登録がない場合はビルトインのポーズ定義にフォールバックする。

---

## APIエンドポイント

| メソッド | パス | 説明 |
|---------|------|------|
| GET | `/api/health` | サーバー死活確認 |
| POST | `/api/audio/upload` | 音楽アップロード & 解析 |
| GET | `/api/audio/{filename}` | 音楽ファイル配信（Rangeリクエスト対応） |
| POST | `/api/audio/analyze` | `uploads/` 内の音楽を解析（デスクトップ版用） |
| POST | `/api/video/upload` | 動画アップロード & ポーズ抽出・登録 |
| POST | `/api/video/analyze` | `uploads/` 内の動画を解析・登録（デスクトップ版用） |
| GET | `/api/poses` | ポーズライブラリ一覧（`?category=` で絞り込み） |
| DELETE | `/api/poses/{id}` | ポーズを削除 |
| POST | `/api/routine/generate` | ルーティン自動生成（保存も行う） |
| GET | `/api/routines` | 保存済みルーティン一覧 |
| GET | `/api/routines/{id}` | 保存済みルーティンを取得 |
| DELETE | `/api/routines/{id}` | ルーティンを削除 |
| GET | `/api/models` | 利用可能な3Dモデル一覧 |
| POST | `/api/models/upload` | 3Dモデル(.glb/.gltf)をアップロード |

FastAPI の対話ドキュメントは `http://localhost:8000/docs` で確認できる。

---

## 3Dアニメーションの仕組み

1. `viewer3d.ts` が Mixamo GLBモデルのボーン構造を読み込み、各ボーンの初期回転（バインドポーズ）を保存
2. ポーズ切り替え時に全ボーンのターゲット回転を設定し、0.8秒のease-in-out補間でスムーズにトランジション
3. `player.ts` が音楽の再生位置を監視し、ルーティンのタイムラインに従って `viewer3d.transitionToPose()` を呼び出す
4. ビートタイミングで軽いスケールパルス（`beatPulse()`）を発生させる

---

## テスト

バックエンドのロジック（DB・ルーティン生成・音楽解析・API）は pytest で検証している。

```bash
source venv/bin/activate
pip install -r requirements-dev.txt
pytest
```

テストはDBを一時ディレクトリに切り替えて実行するため、`poses_db/poses.db` には影響しない。
音楽解析・ポーズ抽出のテストは librosa / MediaPipe を呼ばずに済むよう、
純粋な計算部分とAPI層を分けて検証している。

フロントエンドは型チェックとLintで検証する。

```bash
cd frontend
npm run build   # tsc -b + vite build
npm run lint
```

---

## 注意事項

- `models/` 内の GLB ファイルはサイズが大きいため `.gitignore` に含める
- `uploads/` 内のファイルも `.gitignore` に含める
- `poses_db/poses.db` は学習済みデータのため必要に応じて除外する
- `uploads/` は自動削除されないため、ディスク使用量が気になる場合は手動で削除する
- アップロードサイズの上限は 512MB
- 全ライブラリ無料・OSS。外部有料APIは使用しない
