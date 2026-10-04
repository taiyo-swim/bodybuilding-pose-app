import { useEffect, useState, type FormEvent } from 'react'
import { Link, NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { useData } from '../lib/data'

const NAV = [
  { to: '/schedule', label: 'スケジュール' },
  { to: '/athletes', label: '選手' },
  { to: '/about', label: 'このサイトについて' },
]

export default function Layout() {
  const { dataset } = useData()
  const navigate = useNavigate()
  const { pathname } = useLocation()
  const [q, setQ] = useState('')

  useEffect(() => window.scrollTo(0, 0), [pathname])

  const submit = (e: FormEvent) => {
    e.preventDefault()
    if (q.trim()) navigate(`/search?q=${encodeURIComponent(q.trim())}`)
  }

  return (
    <div className="min-h-screen flex flex-col">
      <header className="bg-zinc-950 text-white">
        <div className="mx-auto max-w-6xl px-4 py-3 flex flex-wrap items-center gap-x-6 gap-y-2">
          <Link to="/" className="font-black tracking-tight text-lg">
            <span className="text-brand">IFBB PRO</span> 日本語ナビ
          </Link>
          <nav className="flex gap-4 text-sm">
            {NAV.map((n) => (
              <NavLink
                key={n.to}
                to={n.to}
                className={({ isActive }) => (isActive ? 'text-white font-bold' : 'text-zinc-400 hover:text-white')}
              >
                {n.label}
              </NavLink>
            ))}
          </nav>
          <form onSubmit={submit} className="ml-auto w-full sm:w-72">
            <input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="大会名・選手名・都市で検索"
              className="w-full rounded bg-zinc-800 px-3 py-1.5 text-sm placeholder:text-zinc-500 focus:outline-none focus:ring-2 focus:ring-brand"
            />
          </form>
        </div>
      </header>

      {dataset.source === 'sample' && (
        <div className="bg-amber-100 text-amber-900 text-sm">
          <div className="mx-auto max-w-6xl px-4 py-2">
            ⚠ 現在表示しているのは<strong>動作確認用のサンプルデータ</strong>です（架空の大会・選手）。
            実データは <code className="bg-amber-200 px-1 rounded">scraper/</code> のスクリプトで取得してください。
          </div>
        </div>
      )}

      <main className="mx-auto max-w-6xl w-full px-4 py-6 flex-1">
        <Outlet />
      </main>

      <footer className="border-t border-zinc-200 text-xs text-zinc-500">
        <div className="mx-auto max-w-6xl px-4 py-4 space-y-1">
          <p>
            本サイトは IFBB Professional League の非公式ファンサイトです。正式な情報は
            <a href="https://ifbbpro.com/" target="_blank" rel="noreferrer" className="underline mx-1">公式サイト</a>
            をご確認ください。
          </p>
          <p>データ更新: {new Date(dataset.generatedAt).toLocaleString('ja-JP')}</p>
        </div>
      </footer>
    </div>
  )
}
