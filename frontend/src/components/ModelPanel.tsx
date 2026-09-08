import { useRef, useState, type ChangeEvent } from 'react'
import { api } from '../lib/api'
import { isDesktop, pickModel } from '../lib/pywebview'
import type { ModelStatus } from './ModelViewer'
import type { ToastType } from '../App'

interface Props {
  models: string[]
  currentModel: string | null
  status: ModelStatus
  onSelect: (file: string) => void
  onRefresh: () => Promise<string[]> | void
  onLoadFile: (file: string) => void
  onToast: (msg: string, type?: ToastType) => void
}

export default function ModelPanel({
  models, currentModel, status, onSelect, onRefresh, onLoadFile, onToast,
}: Props) {
  const fileRef = useRef<HTMLInputElement>(null)
  const [uploading, setUploading] = useState(false)

  const handleFile = async (file: File) => {
    setUploading(true)
    try {
      const { file: saved } = await api.uploadModel(file)
      await onRefresh()
      onLoadFile(saved)
      onToast(`モデルを追加しました: ${saved}`, 'success')
    } catch (e) {
      onToast(`モデルの追加に失敗: ${(e as Error).message}`, 'error')
    } finally {
      setUploading(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  // デスクトップ版はネイティブのファイル選択ダイアログを使う
  const handleDesktopPick = async () => {
    setUploading(true)
    try {
      const saved = await pickModel()
      if (!saved) return
      await onRefresh()
      onLoadFile(saved)
      onToast(`モデルを追加しました: ${saved}`, 'success')
    } catch (e) {
      onToast(`モデルの追加に失敗: ${(e as Error).message}`, 'error')
    } finally {
      setUploading(false)
    }
  }

  return (
    <div className="flex flex-col overflow-y-auto">
      <section className="p-4 border-b" style={{ borderColor: 'var(--border)' }}>
        <h2 className="text-xs font-semibold uppercase tracking-widest mb-3" style={{ color: 'var(--text2)' }}>
          3Dモデル追加
        </h2>

        {isDesktop() ? (
          <button
            onClick={handleDesktopPick}
            disabled={uploading}
            className="w-full py-2 rounded-lg text-sm font-bold disabled:opacity-40 transition-opacity hover:opacity-85"
            style={{ background: 'var(--accent)', color: '#000' }}
          >
            {uploading ? '追加中...' : '📂 GLBファイルを選択'}
          </button>
        ) : (
          <label
            className="flex flex-col items-center gap-1 p-4 rounded-lg border-2 border-dashed cursor-pointer transition-colors hover:border-yellow-400 hover:bg-yellow-400/5"
            style={{ borderColor: 'var(--border)' }}
            onDragOver={e => e.preventDefault()}
            onDrop={e => { e.preventDefault(); const f = e.dataTransfer.files[0]; if (f) handleFile(f) }}
          >
            {uploading ? <span className="text-xs" style={{ color: 'var(--text2)' }}>アップロード中...</span> : (
              <>
                <span className="text-2xl">🧍</span>
                <span className="text-xs" style={{ color: 'var(--text2)' }}>Mixamo の GLB をアップロード</span>
                <span className="text-xs" style={{ color: 'var(--text2)' }}>GLB / GLTF</span>
              </>
            )}
            <input ref={fileRef} type="file" accept=".glb,.gltf" className="hidden"
              onChange={(e: ChangeEvent<HTMLInputElement>) => { const f = e.target.files?.[0]; if (f) handleFile(f) }} />
          </label>
        )}

        <p className="mt-2 text-xs leading-relaxed" style={{ color: 'var(--text2)', opacity: 0.8 }}>
          models/ フォルダに直接 GLB を置いても読み込めます。
        </p>
      </section>

      <section className="p-4 flex-1">
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-xs font-semibold uppercase tracking-widest" style={{ color: 'var(--text2)' }}>
            モデル一覧 {models.length > 0 && <span>({models.length})</span>}
          </h2>
          <button onClick={() => onRefresh()} className="text-xs hover:opacity-70" style={{ color: 'var(--text2)' }}>
            ⟳ 更新
          </button>
        </div>

        {models.length === 0 ? (
          <p className="text-xs leading-relaxed" style={{ color: 'var(--text2)' }}>
            モデルがありません。Mixamo から T ポーズのキャラクターを GLB でダウンロードして追加してください。
            モデルが無い場合は簡易的な人型で動きを確認できます。
          </p>
        ) : (
          <ul className="space-y-1.5">
            {models.map(file => {
              const active = file === currentModel
              return (
                <li key={file}
                  onClick={() => onSelect(file)}
                  className="flex items-center gap-2 px-3 py-2 rounded-lg cursor-pointer border transition-colors"
                  style={{
                    background: active ? 'rgba(232,200,74,0.08)' : 'var(--surface2)',
                    borderColor: active ? 'var(--accent)' : 'transparent',
                  }}>
                  <span className="text-sm">{active ? '🟡' : '⚪'}</span>
                  <span className="text-xs font-semibold truncate flex-1">{file}</span>
                  {active && status === 'loading' && (
                    <span className="text-xs" style={{ color: 'var(--text2)' }}>読込中</span>
                  )}
                </li>
              )
            })}
          </ul>
        )}
      </section>
    </div>
  )
}
