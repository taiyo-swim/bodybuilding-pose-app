import librosa
import numpy as np
from pathlib import Path


def analyze_audio(file_path: str) -> dict:
    """音楽ファイルを解析してBPM・ビート・エネルギー情報を返す"""
    y, sr = librosa.load(file_path, sr=None)
    duration = librosa.get_duration(y=y, sr=sr)

    # BPM・ビート検出
    tempo, beat_frames = librosa.beat.beat_track(y=y, sr=sr)
    beat_times = librosa.frames_to_time(beat_frames, sr=sr).tolist()
    bpm = float(tempo[0]) if hasattr(tempo, '__len__') else float(tempo)

    # RMSエネルギー（フレームごと）
    rms = librosa.feature.rms(y=y)[0]
    rms_times = librosa.frames_to_time(np.arange(len(rms)), sr=sr)

    # 全体エネルギー推移を16分割でサンプリング
    segments = 16
    energy_curve = []
    seg_len = len(rms) // segments
    for i in range(segments):
        chunk = rms[i * seg_len:(i + 1) * seg_len]
        energy_curve.append(float(np.mean(chunk)))

    # エネルギーを0〜1に正規化
    e_min, e_max = min(energy_curve), max(energy_curve)
    if e_max > e_min:
        energy_curve = [(e - e_min) / (e_max - e_min) for e in energy_curve]
    else:
        energy_curve = [0.5] * segments

    # スペクトル重心（明るさ）
    spectral_centroid = librosa.feature.spectral_centroid(y=y, sr=sr)[0]
    brightness = float(np.mean(spectral_centroid) / (sr / 2))

    return {
        "duration": round(duration, 2),
        "bpm": round(bpm, 1),
        "beat_times": [round(t, 3) for t in beat_times],
        "energy_curve": [round(e, 3) for e in energy_curve],
        "brightness": round(brightness, 3),
    }
