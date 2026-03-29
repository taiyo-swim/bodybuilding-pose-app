import sqlite3
import json
from pathlib import Path

DB_PATH = Path(__file__).parent.parent / "poses_db" / "poses.db"


def get_connection():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    DB_PATH.parent.mkdir(exist_ok=True)
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
    """)
    conn.commit()
    conn.close()


def save_pose(name: str, category: str, energy_level: float, keypoints: dict) -> int:
    conn = get_connection()
    cursor = conn.execute(
        "INSERT INTO poses (name, category, energy_level, keypoints) VALUES (?, ?, ?, ?)",
        (name, category, energy_level, json.dumps(keypoints))
    )
    pose_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return pose_id


def get_poses(category: str = None) -> list[dict]:
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


def save_routine(name: str, audio_file: str, bpm: float, duration: float, pose_sequence: list) -> int:
    conn = get_connection()
    cursor = conn.execute(
        "INSERT INTO routines (name, audio_file, bpm, duration, pose_sequence) VALUES (?, ?, ?, ?, ?)",
        (name, audio_file, bpm, duration, json.dumps(pose_sequence))
    )
    routine_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return routine_id


def get_routines() -> list[dict]:
    conn = get_connection()
    rows = conn.execute("SELECT * FROM routines ORDER BY created_at DESC").fetchall()
    conn.close()
    routines = []
    for row in rows:
        r = dict(row)
        r["pose_sequence"] = json.loads(r["pose_sequence"])
        routines.append(r)
    return routines
