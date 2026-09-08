/**
 * pywebview (デスクトップアプリ) 連携。
 *
 * ブラウザでは通常の <input type="file"> を使うが、pywebview で起動した場合は
 * ネイティブのファイル選択ダイアログ (app.py の Api クラス) を使う。
 * Python 側がファイルを uploads/ にコピーし、そのファイル名を返すので、
 * フロントは /api/audio/analyze・/api/video/analyze でそのファイルを解析させる。
 */

type PickResult = string | { error: string } | null

interface PyWebviewApi {
  pick_audio: () => Promise<PickResult>
  pick_video: () => Promise<PickResult>
  pick_model: () => Promise<PickResult>
}

declare global {
  interface Window {
    pywebview?: { api: PyWebviewApi }
  }
}

/** pywebview のネイティブAPIが使えるか */
export function isDesktop(): boolean {
  return typeof window !== 'undefined' && !!window.pywebview?.api?.pick_audio
}

function unwrap(result: PickResult): string | null {
  if (result === null || result === undefined) return null      // ダイアログをキャンセル
  if (typeof result === 'object' && 'error' in result) throw new Error(result.error)
  return typeof result === 'string' ? result : null
}

/** 音楽を選択し、uploads/ にコピーされたファイル名を返す（キャンセル時 null） */
export async function pickAudio(): Promise<string | null> {
  return unwrap(await window.pywebview!.api.pick_audio())
}

/** 動画を選択し、uploads/ にコピーされたファイル名を返す（キャンセル時 null） */
export async function pickVideo(): Promise<string | null> {
  return unwrap(await window.pywebview!.api.pick_video())
}

/** GLBモデルを選択し、models/ にコピーされたファイル名を返す（キャンセル時 null） */
export async function pickModel(): Promise<string | null> {
  return unwrap(await window.pywebview!.api.pick_model())
}
