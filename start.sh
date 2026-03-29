#!/bin/bash
set -e
export PATH="/opt/homebrew/bin:$PATH"
cd "$(dirname "$0")"

echo "📦 フロントエンドをビルド中..."
cd frontend
if [ ! -d node_modules ]; then npm install; fi
npm run build
cd ..

echo "🚀 サーバー起動中... → http://localhost:8000"
source venv/bin/activate
uvicorn backend.main:app --host 0.0.0.0 --port 8000
