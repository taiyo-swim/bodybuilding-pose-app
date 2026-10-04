import { HashRouter, Route, Routes } from 'react-router-dom'
import { DataProvider } from './lib/data'
import Layout from './components/Layout'
import Home from './pages/Home'
import Schedule from './pages/Schedule'
import ContestDetail from './pages/ContestDetail'
import Athletes from './pages/Athletes'
import AthleteDetail from './pages/AthleteDetail'
import Search from './pages/Search'
import About from './pages/About'

// HashRouter: 静的ホスティング（GitHub Pages 等）でサーバー設定なしに動かすため
export default function App() {
  return (
    <DataProvider>
      <HashRouter>
        <Routes>
          <Route element={<Layout />}>
            <Route index element={<Home />} />
            <Route path="schedule" element={<Schedule />} />
            <Route path="contests/:id" element={<ContestDetail />} />
            <Route path="athletes" element={<Athletes />} />
            <Route path="athletes/:id" element={<AthleteDetail />} />
            <Route path="search" element={<Search />} />
            <Route path="about" element={<About />} />
            <Route path="*" element={<p className="text-zinc-500">ページが見つかりません。</p>} />
          </Route>
        </Routes>
      </HashRouter>
    </DataProvider>
  )
}
