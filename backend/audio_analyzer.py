"""音楽ファイルの解析（BPM・ビートタイム・エネルギーカーブ）。"""

import numpy as np

# エネルギーカーブの分割数
ENERGY_SEGMENTS = 16


def _energy_curve(rms: np.ndarray, segments: int = ENERGY_SEGMENTS) -> list[float]:
    """RMS列を segments 個に等分し、0〜1に正規化したエネルギーカーブを返す。

    非常に短い音源（rmsフレーム数 < segments）でも必ず segments 個返す。
    """
    if len(rms) == 0:
        return [0.5] * segments

    # np.array_split はフレーム数が segments 未満でも空チャンクを作るため、
    # インデックス補間でサンプリングする
    idx = np.linspace(0, len(rms), segments + 1).astype(int)
    curve = []
    for i in range(segments):
        lo, hi = idx[i], max(idx[i] + 1, idx[i + 1])
        curve.append(float(np.mean(rms[lo:min(hi, len(rms))])))

    e_min, e_max = min(curve), max(curve)
    if e_max - e_min > 1e-9:
        curve = [(e - e_min) / (e_max - e_min) for e in curve]
    else:
        curve = [0.5] * segments
    return curve


def _fallback_beats(duration: float, bpm: float) -> list[float]:
    """ビート検出に失敗した場合に BPM から等間隔ビートを生成する。"""
    if bpm <= 0 or duration <= 0:
        return []
    interval = 60.0 / bpm
    n = int(duration / interval)
    return [round(i * interval, 3) for i in range(n + 1)]


def analyze_audio(file_path: str) -> dict:
    """音楽ファイルを解析してBPM・ビート・エネルギー情報を返す"""
    import librosa  # 起動を軽くするため遅延インポート

    y, sr = librosa.load(file_path, sr=None, mono=True)
    duration = float(librosa.get_duration(y=y, sr=sr))

    if y.size == 0 or duration <= 0:
        raise ValueError("音声データを読み込めませんでした（空のファイルの可能性があります）")

    # BPM・ビート検出
    try:
        tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr)
        beat_times = librosa.frames_to_time(beat_frames, sr=sr).tolist()
        bpm = float(np.atleast_1d(tempo)[0])
    except Exception:
        bpm, beat_times = 0.0, []

    # BPMが取れない/異常な場合は既定値に丸める
    if not np.isfinite(bpm) or bpm <= 0:
        bpm = 120.0

    # ビートが検出できなかった場合は BPM から等間隔で補完する
    if len(beat_times) < 2:
        beat_times = _fallback_beats(duration, bpm)

    # RMSエネルギー（フレームごと）
    rms = librosa.feature.rms(y=y)[0]
    energy_curve = _energy_curve(rms)

    # スペクトル重心（明るさ）
    spectral_centroid = librosa.feature.spectral_centroid(y=y, sr=sr)[0]
    brightness = float(np.mean(spectral_centroid) / (sr / 2)) if spectral_centroid.size else 0.0

    return {
        "duration": round(duration, 2),
        "bpm": round(bpm, 1),
        "beat_times": [round(float(t), 3) for t in beat_times],
        "energy_curve": [round(e, 3) for e in energy_curve],
        "brightness": round(brightness, 3),
    }
