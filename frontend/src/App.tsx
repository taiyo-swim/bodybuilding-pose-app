import { useState, useEffect, useRef, useCallback } from 'react'
import ModelViewer from './components/ModelViewer'
import AudioPanel from './components/AudioPanel'
import PosePanel from './components/PosePanel'
import PlaybackBar from './components/PlaybackBar'
import type { AudioAnalysis, Pose, Routine } from './types'
import { api } from './lib/api'
import type { Viewer3D } from './lib/viewer3d'
import { Player } from './lib/player'

type Tab = 'music' | 'pose'
type Toast = { msg: string; type: 'success' | 'error' | '' }

export default function App() {
  const [tab, setTab] = useState<Tab>('music')
  const [connected, setConnected] = useState(false)
  const [audio, setAudio] = useState<AudioAnalysis | null>(null)
  const [poses, setPoses] = useState<Pose[]>([])
  const [routine, setRoutine] = useState<Routine | null>(null)
  const [isGenerating, setIsGenerating] = useState(false)
  const [routineInfo, setRoutineInfo] = useState('')
  const [trimStart, setTrimStart] = useState(0)
  const [trimEnd, setTrimEnd] = useState<number | null>(null)
  const [isPlaying, setIsPlaying] = useState(false)
  const [playerReady, setPlayerReady] = useState(false)
  const [currentTime, setCurrentTime] = useState(0)
  const [currentPose, setCurrentPose] = useState('')
  const [toast, setToast] = useState<Toast>({ msg: '', type: '' })

  const viewerRef = useRef<Viewer3D | null>(null)
  const playerRef = useRef<Player | null>(null)
  const toastTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)

  useEffect(() => {
    api.health().then(() => setConnected(true)).catch(() => setConnected(false))
  }, [])

  const loadPoses = useCallback(() => {
    api.getPoses().then(setPoses).catch(() => {})
  }, [])
  useEffect(() => { loadPoses() }, [loadPoses])

  const showToast = useCallback((msg: string, type: 'success' | 'error' | '' = '') => {
    setToast({ msg, type })
    clearTimeout(toastTimer.current)
    toastTimer.current = setTimeout(() => setToast({ msg: '', type: '' }), 3500)
  }, [])

  // Viewer 準備完了 → models/ から自動 GLB ロード
  const onViewerReady = useCallback((viewer: Viewer3D) => {
    viewerRef.current = viewer

    // プレイヤーは viewer と 1:1 なので毎回再生成
    const player = new Player(viewer)
    player.on('timeUpdate', (t) => setCurrentTime(t))
    player.on('end', () => setIsPlaying(false))
    player.on('poseChange', (entry) => setCurrentPose(entry.pose_name))
    player.on('beat', () => viewer.beatPulse())
    playerRef.current = player
    setPlayerReady(true)

    // モデルを常にロード（ルーティンがあれば再セット）
    api.listModels().then(({ files }) => {
      if (files.length === 0) return
      viewer.loadModel(`/models/${files[0]}`).catch(() => {})
    }).catch(() => {})
  }, [showToast])

  // 音楽アップロード完了
  const onAudioReady = useCallback((a: AudioAnalysis) => {
    setAudio(a)
    setTrimStart(0)
    setTrimEnd(a.duration)
    playerRef.current?.setAudio(`/api/audio/${a.file}`)
  }, [])

  // トリム範囲変更
  const onTrimChange = useCallback((start: number, end: number) => {
    setTrimStart(start)
    setTrimEnd(end)
  }, [])

  // ルーティン生成
  const generateRoutine = useCallback(async () => {
    if (!audio) return
    setIsGenerating(true)
    try {
      const end = trimEnd ?? audio.duration
      const r = await api.generateRoutine(audio.file, 'My Routine', undefined, trimStart, end)
      setRoutine(r)
      playerRef.current?.setRoutine(r)
      const fmt = (s: number) => `${Math.floor(s/60)}:${(s%60|0).toString().padStart(2,'0')}`
      setRoutineInfo(`${r.pose_count}ポーズ / ${r.bpm} BPM / ${fmt(r.duration)}`)
      showToast(`ルーティン生成完了 (${r.pose_count}ポーズ)`, 'success')
    } catch (e: any) {
      showToast(`生成失敗: ${e.message}`, 'error')
    } finally {
      setIsGenerating(false)
    }
  }, [audio, trimStart, trimEnd, showToast])

  const onPlayPause = useCallback(() => {
    const player = playerRef.current; if (!player) return
    if (player.isPlaying) { player.pause(); setIsPlaying(false) }
    else { player.play(); setIsPlaying(true) }
  }, [])

  const routineDuration = routine?.duration ?? 0
  const beatTimes = routine?.beat_times ?? []

  return (
    <div className="flex flex-col h-screen" style={{ background: 'var(--bg)', color: 'var(--text)' }}>
      {/* Header */}
      <header className="flex items-center gap-3 px-5 py-3 border-b flex-shrink-0" style={{ background: 'var(--surface)', borderColor: 'var(--border)' }}>
        <div>
          <h1 className="text-base font-bold tracking-wide" style={{ color: 'var(--accent)' }}>BODYBUILDING POSE APP</h1>
          <p className="text-xs" style={{ color: 'var(--text2)' }}>音楽に合わせた3Dポーズルーティン自動生成</p>
        </div>
        <div className="ml-auto">
          <span className={`text-xs font-semibold px-2 py-1 rounded-full border ${connected ? 'border-green-500 text-green-400' : 'border-orange-500 text-orange-400'}`}>
            {connected ? '● 接続中' : '○ 未接続'}
          </span>
        </div>
      </header>

      <div className="flex flex-1 overflow-hidden">
        {/* Sidebar */}
        <aside className="w-72 flex flex-col border-r flex-shrink-0" style={{ background: 'var(--surface)', borderColor: 'var(--border)' }}>
          <div className="flex border-b flex-shrink-0" style={{ borderColor: 'var(--border)' }}>
            {(['music', 'pose'] as Tab[]).map(t => (
              <button key={t} onClick={() => setTab(t)}
                className="flex-1 py-2.5 text-xs font-semibold border-b-2 transition-colors"
                style={{
                  borderBottomColor: tab === t ? 'var(--accent)' : 'transparent',
                  color: tab === t ? 'var(--accent)' : 'var(--text2)',
                }}>
                {t === 'music' ? '🎵 音楽' : '🏋️ ポーズ'}
              </button>
            ))}
          </div>

          <div className="flex-1 overflow-y-auto">
            {tab === 'music' ? (
              <AudioPanel
                audio={audio}
                isGenerating={isGenerating}
                routineInfo={routineInfo}
                trimStart={trimStart}
                trimEnd={trimEnd}
                onAudioReady={onAudioReady}
                onGenerate={generateRoutine}
                onTrimChange={onTrimChange}
                onToast={showToast}
              />
            ) : (
              <PosePanel
                poses={poses}
                viewer={viewerRef.current}
                onPosesChange={loadPoses}
                onToast={showToast}
              />
            )}
          </div>
        </aside>

        {/* Main */}
        <div className="flex flex-col flex-1 overflow-hidden">
          <ModelViewer onReady={onViewerReady} currentPose={currentPose} />
          <PlaybackBar
            player={playerReady ? playerRef.current : null}
            currentTime={currentTime}
            duration={routineDuration}
            beatTimes={beatTimes}
            currentPose={currentPose}
            isPlaying={isPlaying}
            onPlayPause={onPlayPause}
          />
        </div>
      </div>

      {/* Toast */}
      {toast.msg && (
        <div className="fixed bottom-5 right-5 px-4 py-2.5 rounded-xl text-sm font-semibold border z-50"
          style={{
            background: 'var(--surface2)',
            borderColor: toast.type === 'success' ? '#4caf50' : toast.type === 'error' ? 'var(--accent2)' : 'var(--border)',
            color: toast.type === 'success' ? '#4caf50' : toast.type === 'error' ? 'var(--accent2)' : 'var(--text)',
          }}>
          {toast.msg}
        </div>
      )}
    </div>
  )
}
