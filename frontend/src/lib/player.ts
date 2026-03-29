import type { Routine, PoseEntry } from '../types'
import type { Viewer3D } from './viewer3d'

type CB<T = void> = (data: T) => void

export class Player {
  private audio = new Audio()
  private routine: Routine | null = null
  private _raf: number | null = null
  private lastPoseName: string | null = null
  private lastBeatIdx = -1
  private trimStart = 0      // オーディオファイル内の開始位置(秒)
  private trimEnd = Infinity // オーディオファイル内の終了位置(秒)
  private cbs: { timeUpdate: CB<number>[]; end: CB[]; poseChange: CB<PoseEntry>[]; beat: CB[] } = {
    timeUpdate: [], end: [], poseChange: [], beat: [],
  }

  isPlaying = false

  constructor(private viewer: Viewer3D) {
    this.audio.addEventListener('ended', () => {
      this.isPlaying = false
      this.cancelLoop()
      this.emit('end')
    })
  }

  on(event: string, cb: CB<any>) { (this.cbs as any)[event]?.push(cb) }

  private emit<T>(event: string, data?: T) { for (const cb of (this.cbs as any)[event] ?? []) cb(data) }

  /** オーディオファイル内での現在位置(秒) */
  get currentTime() { return this.audio.currentTime }
  /** ルーティン内部での経過時間(秒) = audio.currentTime - trimStart */
  get routineTime() { return Math.max(0, this.audio.currentTime - this.trimStart) }
  get duration()    { return this.trimEnd === Infinity ? (this.audio.duration || 0) : this.trimEnd - this.trimStart }

  setAudio(url: string) {
    this.audio.src = url
    this.audio.load()
    this.trimStart = 0
    this.trimEnd = Infinity
  }

  setRoutine(r: Routine) {
    this.routine = r
    this.trimStart = r.trim_start ?? 0
    this.trimEnd = this.trimStart + r.duration
    this.lastPoseName = null
    this.lastBeatIdx = -1
    // 現在位置がトリム範囲外なら開始位置に戻す
    if (this.audio.currentTime < this.trimStart || this.audio.currentTime >= this.trimEnd) {
      this.audio.currentTime = this.trimStart
    }
  }

  play() {
    // トリム範囲の先頭から開始
    if (this.audio.currentTime < this.trimStart || this.audio.currentTime >= this.trimEnd) {
      this.audio.currentTime = this.trimStart
    }
    this.audio.play().catch(err => console.warn('[Player] audio.play() rejected:', err))
    this.isPlaying = true
    this.loop()
  }

  pause() {
    this.audio.pause()
    this.isPlaying = false
    this.cancelLoop()
  }

  seek(t: number) {
    // t はルーティン内部時刻(0始まり) → オーディオ位置に変換
    const audioT = this.trimStart + Math.max(0, Math.min(t, this.duration))
    this.audio.currentTime = audioT
    this.lastPoseName = null
    this.lastBeatIdx = -1
  }

  private loop() {
    this._raf = requestAnimationFrame(() => this.loop())
    const rt = this.routineTime
    this.emit('timeUpdate', rt)
    this.syncPose(rt)
    this.syncBeat(rt)

    // トリム終端に達したら停止
    if (this.audio.currentTime >= this.trimEnd) {
      this.pause()
      this.audio.currentTime = this.trimStart
      this.emit('end')
    }
  }

  private cancelLoop() { if (this._raf) { cancelAnimationFrame(this._raf); this._raf = null } }

  private syncPose(rt: number) {
    if (!this.routine) return
    const seq = this.routine.pose_sequence
    let current: PoseEntry | null = null
    for (let i = seq.length - 1; i >= 0; i--) {
      if (rt >= seq[i].time) { current = seq[i]; break }
    }
    if (!current) return
    if (this.lastPoseName !== current.pose_name) {
      this.lastPoseName = current.pose_name
      console.log('[Player] transitionToPose:', current.pose_name)
      this.emit('poseChange', current)
      this.viewer.transitionToPose(current.pose_name, current.keypoints)
    }
  }

  private syncBeat(rt: number) {
    const beats = this.routine?.beat_times; if (!beats) return
    let idx = -1
    for (let i = 0; i < beats.length; i++) { if (beats[i] <= rt) idx = i; else break }
    if (idx !== this.lastBeatIdx && idx >= 0) { this.lastBeatIdx = idx; this.emit('beat') }
  }
}
