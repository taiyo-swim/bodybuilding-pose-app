import os
import sys
import tempfile
from pathlib import Path

import pytest

ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(ROOT))


@pytest.fixture()
def temp_db(monkeypatch):
    """テストごとに独立したSQLite DBを使う。"""
    with tempfile.TemporaryDirectory() as tmp:
        db_path = Path(tmp) / "test.db"
        monkeypatch.setenv("POSE_DB_PATH", str(db_path))

        from backend import database
        monkeypatch.setattr(database, "DB_PATH", db_path)
        database.init_db()
        yield database


@pytest.fixture()
def audio_info():
    """analyze_audio() が返す形の解析結果（120BPM / 60秒）。"""
    bpm = 120.0
    duration = 60.0
    interval = 60.0 / bpm
    beats = [round(i * interval, 3) for i in range(int(duration / interval))]
    return {
        "duration": duration,
        "bpm": bpm,
        "beat_times": beats,
        "energy_curve": [round(0.2 + 0.05 * i, 3) for i in range(16)],
        "brightness": 0.3,
    }
