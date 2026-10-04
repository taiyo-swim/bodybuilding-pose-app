import { useData } from '../lib/data'
import { DIVISIONS, sortDivisions } from '../lib/i18n'

export default function About() {
  const { dataset } = useData()
  return (
    <div className="prose max-w-3xl space-y-6 text-sm leading-relaxed">
      <h1 className="text-2xl font-bold">このサイトについて</h1>
      <p>
        IFBB Professional League（IFBBプロリーグ）が世界各国で開催しているプロコンテストの
        スケジュール・出場選手・結果を、日本語で横断検索するための非公式サイトです。
        公式サイトの情報を定期的に取得して整形しています。正確な情報は必ず
        <a href="https://ifbbpro.com/" target="_blank" rel="noreferrer" className="text-brand underline mx-1">公式サイト</a>
        でご確認ください。
      </p>

      <section>
        <h2 className="text-lg font-bold mb-2">ディビジョン名の対応表</h2>
        <table className="w-full border border-zinc-200 bg-white">
          <tbody>
            {sortDivisions(Object.keys(DIVISIONS)).map((id) => (
              <tr key={id} className="border-t border-zinc-100">
                <td className="px-3 py-1.5">{DIVISIONS[id].ja}</td>
                <td className="px-3 py-1.5 text-zinc-500">{DIVISIONS[id].en}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <section>
        <h2 className="text-lg font-bold mb-2">用語</h2>
        <ul className="list-disc pl-5 space-y-1">
          <li><strong>スコアカード</strong>: 各審査員がつけた順位の一覧。合計点が低いほど上位。</li>
          <li><strong>オリンピア予選</strong>: 優勝などで Mr. / Ms. オリンピアへの出場資格が得られる大会。</li>
        </ul>
      </section>

      <p className="text-zinc-500">
        データ種別: {dataset.source === 'sample' ? 'サンプル（架空）' : '公式サイトから取得'} ／
        最終更新: {new Date(dataset.generatedAt).toLocaleString('ja-JP')}
      </p>
    </div>
  )
}
