import { useMemo } from 'react'
import { useSearchParams } from 'react-router-dom'
import { hasResults, useData } from '../lib/data'
import { countryJa, divisionJa, sortDivisions } from '../lib/i18n'
import { matches } from '../lib/search'
import ContestCard from '../components/ContestCard'

const STATUS = [
  { v: '', label: 'すべて' },
  { v: 'upcoming', label: '開催予定' },
  { v: 'results', label: '結果あり' },
]

export default function Schedule() {
  const { contests, today } = useData()
  const [params, setParams] = useSearchParams()
  const get = (k: string) => params.get(k) ?? ''
  const set = (k: string, v: string) => {
    const next = new URLSearchParams(params)
    if (v) next.set(k, v)
    else next.delete(k)
    setParams(next, { replace: true })
  }

  const years = useMemo(() => [...new Set(contests.map((c) => c.date.slice(0, 4)))].sort().reverse(), [contests])
  const countries = useMemo(
    () =>
      [...new Set(contests.map((c) => c.country).filter(Boolean) as string[])].sort((a, b) =>
        countryJa(a).localeCompare(countryJa(b), 'ja'),
      ),
    [contests],
  )
  const divisions = useMemo(() => sortDivisions([...new Set(contests.flatMap((c) => c.divisions))]), [contests])

  const year = get('year')
  const filtered = contests.filter((c) => {
    if (year && !c.date.startsWith(year)) return false
    if (get('month') && c.date.slice(5, 7) !== get('month')) return false
    if (get('country') && c.country !== get('country')) return false
    if (get('division') && !c.divisions.includes(get('division'))) return false
    if (get('status') === 'upcoming' && ((c.endDate ?? c.date) < today || hasResults(c))) return false
    if (get('status') === 'results' && !hasResults(c)) return false
    if (get('olympia') && !c.olympiaQualifier) return false
    return matches(get('q'), c.name, c.city, c.promoter, countryJa(c.country))
  })
  // 結果を見たいときは新しい順、予定を見たいときは近い順
  const ordered = get('status') === 'results' ? [...filtered].reverse() : filtered

  const groups = new Map<string, typeof ordered>()
  for (const c of ordered) {
    const key = c.date.slice(0, 7)
    groups.set(key, [...(groups.get(key) ?? []), c])
  }

  const select = 'rounded border border-zinc-300 bg-white px-2 py-1.5 text-sm'

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">大会スケジュール</h1>

      <div className="rounded-lg border border-zinc-200 bg-white p-4 space-y-3">
        <div className="flex flex-wrap gap-2">
          <input
            value={get('q')}
            onChange={(e) => set('q', e.target.value)}
            placeholder="大会名・都市・プロモーター"
            className={`${select} flex-1 min-w-48`}
          />
          <select value={year} onChange={(e) => set('year', e.target.value)} className={select}>
            <option value="">全期間</option>
            {years.map((y) => <option key={y} value={y}>{y}年</option>)}
          </select>
          <select value={get('month')} onChange={(e) => set('month', e.target.value)} className={select}>
            <option value="">全月</option>
            {Array.from({ length: 12 }, (_, i) => String(i + 1).padStart(2, '0')).map((m) => (
              <option key={m} value={m}>{Number(m)}月</option>
            ))}
          </select>
          <select value={get('country')} onChange={(e) => set('country', e.target.value)} className={select}>
            <option value="">全ての国</option>
            {countries.map((c) => <option key={c} value={c}>{countryJa(c)}</option>)}
          </select>
          <select value={get('division')} onChange={(e) => set('division', e.target.value)} className={select}>
            <option value="">全ディビジョン</option>
            {divisions.map((d) => <option key={d} value={d}>{divisionJa(d)}</option>)}
          </select>
        </div>
        <div className="flex flex-wrap items-center gap-4 text-sm">
          <div className="flex rounded border border-zinc-300 overflow-hidden">
            {STATUS.map((s) => (
              <button
                key={s.v}
                onClick={() => set('status', s.v)}
                className={`px-3 py-1 ${get('status') === s.v ? 'bg-zinc-900 text-white' : 'bg-white hover:bg-zinc-100'}`}
              >
                {s.label}
              </button>
            ))}
          </div>
          <label className="flex items-center gap-1">
            <input type="checkbox" checked={!!get('olympia')} onChange={(e) => set('olympia', e.target.checked ? '1' : '')} />
            オリンピア予選のみ
          </label>
          <span className="ml-auto text-zinc-500">{filtered.length} 件</span>
        </div>
      </div>

      {[...groups].map(([ym, list]) => (
        <section key={ym}>
          <h2 className="mb-2 border-b border-zinc-300 pb-1 font-bold text-zinc-700">
            {ym.slice(0, 4)}年{Number(ym.slice(5))}月
          </h2>
          <div className="grid gap-3 sm:grid-cols-2">
            {list.map((c) => <ContestCard key={c.id} contest={c} />)}
          </div>
        </section>
      ))}
      {!filtered.length && <p className="text-zinc-500">条件に合う大会はありません。</p>}
    </div>
  )
}
