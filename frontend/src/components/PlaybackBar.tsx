import { useRef } from 'react'
import type { Player } from '../lib/player'

interface Props {
  player: Player | null
  currentTime: number
  duration: number
  beatTimes: number[]
  currentPose: string
  isPlaying: boolean
  onPlayPause: () => void
}

export default function PlaybackBar({ player, currentTime, duration, beatTimes, isPlaying, onPlayPause }: Props) {
  const wrapRef = useRef<HTMLDivElement>(null)
  const pct = duration > 0 ? (currentTime / duration) * 100 : 0

  const fmt = (s: number) => {
    s = Math.floor(s || 0)
    return `${Math.floor(s / 60)}:${(s % 60).toString().padStart(2, '0')}`
  }

  const seek = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!player || !duration) return
    const rect = e.currentTarget.getBoundingClientRect()
    player.seek(((e.clientX - rect.left) / rect.width) * duration)
  }

  return (
    <div className="flex items-center gap-3 px-4 py-3 border-t" style={{ background: 'var(--surface)', borderColor: 'var(--border)' }}>
      <button
        onClick={onPlayPause}
        disabled={!duration}
        className="w-9 h-9 rounded-lg font-bold text-sm disabled:opacity-40 disabled:cursor-not-allowed transition-opacity hover:opacity-80"
        style={{ background: 'var(--accent)', color: '#000' }}
      >
        {isPlaying ? '⏸' : '▶'}
      </button>

      <span className="text-xs w-10 text-center" style={{ color: 'var(--text2)' }}>{fmt(currentTime)}</span>

      <div ref={wrapRef} onClick={seek} className="relative flex-1 h-1.5 rounded cursor-pointer" style={{ background: 'var(--border)' }}>
        <div className="absolute inset-y-0 left-0 rounded pointer-events-none" style={{ width: `${pct}%`, background: 'var(--accent)' }} />
        {duration > 0 && beatTimes.map((t, i) => (
          <div key={i} className="absolute inset-y-0 w-px pointer-events-none"
            style={{ left: `${(t / duration) * 100}%`, background: 'rgba(232,200,74,0.35)' }} />
        ))}
      </div>

      <span className="text-xs w-10 text-center" style={{ color: 'var(--text2)' }}>{fmt(duration)}</span>
    </div>
  )
}
