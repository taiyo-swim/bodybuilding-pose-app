"""音楽解析結果からポーズルーティンを自動生成する。"""

import random

from .database import get_poses, save_routine

# デフォルトポーズ: エネルギーレベルと対応させる
DEFAULT_POSES = [
    {"name": "front_double_bicep", "energy": 0.80},
    {"name": "front_lat_spread",   "energy": 0.60},
    {"name": "most_muscular",      "energy": 0.90},
    {"name": "side_chest",         "energy": 0.50},
    {"name": "rear_lat_spread",    "energy": 0.65},
    {"name": "side_tricep",        "energy": 0.45},
    {"name": "abdominal_thigh",    "energy": 0.75},
    {"name": "rear_double_bicep",  "energy": 0.80},
    {"name": "hands_on_hips",      "energy": 0.30},
    {"name": "vacuum",             "energy": 0.70},
    {"name": "side_lat_spread",    "energy": 0.55},
    {"name": "front_relaxed",      "energy": 0.25},
]

# ポーズ1つあたりのホールド時間の下限・上限（秒）
MIN_HOLD = 2.0
MAX_HOLD = 8.0


def _beat_step(bpm: float) -> int:
    """BPMに応じたポーズ切り替え間隔（ビート数）を返す。

    遅い曲: 4ビート / 速い曲: 8ビート / 非常に速い曲: 12ビート
    """
    if bpm >= 140:
        return 12
    if bpm >= 110:
        return 8
    return 4


def _interval_from_bpm(bpm: float) -> float:
    """BPMから1ポーズあたりの目安秒数を求める（MIN/MAX_HOLDにクランプ）。"""
    if bpm <= 0:
        return 4.0
    interval = _beat_step(bpm) * 60.0 / bpm
    return min(MAX_HOLD, max(MIN_HOLD, interval))


def _switch_times(beat_times: list[float], duration: float, bpm: float) -> list[float]:
    """ポーズを切り替える時刻（ルーティン内部時刻、0始まり）のリストを返す。

    ビートが十分にあればビートに合わせ、足りなければBPMから等間隔で生成する。
    どちらの場合も MIN_HOLD 未満の間隔は間引き、MAX_HOLD を超える間隔は分割する。
    """
    if duration <= 0:
        return []

    step = _beat_step(bpm)
    times = [t for t in beat_times if 0 <= t < duration]
    switch = times[::step] if len(times) > step else []

    # ビート情報が使えない場合は等間隔にフォールバック
    if len(switch) < 2:
        interval = _interval_from_bpm(bpm)
        n = max(1, int(duration / interval))
        switch = [round(i * interval, 3) for i in range(n)]

    # ルーティンは必ず先頭(0秒)から始める
    if not switch or switch[0] > 0.05:
        switch.insert(0, 0.0)

    # 短すぎるホールドを間引く
    filtered: list[float] = []
    for t in switch:
        if not filtered or t - filtered[-1] >= MIN_HOLD:
            filtered.append(t)

    # 長すぎるホールドを分割する
    result: list[float] = []
    for i, t in enumerate(filtered):
        result.append(t)
        next_t = filtered[i + 1] if i + 1 < len(filtered) else duration
        gap = next_t - t
        if gap > MAX_HOLD:
            splits = int(gap // MAX_HOLD)
            sub = gap / (splits + 1)
            for k in range(1, splits + 1):
                result.append(round(t + sub * k, 3))

    return [t for t in result if t < duration]


def _energy_at(energy_curve: list[float], song_time: float, total_duration: float) -> float:
    """曲全体のエネルギーカーブから、指定した曲内時刻のエネルギーを線形補間で取得する。"""
    if not energy_curve:
        return 0.5
    if total_duration <= 0 or len(energy_curve) == 1:
        return float(energy_curve[0])

    pos = max(0.0, min(1.0, song_time / total_duration)) * (len(energy_curve) - 1)
    lo = int(pos)
    hi = min(lo + 1, len(energy_curve) - 1)
    frac = pos - lo
    return float(energy_curve[lo] * (1 - frac) + energy_curve[hi] * frac)


def _pick_pose(candidates: list[dict], energy_key: str, energy: float,
               recent: list[str], tolerance: float, rng: random.Random) -> dict:
    """エネルギーが近いポーズを、直近で使ったものを避けつつ選ぶ。"""
    near = [p for p in candidates if abs(p[energy_key] - energy) < tolerance]
    pool = near or candidates
    # 直近2ポーズと重複しないものを優先
    fresh = [p for p in pool if p["name"] not in recent[-2:]]
    if not fresh:
        fresh = [p for p in pool if p["name"] not in recent[-1:]]
    return rng.choice(fresh or pool)


def generate_routine(
    audio_info: dict,
    audio_file: str,
    name: str = "Auto Routine",
    pose_duration: float | None = None,
    trim_start: float = 0.0,
    trim_end: float | None = None,
    seed: int | None = None,
    persist: bool = True,
) -> dict:
    """
    音楽解析結果からポーズルーティンを自動生成する。
    trim_start / trim_end: 曲のどの区間を使うか（秒）
    pose_duration: その区間をさらに短縮する場合（Noneなら区間全体）
    seed: 指定するとポーズ選択が再現可能になる（テスト用）
    persist: False の場合DBに保存しない
    """
    rng = random.Random(seed)
    poses = get_poses()
    bpm = float(audio_info.get("bpm") or 0.0)
    all_beat_times = audio_info.get("beat_times") or []
    energy_curve = audio_info.get("energy_curve") or [0.5]
    total_duration = float(audio_info.get("duration") or 0.0)

    # トリム範囲を確定
    t_start = max(0.0, float(trim_start))
    t_end = min(total_duration, float(trim_end)) if trim_end is not None else total_duration
    if pose_duration is not None and pose_duration > 0:
        t_end = min(t_end, t_start + pose_duration)

    # 不正なトリム指定（範囲が無い・逆転している）は曲全体にフォールバック
    if t_end - t_start < MIN_HOLD:
        t_start, t_end = 0.0, total_duration

    duration = t_end - t_start

    # トリム範囲内のビートタイムをルーティン内部時刻（0始まり）に変換
    beat_times = [round(t - t_start, 3) for t in all_beat_times if t_start <= t < t_end]

    switch_times = _switch_times(beat_times, duration, bpm)

    pose_sequence = []
    used_names: list[str] = []

    for i, t in enumerate(switch_times):
        next_t = switch_times[i + 1] if i + 1 < len(switch_times) else duration
        hold_duration = round(next_t - t, 3)
        if hold_duration <= 0:
            continue

        energy = _energy_at(energy_curve, t_start + t, total_duration)

        if poses:
            # DBにポーズがある場合: エネルギーに近いものを選択
            chosen = _pick_pose(poses, "energy_level", energy, used_names, 0.3, rng)
            entry = {
                "time": round(t, 3),
                "duration": hold_duration,
                "pose_id": chosen["id"],
                "pose_name": chosen["name"],
                "energy": round(energy, 3),
                "transition": "smooth" if hold_duration > 1.5 else "snap",
                "keypoints": chosen.get("keypoints"),
            }
        else:
            # デフォルトポーズ（ビルトイン定義）にフォールバック
            chosen = _pick_pose(DEFAULT_POSES, "energy", energy, used_names, 0.35, rng)
            entry = {
                "time": round(t, 3),
                "duration": hold_duration,
                "pose_id": None,
                "pose_name": chosen["name"],
                "energy": round(energy, 3),
                "transition": "smooth" if hold_duration > 1.5 else "snap",
                "keypoints": None,
            }

        used_names.append(chosen["name"])
        pose_sequence.append(entry)

    routine_id = (
        save_routine(name, audio_file, bpm, duration, pose_sequence, t_start, beat_times)
        if persist else None
    )
    return {
        "id": routine_id,
        "name": name,
        "audio_file": audio_file,
        "bpm": bpm,
        "beat_times": beat_times,       # ルーティン内部時刻（0始まり）
        "duration": round(duration, 3),
        "trim_start": round(t_start, 3),  # フロントエンドでオーディオ位置合わせに使用
        "pose_count": len(pose_sequence),
        "pose_sequence": pose_sequence,
    }
