import { useCallback, useEffect, useRef, useState } from 'react'
import ModelViewer from './components/ModelViewer'
import AudioPanel from './components/AudioPanel'
import PosePanel from './components/PosePanel'
import ModelPanel from './components/ModelPanel'
import PlaybackBar from './components/PlaybackBar'
import type { AudioAnalysis, Pose, Routine, SavedRoutine } from './types'
import { api } from './lib/api'
import { Viewer3D } from './lib/viewer3d'
import { Player } from './lib/player'
import { isDesktop } from './lib/pywebview'

type Tab = 'music' | 'pose' | 'model'
export type ToastType = 'success' | 'error' | ''
type Toast = { msg: string; type: ToastType }

const TABS: { id: Tab; label: string }[] = [
  { id: 'music', label: '🎵 音楽' },
  { id: 'pose',  label: '🏋️ ポーズ' },
  { id: 'model', label: '🧍 モデル' },
]

export default function App() {
  const [tab, setTab] = useState<Tab>('music')
  const [connected, setConnected] = useState<boolean | null>(null)
  const [audio, setAudio] = useState<AudioAnalysis | null>(null)
  const [poses, setPoses] = useState<Pose[]>([])
  const [routine, setRoutine] = useState<Routine | null>(null)
  const [savedRoutines, setSavedRoutines] = useState<SavedRoutine[]>([])
  const [isGenerating, setIsGenerating] = useState(false)
  const [trimStart, setTrimStart] = useState(0)
  const [trimEnd, setTrimEnd] = useState<number | null>(null)
  const [isPlaying, setIsPlaying] = useState(false)
  const [currentTime, setCurrentTime] = useState(0)
  const [currentPose, setCurrentPose] = useState('')
  const [toast, setToast] = useState<Toast>({ msg: '', type: '' })

  // viewer / player は state で保持する（子コンポーネントの再描画を発火させるため）
  const [viewer, setViewer] = useState<Viewer3D | null>(null)
  const [player, setPlayer] = useState<Player | null>(null)

  const [models, setModels] = useState<string[]>([])
  const [currentModel, setCurrentModel] = useState<string | null>(null)
  const [modelStatus, setModelStatus] = useState<'none' | 'loading' | 'loaded' | 'error'>('none')

  const toastTimer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)

  const showToast = useCallback((msg: string, type: ToastType = '') => {
    setToast({ msg, type })
    clearTimeout(toastTimer.current)
    toastTimer.current = setTimeout(() => setToast({ msg: '', type: '' }), 3500)
  }, [])

  useEffect(() => () => clearTimeout(toastTimer.current), [])

  // ── サーバー接続確認 ────────────────────────────────────────────
  useEffect(() => {
    api.health().then(() => setConnected(true)).catch(() => setConnected(false))
  }, [])

  // ── ポーズライブラリ / 保存済みルーティンの読み込み ─────────────
  const loadPoses = useCallback(() => {
    api.getPoses().then(setPoses).catch(() => {})
  }, [])

  const loadSavedRoutines = useCallback(() => {
    api.getRoutines().then(setSavedRoutines).catch(() => {})
  }, [])

  useEffect(() => { loadPoses(); loadSavedRoutines() }, [loadPoses, loadSavedRoutines])

  // ── 3Dモデルの読み込み ──────────────────────────────────────────
  const loadModelInto = useCallback(async (v: Viewer3D, file: string) => {
    setModelStatus('loading')
    try {
      await v.loadModel(`/models/${encodeURIComponent(file)}`)
      setCurrentModel(file)
      setModelStatus('loaded')
    } catch {
      setModelStatus('error')
      v.showPlaceholder()
      showToast(`3Dモデルの読み込みに失敗しました: ${file}`, 'error')
    }
  }, [showToast])

  const refreshModels = useCallback(async (v: Viewer3D | null, autoLoad = false) => {
    try {
      const { files } = await api.listModels()
      setModels(files)
      if (autoLoad && v && files.length > 0) await loadModelInto(v, files[0])
      return files
    } catch {
      return []
    }
  }, [loadModelInto])

  const selectModel = useCallback((file: string) => {
    if (viewer) loadModelInto(viewer, file)
  }, [viewer, loadModelInto])

  // ── Viewer 準備完了 → Player 生成 & モデル自動ロード ────────────
  const onViewerReady = useCallback((v: Viewer3D) => {
    const p = new Player(v)
    p.on('timeUpdate', (t) => setCurrentTime(t))
    p.on('end', () => setIsPlaying(false))
    p.on('poseChange', (entry) => setCurrentPose(entry.pose_name))
    p.on('beat', () => v.beatPulse())

    setViewer(v)
    setPlayer(p)
    refreshModels(v, true)

    return () => { p.destroy() }
  }, [refreshModels])

  // ── 音楽アップロード完了 ────────────────────────────────────────
  const onAudioReady = useCallback((a: AudioAnalysis) => {
    setAudio(a)
    setTrimStart(0)
    setTrimEnd(a.duration)
    setRoutine(null)
    setCurrentTime(0)
    setIsPlaying(false)
    player?.reset()
    player?.setAudio(`/api/audio/${a.file}`)
  }, [player])

  const onTrimChange = useCallback((start: number, end: number) => {
    setTrimStart(start)
    setTrimEnd(end)
  }, [])

  // ── ルーティン生成 ──────────────────────────────────────────────
  const applyRoutine = useCallback((r: Routine) => {
    setRoutine(r)
    setCurrentTime(0)
    setIsPlaying(false)
    player?.setRoutine(r)
  }, [player])

  const generateRoutine = useCallback(async () => {
    if (!audio) return
    setIsGenerating(true)
    try {
      const end = trimEnd ?? audio.duration
      const r = await api.generateRoutine(audio.file, 'My Routine', undefined, trimStart, end)
      applyRoutine(r)
      loadSavedRoutines()
      showToast(`ルーティン生成完了 (${r.pose_count}ポーズ)`, 'success')
    } catch (e) {
      showToast(`生成失敗: ${(e as Error).message}`, 'error')
    } finally {
      setIsGenerating(false)
    }
  }, [audio, trimStart, trimEnd, applyRoutine, loadSavedRoutines, showToast])

  // ── 保存済みルーティンの読み込み / 削除 ─────────────────────────
  const loadRoutine = useCallback(async (saved: SavedRoutine) => {
    try {
      const r = await api.getRoutine(saved.id)
      if (!r.audio_file) throw new Error('音源が紐づいていません')
      player?.setAudio(`/api/audio/${r.audio_file}`)
      applyRoutine(r)
      setAudio(null)
      showToast(`ルーティンを読み込みました: ${r.name}`, 'success')
    } catch (e) {
      showToast(`読み込み失敗: ${(e as Error).message}`, 'error')
    }
  }, [player, applyRoutine, showToast])

  const removeRoutine = useCallback(async (saved: SavedRoutine) => {
    try {
      await api.deleteRoutine(saved.id)
      if (routine?.id === saved.id) {
        setRoutine(null)
        player?.reset()
        setIsPlaying(false)
      }
      loadSavedRoutines()
      showToast('ルーティンを削除しました', 'success')
    } catch (e) {
      showToast(`削除失敗: ${(e as Error).message}`, 'error')
    }
  }, [routine, player, loadSavedRoutines, showToast])

  // ── 再生 / 一時停止 ─────────────────────────────────────────────
  const onPlayPause = useCallback(() => {
    if (!player || !routine) return
    if (player.isPlaying) { player.pause(); setIsPlaying(false) }
    else { player.play(); setIsPlaying(true) }
  }, [player, routine])

  // スペースキーで再生/一時停止
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null
      if (target && ['INPUT', 'TEXTAREA', 'SELECT'].includes(target.tagName)) return
      if (e.code === 'Space') { e.preventDefault(); onPlayPause() }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onPlayPause])

  const routineDuration = routine?.duration ?? 0
  const routineInfo = routine
    ? `${routine.pose_count}ポーズ / ${routine.bpm} BPM / ${fmtTime(routine.duration)}`
    : ''

  return (
    <div className="flex flex-col h-screen" style={{ background: 'var(--bg)', color: 'var(--text)' }}>
      {/* Header */}
      <header className="flex items-center gap-3 px-5 py-3 border-b flex-shrink-0" style={{ background: 'var(--surface)', borderColor: 'var(--border)' }}>
        <div>
          <h1 className="text-base font-bold tracking-wide" style={{ color: 'var(--accent)' }}>BODYBUILDING POSE APP</h1>
          <p className="text-xs" style={{ color: 'var(--text2)' }}>音楽に合わせた3Dポーズルーティン自動生成</p>
        </div>
        <div className="ml-auto flex items-center gap-2">
          {isDesktop() && (
            <span className="text-xs px-2 py-1 rounded-full border" style={{ borderColor: 'var(--border)', color: 'var(--text2)' }}>
              デスクトップ
            </span>
          )}
          <span className={`text-xs font-semibold px-2 py-1 rounded-full border ${connected ? 'border-green-500 text-green-400' : 'border-orange-500 text-orange-400'}`}>
            {connected === null ? '… 接続確認中' : connected ? '● 接続中' : '○ 未接続'}
          </span>
        </div>
      </header>

      <div className="flex flex-1 overflow-hidden">
        {/* Sidebar */}
        <aside className="w-72 flex flex-col border-r flex-shrink-0" style={{ background: 'var(--surface)', borderColor: 'var(--border)' }}>
          <div className="flex border-b flex-shrink-0" style={{ borderColor: 'var(--border)' }}>
            {TABS.map(t => (
              <button key={t.id} onClick={() => setTab(t.id)}
                className="flex-1 py-2.5 text-xs font-semibold border-b-2 transition-colors"
                style={{
                  borderBottomColor: tab === t.id ? 'var(--accent)' : 'transparent',
                  color: tab === t.id ? 'var(--accent)' : 'var(--text2)',
                }}>
                {t.label}
              </button>
            ))}
          </div>

          <div className="flex-1 overflow-y-auto">
            {tab === 'music' && (
              <AudioPanel
                audio={audio}
                isGenerating={isGenerating}
                routineInfo={routineInfo}
                trimStart={trimStart}
                trimEnd={trimEnd}
                savedRoutines={savedRoutines}
                activeRoutineId={routine?.id ?? null}
                onAudioReady={onAudioReady}
                onGenerate={generateRoutine}
                onTrimChange={onTrimChange}
                onLoadRoutine={loadRoutine}
                onDeleteRoutine={removeRoutine}
                onToast={showToast}
              />
            )}
            {tab === 'pose' && (
              <PosePanel
                poses={poses}
                viewer={viewer}
                onPosesChange={loadPoses}
                onToast={showToast}
              />
            )}
            {tab === 'model' && (
              <ModelPanel
                models={models}
                currentModel={currentModel}
                status={modelStatus}
                onSelect={selectModel}
                onRefresh={() => refreshModels(viewer, false)}
                onLoadFile={(file) => { if (viewer) loadModelInto(viewer, file) }}
                onToast={showToast}
              />
            )}
          </div>
        </aside>

        {/* Main */}
        <div className="flex flex-col flex-1 overflow-hidden">
          <ModelViewer
            onReady={onViewerReady}
            currentPose={currentPose}
            modelStatus={modelStatus}
          />
          <PlaybackBar
            player={player}
            currentTime={currentTime}
            duration={routineDuration}
            beatTimes={routine?.beat_times ?? []}
            poseSequence={routine?.pose_sequence ?? []}
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

function fmtTime(s: number): string {
  const sec = Math.floor(s || 0)
  return `${Math.floor(sec / 60)}:${(sec % 60).toString().padStart(2, '0')}`
}
