#!/bin/bash
export PATH="/opt/homebrew/bin:$PATH"
cd "$(dirname "$0")"

# バックエンド起動
source venv/bin/activate
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload &
BACK_PID=$!

# フロントエンド開発サーバー起動
cd frontend
if [ ! -d node_modules ]; then npm install; fi
npm run dev

kill $BACK_PID
