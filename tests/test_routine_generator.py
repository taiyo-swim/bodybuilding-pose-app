import pytest

from backend import routine_generator as rg


def test_generates_sequence_covering_whole_track(temp_db, audio_info):
    routine = rg.generate_routine(audio_info, "song.mp3", seed=1, persist=False)

    assert routine["pose_count"] > 0
    assert routine["duration"] == pytest.approx(audio_info["duration"])
    assert routine["trim_start"] == 0.0

    seq = routine["pose_sequence"]
    assert seq[0]["time"] == 0.0
    # 時刻は単調増加し、ホールド時間の合計が区間全体を覆う
    assert all(b["time"] > a["time"] for a, b in zip(seq, seq[1:]))
    assert sum(e["duration"] for e in seq) == pytest.approx(routine["duration"], abs=0.05)


def test_hold_durations_within_bounds(temp_db, audio_info):
    seq = rg.generate_routine(audio_info, "song.mp3", seed=2, persist=False)["pose_sequence"]
    for entry in seq:
        assert rg.MIN_HOLD <= entry["duration"] <= rg.MAX_HOLD + 0.01


def test_no_immediate_pose_repetition(temp_db, audio_info):
    seq = rg.generate_routine(audio_info, "song.mp3", seed=3, persist=False)["pose_sequence"]
    names = [e["pose_name"] for e in seq]
    assert all(a != b for a, b in zip(names, names[1:]))


def test_trim_shifts_times_to_zero_and_records_offset(temp_db, audio_info):
    routine = rg.generate_routine(
        audio_info, "song.mp3", trim_start=20.0, trim_end=40.0, seed=4, persist=False
    )

    assert routine["trim_start"] == 20.0
    assert routine["duration"] == pytest.approx(20.0)
    assert routine["pose_sequence"][0]["time"] == 0.0
    assert all(e["time"] < 20.0 for e in routine["pose_sequence"])
    assert all(0 <= t < 20.0 for t in routine["beat_times"])


def test_trimmed_segment_uses_energy_of_that_segment(temp_db):
    """トリム区間のエネルギーは、曲全体ではなくその区間の値が使われること。"""
    info = {
        "duration": 100.0,
        "bpm": 120.0,
        "beat_times": [round(i * 0.5, 3) for i in range(200)],
        # 前半は静か、後半は盛り上がる曲
        "energy_curve": [0.0] * 8 + [1.0] * 8,
        "brightness": 0.3,
    }
    quiet = rg.generate_routine(info, "s.mp3", trim_start=0.0, trim_end=20.0, seed=5, persist=False)
    loud = rg.generate_routine(info, "s.mp3", trim_start=80.0, trim_end=100.0, seed=5, persist=False)

    assert max(e["energy"] for e in quiet["pose_sequence"]) < 0.3
    assert min(e["energy"] for e in loud["pose_sequence"]) > 0.7


def test_falls_back_to_even_spacing_without_beats(temp_db):
    """ビート検出に失敗した曲でもルーティンが生成できること。"""
    info = {"duration": 40.0, "bpm": 120.0, "beat_times": [], "energy_curve": [0.5] * 16}
    routine = rg.generate_routine(info, "s.mp3", seed=6, persist=False)

    assert routine["pose_count"] >= 5
    assert routine["pose_sequence"][0]["time"] == 0.0


def test_bpm_controls_switch_interval(temp_db):
    def make(bpm):
        interval = 60.0 / bpm
        return {
            "duration": 120.0,
            "bpm": bpm,
            "beat_times": [round(i * interval, 3) for i in range(int(120 / interval))],
            "energy_curve": [0.5] * 16,
        }

    slow = rg.generate_routine(make(90), "s.mp3", seed=7, persist=False)
    fast = rg.generate_routine(make(160), "s.mp3", seed=7, persist=False)

    # 速い曲ほど1ポーズあたりのビート数が増えるので、ポーズ数は減る
    assert slow["pose_count"] > fast["pose_count"]


def test_invalid_trim_range_falls_back_to_full_track(temp_db, audio_info):
    routine = rg.generate_routine(
        audio_info, "song.mp3", trim_start=50.0, trim_end=10.0, seed=8, persist=False
    )
    assert routine["trim_start"] == 0.0
    assert routine["duration"] == pytest.approx(audio_info["duration"])


def test_uses_db_poses_when_available(temp_db, audio_info):
    temp_db.save_pose("db_pose_low", "competition", 0.1, {"nose": {"x": 0, "y": 0, "z": 0}})
    temp_db.save_pose("db_pose_high", "competition", 0.9, {"nose": {"x": 1, "y": 1, "z": 0}})

    seq = rg.generate_routine(audio_info, "song.mp3", seed=9, persist=False)["pose_sequence"]

    assert {e["pose_name"] for e in seq} <= {"db_pose_low", "db_pose_high"}
    assert all(e["pose_id"] is not None for e in seq)
    assert all(e["keypoints"] is not None for e in seq)


def test_default_poses_used_when_db_empty(temp_db, audio_info):
    seq = rg.generate_routine(audio_info, "song.mp3", seed=10, persist=False)["pose_sequence"]
    builtin = {p["name"] for p in rg.DEFAULT_POSES}

    assert {e["pose_name"] for e in seq} <= builtin
    assert all(e["pose_id"] is None for e in seq)


def test_persist_saves_routine_to_db(temp_db, audio_info):
    routine = rg.generate_routine(audio_info, "song.mp3", name="保存テスト", seed=11)

    assert routine["id"] is not None
    saved = temp_db.get_routine(routine["id"])
    assert saved["name"] == "保存テスト"
    assert saved["pose_count"] == routine["pose_count"]
    assert saved["beat_times"] == routine["beat_times"]


def test_short_track_still_produces_one_pose(temp_db):
    info = {"duration": 3.0, "bpm": 120.0, "beat_times": [0.0, 0.5, 1.0, 1.5, 2.0, 2.5],
            "energy_curve": [0.5] * 16}
    routine = rg.generate_routine(info, "s.mp3", seed=12, persist=False)
    assert routine["pose_count"] == 1
    assert routine["pose_sequence"][0]["duration"] == pytest.approx(3.0)
