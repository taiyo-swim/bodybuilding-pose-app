import type { AudioAnalysis, Pose, Routine } from '../types'

async function request<T>(input: RequestInfo, init?: RequestInit): Promise<T> {
  const res = await fetch(input, init)
  if (!res.ok) {
    const text = await res.text()
    throw new Error(text || `HTTP ${res.status}`)
  }
  return res.json()
}

export const api = {
  health: () => request<{ status: string }>('/api/health'),

  listModels: () => request<{ files: string[] }>('/api/models'),

  uploadAudio: (file: File) => {
    const form = new FormData()
    form.append('file', file)
    return request<AudioAnalysis>('/api/audio/upload', { method: 'POST', body: form })
  },

  uploadVideo: (file: File, poseName: string, category: string, energyLevel: number) => {
    const form = new FormData()
    form.append('file', file)
    const params = new URLSearchParams({ pose_name: poseName, category, energy_level: String(energyLevel) })
    return request<{ pose_id: number; name: string; keypoint_count: number }>(
      `/api/video/upload?${params}`, { method: 'POST', body: form }
    )
  },

  getPoses: () => request<Pose[]>('/api/poses'),

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
}
