import { Link } from 'react-router-dom'
import type { Contest } from '../types'
import { formatDate, sortDivisions } from '../lib/i18n'
import { Country, DivisionChip, OlympiaBadge, StatusBadge } from './Badges'

export default function ContestCard({ contest }: { contest: Contest }) {
  return (
    <Link
      to={`/contests/${contest.id}`}
      className="block rounded-lg border border-zinc-200 bg-white p-4 hover:border-brand hover:shadow-sm transition"
    >
      <div className="flex flex-wrap items-center gap-2 text-sm text-zinc-600">
        <span className="font-semibold text-zinc-800">{formatDate(contest.date, contest.endDate)}</span>
        <StatusBadge contest={contest} />
        {contest.olympiaQualifier && <OlympiaBadge />}
      </div>
      <h3 className="mt-1 text-lg font-bold">{contest.name}</h3>
      <p className="text-sm text-zinc-600">
        {contest.city && <span className="mr-2">{contest.city}</span>}
        <Country code={contest.country} />
      </p>
      <div className="mt-2 flex flex-wrap gap-1">
        {sortDivisions(contest.divisions).map((d) => (
          <DivisionChip key={d} id={d} />
        ))}
      </div>
    </Link>
  )
}
