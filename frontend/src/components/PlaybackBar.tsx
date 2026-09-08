import type { PoseEntry } from '../types'
import type { Player } from '../lib/player'
import { poseLabel } from '../lib/poseLabels'

interface Props {
  player: Player | null
  currentTime: number
  duration: number
  beatTimes: number[]
  poseSequence: PoseEntry[]
  isPlaying: boolean
  onPlayPause: () => void
}

const fmt = (s: number) => {
  const sec = Math.floor(s || 0)
  return `${Math.floor(sec / 60)}:${(sec % 60).toString().padStart(2, '0')}`
}

export default function PlaybackBar({
  player, currentTime, duration, beatTimes, poseSequence, isPlaying, onPlayPause,
}: Props) {
  const pct = duration > 0 ? Math.min(100, (currentTime / duration) * 100) : 0
  const enabled = !!player && duration > 0

  const seek = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!enabled) return
    const rect = e.currentTarget.getBoundingClientRect()
    player!.seek(((e.clientX - rect.left) / rect.width) * duration)
  }

  // ビート線が多すぎると描画負荷が高くなるため間引く
  const beatStep = Math.ceil(beatTimes.length / 200) || 1
  const beats = beatTimes.filter((_, i) => i % beatStep === 0)

  return (
    <div className="flex items-center gap-3 px-4 py-3 border-t flex-shrink-0" style={{ background: 'var(--surface)', borderColor: 'var(--border)' }}>
      <button
        onClick={onPlayPause}
        disabled={!enabled}
        title={enabled ? '再生 / 一時停止 (Space)' : 'ルーティンを生成してください'}
        className="w-9 h-9 rounded-lg font-bold text-sm disabled:opacity-40 disabled:cursor-not-allowed transition-opacity hover:opacity-80"
        style={{ background: 'var(--accent)', color: '#000' }}
      >
        {isPlaying ? '⏸' : '▶'}
      </button>

      <span className="text-xs w-10 text-center tabular-nums" style={{ color: 'var(--text2)' }}>{fmt(currentTime)}</span>

      <div
        onClick={seek}
        className={`relative flex-1 h-4 flex items-center ${enabled ? 'cursor-pointer' : ''}`}
      >
        <div className="relative w-full h-1.5 rounded" style={{ background: 'var(--border)' }}>
          {/* ビート位置 */}
          {duration > 0 && beats.map((t, i) => (
            <div key={i} className="absolute inset-y-0 w-px pointer-events-none"
              style={{ left: `${(t / duration) * 100}%`, background: 'rgba(232,200,74,0.3)' }} />
          ))}

          {/* ポーズ切り替え位置 */}
          {duration > 0 && poseSequence.map((entry, i) => (
            <div key={i}
              title={`${fmt(entry.time)} ${poseLabel(entry.pose_name)}`}
              className="absolute -inset-y-1 w-0.5 pointer-events-none"
              style={{ left: `${(entry.time / duration) * 100}%`, background: 'rgba(232,200,74,0.75)' }} />
          ))}

          {/* 再生済み範囲 */}
          <div className="absolute inset-y-0 left-0 rounded pointer-events-none"
            style={{ width: `${pct}%`, background: 'var(--accent)', opacity: 0.55 }} />

          {/* 再生ヘッド */}
          {enabled && (
            <div className="absolute w-2 h-2 rounded-full -translate-x-1/2 -translate-y-1/4 pointer-events-none"
              style={{ left: `${pct}%`, background: 'var(--accent)' }} />
          )}
        </div>
      </div>

      <span className="text-xs w-10 text-center tabular-nums" style={{ color: 'var(--text2)' }}>{fmt(duration)}</span>
    </div>
  )
}
