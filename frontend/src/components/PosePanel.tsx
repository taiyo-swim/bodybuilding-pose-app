import { useRef, useState, type ChangeEvent } from 'react'
import type { Pose } from '../types'
import { api } from '../lib/api'
import type { Viewer3D } from '../lib/viewer3d'
import { poseLabel, POSE_LABELS } from '../lib/poseLabels'
import { isDesktop, pickVideo } from '../lib/pywebview'
import type { ToastType } from '../App'

interface Props {
  poses: Pose[]
  viewer: Viewer3D | null
  onPosesChange: () => void
  onToast: (msg: string, type?: ToastType) => void
}

const CATEGORIES = [
  { value: 'competition', label: '規定ポーズ',      color: '#e8c84a' },
  { value: 'optional',    label: '任意ポーズ',      color: '#4a9ee8' },
  { value: 'transition',  label: 'トランジション',  color: '#a84ae8' },
]

/** 定義済みポーズ名（datalist の候補として提示する） */
const KNOWN_POSE_NAMES = Object.keys(POSE_LABELS)

export default function PosePanel({ poses, viewer, onPosesChange, onToast }: Props) {
  const videoRef = useRef<HTMLInputElement>(null)
  const [poseName, setPoseName] = useState('')
  const [category, setCategory] = useState('competition')
  const [energy, setEnergy] = useState(0.5)
  const [uploading, setUploading] = useState(false)
  const [activePose, setActivePose] = useState<number | null>(null)

  const normalisedName = (fallback: string) =>
    (poseName.trim() || fallback).replace(/\s+/g, '_')

  const handleVideo = async (file: File) => {
    if (uploading) return
    setUploading(true)
    const name = normalisedName(file.name.replace(/\.[^.]+$/, ''))
    try {
      const result = await api.uploadVideo(file, name, category, energy)
      onToast(`ポーズ登録: ${poseLabel(result.name)} (${result.keypoint_count}点)`, 'success')
      setPoseName('')
      onPosesChange()
    } catch (e) {
      onToast(`動画解析失敗: ${(e as Error).message}`, 'error')
    } finally {
      setUploading(false)
      if (videoRef.current) videoRef.current.value = ''
    }
  }

  // デスクトップ版: ネイティブダイアログで選択 → Python が uploads/ にコピー → 解析
  const handleDesktopPick = async () => {
    if (uploading) return
    setUploading(true)
    try {
      const filename = await pickVideo()
      if (!filename) return
      const name = normalisedName(filename.replace(/\.[^.]+$/, ''))
      const result = await api.analyzeVideoFile(filename, name, category, energy)
      onToast(`ポーズ登録: ${poseLabel(result.name)} (${result.keypoint_count}点)`, 'success')
      setPoseName('')
      onPosesChange()
    } catch (e) {
      onToast(`動画解析失敗: ${(e as Error).message}`, 'error')
    } finally {
      setUploading(false)
    }
  }

  const handleDelete = async (pose: Pose) => {
    try {
      await api.deletePose(pose.id)
      if (activePose === pose.id) setActivePose(null)
      onPosesChange()
      onToast(`ポーズを削除しました: ${poseLabel(pose.name)}`, 'success')
    } catch (e) {
      onToast(`削除失敗: ${(e as Error).message}`, 'error')
    }
  }

  const previewPose = (pose: Pose) => {
    setActivePose(pose.id)
    viewer?.transitionToPose(pose.name, pose.keypoints)
  }

  const catColor = (c: string) => CATEGORIES.find(x => x.value === c)?.color ?? '#e8c84a'

  return (
    <div className="flex flex-col overflow-y-auto">
      {/* 動画アップロード */}
      <section className="p-4 border-b" style={{ borderColor: 'var(--border)' }}>
        <h2 className="text-xs font-semibold uppercase tracking-widest mb-3" style={{ color: 'var(--text2)' }}>動画からポーズ追加</h2>

        <input
          type="text"
          list="known-pose-names"
          placeholder="ポーズ名 (例: front_double_bicep)"
          value={poseName}
          onChange={e => setPoseName(e.target.value)}
          className="w-full mb-2 px-3 py-2 rounded-lg text-sm outline-none border focus:border-yellow-400 transition-colors"
          style={{ background: 'var(--surface2)', borderColor: 'var(--border)', color: 'var(--text)' }}
        />
        <datalist id="known-pose-names">
          {KNOWN_POSE_NAMES.map(n => <option key={n} value={n}>{POSE_LABELS[n]}</option>)}
        </datalist>

        <div className="flex gap-2 mb-3">
          <select value={category} onChange={e => setCategory(e.target.value)}
            className="flex-1 px-2 py-1.5 rounded-lg text-sm outline-none border"
            style={{ background: 'var(--surface2)', borderColor: 'var(--border)', color: 'var(--text)' }}>
            {CATEGORIES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
          </select>
          <div className="flex items-center gap-2 flex-1">
            <span className="text-xs" style={{ color: 'var(--text2)' }}>強度</span>
            <input type="range" min={0} max={1} step={0.1} value={energy} onChange={e => setEnergy(Number(e.target.value))} className="flex-1" />
            <span className="text-xs w-6" style={{ color: 'var(--accent)' }}>{energy.toFixed(1)}</span>
          </div>
        </div>

        {isDesktop() ? (
          <button
            onClick={handleDesktopPick}
            disabled={uploading}
            className="w-full py-2.5 rounded-lg text-sm font-bold disabled:opacity-40 transition-opacity hover:opacity-85"
            style={{ background: 'var(--accent)', color: '#000' }}
          >
            {uploading ? '解析中...' : '🎬 動画ファイルを選択'}
          </button>
        ) : (
          <label
            className="flex flex-col items-center gap-1 p-4 rounded-lg border-2 border-dashed cursor-pointer transition-colors hover:border-yellow-400 hover:bg-yellow-400/5"
            style={{ borderColor: 'var(--border)' }}
            onDragOver={e => e.preventDefault()}
            onDrop={e => { e.preventDefault(); const f = e.dataTransfer.files[0]; if (f) handleVideo(f) }}
          >
            {uploading ? <span className="text-xs" style={{ color: 'var(--text2)' }}>解析中...</span> : (
              <>
                <span className="text-2xl">🎬</span>
                <span className="text-xs" style={{ color: 'var(--text2)' }}>動画をアップロード</span>
                <span className="text-xs" style={{ color: 'var(--text2)' }}>MP4 / MOV / AVI</span>
              </>
            )}
            <input ref={videoRef} type="file" accept=".mp4,.mov,.avi,.mkv,.webm,.m4v" className="hidden"
              onChange={(e: ChangeEvent<HTMLInputElement>) => { const f = e.target.files?.[0]; if (f) handleVideo(f) }} />
          </label>
        )}
      </section>

      {/* ポーズライブラリ */}
      <section className="p-4 flex-1">
        <h2 className="text-xs font-semibold uppercase tracking-widest mb-3" style={{ color: 'var(--text2)' }}>
          ポーズライブラリ {poses.length > 0 && <span>({poses.length})</span>}
        </h2>
        {poses.length === 0 ? (
          <p className="text-xs leading-relaxed" style={{ color: 'var(--text2)' }}>
            ポーズがまだありません。動画をアップロードするか、
            <code className="px-1">python train_poses.py</code> で一括登録できます。
            登録が無い場合はビルトインの12ポーズが使われます。
          </p>
        ) : (
          <ul className="space-y-1.5">
            {poses.map(p => (
              <li key={p.id}
                className="flex items-center gap-2 px-3 py-2 rounded-lg border transition-colors"
                style={{
                  background: activePose === p.id ? 'rgba(232,200,74,0.08)' : 'var(--surface2)',
                  borderColor: activePose === p.id ? 'var(--accent)' : 'transparent',
                }}>
                <div className="w-2 h-2 rounded-full flex-shrink-0" style={{ background: catColor(p.category) }} />
                <button onClick={() => previewPose(p)} className="flex-1 min-w-0 text-left cursor-pointer">
                  <div className="text-xs font-semibold truncate">{poseLabel(p.name)}</div>
                  <div className="text-xs" style={{ color: 'var(--text2)' }}>{p.category} · 強度 {p.energy_level.toFixed(1)}</div>
                </button>
                <button
                  onClick={() => handleDelete(p)}
                  title="削除"
                  className="text-xs px-1.5 py-0.5 rounded hover:opacity-70"
                  style={{ color: 'var(--accent2)' }}
                >
                  ✕
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  )
}
