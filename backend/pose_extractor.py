"""MediaPipe を使って動画からポーズキーポイントを抽出する。"""

import cv2
import mediapipe as mp
import numpy as np

mp_pose = mp.solutions.pose

# MediaPipeのランドマーク名
LANDMARK_NAMES = [lm.name.lower() for lm in mp_pose.PoseLandmark]

DEFAULT_FPS = 30.0


def extract_poses_from_video(video_path: str, sample_interval: float = 0.5) -> list[dict]:
    """
    動画からMediaPipeでポーズキーポイントを抽出する。
    sample_interval秒ごとにフレームをサンプリング。
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise ValueError(f"動画を開けませんでした: {video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS)
    if not fps or not np.isfinite(fps) or fps <= 0:
        fps = DEFAULT_FPS
    frame_interval = max(1, int(round(fps * sample_interval)))

    poses: list[dict] = []
    frame_idx = 0

    try:
        with mp_pose.Pose(
            static_image_mode=False,
            model_complexity=1,
            smooth_landmarks=True,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5
        ) as pose_model:
            while True:
                ret, frame = cap.read()
                if not ret:
                    break

                if frame_idx % frame_interval == 0:
                    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
                    result = pose_model.process(rgb)

                    if result.pose_landmarks:
                        keypoints = {}
                        for i, lm in enumerate(result.pose_landmarks.landmark):
                            keypoints[LANDMARK_NAMES[i]] = {
                                "x": round(lm.x, 4),
                                "y": round(lm.y, 4),
                                "z": round(lm.z, 4),
                                "visibility": round(lm.visibility, 4),
                            }
                        timestamp = frame_idx / fps
                        poses.append({"timestamp": round(timestamp, 3), "keypoints": keypoints})

                frame_idx += 1
    finally:
        cap.release()

    return poses


def pose_spread(pose: dict) -> float:
    """キーポイントの広がり（腕を開いているほど大きい）を返す。"""
    kps = pose["keypoints"]
    visible = [v for v in kps.values() if v.get("visibility", 1.0) > 0.5]
    if len(visible) < 10:
        return 0.0
    xs = [v["x"] for v in visible]
    ys = [v["y"] for v in visible]
    return float(np.std(xs) + np.std(ys))


def extract_representative_pose(video_path: str) -> dict | None:
    """動画からポーズの広がりが最も大きいフレームのポーズを1つ抽出する"""
    poses = extract_poses_from_video(video_path, sample_interval=0.25)
    if not poses:
        return None

    best = max(poses, key=pose_spread)
    # どのフレームも十分に検出できていない場合は登録しない
    if pose_spread(best) <= 0.0:
        return None
    return best
