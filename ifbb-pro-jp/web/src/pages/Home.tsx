import { Link } from 'react-router-dom'
import { hasResults, useData } from '../lib/data'
import ContestCard from '../components/ContestCard'

export default function Home() {
  const { contests, athletes, today } = useData()
  const upcoming = contests.filter((c) => (c.endDate ?? c.date) >= today && !hasResults(c)).slice(0, 6)
  const recent = contests.filter(hasResults).reverse().slice(0, 6)
  const thisYear = today.slice(0, 4)

  return (
    <div className="space-y-10">
      <section className="rounded-xl bg-gradient-to-br from-zinc-900 to-brand-dark p-6 sm:p-10 text-white">
        <h1 className="text-2xl sm:text-3xl font-black">IFBBプロリーグの大会情報を、日本語で。</h1>
        <p className="mt-2 text-zinc-300 text-sm sm:text-base">
          世界各国で毎週開催されるプロコンテストのスケジュール、出場選手、順位・スコアカードをまとめて検索できます。
        </p>
        <dl className="mt-6 grid grid-cols-3 gap-4 max-w-md">
          <Stat label={`${thisYear}年の大会`} value={contests.filter((c) => c.date.startsWith(thisYear)).length} />
          <Stat label="結果掲載" value={contests.filter(hasResults).length} />
          <Stat label="登録選手" value={athletes.length} />
        </dl>
      </section>

      <Section title="今後の大会" more="/schedule?status=upcoming">
        {upcoming.length ? upcoming.map((c) => <ContestCard key={c.id} contest={c} />) : <Empty />}
      </Section>

      <Section title="最新の結果" more="/schedule?status=results">
        {recent.length ? recent.map((c) => <ContestCard key={c.id} contest={c} />) : <Empty />}
      </Section>
    </div>
  )
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div>
      <dt className="text-xs text-zinc-400">{label}</dt>
      <dd className="text-2xl font-black">{value}</dd>
    </div>
  )
}

function Section({ title, more, children }: { title: string; more: string; children: React.ReactNode }) {
  return (
    <section>
      <div className="mb-3 flex items-baseline justify-between">
        <h2 className="text-xl font-bold">{title}</h2>
        <Link to={more} className="text-sm text-brand hover:underline">すべて見る →</Link>
      </div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{children}</div>
    </section>
  )
}

const Empty = () => <p className="text-zinc-500 text-sm">該当する大会はありません。</p>
