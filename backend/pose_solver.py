"""
MediaPipe の world landmarks から Mixamo スケルトンのボーン回転を解くソルバー。

## 現行 pose_extractor との違い

`pose_extractor.extract_representative_pose()` は
  - 動画1本から**最も広がったフレーム1枚**だけを返す（動きを捨てる）
  - `pose_landmarks`（画像内の正規化座標。z は当てにならない相対深度）を使う
  - 腕・前腕・大腿・下腿の**8ボーン**しか駆動しない（腰・脊椎・肩・首を動かさない）
ため、トランジションを学習できず、学習した背面ポーズが正面を向いてしまう。

こちらは
  - `pose_world_landmarks`（腰中心を原点とするメートル単位の実3D座標）を使う
  - **全身**（腰のヨーを含む）を解く → 体の向きが再現される
  - 時系列を保持し、速度で「決めポーズ」と「トランジション」を分離する
  - heel / foot_index からかかとの上げ下げと接地を判定する

## 既知の限界

- MediaPipe は単眼推定なので奥行きは近似。斜めを向いたときの回転量に誤差が出る
- **ねじり(twist)は3点からは一意に決まらない。** 前腕・下腿は手先/つま先の
  ランドマークで部分的に解決するが、上腕のねじりは観測できない
- 脊椎は hip中心と shoulder中心の2点しか観測できないため、
  Spine / Spine1 / Spine2 の個別角度は解けない。総回転を3分割して配分する
- `MP_AXES` の座標系変換は**実写での検証が必要**（「座標系」節を参照）
"""

from __future__ import annotations

import numpy as np

# ── MediaPipe ランドマーク索引 ───────────────────────────────────────
LM = {
    "nose": 0,
    "left_ear": 7, "right_ear": 8,
    "left_shoulder": 11, "right_shoulder": 12,
    "left_elbow": 13, "right_elbow": 14,
    "left_wrist": 15, "right_wrist": 16,
    "left_pinky": 17, "right_pinky": 18,
    "left_index": 19, "right_index": 20,
    "left_hip": 23, "right_hip": 24,
    "left_knee": 25, "right_knee": 26,
    "left_ankle": 27, "right_ankle": 28,
    "left_heel": 29, "right_heel": 30,
    "left_foot_index": 31, "right_foot_index": 32,
}

# ── 座標系 ───────────────────────────────────────────────────────────
# MediaPipe world landmarks は画像系に準じた軸（x:右, y:下, z:カメラ方向）で
# 返るとされるが、符号の扱いは版や資料で揺れがある。
# ここでは「x:被写体の左, y:上, z:客席（カメラ）方向」の右手系へ移す行列として
# 外に出しておき、実写1本で検証して確定させる。
#   検証手順: 正面を向いたフレームを解いて facing_deg が 0 付近になり、
#             かかとを上げた足の heel_raised が True になることを確認する。
MP_AXES = np.array([
    [-1.0, 0.0, 0.0],   # MediaPipe x(右) → Mixamo -x（被写体の左が +x）
    [0.0, -1.0, 0.0],   # MediaPipe y(下) → Mixamo -y（上が +y）
    [0.0, 0.0, -1.0],   # MediaPipe z     → Mixamo -z（客席方向が +z）
])

# ── Mixamo スケルトン（Tポーズでのボーン方向と親子関係）─────────────
# 方向は「x:被写体の左, y:上, z:客席方向」のワールド系
REST_DIRS: dict[str, np.ndarray] = {
    "Spine":         np.array([0.0,  1.0, 0.0]),
    "Spine1":        np.array([0.0,  1.0, 0.0]),
    "Spine2":        np.array([0.0,  1.0, 0.0]),
    "Neck":          np.array([0.0,  1.0, 0.0]),
    "LeftShoulder":  np.array([1.0,  0.0, 0.0]),
    "LeftArm":       np.array([1.0,  0.0, 0.0]),
    "LeftForeArm":   np.array([1.0,  0.0, 0.0]),
    "RightShoulder": np.array([-1.0, 0.0, 0.0]),
    "RightArm":      np.array([-1.0, 0.0, 0.0]),
    "RightForeArm":  np.array([-1.0, 0.0, 0.0]),
    "LeftUpLeg":     np.array([0.0, -1.0, 0.0]),
    "LeftLeg":       np.array([0.0, -1.0, 0.0]),
    "LeftFoot":      np.array([0.0,  0.0, 1.0]),
    "RightUpLeg":    np.array([0.0, -1.0, 0.0]),
    "RightLeg":      np.array([0.0, -1.0, 0.0]),
    "RightFoot":     np.array([0.0,  0.0, 1.0]),
}

PARENT: dict[str, str | None] = {
    "Hips": None,
    "Spine": "Hips", "Spine1": "Spine", "Spine2": "Spine1",
    "Neck": "Spine2",
    "LeftShoulder": "Spine2", "LeftArm": "LeftShoulder", "LeftForeArm": "LeftArm",
    "RightShoulder": "Spine2", "RightArm": "RightShoulder", "RightForeArm": "RightArm",
    "LeftUpLeg": "Hips", "LeftLeg": "LeftUpLeg", "LeftFoot": "LeftLeg",
    "RightUpLeg": "Hips", "RightLeg": "RightUpLeg", "RightFoot": "RightLeg",
}

# 親が先に来る解決順
SOLVE_ORDER = [
    "Hips", "Spine", "Spine1", "Spine2", "Neck",
    "LeftShoulder", "LeftArm", "LeftForeArm",
    "RightShoulder", "RightArm", "RightForeArm",
    "LeftUpLeg", "LeftLeg", "LeftFoot",
    "RightUpLeg", "RightLeg", "RightFoot",
]

# ボーン → (始点ランドマーク, 終点ランドマーク)
BONE_SEGMENTS: dict[str, tuple[str, str]] = {
    "LeftShoulder":  ("_shoulder_center", "left_shoulder"),
    "LeftArm":       ("left_shoulder", "left_elbow"),
    "LeftForeArm":   ("left_elbow", "left_wrist"),
    "RightShoulder": ("_shoulder_center", "right_shoulder"),
    "RightArm":      ("right_shoulder", "right_elbow"),
    "RightForeArm":  ("right_elbow", "right_wrist"),
    "LeftUpLeg":     ("left_hip", "left_knee"),
    "LeftLeg":       ("left_knee", "left_ankle"),
    "LeftFoot":      ("left_ankle", "left_foot_index"),
    "RightUpLeg":    ("right_hip", "right_knee"),
    "RightLeg":      ("right_knee", "right_ankle"),
    "RightFoot":     ("right_ankle", "right_foot_index"),
    "Neck":          ("_shoulder_center", "nose"),
}


# ── クォータニオン（[x, y, z, w]）────────────────────────────────────

def quat_identity() -> np.ndarray:
    return np.array([0.0, 0.0, 0.0, 1.0])


def quat_mul(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return np.array([
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    ])


def quat_conj(q: np.ndarray) -> np.ndarray:
    return np.array([-q[0], -q[1], -q[2], q[3]])


def quat_apply(q: np.ndarray, v: np.ndarray) -> np.ndarray:
    qv = q[:3]
    w = q[3]
    return v + 2.0 * np.cross(qv, np.cross(qv, v) + w * v)


def quat_from_vectors(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    """a を b に向ける最小回転（ねじりは含まない）。"""
    a = _normalize(a)
    b = _normalize(b)
    d = float(np.dot(a, b))
    if d > 1.0 - 1e-9:
        return quat_identity()
    if d < -1.0 + 1e-9:
        # 180度: a に直交する任意軸で回す
        axis = np.cross(a, np.array([1.0, 0.0, 0.0]))
        if np.linalg.norm(axis) < 1e-6:
            axis = np.cross(a, np.array([0.0, 1.0, 0.0]))
        axis = _normalize(axis)
        return np.array([axis[0], axis[1], axis[2], 0.0])
    axis = np.cross(a, b)
    q = np.array([axis[0], axis[1], axis[2], 1.0 + d])
    return q / np.linalg.norm(q)


def quat_from_basis(x: np.ndarray, y: np.ndarray, z: np.ndarray) -> np.ndarray:
    """正規直交基底（列ベクトル x, y, z）を表す回転クォータニオン。"""
    m = np.column_stack([x, y, z])
    t = float(np.trace(m))
    if t > 0.0:
        s = np.sqrt(t + 1.0) * 2.0
        return np.array([
            (m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s,
            (m[1, 0] - m[0, 1]) / s, 0.25 * s,
        ])
    i = int(np.argmax(np.diag(m)))
    if i == 0:
        s = np.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2.0
        return np.array([0.25 * s, (m[0, 1] + m[1, 0]) / s,
                         (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s])
    if i == 1:
        s = np.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2.0
        return np.array([(m[0, 1] + m[1, 0]) / s, 0.25 * s,
                         (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s])
    s = np.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2.0
    return np.array([(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s,
                     0.25 * s, (m[1, 0] - m[0, 1]) / s])


def quat_slerp_fraction(q: np.ndarray, t: float) -> np.ndarray:
    """恒等回転から q へ t だけ進めた回転（脊椎の配分に使う）。"""
    q = q / np.linalg.norm(q)
    w = float(np.clip(q[3], -1.0, 1.0))
    angle = 2.0 * np.arccos(w)
    if angle < 1e-8:
        return quat_identity()
    axis = q[:3] / np.sin(angle / 2.0)
    half = angle * t / 2.0
    s = np.sin(half)
    return np.array([axis[0] * s, axis[1] * s, axis[2] * s, np.cos(half)])


def _normalize(v: np.ndarray) -> np.ndarray:
    n = float(np.linalg.norm(v))
    return v / n if n > 1e-12 else v


# ── ランドマーク前処理 ───────────────────────────────────────────────

def to_world(landmarks: np.ndarray) -> np.ndarray:
    """MediaPipe world landmarks (33,3) を Mixamo ワールド系へ移す。"""
    return landmarks @ MP_AXES.T


def named_points(world: np.ndarray) -> dict[str, np.ndarray]:
    pts = {name: world[idx] for name, idx in LM.items()}
    pts["_hip_center"] = 0.5 * (pts["left_hip"] + pts["right_hip"])
    pts["_shoulder_center"] = 0.5 * (pts["left_shoulder"] + pts["right_shoulder"])
    return pts


def torso_basis(pts: dict[str, np.ndarray]) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """腰の正規直交基底 (x=被写体の左, y=上, z=正面) を返す。

    方向1本ではなく基底を求めることで**体の向き(ヨー)が解ける**。
    現行実装が Hips を動かさないために背面ポーズが正面を向いてしまう問題は、
    これで解消する。
    """
    x = _normalize(pts["left_hip"] - pts["right_hip"])
    up = _normalize(pts["_shoulder_center"] - pts["_hip_center"])
    z = _normalize(np.cross(x, up))
    y = _normalize(np.cross(z, x))
    return x, y, z


# ── 1フレームを解く ─────────────────────────────────────────────────

def solve_pose(landmarks: np.ndarray) -> dict:
    """world landmarks (33,3) から全ボーンのローカル回転と診断値を返す。

    返り値:
      bones: {ボーン名: [x,y,z,w]} ローカル回転（親相対）
      facing_deg: 体の向き（0=正面, +90=被写体の左が客席, 180=背面）
      hip_height / heel_raised / foot_contact: 接地と足さばきの診断
    """
    world = to_world(np.asarray(landmarks, dtype=float))
    pts = named_points(world)

    world_q: dict[str, np.ndarray] = {}

    # Hips: 基底から直接。これがヨー（体の向き）を決める
    bx, by, bz = torso_basis(pts)
    world_q["Hips"] = quat_from_basis(bx, by, bz)

    # 脊椎: hip中心→shoulder中心 の総回転を3ボーンに配分する
    # （2点しか観測できないため個別角度は解けない。等分で近似）
    spine_dir = _normalize(pts["_shoulder_center"] - pts["_hip_center"])
    hips_up = quat_apply(world_q["Hips"], REST_DIRS["Spine"])
    total_spine = quat_from_vectors(hips_up, spine_dir)
    for i, bone in enumerate(("Spine", "Spine1", "Spine2"), start=1):
        part = quat_slerp_fraction(total_spine, i / 3.0)
        world_q[bone] = quat_mul(part, world_q["Hips"])

    # 残りのボーンは方向合わせ（親のワールド回転を基準にローカル化）
    for bone in SOLVE_ORDER:
        if bone in world_q:
            continue
        seg = BONE_SEGMENTS.get(bone)
        parent = PARENT[bone]
        pq = world_q.get(parent, quat_identity())
        if seg is None:
            world_q[bone] = pq
            continue
        a, b = seg
        target = pts[b] - pts[a]
        if float(np.linalg.norm(target)) < 1e-6:
            world_q[bone] = pq
            continue
        rest_world = quat_apply(pq, REST_DIRS[bone])
        world_q[bone] = quat_mul(quat_from_vectors(rest_world, _normalize(target)), pq)

    # ローカル回転へ変換
    bones: dict[str, list[float]] = {}
    for bone in SOLVE_ORDER:
        parent = PARENT[bone]
        pq = world_q.get(parent, quat_identity()) if parent else quat_identity()
        local = quat_mul(quat_conj(pq), world_q[bone])
        bones[bone] = [round(float(v), 6) for v in local / np.linalg.norm(local)]

    return {
        "bones": bones,
        "facing_deg": round(facing_degrees(pts), 2),
        "hip_height": round(float(pts["_hip_center"][1]), 4),
        "heel_raised": {
            "left": heel_raised(pts, "left"),
            "right": heel_raised(pts, "right"),
        },
        "ankle_height": {
            "left": round(float(pts["left_ankle"][1]), 4),
            "right": round(float(pts["right_ankle"][1]), 4),
        },
    }


def facing_degrees(pts: dict[str, np.ndarray]) -> float:
    """体の向きを +Y 軸まわりの回転角[度]で返す。

    ワールド +z（客席方向）を 0 とし、+z が +x へ向かう向きを正にとる。
      0 = 正面 / ±90 = 側面 / 180 = 背面
    胴体基底の前方ベクトル z から求める。
    """
    _, _, z = torso_basis(pts)
    return float(np.degrees(np.arctan2(z[0], z[2])))


def heel_raised(pts: dict[str, np.ndarray], side: str, margin: float = 0.02) -> bool:
    """かかとが上がっているか。

    サイドチェスト／サイドトライセップス／バックラットスプレッドで
    「前足のかかとを上げる」形が取れているかを直接判定する。
    heel と foot_index の高さの差で見る（margin はメートル）。
    """
    return bool(pts[f"{side}_heel"][1] - pts[f"{side}_foot_index"][1] > margin)


# ════════════════════════════════════════════════════════════════════
# 時系列の分割: 「決めポーズ」と「トランジション」を分離する
# ════════════════════════════════════════════════════════════════════
#
# 現行 extract_representative_pose() は動画1本から1フレームだけ返すため、
# 動きが全部捨てられ、トランジションを学習できない。
#
# フリーポーズは「決めを2〜3秒止め、つなぎは速く」という構造なので、
# ランドマークの速度を見れば両者を機械的に分離できる。
#   速度が低い区間 → 決めポーズ（ポーズライブラリへ）
#   速度が高い区間 → トランジション軌道（動きとして保存）

# 速度を測るランドマーク（顔や指は誤差が大きいので使わない）
VELOCITY_LANDMARKS = [
    "left_shoulder", "right_shoulder", "left_elbow", "right_elbow",
    "left_wrist", "right_wrist", "left_hip", "right_hip",
    "left_knee", "right_knee", "left_ankle", "right_ankle",
]

# 決めポーズと判定する速度のしきい値[m/s]と最短の静止時間[秒]
# 実写では手ぶれや推定ノイズで静止中も速度が出るため、
# 素材に合わせて調整する前提の既定値。
HOLD_SPEED_MAX = 0.20
HOLD_MIN_DURATION = 0.45

# ホールド中に許容するランドマークの移動量[m]。
# 速度が低いだけでは不十分で、ゆっくり動き続ける転換を
# 決めポーズと誤認してしまう（転換途中の姿勢がライブラリに入る）。
# 変位でも縛ることで「止まっている」ことを担保する。
HOLD_MAX_DRIFT = 0.12

# 速度は全ランドマークの平均ではなく「最も速い上位K個の平均」で測る。
# 平均だと、腕だけを動かす転換が静止している体幹・脚に薄められて
# 検出できない（腕だけの動きも転換である）。
SPEED_TOP_K = 4


def landmark_speeds(times: list[float], frames: list[np.ndarray]) -> np.ndarray:
    """フレームごとの動きの速さ[m/s]を返す。

    代表ランドマークのうち**最も速い上位 SPEED_TOP_K 個の平均**を使う。
    times と frames は同じ長さ。frames は MediaPipe world landmarks (33,3)。
    """
    if len(frames) < 2:
        return np.zeros(len(frames))

    idx = [LM[n] for n in VELOCITY_LANDMARKS]
    pts = np.stack([to_world(np.asarray(f, dtype=float))[idx] for f in frames])
    t = np.asarray(times, dtype=float)
    k = min(SPEED_TOP_K, len(idx))

    speeds = np.zeros(len(frames))
    for i in range(len(frames)):
        lo = max(0, i - 1)
        hi = min(len(frames) - 1, i + 1)
        dt = t[hi] - t[lo]
        if dt <= 1e-6:
            continue
        per_lm = np.linalg.norm(pts[hi] - pts[lo], axis=1) / dt
        speeds[i] = float(np.mean(np.sort(per_lm)[-k:]))
    return speeds


def smooth(values: np.ndarray, window: int = 5) -> np.ndarray:
    """移動平均。検出のちらつきを抑える。"""
    if len(values) == 0 or window <= 1:
        return values
    window = min(window, len(values))
    if window % 2 == 0:
        window += 1
    pad = window // 2
    padded = np.pad(values, pad, mode="edge")
    kernel = np.ones(window) / window
    return np.convolve(padded, kernel, mode="valid")[: len(values)]


def landmark_drift(frames: list[np.ndarray], lo: int, hi: int) -> float:
    """区間 [lo, hi] における代表ランドマークの最大移動量[m]。"""
    idx = [LM[n] for n in VELOCITY_LANDMARKS]
    pts = np.stack([to_world(np.asarray(frames[i], dtype=float))[idx]
                    for i in range(lo, hi + 1)])
    center = np.median(pts, axis=0)
    return float(np.max(np.linalg.norm(pts - center, axis=2)))


def segment_motion(
    times: list[float],
    frames: list[np.ndarray],
    *,
    hold_speed_max: float = HOLD_SPEED_MAX,
    hold_min_duration: float = HOLD_MIN_DURATION,
    hold_max_drift: float = HOLD_MAX_DRIFT,
) -> list[dict]:
    """時系列を hold（決めポーズ）と transition（つなぎ）に分割する。

    返り値は時刻順のセグメント列:
      {"kind": "hold", "start", "end", "duration",
       "frame": 代表フレーム索引, "mean_speed"}
      {"kind": "transition", "start", "end", "duration",
       "frames": [索引...], "peak_speed"}

    hold は「代表1枚」を持つのでポーズライブラリに入れられる。
    transition は軌道としてフレーム列を保持するので、動きそのものを再現できる。
    """
    if not frames:
        return []
    if len(frames) == 1:
        return [{"kind": "hold", "start": times[0], "end": times[0],
                 "duration": 0.0, "frame": 0, "mean_speed": 0.0}]

    speeds = smooth(landmark_speeds(times, frames))
    slow = speeds <= hold_speed_max

    # 連続する同ラベルの区間にまとめる
    runs: list[tuple[bool, int, int]] = []
    start = 0
    for i in range(1, len(slow) + 1):
        if i == len(slow) or slow[i] != slow[start]:
            runs.append((bool(slow[start]), start, i - 1))
            start = i

    # ホールドの条件を絞る:
    #   - 短すぎる静止は拾わない（つなぎの途中の減速を除外）
    #   - 変位が大きいものは拾わない（ゆっくり動き続ける転換を除外）
    normalized: list[tuple[bool, int, int]] = []
    for is_slow, lo, hi in runs:
        if is_slow and times[hi] - times[lo] < hold_min_duration:
            is_slow = False
        if is_slow and landmark_drift(frames, lo, hi) > hold_max_drift:
            is_slow = False
        if normalized and normalized[-1][0] == is_slow:
            normalized[-1] = (is_slow, normalized[-1][1], hi)
        else:
            normalized.append((is_slow, lo, hi))

    segments: list[dict] = []
    for is_slow, lo, hi in normalized:
        span = {"start": round(times[lo], 3), "end": round(times[hi], 3),
                "duration": round(times[hi] - times[lo], 3)}
        if is_slow:
            # 最も静止しているフレームを代表にする
            rep = lo + int(np.argmin(speeds[lo:hi + 1]))
            segments.append({"kind": "hold", **span, "frame": rep,
                             "mean_speed": round(float(np.mean(speeds[lo:hi + 1])), 4)})
        else:
            segments.append({"kind": "transition", **span,
                             "frames": list(range(lo, hi + 1)),
                             "peak_speed": round(float(np.max(speeds[lo:hi + 1])), 4)})
    return segments


def extract_routine(times: list[float], frames: list[np.ndarray]) -> dict:
    """動画1本から、決めポーズ列とトランジション軌道の両方を取り出す。

    現行 extract_representative_pose() の置き換え。あちらは1枚しか返さない。
    """
    segments = segment_motion(times, frames)
    holds, transitions = [], []
    for seg in segments:
        if seg["kind"] == "hold":
            solved = solve_pose(frames[seg["frame"]])
            holds.append({
                "time": seg["start"], "duration": seg["duration"],
                "timestamp": round(times[seg["frame"]], 3),
                **solved,
            })
        else:
            transitions.append({
                "time": seg["start"], "duration": seg["duration"],
                "peak_speed": seg["peak_speed"],
                # 軌道は始点・中間・終点の3点に間引いて保持する
                "keyframes": [solve_pose(frames[i]) for i in _thin(seg["frames"], 3)],
            })
    return {"holds": holds, "transitions": transitions, "segments": segments}


def _thin(indices: list[int], count: int) -> list[int]:
    if len(indices) <= count:
        return indices
    picks = np.linspace(0, len(indices) - 1, count).astype(int)
    return [indices[i] for i in picks]
