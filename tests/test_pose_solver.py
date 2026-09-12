"""pose_solver の往復テスト。

既知のボーン方向からランドマークを合成し、ソルバーがその方向を復元できるかを見る。
実写がなくてもソルバーの数学（階層のローカル↔ワールド変換、基底からのヨー復元、
かかと判定）を検証できる。
"""

import numpy as np
import pytest

from backend import pose_solver as ps

MP_FROM_WORLD = np.linalg.inv(ps.MP_AXES)


def build_landmarks(
    *,
    yaw_deg: float = 0.0,
    left_arm=(1.0, 0.0, 0.0),
    left_forearm=(1.0, 0.0, 0.0),
    right_arm=(-1.0, 0.0, 0.0),
    right_forearm=(-1.0, 0.0, 0.0),
    left_upleg=(0.0, -1.0, 0.0),
    left_leg=(0.0, -1.0, 0.0),
    right_upleg=(0.0, -1.0, 0.0),
    right_leg=(0.0, -1.0, 0.0),
    left_heel_lift: float = 0.0,
    right_heel_lift: float = 0.0,
    hip_height: float = 0.0,
) -> np.ndarray:
    """Mixamoワールド系で骨格を組み、MediaPipe world landmarks 形式で返す。"""
    n = lambda v: np.array(v, dtype=float) / max(np.linalg.norm(v), 1e-12)

    hip_c = np.array([0.0, hip_height, 0.0])
    shoulder_c = hip_c + np.array([0.0, 0.55, 0.0])
    hip_half, sh_half = 0.10, 0.20
    upper_arm, fore_arm = 0.28, 0.26
    thigh, shin, foot = 0.42, 0.40, 0.18

    p = {}
    p["left_hip"]  = hip_c + np.array([ hip_half, 0, 0])
    p["right_hip"] = hip_c + np.array([-hip_half, 0, 0])
    p["left_shoulder"]  = shoulder_c + np.array([ sh_half, 0, 0])
    p["right_shoulder"] = shoulder_c + np.array([-sh_half, 0, 0])
    p["nose"] = shoulder_c + np.array([0.0, 0.25, 0.05])
    p["left_ear"]  = p["nose"] + np.array([ 0.07, 0.02, -0.05])
    p["right_ear"] = p["nose"] + np.array([-0.07, 0.02, -0.05])

    p["left_elbow"] = p["left_shoulder"] + n(left_arm) * upper_arm
    p["left_wrist"] = p["left_elbow"] + n(left_forearm) * fore_arm
    p["right_elbow"] = p["right_shoulder"] + n(right_arm) * upper_arm
    p["right_wrist"] = p["right_elbow"] + n(right_forearm) * fore_arm
    for s in ("left", "right"):
        p[f"{s}_index"] = p[f"{s}_wrist"] + np.array([0.0, 0.0, 0.06])
        p[f"{s}_pinky"] = p[f"{s}_wrist"] + np.array([0.0, -0.02, 0.05])

    p["left_knee"]  = p["left_hip"]  + n(left_upleg) * thigh
    p["left_ankle"] = p["left_knee"] + n(left_leg) * shin
    p["right_knee"]  = p["right_hip"]  + n(right_upleg) * thigh
    p["right_ankle"] = p["right_knee"] + n(right_leg) * shin
    p["left_foot_index"]  = p["left_ankle"]  + np.array([0.0, -0.02, foot])
    p["right_foot_index"] = p["right_ankle"] + np.array([0.0, -0.02, foot])
    p["left_heel"]  = p["left_ankle"]  + np.array([0.0, -0.04 + left_heel_lift, -0.05])
    p["right_heel"] = p["right_ankle"] + np.array([0.0, -0.04 + right_heel_lift, -0.05])

    # 体全体をヨー回転させる
    if yaw_deg:
        a = np.radians(yaw_deg)
        rot = np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]])
        p = {k: rot @ v for k, v in p.items()}

    out = np.zeros((33, 3))
    for name, idx in ps.LM.items():
        out[idx] = p[name]
    return out @ MP_FROM_WORLD.T


def world_dir(result: dict, bone: str) -> np.ndarray:
    """解かれたローカル回転を階層で合成し、そのボーンのワールド方向を復元する。"""
    chain = []
    b = bone
    while b is not None:
        chain.append(b)
        b = ps.PARENT[b]
    q = ps.quat_identity()
    for b in reversed(chain):
        q = ps.quat_mul(q, np.array(result["bones"][b]))
    return ps.quat_apply(q, ps.REST_DIRS[bone])


# ── 体の向き（現行実装が解けていない部分）──────────────────────────

@pytest.mark.parametrize("yaw", [0, 30, 90, -90, 180, -135])
def test_facing_is_recovered(yaw):
    """体の向きが復元できること。

    現行実装は Hips を動かさないため学習した背面ポーズが正面を向いてしまう。
    基底から解くことでヨーが復元されることを確認する。
    """
    r = ps.solve_pose(build_landmarks(yaw_deg=yaw))
    diff = (r["facing_deg"] - yaw + 180) % 360 - 180
    assert abs(diff) < 1.0, f"yaw={yaw} → facing={r['facing_deg']}"


def test_hips_rotation_encodes_facing():
    """背面向きのとき Hips のローカル回転が約180度になること。"""
    r = ps.solve_pose(build_landmarks(yaw_deg=180))
    forward = ps.quat_apply(np.array(r["bones"]["Hips"]), np.array([0.0, 0.0, 1.0]))
    assert forward[2] < -0.99, forward


def test_torso_basis_is_orthonormal():
    pts = ps.named_points(ps.to_world(build_landmarks(yaw_deg=37)))
    x, y, z = ps.torso_basis(pts)
    for v in (x, y, z):
        assert abs(np.linalg.norm(v) - 1.0) < 1e-9
    assert abs(np.dot(x, y)) < 1e-9
    assert abs(np.dot(y, z)) < 1e-9
    assert abs(np.dot(z, x)) < 1e-9


# ── 四肢の往復 ──────────────────────────────────────────────────────

def test_tpose_roundtrip_is_identity():
    r = ps.solve_pose(build_landmarks())
    for bone in ("LeftArm", "LeftForeArm", "RightArm", "RightForeArm",
                 "LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg"):
        got = world_dir(r, bone)
        assert np.allclose(got, ps.REST_DIRS[bone], atol=1e-6), f"{bone}: {got}"


def test_front_double_biceps_arms_roundtrip():
    """フロントダブルバイセップス相当（腕を水平に上げ肘を曲げる）の復元。"""
    dirs = {
        "left_arm": (0.9, 0.45, 0.0), "left_forearm": (0.1, 0.95, 0.1),
        "right_arm": (-0.9, 0.45, 0.0), "right_forearm": (-0.1, 0.95, 0.1),
    }
    r = ps.solve_pose(build_landmarks(**dirs))
    for bone, key in (("LeftArm", "left_arm"), ("LeftForeArm", "left_forearm"),
                      ("RightArm", "right_arm"), ("RightForeArm", "right_forearm")):
        want = np.array(dirs[key]) / np.linalg.norm(dirs[key])
        assert np.allclose(world_dir(r, bone), want, atol=1e-5), bone


def test_limb_roundtrip_under_body_rotation():
    """体をひねった状態でも四肢のワールド方向が復元されること（階層の検証）。"""
    dirs = {"left_arm": (0.3, 0.9, 0.3), "left_forearm": (0.0, 0.2, 0.98),
            "left_upleg": (0.1, -0.95, 0.3), "left_leg": (0.0, -0.99, -0.14)}
    lm = build_landmarks(yaw_deg=55, **dirs)
    r = ps.solve_pose(lm)
    # 期待方向も同じヨーで回す
    a = np.radians(55)
    rot = np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]])
    for bone, key in (("LeftArm", "left_arm"), ("LeftForeArm", "left_forearm"),
                      ("LeftUpLeg", "left_upleg"), ("LeftLeg", "left_leg")):
        want = rot @ (np.array(dirs[key]) / np.linalg.norm(dirs[key]))
        assert np.allclose(world_dir(r, bone), want, atol=1e-5), bone


def test_bent_knee_roundtrip():
    """サイドチェストの前脚（膝を曲げる）が復元されること。"""
    dirs = {"left_upleg": (0.05, -0.9, 0.43), "left_leg": (0.0, -0.95, -0.31)}
    r = ps.solve_pose(build_landmarks(**dirs))
    for bone, key in (("LeftUpLeg", "left_upleg"), ("LeftLeg", "left_leg")):
        want = np.array(dirs[key]) / np.linalg.norm(dirs[key])
        assert np.allclose(world_dir(r, bone), want, atol=1e-5), bone


# ── 足さばき（heel / foot_index があることで可能になった判定）───────

def test_heel_raised_detection():
    """「前足のかかとを上げる」が検出できること。

    サイドチェスト／サイドトライセップス／バックラットスプレッドの要件。
    """
    flat = ps.solve_pose(build_landmarks())
    assert flat["heel_raised"] == {"left": False, "right": False}

    lifted = ps.solve_pose(build_landmarks(left_heel_lift=0.08))
    assert lifted["heel_raised"]["left"] is True
    assert lifted["heel_raised"]["right"] is False


def test_heel_raised_survives_body_rotation():
    """側面を向いていてもかかと判定が効くこと。"""
    r = ps.solve_pose(build_landmarks(yaw_deg=90, left_heel_lift=0.08))
    assert r["heel_raised"]["left"] is True


def test_hip_height_tracks_crouch():
    """腰の高さが取れること（膝つき検出の土台）。"""
    tall = ps.solve_pose(build_landmarks(hip_height=0.0))["hip_height"]
    low = ps.solve_pose(build_landmarks(hip_height=-0.35))["hip_height"]
    assert low < tall - 0.3


# ── クォータニオン基礎 ──────────────────────────────────────────────

def test_quat_from_vectors_aligns():
    rng = np.random.default_rng(0)
    for _ in range(50):
        a, b = rng.normal(size=3), rng.normal(size=3)
        q = ps.quat_from_vectors(a, b)
        got = ps.quat_apply(q, a / np.linalg.norm(a))
        assert np.allclose(got, b / np.linalg.norm(b), atol=1e-9)


def test_quat_from_vectors_handles_antiparallel():
    a = np.array([1.0, 0.0, 0.0])
    q = ps.quat_from_vectors(a, -a)
    assert np.allclose(ps.quat_apply(q, a), -a, atol=1e-9)


def test_quat_basis_roundtrip():
    """右手系の基底（x × y = z）が回転として復元できること。"""
    a = np.radians(40)
    x = np.array([np.cos(a), 0.0, -np.sin(a)])
    y = np.array([0.0, 1.0, 0.0])
    z = np.cross(x, y)
    q = ps.quat_from_basis(x, y, z)
    assert np.allclose(ps.quat_apply(q, np.array([1.0, 0, 0])), x, atol=1e-9)
    assert np.allclose(ps.quat_apply(q, np.array([0, 1.0, 0])), y, atol=1e-9)
    assert np.allclose(ps.quat_apply(q, np.array([0, 0, 1.0])), z, atol=1e-9)


def test_quat_from_basis_is_unit():
    rng = np.random.default_rng(3)
    for _ in range(30):
        x = rng.normal(size=3); x /= np.linalg.norm(x)
        tmp = rng.normal(size=3)
        y = tmp - np.dot(tmp, x) * x; y /= np.linalg.norm(y)
        z = np.cross(x, y)
        q = ps.quat_from_basis(x, y, z)
        assert abs(np.linalg.norm(q) - 1.0) < 1e-9


def test_slerp_fraction_endpoints():
    total = ps.quat_from_vectors(np.array([0.0, 1.0, 0.0]), np.array([0.0, 0.9, 0.44]))
    assert np.allclose(ps.quat_slerp_fraction(total, 0.0), ps.quat_identity(), atol=1e-9)
    up = np.array([0.0, 1.0, 0.0])
    assert np.allclose(ps.quat_apply(ps.quat_slerp_fraction(total, 1.0), up),
                       ps.quat_apply(total, up), atol=1e-9)


def test_solved_spine_chain_reproduces_torso_lean():
    """3分割した脊椎を合成すると hip中心→shoulder中心 の方向が再現されること。"""
    lm = build_landmarks(yaw_deg=25)
    r = ps.solve_pose(lm)
    pts = ps.named_points(ps.to_world(lm))
    want = pts["_shoulder_center"] - pts["_hip_center"]
    want = want / np.linalg.norm(want)
    assert np.allclose(world_dir(r, "Spine2"), want, atol=1e-6)
