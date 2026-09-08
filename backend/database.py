"""SQLite への poses / routines テーブルのCRUD操作。"""

import json
import os
import sqlite3
from pathlib import Path

DB_PATH = Path(os.environ.get(
    "POSE_DB_PATH",
    Path(__file__).parent.parent / "poses_db" / "poses.db",
))


def get_connection() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = get_connection()
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS poses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            category TEXT NOT NULL,
            energy_level REAL NOT NULL DEFAULT 0.5,
            keypoints TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS routines (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            audio_file TEXT,
            bpm REAL,
            duration REAL,
            pose_sequence TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE INDEX IF NOT EXISTS idx_poses_name ON poses(name);
        CREATE INDEX IF NOT EXISTS idx_poses_category ON poses(category);
    """)

    # 既存DBのマイグレーション: 保存済みルーティンを再生するために必要な列を追加
    existing = {row["name"] for row in conn.execute("PRAGMA table_info(routines)")}
    if "trim_start" not in existing:
        conn.execute("ALTER TABLE routines ADD COLUMN trim_start REAL NOT NULL DEFAULT 0")
    if "beat_times" not in existing:
        conn.execute("ALTER TABLE routines ADD COLUMN beat_times TEXT NOT NULL DEFAULT '[]'")

    conn.commit()
    conn.close()


# ── poses ────────────────────────────────────────────────────────────

def save_pose(name: str, category: str, energy_level: float, keypoints: dict) -> int:
    conn = get_connection()
    cursor = conn.execute(
        "INSERT INTO poses (name, category, energy_level, keypoints) VALUES (?, ?, ?, ?)",
        (name, category, float(energy_level), json.dumps(keypoints))
    )
    pose_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return pose_id


def get_poses(category: str | None = None) -> list[dict]:
    conn = get_connection()
    if category:
        rows = conn.execute(
            "SELECT * FROM poses WHERE category = ? ORDER BY energy_level",
            (category,)
        ).fetchall()
    else:
        rows = conn.execute("SELECT * FROM poses ORDER BY category, energy_level").fetchall()
    conn.close()
    poses = []
    for row in rows:
        p = dict(row)
        p["keypoints"] = json.loads(p["keypoints"])
        poses.append(p)
    return poses


def get_pose(pose_id: int) -> dict | None:
    conn = get_connection()
    row = conn.execute("SELECT * FROM poses WHERE id = ?", (pose_id,)).fetchone()
    conn.close()
    if row is None:
        return None
    p = dict(row)
    p["keypoints"] = json.loads(p["keypoints"])
    return p


def delete_pose(pose_id: int) -> bool:
    """ポーズを削除する。削除できたら True。"""
    conn = get_connection()
    deleted = conn.execute("DELETE FROM poses WHERE id = ?", (pose_id,)).rowcount
    conn.commit()
    conn.close()
    return deleted > 0


def delete_poses_by_name(name: str) -> int:
    """同名ポーズをすべて削除し、削除件数を返す（学習スクリプトの上書き用）。"""
    conn = get_connection()
    deleted = conn.execute("DELETE FROM poses WHERE name = ?", (name,)).rowcount
    conn.commit()
    conn.close()
    return deleted


# ── routines ─────────────────────────────────────────────────────────

def save_routine(name: str, audio_file: str, bpm: float, duration: float,
                 pose_sequence: list, trim_start: float = 0.0,
                 beat_times: list[float] | None = None) -> int:
    conn = get_connection()
    cursor = conn.execute(
        "INSERT INTO routines (name, audio_file, bpm, duration, pose_sequence, trim_start, beat_times) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        (name, audio_file, bpm, duration, json.dumps(pose_sequence),
         float(trim_start), json.dumps(beat_times or []))
    )
    routine_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return routine_id


def _row_to_routine(row: sqlite3.Row) -> dict:
    r = dict(row)
    r["pose_sequence"] = json.loads(r["pose_sequence"])
    r["beat_times"] = json.loads(r.get("beat_times") or "[]")
    r["pose_count"] = len(r["pose_sequence"])
    return r


def get_routines(limit: int = 50) -> list[dict]:
    conn = get_connection()
    rows = conn.execute(
        "SELECT * FROM routines ORDER BY created_at DESC, id DESC LIMIT ?", (limit,)
    ).fetchall()
    conn.close()
    return [_row_to_routine(row) for row in rows]


def get_routine(routine_id: int) -> dict | None:
    conn = get_connection()
    row = conn.execute("SELECT * FROM routines WHERE id = ?", (routine_id,)).fetchone()
    conn.close()
    return _row_to_routine(row) if row else None


def delete_routine(routine_id: int) -> bool:
    conn = get_connection()
    deleted = conn.execute("DELETE FROM routines WHERE id = ?", (routine_id,)).rowcount
    conn.commit()
    conn.close()
    return deleted > 0
