import { useRef, type ChangeEvent } from 'react'
import type { AudioAnalysis } from '../types'
import { api } from '../lib/api'

interface Props {
  audio: AudioAnalysis | null
  isGenerating: boolean
  routineInfo: string
  trimStart: number
  trimEnd: number | null
  onAudioReady: (a: AudioAnalysis) => void
  onGenerate: () => void
  onTrimChange: (start: number, end: number) => void
  onToast: (msg: string, type?: 'success' | 'error') => void
}

export default function AudioPanel({
  audio, isGenerating, routineInfo, trimStart, trimEnd,
  onAudioReady, onGenerate, onTrimChange, onToast,
}: Props) {
  const audioRef = useRef<HTMLInputElement>(null)
  const uploadingRef = useRef(false)

  const handleAudio = async (file: File) => {
    if (uploadingRef.current) return
    uploadingRef.current = true
    try {
      const result = await api.uploadAudio(file)
      onAudioReady(result)
      onToast(`解析完了: ${result.bpm} BPM`, 'success')
    } catch (e: any) {
      onToast(`アップロード失敗: ${e.message}`, 'error')
    } finally {
      uploadingRef.current = false
      if (audioRef.current) audioRef.current.value = ''
    }
  }

  const maxE = audio ? Math.max(...audio.energy_curve, 0.001) : 1
  const totalDuration = audio?.duration ?? 0
  const end = trimEnd ?? totalDuration

  const fmt = (s: number) => {
    s = Math.floor(s || 0)
    return `${Math.floor(s / 60)}:${(s % 60).toString().padStart(2, '0')}`
  }

  // エネルギーカーブ上でのトリム範囲ハイライト用
  const startPct = totalDuration > 0 ? (trimStart / totalDuration) * 100 : 0
  const endPct   = totalDuration > 0 ? (end / totalDuration) * 100 : 100

  return (
    <div className="flex flex-col overflow-y-auto">
      {/* 音楽アップロード */}
      <section className="p-4 border-b" style={{ borderColor: 'var(--border)' }}>
        <h2 className="text-xs font-semibold uppercase tracking-widest mb-3" style={{ color: 'var(--text2)' }}>音楽ファイル</h2>
        <label
          className="flex flex-col items-center gap-1 p-4 rounded-lg border-2 border-dashed cursor-pointer transition-colors hover:border-yellow-400 hover:bg-yellow-400/5"
          style={{ borderColor: 'var(--border)' }}
          onDragOver={e => e.preventDefault()}
          onDrop={e => { e.preventDefault(); const f = e.dataTransfer.files[0]; if (f) handleAudio(f) }}
        >
          <span className="text-2xl">🎵</span>
          <span className="text-xs" style={{ color: 'var(--text2)' }}>クリックまたはドラッグ&ドロップ</span>
          <span className="text-xs" style={{ color: 'var(--text2)' }}>MP3 / WAV / FLAC / M4A</span>
          <input ref={audioRef} type="file" accept=".mp3,.wav,.flac,.m4a,.ogg,.aac" className="hidden"
            onChange={(e: ChangeEvent<HTMLInputElement>) => { const f = e.target.files?.[0]; if (f) handleAudio(f) }} />
        </label>

        {audio && (
          <div className="mt-3 space-y-1">
            {[['BPM', `${audio.bpm}`], ['長さ', fmt(audio.duration)], ['ビート数', `${audio.beat_times.length}`]].map(([k, v]) => (
              <div key={k} className="flex justify-between text-sm">
                <span style={{ color: 'var(--text2)' }}>{k}</span>
                <span className="font-semibold" style={{ color: 'var(--accent)' }}>{v}</span>
              </div>
            ))}

            {/* エネルギーカーブ（トリム範囲ハイライト付き） */}
            <div className="relative flex gap-0.5 mt-2 h-8 items-end overflow-hidden rounded">
              {audio.energy_curve.map((e, i) => {
                const pct = (i / audio.energy_curve.length) * 100
                const inRange = pct >= startPct && pct < endPct
                return (
                  <div key={i} className="flex-1 rounded-t transition-opacity"
                    style={{
                      height: `${Math.max(4, (e / maxE) * 28)}px`,
                      background: 'var(--accent)',
                      opacity: inRange ? 0.85 : 0.25,
                    }} />
                )
              })}
            </div>
          </div>
        )}
      </section>

      {/* トリム設定 */}
      {audio && totalDuration > 0 && (
        <section className="p-4 border-b" style={{ borderColor: 'var(--border)' }}>
          <h2 className="text-xs font-semibold uppercase tracking-widest mb-3" style={{ color: 'var(--text2)' }}>使用区間</h2>

          <div className="space-y-2">
            {/* 開始 */}
            <div>
              <div className="flex justify-between text-xs mb-1" style={{ color: 'var(--text2)' }}>
                <span>開始</span>
                <span className="font-semibold" style={{ color: 'var(--accent)' }}>{fmt(trimStart)}</span>
              </div>
              <input type="range" min={0} max={Math.max(0, end - 5)} step={0.5}
                value={trimStart}
                onChange={e => onTrimChange(Number(e.target.value), end)}
                className="w-full h-1.5 rounded cursor-pointer accent-yellow-400" />
            </div>

            {/* 終了 */}
            <div>
              <div className="flex justify-between text-xs mb-1" style={{ color: 'var(--text2)' }}>
                <span>終了</span>
                <span className="font-semibold" style={{ color: 'var(--accent)' }}>{fmt(end)}</span>
              </div>
              <input type="range" min={Math.min(trimStart + 5, totalDuration)} max={totalDuration} step={0.5}
                value={end}
                onChange={e => onTrimChange(trimStart, Number(e.target.value))}
                className="w-full h-1.5 rounded cursor-pointer accent-yellow-400" />
            </div>

            <div className="flex justify-between text-xs pt-1" style={{ color: 'var(--text2)', opacity: 0.7 }}>
              <span>区間長: {fmt(end - trimStart)}</span>
              <span>全体: {fmt(totalDuration)}</span>
            </div>
          </div>
        </section>
      )}

      {/* ルーティン生成 */}
      <section className="p-4">
        <h2 className="text-xs font-semibold uppercase tracking-widest mb-3" style={{ color: 'var(--text2)' }}>ルーティン</h2>
        <button
          onClick={onGenerate}
          disabled={!audio || isGenerating}
          className="w-full py-2 rounded-lg text-sm font-bold disabled:opacity-40 disabled:cursor-not-allowed transition-opacity hover:opacity-85"
          style={{ background: 'var(--accent)', color: '#000' }}
        >
          {isGenerating ? '生成中...' : '✨ ルーティン自動生成'}
        </button>
        {routineInfo && <p className="mt-2 text-xs text-center" style={{ color: 'var(--text2)' }}>{routineInfo}</p>}
      </section>
    </div>
  )
}
