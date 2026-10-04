# IFBB PRO 日本語ナビ

IFBB Professional League のプロコンテストについて、**スケジュール・出場選手・結果（スコアカード）** を
日本語で検索できる非公式 Web サイトです。

```
ifbb-pro-jp/
├── scraper/                 公式サイト → contests.json を作る Python スクリプト
│   ├── scrape.py            スケジュール/大会ページを取得・解析
│   ├── divisions.py         英語ディビジョン名 → ID の正規化
│   ├── sample_data.py       動作確認用の架空データ生成
│   └── test_parse.py        パーサーのテスト（通信なし）
└── web/                     React 19 + TypeScript + Vite + Tailwind の静的サイト
    ├── public/data/contests.json      大会データ（scraper の出力）
    ├── public/data/athletes_ja.json   選手名のカタカナ表記（手動で追記: {"英語名": "カタカナ"}）
    └── src/
```

## 機能

| ページ | 内容 |
|-------|------|
| ホーム | 今後の大会 / 最新の結果 |
| スケジュール | 年・月・国・ディビジョン・開催状況・オリンピア予選で絞り込み（条件はURLに保存され共有可能） |
| 大会詳細 | ディビジョン別タブで順位・国・スコア、公式スコアカードへのリンク、出場予定選手 |
| 選手一覧 / 選手詳細 | 名前（英語・カタカナ、ひらがな入力も可）で検索、戦績・優勝回数・出場予定 |
| 横断検索 | ヘッダーの検索窓から大会・選手をまとめて検索 |

ディビジョン名（Men's Open → メンズ ボディビル など）と国名は日本語に変換して表示します（`web/src/lib/i18n.ts`）。

## 使い方

```bash
# 1. データ取得（初回はサンプルデータが入っています）
cd scraper
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python test_parse.py          # パーサーの動作確認
python scrape.py --limit 5    # まず数件だけ取得して結果を確認
python scrape.py              # 全件取得 → ../web/public/data/contests.json

# 2. サイト起動
cd ../web
npm install
npm run dev                   # http://localhost:5173
npm run build                 # dist/ を任意の静的ホスティングへ（GitHub Pages / Netlify / Cloudflare Pages 等）
```

`python sample_data.py` を実行すると架空のサンプルデータに戻せます。サンプルデータ表示中は画面上部に警告が出ます。

## スクレイパーについての注意

- **公式サイトの HTML 構造に合わせた調整が必要になる可能性があります。** 開発環境から ifbbpro.com に
  接続できなかったため、パーサーは実ページではなく想定構造のテスト HTML で検証しています。
  見出しからディビジョンを検出し、その下の「1. 名前 (国)」形式の行・表を拾うヒューリスティックなので、
  取得件数がおかしい場合は `scrape.py` の `parse_schedule` / `parse_contest` / `parse_division_sections` を
  実際の HTML（`scraper/cache/` に保存されます）に合わせて修正してください。
- robots.txt を確認し、リクエスト間隔は既定で 2 秒空けます。取得した HTML はキャッシュして再利用します。
- 取得データは既存の contests.json とマージされます（公式スケジュールから消えた過去大会も残ります）。

## データ形式（contests.json）

```jsonc
{
  "generatedAt": "2026-10-04T00:00:00Z",
  "source": "scraped",            // "sample" のときは警告バナーを表示
  "contests": [{
    "id": "2026-example-pro",
    "name": "2026 Example Pro",
    "date": "2026-03-06", "endDate": "2026-03-07",
    "city": "Columbus", "country": "US",
    "promoter": "...", "url": "https://ifbbpro.com/contest/...",
    "olympiaQualifier": true,
    "divisions": ["mens-open", "bikini"],
    "entrants": { "bikini": ["Anna Smith"] },          // 結果発表前の出場予定選手
    "results": [{
      "division": "mens-open",
      "scorecardUrl": "https://.../scorecard.pdf",
      "placings": [{ "place": 1, "athlete": "John Doe", "country": "US", "score": 5 }]
    }]
  }]
}
```

## 今後の拡張案

- GitHub Actions で毎週 `scrape.py` を実行し、GitHub Pages に自動デプロイ
- スコアカード PDF の表を解析して審査員別の順位を表示
- 選手名カタカナ表記の充実、日本人選手の特集ページ
