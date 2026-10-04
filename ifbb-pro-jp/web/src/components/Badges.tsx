import type { Contest } from '../types'
import { divisionJa, flag, countryJa } from '../lib/i18n'
import { hasResults, useData } from '../lib/data'

export function StatusBadge({ contest }: { contest: Contest }) {
  const { today } = useData()
  const end = contest.endDate ?? contest.date
  if (hasResults(contest))
    return <span className="rounded bg-emerald-100 px-2 py-0.5 text-xs font-bold text-emerald-800">結果あり</span>
  if (contest.date <= today && today <= end)
    return <span className="rounded bg-brand px-2 py-0.5 text-xs font-bold text-white">開催中</span>
  if (end < today)
    return <span className="rounded bg-zinc-200 px-2 py-0.5 text-xs font-bold text-zinc-600">結果未掲載</span>
  return <span className="rounded bg-sky-100 px-2 py-0.5 text-xs font-bold text-sky-800">開催予定</span>
}

export function DivisionChip({ id }: { id: string }) {
  return <span className="rounded-full border border-zinc-300 px-2 py-0.5 text-xs text-zinc-700">{divisionJa(id)}</span>
}

export function Country({ code, showName = true }: { code?: string; showName?: boolean }) {
  if (!code) return null
  return (
    <span title={countryJa(code)}>
      {flag(code)}
      {showName && <span className="ml-1">{countryJa(code)}</span>}
    </span>
  )
}

export function OlympiaBadge() {
  return (
    <span className="rounded bg-amber-400 px-2 py-0.5 text-xs font-bold text-zinc-900" title="優勝者にミスター・オリンピア出場権">
      オリンピア予選
    </span>
  )
}
