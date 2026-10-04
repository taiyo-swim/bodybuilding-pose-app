// 検索用の正規化: 大文字小文字・全角半角・アクセント記号・カタカナ/ひらがなの違いを吸収する
export function normalize(s: string) {
  return s
    .normalize('NFKC')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[ぁ-ゖ]/g, (c) => String.fromCharCode(c.charCodeAt(0) + 0x60))
    .toLowerCase()
    .replace(/[\s・\-'’.]/g, '')
}

export function matches(query: string, ...fields: (string | undefined)[]) {
  const q = normalize(query)
  if (!q) return true
  return fields.some((f) => f && normalize(f).includes(q))
}

export const slugify = (s: string) =>
  s
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
