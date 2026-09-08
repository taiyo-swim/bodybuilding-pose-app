def test_pose_crud(temp_db):
    keypoints = {"nose": {"x": 0.5, "y": 0.2, "z": 0.0, "visibility": 0.99}}
    pose_id = temp_db.save_pose("front_double_bicep", "competition", 0.8, keypoints)

    poses = temp_db.get_poses()
    assert len(poses) == 1
    assert poses[0]["name"] == "front_double_bicep"
    assert poses[0]["keypoints"] == keypoints

    assert temp_db.get_pose(pose_id)["category"] == "competition"
    assert temp_db.get_pose(pose_id + 999) is None

    assert temp_db.delete_pose(pose_id) is True
    assert temp_db.delete_pose(pose_id) is False
    assert temp_db.get_poses() == []


def test_get_poses_filters_by_category(temp_db):
    temp_db.save_pose("a", "competition", 0.8, {})
    temp_db.save_pose("b", "transition", 0.2, {})

    assert [p["name"] for p in temp_db.get_poses("competition")] == ["a"]
    assert [p["name"] for p in temp_db.get_poses("transition")] == ["b"]
    assert len(temp_db.get_poses()) == 2


def test_delete_poses_by_name(temp_db):
    temp_db.save_pose("side_chest", "competition", 0.5, {})
    temp_db.save_pose("side_chest", "competition", 0.5, {})
    temp_db.save_pose("vacuum", "competition", 0.7, {})

    assert temp_db.delete_poses_by_name("side_chest") == 2
    assert [p["name"] for p in temp_db.get_poses()] == ["vacuum"]


def test_routine_roundtrip(temp_db):
    """保存したルーティンが再生に必要な情報を保ったまま読み戻せること。"""
    sequence = [{"time": 0.0, "duration": 4.0, "pose_name": "most_muscular"}]
    routine_id = temp_db.save_routine(
        "My Routine", "song.mp3", 128.0, 32.0, sequence,
        trim_start=12.5, beat_times=[0.0, 0.5, 1.0],
    )

    routine = temp_db.get_routine(routine_id)
    assert routine["name"] == "My Routine"
    assert routine["trim_start"] == 12.5
    assert routine["beat_times"] == [0.0, 0.5, 1.0]
    assert routine["pose_sequence"] == sequence
    assert routine["pose_count"] == 1

    assert len(temp_db.get_routines()) == 1
    assert temp_db.delete_routine(routine_id) is True
    assert temp_db.get_routines() == []


def test_init_db_migrates_legacy_routines_table(temp_db, monkeypatch):
    """trim_start / beat_times 列が無い旧DBでも init_db でマイグレーションされること。"""
    conn = temp_db.get_connection()
    conn.executescript("""
        DROP TABLE routines;
        CREATE TABLE routines (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            audio_file TEXT,
            bpm REAL,
            duration REAL,
            pose_sequence TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        INSERT INTO routines (name, audio_file, bpm, duration, pose_sequence)
        VALUES ('legacy', 'old.mp3', 100, 30, '[]');
    """)
    conn.commit()
    conn.close()

    temp_db.init_db()

    routine = temp_db.get_routines()[0]
    assert routine["name"] == "legacy"
    assert routine["trim_start"] == 0
    assert routine["beat_times"] == []
