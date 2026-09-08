#!/bin/bash
# 本番モード: フロントエンドをビルドしてバックエンドから一括配信する
set -e
export PATH="/opt/homebrew/bin:$PATH"
cd "$(dirname "$0")"

if [ ! -d venv ]; then
  echo "❌ venv/ がありません。先に以下を実行してください:"
  echo "   python3.11 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
  exit 1
fi

echo "📦 フロントエンドをビルド中..."
cd frontend
if [ ! -d node_modules ]; then npm install; fi
npm run build
cd ..

echo "🚀 サーバー起動中... → http://localhost:8000"
source venv/bin/activate
exec uvicorn backend.main:app --host 0.0.0.0 --port 8000
