import { Link, useParams } from 'react-router-dom'
import { useData } from '../lib/data'
import { divisionJa, formatDate, sortDivisions } from '../lib/i18n'
import { Country } from '../components/Badges'

export default function AthleteDetail() {
  const { id } = useParams()
  const { athleteById } = useData()
  const a = athleteById.get(id ?? '')
  if (!a) return <p className="text-zinc-500">選手が見つかりません。</p>

  const top3 = a.records.filter((r) => r.place <= 3).length

  return (
    <div className="space-y-6">
      <div>
        <Link to="/athletes" className="text-sm text-brand hover:underline">← 選手一覧へ戻る</Link>
        <h1 className="mt-2 text-2xl sm:text-3xl font-black">{a.name}</h1>
        {a.nameJa && <p className="text-zinc-600">{a.nameJa}</p>}
        <p className="mt-1 text-sm"><Country code={a.country} /></p>
        <p className="mt-1 text-sm text-zinc-600">{sortDivisions(a.divisions).map(divisionJa).join(' / ')}</p>
      </div>

      <dl className="grid grid-cols-3 gap-3 max-w-md">
        {[['出場', a.records.length], ['優勝', a.wins], ['表彰台', top3]].map(([k, v]) => (
          <div key={k} className="rounded-lg border border-zinc-200 bg-white p-3 text-center">
            <dt className="text-xs text-zinc-500">{k}</dt>
            <dd className="text-2xl font-black">{v}</dd>
          </div>
        ))}
      </dl>

      {a.upcoming.length > 0 && (
        <section>
          <h2 className="mb-2 text-lg font-bold">出場予定</h2>
          <ul className="space-y-1 text-sm">
            {a.upcoming.map((u) => (
              <li key={u.contestId + u.division}>
                <span className="text-zinc-500 mr-2">{formatDate(u.date)}</span>
                <Link to={`/contests/${u.contestId}`} className="font-semibold hover:text-brand hover:underline">{u.contestName}</Link>
                <span className="ml-2 text-zinc-500">{divisionJa(u.division)}</span>
              </li>
            ))}
          </ul>
        </section>
      )}

      <section>
        <h2 className="mb-2 text-lg font-bold">戦績</h2>
        {a.records.length ? (
          <div className="overflow-x-auto rounded-lg border border-zinc-200 bg-white">
            <table className="w-full text-sm">
              <thead className="bg-zinc-100 text-left text-zinc-600">
                <tr>
                  <th className="px-3 py-2">日付</th>
                  <th className="px-3 py-2">大会</th>
                  <th className="px-3 py-2">ディビジョン</th>
                  <th className="px-3 py-2 text-right">順位</th>
                  <th className="px-3 py-2">スコアカード</th>
                </tr>
              </thead>
              <tbody>
                {a.records.map((r) => (
                  <tr key={r.contestId + r.division} className="border-t border-zinc-100">
                    <td className="px-3 py-2 whitespace-nowrap text-zinc-600">{r.date}</td>
                    <td className="px-3 py-2">
                      <Link to={`/contests/${r.contestId}`} className="font-semibold hover:text-brand hover:underline">{r.contestName}</Link>
                    </td>
                    <td className="px-3 py-2 text-zinc-600">{divisionJa(r.division)}</td>
                    <td className="px-3 py-2 text-right whitespace-nowrap">
                      <span className={`font-bold ${r.place === 1 ? 'text-amber-500' : ''}`}>{r.place}位</span>
                      <span className="text-xs text-zinc-400"> / {r.fieldSize}</span>
                    </td>
                    <td className="px-3 py-2">
                      {r.scorecardUrl ? (
                        <a href={r.scorecardUrl} target="_blank" rel="noreferrer" className="text-brand underline">開く</a>
                      ) : '-'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="text-sm text-zinc-500">掲載されている戦績はありません。</p>
        )}
      </section>
    </div>
  )
}
