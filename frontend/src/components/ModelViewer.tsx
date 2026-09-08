import { useEffect, useRef } from 'react'
import { Viewer3D } from '../lib/viewer3d'
import { poseLabel } from '../lib/poseLabels'

export type ModelStatus = 'none' | 'loading' | 'loaded' | 'error'

interface Props {
  /** Viewer 生成時に呼ばれる。クリーンアップ関数を返すとアンマウント時に実行される */
  onReady: (viewer: Viewer3D) => (() => void) | void
  currentPose: string
  modelStatus: ModelStatus
}

const STATUS_TEXT: Record<ModelStatus, string> = {
  none:    'モデル未配置（簡易表示中）',
  loading: '3Dモデル読み込み中...',
  loaded:  '',
  error:   'モデル読み込み失敗（簡易表示中）',
}

export default function ModelViewer({ onReady, currentPose, modelStatus }: Props) {
  const containerRef = useRef<HTMLDivElement>(null)
  const viewerRef    = useRef<Viewer3D | null>(null)
  // マウント時の onReady だけを使う（Viewer は1度しか生成しない）
  const onReadyRef   = useRef(onReady)

  useEffect(() => {
    if (!containerRef.current || viewerRef.current) return
    const viewer = new Viewer3D(containerRef.current)
    viewer.showPlaceholder()
    viewerRef.current = viewer

    const cleanup = onReadyRef.current(viewer)
    return () => {
      cleanup?.()
      viewer.destroy()
      viewerRef.current = null
    }
  }, [])

  useEffect(() => { onReadyRef.current = onReady }, [onReady])

  const statusText = STATUS_TEXT[modelStatus]

  return (
    <div
      className="relative flex-1 overflow-hidden"
      style={{ background: 'radial-gradient(ellipse at center, #1a1a2e 0%, #0a0a0f 100%)', minHeight: 0 }}
    >
      {/* Three.js canvas がここに挿入される */}
      <div ref={containerRef} style={{ width: '100%', height: '100%', position: 'absolute', inset: 0 }} />

      {/* モデル読み込み状態 */}
      {statusText && (
        <div
          className="absolute top-4 left-1/2 -translate-x-1/2 px-3 py-1 rounded-full text-xs pointer-events-none"
          style={{
            background: 'rgba(0,0,0,0.45)',
            border: '1px solid var(--border)',
            color: modelStatus === 'error' ? 'var(--accent2)' : 'var(--text2)',
          }}
        >
          {statusText}
        </div>
      )}

      {/* 現在ポーズ名 */}
      {currentPose && (
        <div
          className="absolute bottom-4 left-1/2 -translate-x-1/2 px-4 py-1.5 rounded-full text-sm font-bold pointer-events-none"
          style={{ background: 'rgba(232,200,74,0.15)', border: '1px solid var(--accent)', color: 'var(--accent)' }}
        >
          {poseLabel(currentPose)}
        </div>
      )}
    </div>
  )
}
