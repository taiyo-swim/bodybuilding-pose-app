#!/bin/bash
# 開発サーバー起動: バックエンド(8000) + Vite dev server(5173)
set -e
export PATH="/opt/homebrew/bin:$PATH"
cd "$(dirname "$0")"

if [ ! -d venv ]; then
  echo "❌ venv/ がありません。先に以下を実行してください:"
  echo "   python3.11 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
  exit 1
fi

# バックエンド起動
source venv/bin/activate
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload &
BACK_PID=$!

# Vite を終了したらバックエンドも確実に落とす
cleanup() {
  kill "$BACK_PID" 2>/dev/null || true
  wait "$BACK_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "🔧 バックエンド: http://localhost:8000"
echo "🎨 フロントエンド: http://localhost:5173"

# フロントエンド開発サーバー起動
cd frontend
if [ ! -d node_modules ]; then npm install; fi
npm run dev
