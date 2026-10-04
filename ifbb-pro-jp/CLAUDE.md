# CLAUDE.md — IFBB PRO 日本語ナビ

IFBB Professional League のプロコンテストの **スケジュール・出場選手・結果（スコアカード）** を
日本語で検索できる非公式 Web サイト。詳細は README.md。

## 構成

- `web/` — React 19 + TypeScript + Vite + Tailwind v4 の静的サイト（HashRouter、`base: './'`）
  - データは `web/public/data/contests.json`（scraper の出力）と `athletes_ja.json`（選手名カタカナ、手動）
  - `src/lib/data.tsx` で読み込み、選手一覧は大会結果から派生生成
  - `src/lib/i18n.ts` にディビジョン・国名の日本語対応表
- `scraper/` — Python。`scrape.py` が ifbbpro.com からスケジュール・大会ページを取得・解析
  - `divisions.py` 英語ディビジョン名の正規化、`test_parse.py` 通信なしのパーサーテスト
  - `sample_data.py` 架空のサンプルデータ生成（`source: "sample"` のとき画面に警告バナー）

## コマンド

```bash
cd web && npm install && npm run dev      # 開発サーバー
cd web && npm run build                   # 型チェック + ビルド
cd scraper && python test_parse.py        # パーサーテスト
cd scraper && python scrape.py --limit 5  # 実データを数件取得
```

## 現状と最優先タスク

- 現在の contests.json は **架空のサンプルデータ**。
- `scrape.py` は ifbbpro.com に接続できない環境で書かれたため、**実際の HTML では未検証**。
  まず `python scrape.py --limit 5` を実行し、`scraper/cache/` に保存された実 HTML を見て
  `parse_schedule` / `parse_contest` / `parse_division_sections` のセレクタを調整すること。
  修正したら実 HTML の一部を使ったテストケースを `test_parse.py` に追加する。

## 方針

- 非公式サイトである旨と公式サイトへのリンクを必ず表示する
- スクレイピングは robots.txt を尊重し、リクエスト間隔を空ける（既定 2 秒）。キャッシュを再利用する
- 実在選手の結果を捏造しない。取得できないデータは空のままにする
