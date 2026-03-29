export interface AudioAnalysis {
  file: string
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
  id: number
  name: string
  bpm: number
  beat_times: number[]
  duration: number
  trim_start: number   // 曲の何秒から開始するか
  pose_count: number
  pose_sequence: PoseEntry[]
}
