/** ポーズ名（内部ID）→ 日本語表示名 */
export const POSE_LABELS: Record<string, string> = {
  front_double_bicep: 'フロントダブルバイセップス',
  front_lat_spread:   'フロントラットスプレッド',
  most_muscular:      'モストマスキュラー',
  side_chest:         'サイドチェスト',
  rear_lat_spread:    'リアラットスプレッド',
  side_tricep:        'サイドトライセップス',
  abdominal_thigh:    'アブドミナルアンドサイ',
  rear_double_bicep:  'リアダブルバイセップス',
  hands_on_hips:      'ハンズオンヒップ',
  vacuum:             'バキューム',
  side_lat_spread:    'サイドラットスプレッド',
  front_relaxed:      'フロントリラックス',
}

/** 定義済みなら日本語名、未定義（学習した独自ポーズ）ならアンダースコアを空白に置換して返す */
export function poseLabel(name: string): string {
  return POSE_LABELS[name] ?? name.replace(/_/g, ' ')
}
