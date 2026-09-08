import type { AudioAnalysis, Pose, Routine, SavedRoutine, VideoUploadResult } from '../types'

async function request<T>(input: RequestInfo, init?: RequestInit): Promise<T> {
  const res = await fetch(input, init)
  if (!res.ok) {
    let message = `HTTP ${res.status}`
    try {
      const text = await res.text()
      // FastAPI のエラーは {"detail": "..."} 形式
      try {
        const json = JSON.parse(text)
        message = typeof json.detail === 'string' ? json.detail : text || message
      } catch {
        message = text || message
      }
    } catch { /* body が読めない場合はステータスのみ */ }
    throw new Error(message)
  }
  return res.json()
}

export const api = {
  health: () => request<{ status: string }>('/api/health'),

  listModels: () => request<{ files: string[] }>('/api/models'),

  uploadModel: (file: File) => {
    const form = new FormData()
    form.append('file', file)
    return request<{ file: string }>('/api/models/upload', { method: 'POST', body: form })
  },

  // ── 音楽 ──────────────────────────────────────────────────────────
  uploadAudio: (file: File) => {
    const form = new FormData()
    form.append('file', file)
    return request<AudioAnalysis>('/api/audio/upload', { method: 'POST', body: form })
  },

  /** pywebview がコピー済みの uploads/ 内ファイルを解析する */
  analyzeAudioFile: (filename: string) =>
    request<AudioAnalysis>(`/api/audio/analyze?${new URLSearchParams({ filename })}`, { method: 'POST' }),

  // ── 動画 / ポーズ ─────────────────────────────────────────────────
  uploadVideo: (file: File, poseName: string, category: string, energyLevel: number) => {
    const form = new FormData()
    form.append('file', file)
    const params = new URLSearchParams({ pose_name: poseName, category, energy_level: String(energyLevel) })
    return request<VideoUploadResult>(`/api/video/upload?${params}`, { method: 'POST', body: form })
  },

  /** pywebview がコピー済みの uploads/ 内動画を解析してポーズ登録する */
  analyzeVideoFile: (filename: string, poseName: string, category: string, energyLevel: number) => {
    const params = new URLSearchParams({
      filename, pose_name: poseName, category, energy_level: String(energyLevel),
    })
    return request<VideoUploadResult>(`/api/video/analyze?${params}`, { method: 'POST' })
  },

  getPoses: () => request<Pose[]>('/api/poses'),

  deletePose: (poseId: number) =>
    request<{ deleted: number }>(`/api/poses/${poseId}`, { method: 'DELETE' }),

  // ── ルーティン ────────────────────────────────────────────────────
  generateRoutine: (
    audioFile: string,
    routineName = 'My Routine',
    poseDuration?: number,
    trimStart?: number,
    trimEnd?: number,
  ) => {
    const params = new URLSearchParams({ audio_file: audioFile, routine_name: routineName })
    if (poseDuration !== undefined) params.set('pose_duration', String(poseDuration))
    if (trimStart !== undefined && trimStart > 0) params.set('trim_start', String(trimStart))
    if (trimEnd !== undefined) params.set('trim_end', String(trimEnd))
    return request<Routine>(`/api/routine/generate?${params}`, { method: 'POST' })
  },

  getRoutines: () => request<SavedRoutine[]>('/api/routines'),

  getRoutine: (routineId: number) => request<SavedRoutine>(`/api/routines/${routineId}`),

  deleteRoutine: (routineId: number) =>
    request<{ deleted: number }>(`/api/routines/${routineId}`, { method: 'DELETE' }),
}
