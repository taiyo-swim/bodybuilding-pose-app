import { Link, useSearchParams } from 'react-router-dom'
import { useData } from '../lib/data'
import { countryJa, divisionJa, sortDivisions } from '../lib/i18n'
import { matches } from '../lib/search'
import { Country } from '../components/Badges'

const PAGE = 50

export default function Athletes() {
  const { athletes } = useData()
  const [params, setParams] = useSearchParams()
  const q = params.get('q') ?? ''
  const division = params.get('division') ?? ''
  const country = params.get('country') ?? ''
  const sort = params.get('sort') ?? 'name'
  const limit = Number(params.get('n') ?? PAGE)
  const set = (k: string, v: string) => {
    const next = new URLSearchParams(params)
    if (v) next.set(k, v)
    else next.delete(k)
    if (k !== 'n') next.delete('n')
    setParams(next, { replace: true })
  }

  const divisions = sortDivisions([...new Set(athletes.flatMap((a) => a.divisions))])
  const countries = [...new Set(athletes.map((a) => a.country).filter(Boolean) as string[])].sort((a, b) =>
    countryJa(a).localeCompare(countryJa(b), 'ja'),
  )

  const filtered = athletes
    .filter(
      (a) =>
        (!division || a.divisions.includes(division)) &&
        (!country || a.country === country) &&
        matches(q, a.name, a.nameJa),
    )
    .sort((a, b) =>
      sort === 'wins' ? b.wins - a.wins || b.records.length - a.records.length
      : sort === 'contests' ? b.records.length - a.records.length
      : a.name.localeCompare(b.name),
    )

  const select = 'rounded border border-zinc-300 bg-white px-2 py-1.5 text-sm'

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">選手を探す</h1>
      <div className="flex flex-wrap gap-2 rounded-lg border border-zinc-200 bg-white p-4">
        <input value={q} onChange={(e) => set('q', e.target.value)} placeholder="選手名（英語・カタカナ）"
               className={`${select} flex-1 min-w-48`} />
        <select value={division} onChange={(e) => set('division', e.target.value)} className={select}>
          <option value="">全ディビジョン</option>
          {divisions.map((d) => <option key={d} value={d}>{divisionJa(d)}</option>)}
        </select>
        <select value={country} onChange={(e) => set('country', e.target.value)} className={select}>
          <option value="">全ての国</option>
          {countries.map((c) => <option key={c} value={c}>{countryJa(c)}</option>)}
        </select>
        <select value={sort} onChange={(e) => set('sort', e.target.value)} className={select}>
          <option value="name">名前順</option>
          <option value="wins">優勝回数順</option>
          <option value="contests">出場回数順</option>
        </select>
      </div>

      <p className="text-sm text-zinc-500">{filtered.length} 名</p>
      <div className="overflow-x-auto rounded-lg border border-zinc-200 bg-white">
        <table className="w-full text-sm">
          <thead className="bg-zinc-100 text-left text-zinc-600">
            <tr>
              <th className="px-3 py-2">選手</th>
              <th className="px-3 py-2">国</th>
              <th className="px-3 py-2">ディビジョン</th>
              <th className="px-3 py-2 text-right">出場</th>
              <th className="px-3 py-2 text-right">優勝</th>
              <th className="px-3 py-2 text-right">最高順位</th>
            </tr>
          </thead>
          <tbody>
            {filtered.slice(0, limit).map((a) => (
              <tr key={a.id} className="border-t border-zinc-100 hover:bg-zinc-50">
                <td className="px-3 py-2">
                  <Link to={`/athletes/${a.id}`} className="font-semibold hover:text-brand hover:underline">{a.name}</Link>
                  {a.nameJa && <div className="text-xs text-zinc-500">{a.nameJa}</div>}
                </td>
                <td className="px-3 py-2 whitespace-nowrap"><Country code={a.country} /></td>
                <td className="px-3 py-2 text-xs text-zinc-600">{sortDivisions(a.divisions).map(divisionJa).join(' / ')}</td>
                <td className="px-3 py-2 text-right tabular-nums">{a.records.length}</td>
                <td className="px-3 py-2 text-right tabular-nums">{a.wins || '-'}</td>
                <td className="px-3 py-2 text-right tabular-nums">{a.bestPlace ? `${a.bestPlace}位` : '-'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {filtered.length > limit && (
        <button onClick={() => set('n', String(limit + PAGE))}
                className="mx-auto block rounded border border-zinc-300 bg-white px-4 py-2 text-sm hover:bg-zinc-100">
          さらに表示（残り {filtered.length - limit} 名）
        </button>
      )}
    </div>
  )
}
