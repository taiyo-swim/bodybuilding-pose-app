import type { Routine, PoseEntry } from '../types'
import type { Viewer3D } from './viewer3d'

type CB<T = void> = (data: T) => void

interface Callbacks {
  timeUpdate: CB<number>[]
  end: CB[]
  poseChange: CB<PoseEntry>[]
  beat: CB[]
  error: CB<Error>[]
}

/**
 * 音楽再生とポーズ表示を同期させるプレイヤー。
 *
 * ルーティンは曲の一部（トリム区間）だけを使うことがあるため、
 * 「オーディオ内の時刻」と「ルーティン内部の時刻(0始まり)」を区別して扱う。
 *   routineTime = audio.currentTime - trimStart
 */
export class Player {
  private audio = new Audio()
  private routine: Routine | null = null
  private _raf: number | null = null
  private lastPoseName: string | null = null
  private lastBeatIdx = -1
  private trimStart = 0      // オーディオファイル内の開始位置(秒)
  private trimEnd = Infinity // オーディオファイル内の終了位置(秒)
  private cbs: Callbacks = { timeUpdate: [], end: [], poseChange: [], beat: [], error: [] }

  isPlaying = false

  constructor(private viewer: Viewer3D) {
    this.audio.preload = 'auto'
    this.audio.addEventListener('ended', () => this.finish())
    this.audio.addEventListener('error', () => {
      if (!this.audio.src) return
      this.isPlaying = false
      this.cancelLoop()
      this.emit('error', new Error('音源を読み込めませんでした'))
    })
  }

  on<K extends keyof Callbacks>(event: K, cb: Callbacks[K][number]) {
    (this.cbs[event] as CB<never>[]).push(cb as CB<never>)
  }

  private emit(event: keyof Callbacks, data?: unknown) {
    for (const cb of this.cbs[event] as CB<unknown>[]) cb(data)
  }

  /** オーディオファイル内での現在位置(秒) */
  get currentTime() { return this.audio.currentTime }
  /** ルーティン内部での経過時間(秒) */
  get routineTime() { return Math.max(0, this.audio.currentTime - this.trimStart) }
  /** ルーティンの長さ(秒) */
  get duration() {
    if (this.routine) return this.routine.duration
    return this.trimEnd === Infinity ? (this.audio.duration || 0) : this.trimEnd - this.trimStart
  }

  setAudio(url: string) {
    this.audio.pause()
    this.audio.src = url
    this.audio.load()
    this.isPlaying = false
    this.cancelLoop()
    this.trimStart = 0
    this.trimEnd = Infinity
    this.lastPoseName = null
    this.lastBeatIdx = -1
  }

  setRoutine(r: Routine) {
    this.routine = r
    this.trimStart = r.trim_start ?? 0
    this.trimEnd = this.trimStart + r.duration
    this.lastPoseName = null
    this.lastBeatIdx = -1
    this.seekAudio(this.trimStart)
    this.emit('timeUpdate', 0)
    // 先頭のポーズをすぐ表示する
    this.syncPose(0)
  }

  /** ルーティンを解除し、再生を停止する */
  reset() {
    this.pause()
    this.routine = null
    this.trimStart = 0
    this.trimEnd = Infinity
    this.lastPoseName = null
    this.lastBeatIdx = -1
    this.emit('timeUpdate', 0)
  }

  play() {
    if (!this.audio.src) return
    // トリム範囲外なら区間の先頭に戻す
    if (this.audio.currentTime < this.trimStart || this.audio.currentTime >= this.trimEnd - 0.05) {
      this.seekAudio(this.trimStart)
    }
    this.isPlaying = true
    this.audio.play().catch((err) => {
      this.isPlaying = false
      this.cancelLoop()
      console.warn('[Player] audio.play() rejected:', err)
      this.emit('error', err instanceof Error ? err : new Error(String(err)))
    })
    this.cancelLoop()
    this.loop()
  }

  pause() {
    this.audio.pause()
    this.isPlaying = false
    this.cancelLoop()
  }

  /** ルーティン内部時刻(0始まり)へシークする */
  seek(t: number) {
    const clamped = Math.max(0, Math.min(t, this.duration))
    this.seekAudio(this.trimStart + clamped)
    this.lastBeatIdx = -1
    this.emit('timeUpdate', clamped)
    this.syncPose(clamped)
  }

  /** 再生を止め、内部リソースを解放する */
  destroy() {
    this.pause()
    this.audio.removeAttribute('src')
    this.audio.load()
    for (const key of Object.keys(this.cbs) as (keyof Callbacks)[]) this.cbs[key] = []
  }

  /** メタデータ未読込でも安全に currentTime を設定する */
  private seekAudio(t: number) {
    try {
      this.audio.currentTime = t
    } catch {
      // readyState が HAVE_NOTHING の間は設定できないので、読み込み後に再試行する
      this.audio.addEventListener('loadedmetadata', () => { this.audio.currentTime = t }, { once: true })
    }
  }

  private finish() {
    this.pause()
    this.seekAudio(this.trimStart)
    this.lastPoseName = null
    this.lastBeatIdx = -1
    this.emit('timeUpdate', 0)
    this.emit('end')
  }

  private loop() {
    this._raf = requestAnimationFrame(() => this.loop())
    const rt = this.routineTime

    // トリム終端に達したら停止（ended イベントを待たない）
    if (this.audio.currentTime >= this.trimEnd) {
      this.finish()
      return
    }

    this.emit('timeUpdate', rt)
    this.syncPose(rt)
    this.syncBeat(rt)
  }

  private cancelLoop() {
    if (this._raf !== null) { cancelAnimationFrame(this._raf); this._raf = null }
  }

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
      this.emit('poseChange', current)
      this.viewer.transitionToPose(current.pose_name, current.keypoints)
    }
  }

  private syncBeat(rt: number) {
    const beats = this.routine?.beat_times
    if (!beats?.length) return
    let idx = -1
    for (let i = 0; i < beats.length; i++) {
      if (beats[i] <= rt) idx = i
      else break
    }
    if (idx !== this.lastBeatIdx && idx >= 0) {
      this.lastBeatIdx = idx
      this.emit('beat')
    }
  }
}
