// 英語のディビジョン名・国コードを日本語に変換する

export const DIVISIONS: Record<string, { ja: string; en: string; order: number }> = {
  'mens-open': { ja: 'メンズ ボディビル（オープン）', en: "Men's Open Bodybuilding", order: 1 },
  '212': { ja: '212 ボディビル', en: '212 Bodybuilding', order: 2 },
  'classic-physique': { ja: 'クラシックフィジーク', en: 'Classic Physique', order: 3 },
  'mens-physique': { ja: 'メンズフィジーク', en: "Men's Physique", order: 4 },
  'womens-bodybuilding': { ja: 'ウィメンズ ボディビル', en: "Women's Bodybuilding", order: 5 },
  'womens-physique': { ja: 'ウィメンズフィジーク', en: "Women's Physique", order: 6 },
  figure: { ja: 'フィギュア', en: 'Figure', order: 7 },
  fitness: { ja: 'フィットネス', en: 'Fitness', order: 8 },
  wellness: { ja: 'ウェルネス', en: 'Wellness', order: 9 },
  bikini: { ja: 'ビキニ', en: 'Bikini', order: 10 },
  'wheelchair': { ja: '車いすボディビル', en: 'Wheelchair', order: 11 },
}

export const divisionJa = (id: string) => DIVISIONS[id]?.ja ?? id
export const divisionEn = (id: string) => DIVISIONS[id]?.en ?? id
export const sortDivisions = (ids: string[]) =>
  [...ids].sort((a, b) => (DIVISIONS[a]?.order ?? 99) - (DIVISIONS[b]?.order ?? 99))

const COUNTRIES: Record<string, string> = {
  US: 'アメリカ', CA: 'カナダ', MX: 'メキシコ', BR: 'ブラジル', AR: 'アルゼンチン', CO: 'コロンビア',
  CL: 'チリ', PE: 'ペルー', EC: 'エクアドル', VE: 'ベネズエラ', DO: 'ドミニカ共和国', PR: 'プエルトリコ',
  GB: 'イギリス', IE: 'アイルランド', FR: 'フランス', DE: 'ドイツ', IT: 'イタリア', ES: 'スペイン',
  PT: 'ポルトガル', NL: 'オランダ', BE: 'ベルギー', CH: 'スイス', AT: 'オーストリア', PL: 'ポーランド',
  CZ: 'チェコ', SK: 'スロバキア', HU: 'ハンガリー', RO: 'ルーマニア', BG: 'ブルガリア', GR: 'ギリシャ',
  SE: 'スウェーデン', NO: 'ノルウェー', FI: 'フィンランド', DK: 'デンマーク', RU: 'ロシア', UA: 'ウクライナ',
  TR: 'トルコ', EG: 'エジプト', ZA: '南アフリカ', MA: 'モロッコ', AE: 'アラブ首長国連邦', SA: 'サウジアラビア',
  KW: 'クウェート', QA: 'カタール', BH: 'バーレーン', OM: 'オマーン', IR: 'イラン', IQ: 'イラク',
  JO: 'ヨルダン', LB: 'レバノン', IL: 'イスラエル', IN: 'インド', PK: 'パキスタン', CN: '中国',
  HK: '香港', TW: '台湾', KR: '韓国', JP: '日本', TH: 'タイ', VN: 'ベトナム', PH: 'フィリピン',
  MY: 'マレーシア', SG: 'シンガポール', ID: 'インドネシア', AU: 'オーストラリア', NZ: 'ニュージーランド',
  KZ: 'カザフスタン', UZ: 'ウズベキスタン', GE: 'ジョージア', AM: 'アルメニア', AZ: 'アゼルバイジャン',
}

export const countryJa = (code?: string) => (code ? COUNTRIES[code.toUpperCase()] ?? code : '')

export const flag = (code?: string) =>
  code && /^[A-Za-z]{2}$/.test(code)
    ? String.fromCodePoint(...[...code.toUpperCase()].map((c) => 0x1f1a5 + c.charCodeAt(0)))
    : ''

const WEEKDAYS = ['日', '月', '火', '水', '木', '金', '土']

export function formatDate(date: string, endDate?: string) {
  const fmt = (s: string) => {
    const d = new Date(s + 'T00:00:00')
    return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日(${WEEKDAYS[d.getDay()]})`
  }
  if (!endDate || endDate === date) return fmt(date)
  const e = new Date(endDate + 'T00:00:00')
  return `${fmt(date)}〜${e.getMonth() + 1}月${e.getDate()}日(${WEEKDAYS[e.getDay()]})`
}

export const placeLabel = (p: number) => `${p}位`
