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


def generate_routine(
    audio_info: dict,
    audio_file: str,
    name: str = "Auto Routine",
    pose_duration: float | None = None,
    trim_start: float = 0.0,
    trim_end: float | None = None,
) -> dict:
    """
    音楽解析結果からポーズルーティンを自動生成する。
    trim_start / trim_end: 曲のどの区間を使うか（秒）
    pose_duration: その区間をさらに短縮する場合（Noneなら区間全体）
    """
    poses = get_poses()
    bpm = audio_info["bpm"]
    all_beat_times = audio_info["beat_times"]
    energy_curve = audio_info["energy_curve"]
    total_duration = audio_info["duration"]

    # トリム範囲を確定
    t_start = max(0.0, trim_start)
    t_end = min(total_duration, trim_end) if trim_end is not None else total_duration
    if pose_duration is not None and pose_duration > 0:
        t_end = min(t_end, t_start + pose_duration)

    segment_duration = t_end - t_start
    if segment_duration <= 0:
        segment_duration = total_duration
        t_start = 0.0
        t_end = total_duration

    # トリム範囲内のビートタイムを抽出し、ルーティン内部時刻（0始まり）に変換
    beat_times = [t - t_start for t in all_beat_times if t_start <= t < t_end]
    duration = segment_duration

    # BPMに応じてポーズ切り替えタイミングを決定
    # 遅い曲: 4ビートごと / 速い曲: 8ビートごと / 非常に速い曲: 12ビートごと
    if bpm >= 140:
        step = 12
    elif bpm >= 110:
        step = 8
    else:
        step = 4

    switch_times = beat_times[::step] if len(beat_times) > step else beat_times
    # 最低でも2秒以上のホールドになるよう間引き
    filtered = []
    last_t = -999.0
    for t in switch_times:
        if t - last_t >= 2.0:
            filtered.append(t)
            last_t = t
    switch_times = filtered if filtered else switch_times

    segments = len(energy_curve)
    pose_sequence = []
    used_names: list[str] = []

    for i, t in enumerate(switch_times):
        if t >= duration:
            break

        seg_idx = min(int(i / max(len(switch_times), 1) * segments), segments - 1)
        energy = energy_curve[seg_idx]
        next_t = switch_times[i + 1] if i + 1 < len(switch_times) else duration
        hold_duration = round(next_t - t, 3)

        if poses:
            # DBにポーズがある場合: エネルギーに近いものを選択
            candidates = [p for p in poses if abs(p["energy_level"] - energy) < 0.3]
            if not candidates:
                candidates = poses
            # 直前と同じポーズを避ける
            if len(candidates) > 1 and used_names:
                candidates = [p for p in candidates if p["name"] != used_names[-1]] or candidates
            chosen = random.choice(candidates)
            entry = {
                "time": round(t, 3),
                "duration": hold_duration,
                "pose_id": chosen["id"],
                "pose_name": chosen["name"],
                "energy": round(energy, 3),
                "transition": "smooth" if hold_duration > 1.5 else "snap",
                "keypoints": chosen.get("keypoints"),
            }
            used_names.append(chosen["name"])
        else:
            # デフォルトポーズ: エネルギー連動で選択 + 連続回避
            candidates = [p for p in DEFAULT_POSES if abs(p["energy"] - energy) < 0.35]
            if not candidates:
                candidates = DEFAULT_POSES
            if len(candidates) > 1 and used_names:
                candidates = [p for p in candidates if p["name"] != used_names[-1]] or candidates
            chosen = random.choice(candidates)
            pose_name = chosen["name"]
            entry = {
                "time": round(t, 3),
                "duration": hold_duration,
                "pose_id": None,
                "pose_name": pose_name,
                "energy": round(energy, 3),
                "transition": "smooth",
                "keypoints": None,
            }
            used_names.append(pose_name)

        pose_sequence.append(entry)

    routine_id = save_routine(name, audio_file, bpm, duration, pose_sequence)
    return {
        "id": routine_id,
        "name": name,
        "bpm": bpm,
        "beat_times": beat_times,       # ルーティン内部時刻（0始まり）
        "duration": duration,
        "trim_start": t_start,          # フロントエンドでオーディオ位置合わせに使用
        "pose_count": len(pose_sequence),
        "pose_sequence": pose_sequence,
    }
