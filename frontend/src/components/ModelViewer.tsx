import { useEffect, useRef, useState } from 'react'
import { Viewer3D } from '../lib/viewer3d'

interface Props {
  onReady: (viewer: Viewer3D) => void
  currentPose: string
}

export default function ModelViewer({ onReady, currentPose }: Props) {
  const containerRef = useRef<HTMLDivElement>(null)
  const viewerRef    = useRef<Viewer3D | null>(null)
  const [modelStatus, setModelStatus] = useState<'loading' | 'loaded' | 'placeholder'>('placeholder')

  useEffect(() => {
    if (!containerRef.current || viewerRef.current) return
    const container = containerRef.current
    const viewer = new Viewer3D(container)
    viewer.showPlaceholder()
    viewerRef.current = viewer
    onReady(viewer)
    return () => {
      viewer.destroy()
      viewerRef.current = null
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // モデル読み込み状態をApp側から受け取れるようにする暫定コールバック
  // （現在は未使用だが将来の拡張用）

  const poseName = currentPose.replace(/_/g, ' ')

  return (
    <div
      className="relative flex-1 overflow-hidden"
      style={{ background: 'radial-gradient(ellipse at center, #1a1a2e 0%, #0a0a0f 100%)', minHeight: 0 }}
    >
      {/* Three.js canvas がここに挿入される */}
      <div ref={containerRef} style={{ width: '100%', height: '100%', position: 'absolute', inset: 0 }} />

      {/* 現在ポーズ名 */}
      {currentPose && (
        <div
          className="absolute bottom-4 left-1/2 -translate-x-1/2 px-4 py-1.5 rounded-full text-sm font-bold pointer-events-none"
          style={{ background: 'rgba(232,200,74,0.15)', border: '1px solid var(--accent)', color: 'var(--accent)' }}
        >
          {poseName}
        </div>
      )}
    </div>
  )
}
