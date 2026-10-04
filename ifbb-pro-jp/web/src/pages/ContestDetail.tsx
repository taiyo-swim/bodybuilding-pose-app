import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { athleteId, hasResults, useData } from '../lib/data'
import { divisionEn, divisionJa, formatDate, sortDivisions } from '../lib/i18n'
import { Country, OlympiaBadge, StatusBadge } from '../components/Badges'

export default function ContestDetail() {
  const { id } = useParams()
  const { contestById, athleteById } = useData()
  const contest = contestById.get(id ?? '')
  const [tab, setTab] = useState<string | null>(null)

  if (!contest) return <p className="text-zinc-500">大会が見つかりません。</p>

  const results = hasResults(contest)
  const divisions = sortDivisions(contest.divisions)
  const active = tab && divisions.includes(tab) ? tab : divisions[0]
  const result = contest.results?.find((r) => r.division === active)
  const entrants = contest.entrants?.[active] ?? []

  return (
    <div className="space-y-6">
      <div>
        <Link to="/schedule" className="text-sm text-brand hover:underline">← スケジュールへ戻る</Link>
        <div className="mt-2 flex flex-wrap items-center gap-2">
          <StatusBadge contest={contest} />
          {contest.olympiaQualifier && <OlympiaBadge />}
        </div>
        <h1 className="mt-1 text-2xl sm:text-3xl font-black">{contest.name}</h1>
        <dl className="mt-3 grid gap-x-6 gap-y-1 text-sm sm:grid-cols-[auto_1fr]">
          <dt className="text-zinc-500">開催日</dt>
          <dd>{formatDate(contest.date, contest.endDate)}</dd>
          <dt className="text-zinc-500">開催地</dt>
          <dd>{contest.city} <Country code={contest.country} /></dd>
          {contest.promoter && (<><dt className="text-zinc-500">プロモーター</dt><dd>{contest.promoter}</dd></>)}
          {contest.url && (
            <>
              <dt className="text-zinc-500">公式ページ</dt>
              <dd><a href={contest.url} target="_blank" rel="noreferrer" className="text-brand underline break-all">{contest.url}</a></dd>
            </>
          )}
        </dl>
      </div>

      <div>
        <div className="flex gap-1 overflow-x-auto border-b border-zinc-300">
          {divisions.map((d) => (
            <button
              key={d}
              onClick={() => setTab(d)}
              className={`whitespace-nowrap px-3 py-2 text-sm -mb-px border-b-2 ${
                d === active ? 'border-brand font-bold text-zinc-900' : 'border-transparent text-zinc-500 hover:text-zinc-800'
              }`}
            >
              {divisionJa(d)}
            </button>
          ))}
        </div>

        <div className="mt-4">
          <div className="mb-3 flex flex-wrap items-baseline justify-between gap-2">
            <h2 className="text-lg font-bold">
              {divisionJa(active)} <span className="text-sm font-normal text-zinc-500">{divisionEn(active)}</span>
            </h2>
            {result?.scorecardUrl && (
              <a href={result.scorecardUrl} target="_blank" rel="noreferrer"
                 className="rounded bg-zinc-900 px-3 py-1.5 text-sm font-bold text-white hover:bg-brand">
                📄 公式スコアカードを開く
              </a>
            )}
          </div>

          {result && result.placings.length > 0 ? (
            <div className="overflow-x-auto rounded-lg border border-zinc-200 bg-white">
              <table className="w-full text-sm">
                <thead className="bg-zinc-100 text-left text-zinc-600">
                  <tr>
                    <th className="px-3 py-2 w-16">順位</th>
                    <th className="px-3 py-2">選手</th>
                    <th className="px-3 py-2">国</th>
                    {result.placings.some((p) => p.score !== undefined) && <th className="px-3 py-2 text-right">スコア</th>}
                  </tr>
                </thead>
                <tbody>
                  {[...result.placings].sort((a, b) => a.place - b.place).map((p) => {
                    const a = athleteById.get(athleteId(p.athlete))
                    return (
                      <tr key={p.athlete} className="border-t border-zinc-100">
                        <td className="px-3 py-2 font-bold">
                          <span className={p.place <= 3 ? ['', 'text-amber-500', 'text-zinc-400', 'text-orange-700'][p.place] : ''}>
                            {p.place}位
                          </span>
                        </td>
                        <td className="px-3 py-2">
                          <Link to={`/athletes/${athleteId(p.athlete)}`} className="font-semibold hover:text-brand hover:underline">
                            {p.athlete}
                          </Link>
                          {a?.nameJa && <span className="ml-2 text-xs text-zinc-500">{a.nameJa}</span>}
                        </td>
                        <td className="px-3 py-2"><Country code={p.country} /></td>
                        {result.placings.some((x) => x.score !== undefined) && (
                          <td className="px-3 py-2 text-right tabular-nums">{p.score ?? '-'}</td>
                        )}
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          ) : entrants.length > 0 ? (
            <div>
              <p className="mb-2 text-sm text-zinc-600">出場予定選手（{entrants.length}名）</p>
              <ul className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                {entrants.map((n) => (
                  <li key={n} className="rounded border border-zinc-200 bg-white px-3 py-2 text-sm">
                    <Link to={`/athletes/${athleteId(n)}`} className="hover:text-brand hover:underline">{n}</Link>
                  </li>
                ))}
              </ul>
            </div>
          ) : (
            <p className="text-sm text-zinc-500">
              {results ? 'このディビジョンの結果は未掲載です。' : '出場選手・結果はまだ公開されていません。'}
            </p>
          )}
          {result && result.placings.some((p) => p.score !== undefined) && (
            <p className="mt-2 text-xs text-zinc-500">※スコアは各審査員の順位の合計（低いほど上位）。詳細は公式スコアカードを参照。</p>
          )}
        </div>
      </div>
    </div>
  )
}
