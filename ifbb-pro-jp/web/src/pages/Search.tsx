import { Link, useSearchParams } from 'react-router-dom'
import { useData } from '../lib/data'
import { countryJa, divisionJa } from '../lib/i18n'
import { matches } from '../lib/search'
import ContestCard from '../components/ContestCard'
import { Country } from '../components/Badges'

export default function Search() {
  const [params] = useSearchParams()
  const q = params.get('q') ?? ''
  const { contests, athletes } = useData()

  const contestHits = q ? contests.filter((c) => matches(q, c.name, c.city, c.promoter, countryJa(c.country))).reverse() : []
  const athleteHits = q ? athletes.filter((a) => matches(q, a.name, a.nameJa)) : []

  return (
    <div className="space-y-8">
      <h1 className="text-2xl font-bold">「{q}」の検索結果</h1>

      <section>
        <h2 className="mb-2 text-lg font-bold">選手（{athleteHits.length}）</h2>
        {athleteHits.length ? (
          <ul className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {athleteHits.slice(0, 30).map((a) => (
              <li key={a.id}>
                <Link to={`/athletes/${a.id}`} className="block rounded border border-zinc-200 bg-white px-3 py-2 hover:border-brand">
                  <div className="font-semibold">{a.name} <Country code={a.country} showName={false} /></div>
                  <div className="text-xs text-zinc-500">
                    {a.divisions.map(divisionJa).join(' / ')} ・ 出場{a.records.length}回{a.wins ? ` ・ 優勝${a.wins}回` : ''}
                  </div>
                </Link>
              </li>
            ))}
          </ul>
        ) : <p className="text-sm text-zinc-500">該当なし</p>}
      </section>

      <section>
        <h2 className="mb-2 text-lg font-bold">大会（{contestHits.length}）</h2>
        {contestHits.length ? (
          <div className="grid gap-3 sm:grid-cols-2">
            {contestHits.slice(0, 30).map((c) => <ContestCard key={c.id} contest={c} />)}
          </div>
        ) : <p className="text-sm text-zinc-500">該当なし</p>}
      </section>
    </div>
  )
}
