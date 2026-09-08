export interface AudioAnalysis {
  file: string
  original_name?: string
  duration: number
  bpm: number
  beat_times: number[]
  energy_curve: number[]
  brightness: number
}

export interface Pose {
  id: number
  name: string
  category: string
  energy_level: number
  keypoints: Record<string, { x: number; y: number; z: number; visibility?: number }>
  created_at?: string
}

export interface PoseEntry {
  time: number
  duration: number
  pose_id: number | null
  pose_name: string
  energy: number
  transition: 'smooth' | 'snap'
  keypoints?: Pose['keypoints'] | null
}

export interface Routine {
  id: number | null
  name: string
  audio_file: string
  bpm: number
  beat_times: number[]
  duration: number
  trim_start: number   // 曲の何秒から開始するか
  pose_count: number
  pose_sequence: PoseEntry[]
}

/** DBに保存済みのルーティン（/api/routines） */
export interface SavedRoutine extends Routine {
  id: number
  created_at: string
}

export interface VideoUploadResult {
  pose_id: number
  name: string
  category: string
  energy_level: number
  timestamp: number
  keypoint_count: number
}
