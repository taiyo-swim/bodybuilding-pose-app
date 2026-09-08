import { useRef, useState, type ChangeEvent } from 'react'
import type { AudioAnalysis, SavedRoutine } from '../types'
import { api } from '../lib/api'
import { isDesktop, pickAudio } from '../lib/pywebview'
import type { ToastType } from '../App'

interface Props {
  audio: AudioAnalysis | null
  isGenerating: boolean
  routineInfo: string
  trimStart: number
  trimEnd: number | null
  savedRoutines: SavedRoutine[]
  activeRoutineId: number | null
  onAudioReady: (a: AudioAnalysis) => void
  onGenerate: () => void
  onTrimChange: (start: number, end: number) => void
  onLoadRoutine: (r: SavedRoutine) => void
  onDeleteRoutine: (r: SavedRoutine) => void
  onToast: (msg: string, type?: ToastType) => void
}

const MIN_SEGMENT = 5  // トリム区間の最小長(秒)

const fmt = (s: number) => {
  const sec = Math.floor(s || 0)
  return `${Math.floor(sec / 60)}:${(sec % 60).toString().padStart(2, '0')}`
}

export default function AudioPanel({
  audio, isGenerating, routineInfo, trimStart, trimEnd, savedRoutines, activeRoutineId,
  onAudioReady, onGenerate, onTrimChange, onLoadRoutine, onDeleteRoutine, onToast,
}: Props) {
  const audioRef = useRef<HTMLInputElement>(null)
  const [uploading, setUploading] = useState(false)

  const handleAudio = async (file: File) => {
    if (uploading) return
    setUploading(true)
    try {
      const result = await api.uploadAudio(file)
      onAudioReady(result)
      onToast(`解析完了: ${result.bpm} BPM`, 'success')
    } catch (e) {
      onToast(`アップロード失敗: ${(e as Error).message}`, 'error')
    } finally {
      setUploading(false)
      if (audioRef.current) audioRef.current.value = ''
    }
  }

  // デスクトップ版: ネイティブダイアログで選択 → Python が uploads/ にコピー → 解析
  const handleDesktopPick = async () => {
    if (uploading) return
    setUploading(true)
    try {
      const filename = await pickAudio()
      if (!filename) return
      const result = await api.analyzeAudioFile(filename)
      onAudioReady(result)
      onToast(`解析完了: ${result.bpm} BPM`, 'success')
    } catch (e) {
      onToast(`解析失敗: ${(e as Error).message}`, 'error')
    } finally {
      setUploading(false)
    }
  }

  const maxE = audio ? Math.max(...audio.energy_curve, 0.001) : 1
  const totalDuration = audio?.duration ?? 0
  const end = trimEnd ?? totalDuration
  const canTrim = totalDuration > MIN_SEGMENT

  // エネルギーカーブ上でのトリム範囲ハイライト用
  const startPct = totalDuration > 0 ? (trimStart / totalDuration) * 100 : 0
  const endPct   = totalDuration > 0 ? (end / totalDuration) * 100 : 100

  return (
    <div className="flex flex-col overflow-y-auto">
      {/* 音楽アップロード */}
      <section className="p-4 border-b" style={{ borderColor: 'var(--border)' }}>
        <h2 className="text-xs font-semibold uppercase tracking-widest mb-3" style={{ color: 'var(--text2)' }}>音楽ファイル</h2>

        {isDesktop() ? (
          <button
            onClick={handleDesktopPick}
            disabled={uploading}
            className="w-full py-2.5 rounded-lg text-sm font-bold disabled:opacity-40 transition-opacity hover:opacity-85"
            style={{ background: 'var(--accent)', color: '#000' }}
          >
            {uploading ? '解析中...' : '🎵 音楽ファイルを選択'}
          </button>
        ) : (
          <label
            className="flex flex-col items-center gap-1 p-4 rounded-lg border-2 border-dashed cursor-pointer transition-colors hover:border-yellow-400 hover:bg-yellow-400/5"
            style={{ borderColor: 'var(--border)' }}
            onDragOver={e => e.preventDefault()}
            onDrop={e => { e.preventDefault(); const f = e.dataTransfer.files[0]; if (f) handleAudio(f) }}
          >
            {uploading ? <span className="text-xs" style={{ color: 'var(--text2)' }}>解析中...</span> : (
              <>
                <span className="text-2xl">🎵</span>
                <span className="text-xs" style={{ color: 'var(--text2)' }}>クリックまたはドラッグ&ドロップ</span>
                <span className="text-xs" style={{ color: 'var(--text2)' }}>MP3 / WAV / FLAC / M4A</span>
              </>
            )}
            <input ref={audioRef} type="file" accept=".mp3,.wav,.flac,.m4a,.ogg,.aac" className="hidden"
              onChange={(e: ChangeEvent<HTMLInputElement>) => { const f = e.target.files?.[0]; if (f) handleAudio(f) }} />
          </label>
        )}

        {audio && (
          <div className="mt-3 space-y-1">
            {audio.original_name && (
              <div className="text-xs truncate mb-1" style={{ color: 'var(--text2)' }} title={audio.original_name}>
                {audio.original_name}
              </div>
            )}
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
      {audio && canTrim && (
        <section className="p-4 border-b" style={{ borderColor: 'var(--border)' }}>
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-xs font-semibold uppercase tracking-widest" style={{ color: 'var(--text2)' }}>使用区間</h2>
            <button
              onClick={() => onTrimChange(0, totalDuration)}
              className="text-xs hover:opacity-70"
              style={{ color: 'var(--text2)' }}
            >
              全体に戻す
            </button>
          </div>

          <div className="space-y-2">
            {/* 開始 */}
            <div>
              <div className="flex justify-between text-xs mb-1" style={{ color: 'var(--text2)' }}>
                <span>開始</span>
                <span className="font-semibold" style={{ color: 'var(--accent)' }}>{fmt(trimStart)}</span>
              </div>
              <input type="range" min={0} max={Math.max(0, totalDuration - MIN_SEGMENT)} step={0.5}
                value={trimStart}
                onChange={e => {
                  const start = Number(e.target.value)
                  onTrimChange(start, Math.max(end, start + MIN_SEGMENT))
                }}
                className="w-full h-1.5 rounded cursor-pointer accent-yellow-400" />
            </div>

            {/* 終了 */}
            <div>
              <div className="flex justify-between text-xs mb-1" style={{ color: 'var(--text2)' }}>
                <span>終了</span>
                <span className="font-semibold" style={{ color: 'var(--accent)' }}>{fmt(end)}</span>
              </div>
              <input type="range" min={MIN_SEGMENT} max={totalDuration} step={0.5}
                value={end}
                onChange={e => {
                  const newEnd = Number(e.target.value)
                  onTrimChange(Math.min(trimStart, newEnd - MIN_SEGMENT), newEnd)
                }}
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
      <section className="p-4 border-b" style={{ borderColor: 'var(--border)' }}>
        <h2 className="text-xs font-semibold uppercase tracking-widest mb-3" style={{ color: 'var(--text2)' }}>ルーティン</h2>
        <button
          onClick={onGenerate}
          disabled={!audio || isGenerating}
          className="w-full py-2 rounded-lg text-sm font-bold disabled:opacity-40 disabled:cursor-not-allowed transition-opacity hover:opacity-85"
          style={{ background: 'var(--accent)', color: '#000' }}
        >
          {isGenerating ? '生成中...' : '✨ ルーティン自動生成'}
        </button>
        {!audio && (
          <p className="mt-2 text-xs text-center" style={{ color: 'var(--text2)' }}>
            先に音楽ファイルを読み込んでください
          </p>
        )}
        {routineInfo && <p className="mt-2 text-xs text-center" style={{ color: 'var(--text2)' }}>{routineInfo}</p>}
      </section>

      {/* 保存済みルーティン */}
      {savedRoutines.length > 0 && (
        <section className="p-4">
          <h2 className="text-xs font-semibold uppercase tracking-widest mb-3" style={{ color: 'var(--text2)' }}>
            保存済みルーティン ({savedRoutines.length})
          </h2>
          <ul className="space-y-1.5">
            {savedRoutines.map(r => {
              const active = r.id === activeRoutineId
              return (
                <li key={r.id}
                  className="flex items-center gap-2 px-3 py-2 rounded-lg border transition-colors"
                  style={{
                    background: active ? 'rgba(232,200,74,0.08)' : 'var(--surface2)',
                    borderColor: active ? 'var(--accent)' : 'transparent',
                  }}>
                  <button onClick={() => onLoadRoutine(r)} className="flex-1 min-w-0 text-left cursor-pointer">
                    <div className="text-xs font-semibold truncate">{r.name}</div>
                    <div className="text-xs" style={{ color: 'var(--text2)' }}>
                      {r.pose_count}ポーズ · {Math.round(r.bpm)} BPM · {fmt(r.duration)}
                    </div>
                  </button>
                  <button
                    onClick={() => onDeleteRoutine(r)}
                    title="削除"
                    className="text-xs px-1.5 py-0.5 rounded hover:opacity-70"
                    style={{ color: 'var(--accent2)' }}
                  >
                    ✕
                  </button>
                </li>
              )
            })}
          </ul>
        </section>
      )}
    </div>
  )
}
