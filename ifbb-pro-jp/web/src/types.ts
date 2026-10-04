// public/data/contests.json のスキーマ（scraper/ が出力する形式）

export interface Placing {
  place: number
  athlete: string // 英語表記の選手名（公式表記のまま）
  country?: string // ISO 3166-1 alpha-2
  score?: number // スコアカードの合計点（低いほど上位）
}

export interface DivisionResult {
  division: string // DivisionId（lib/i18n.ts 参照）
  placings: Placing[]
  scorecardUrl?: string
}

export interface Contest {
  id: string
  name: string
  date: string // YYYY-MM-DD
  endDate?: string
  city?: string
  country?: string
  promoter?: string
  url?: string // 公式ページ
  olympiaQualifier?: boolean
  divisions: string[]
  entrants?: Record<string, string[]> // 出場予定選手（ディビジョン別）
  results?: DivisionResult[]
}

export interface Dataset {
  generatedAt: string
  source: 'sample' | 'scraped'
  contests: Contest[]
}

// 以下はフロントエンド側で派生させるデータ
export interface AthleteRecord {
  contestId: string
  contestName: string
  date: string
  division: string
  place: number
  fieldSize: number
  score?: number
  scorecardUrl?: string
}

export interface Athlete {
  id: string
  name: string
  nameJa?: string
  country?: string
  divisions: string[]
  records: AthleteRecord[] // 新しい順
  upcoming: { contestId: string; contestName: string; date: string; division: string }[]
  wins: number
  bestPlace?: number
}
