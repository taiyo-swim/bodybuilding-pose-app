import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import type { Athlete, Contest, Dataset } from '../types'
import { slugify } from './search'

interface Store {
  dataset: Dataset
  contests: Contest[] // 日付昇順
  contestById: Map<string, Contest>
  athletes: Athlete[]
  athleteById: Map<string, Athlete>
  today: string
}

const DataContext = createContext<Store | null>(null)

export const athleteId = (name: string) => slugify(name)
export const hasResults = (c: Contest) => !!c.results?.some((r) => r.placings.length > 0)

function buildAthletes(contests: Contest[], ja: Record<string, string>): Athlete[] {
  const map = new Map<string, Athlete>()
  const get = (name: string, country?: string) => {
    const id = athleteId(name)
    let a = map.get(id)
    if (!a) {
      a = { id, name, nameJa: ja[name], country, divisions: [], records: [], upcoming: [], wins: 0 }
      map.set(id, a)
    }
    if (!a.country && country) a.country = country
    return a
  }
  for (const c of contests) {
    for (const r of c.results ?? []) {
      for (const p of r.placings) {
        const a = get(p.athlete, p.country)
        if (!a.divisions.includes(r.division)) a.divisions.push(r.division)
        a.records.push({
          contestId: c.id, contestName: c.name, date: c.date, division: r.division,
          place: p.place, fieldSize: r.placings.length, score: p.score, scorecardUrl: r.scorecardUrl,
        })
        if (p.place === 1) a.wins++
        if (a.bestPlace === undefined || p.place < a.bestPlace) a.bestPlace = p.place
      }
    }
    if (!hasResults(c)) {
      for (const [division, names] of Object.entries(c.entrants ?? {})) {
        for (const name of names) {
          const a = get(name)
          if (!a.divisions.includes(division)) a.divisions.push(division)
          a.upcoming.push({ contestId: c.id, contestName: c.name, date: c.date, division })
        }
      }
    }
  }
  for (const a of map.values()) a.records.sort((x, y) => y.date.localeCompare(x.date))
  return [...map.values()].sort((x, y) => x.name.localeCompare(y.name))
}

function localToday() {
  const d = new Date()
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

export function DataProvider({ children }: { children: ReactNode }) {
  const [raw, setRaw] = useState<{ dataset: Dataset; ja: Record<string, string> } | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const base = import.meta.env.BASE_URL
    Promise.all([
      fetch(`${base}data/contests.json`).then((r) => {
        if (!r.ok) throw new Error(`contests.json: HTTP ${r.status}`)
        return r.json() as Promise<Dataset>
      }),
      fetch(`${base}data/athletes_ja.json`)
        .then((r) => (r.ok ? (r.json() as Promise<Record<string, string>>) : {}))
        .catch(() => ({})),
    ])
      .then(([dataset, ja]) => setRaw({ dataset, ja }))
      .catch((e) => setError(String(e)))
  }, [])

  const store = useMemo<Store | null>(() => {
    if (!raw) return null
    const contests = [...raw.dataset.contests].sort((a, b) => a.date.localeCompare(b.date))
    const athletes = buildAthletes(contests, raw.ja)
    return {
      dataset: raw.dataset,
      contests,
      contestById: new Map(contests.map((c) => [c.id, c])),
      athletes,
      athleteById: new Map(athletes.map((a) => [a.id, a])),
      today: localToday(),
    }
  }, [raw])

  if (error) return <div className="p-8 text-red-600">データの読み込みに失敗しました: {error}</div>
  if (!store) return <div className="p-8 text-zinc-500">読み込み中…</div>
  return <DataContext.Provider value={store}>{children}</DataContext.Provider>
}

export function useData() {
  const s = useContext(DataContext)
  if (!s) throw new Error('useData must be used inside DataProvider')
  return s
}
