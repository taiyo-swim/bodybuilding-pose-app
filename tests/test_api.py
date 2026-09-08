import io

import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def client(temp_db, tmp_path, monkeypatch):
    from backend import main

    upload_dir = tmp_path / "uploads"
    models_dir = tmp_path / "models"
    upload_dir.mkdir()
    models_dir.mkdir()
    monkeypatch.setattr(main, "UPLOAD_DIR", upload_dir)
    monkeypatch.setattr(main, "MODELS_DIR", models_dir)

    with TestClient(main.app) as c:
        c.upload_dir = upload_dir
        c.models_dir = models_dir
        yield c


def test_health(client):
    assert client.get("/api/health").json() == {"status": "ok"}


def test_list_models_only_returns_3d_files(client):
    (client.models_dir / "Character.glb").write_bytes(b"glb")
    (client.models_dir / "Other.gltf").write_bytes(b"gltf")
    (client.models_dir / "notes.txt").write_text("ignore me")

    assert client.get("/api/models").json() == {"files": ["Character.glb", "Other.gltf"]}


def test_upload_audio_rejects_unsupported_format(client):
    res = client.post("/api/audio/upload", files={"file": ("song.txt", io.BytesIO(b"x"), "text/plain")})
    assert res.status_code == 400
    assert "Unsupported audio format" in res.text


def test_upload_audio_cleans_up_when_analysis_fails(client):
    """解析に失敗したアップロードは422を返し、ファイルを残さないこと。"""
    res = client.post("/api/audio/upload", files={"file": ("song.mp3", io.BytesIO(b"not audio"), "audio/mpeg")})

    assert res.status_code == 422
    assert list(client.upload_dir.iterdir()) == []


def test_upload_rejects_empty_file(client):
    res = client.post("/api/audio/upload", files={"file": ("song.mp3", io.BytesIO(b""), "audio/mpeg")})
    assert res.status_code == 400
    assert list(client.upload_dir.iterdir()) == []


def test_serve_audio_returns_file(client):
    (client.upload_dir / "track.mp3").write_bytes(b"audio-bytes")
    res = client.get("/api/audio/track.mp3")

    assert res.status_code == 200
    assert res.content == b"audio-bytes"


def test_serve_audio_missing_file(client):
    assert client.get("/api/audio/nope.mp3").status_code == 404


@pytest.mark.parametrize("name", ["..%2F..%2Fetc%2Fpasswd", "..%5C..%5Cwindows", "%2Fetc%2Fpasswd"])
def test_serve_audio_rejects_path_traversal(client, name):
    """uploads/ の外にあるファイルを読み出せないこと。"""
    res = client.get(f"/api/audio/{name}")
    assert res.status_code in (400, 404)
    assert b"root:" not in res.content


def test_poses_endpoints(client, temp_db):
    pose_id = temp_db.save_pose("front_double_bicep", "competition", 0.8, {"nose": {"x": 0, "y": 0, "z": 0}})

    poses = client.get("/api/poses").json()
    assert [p["name"] for p in poses] == ["front_double_bicep"]

    assert client.get("/api/poses", params={"category": "transition"}).json() == []
    assert client.delete(f"/api/poses/{pose_id}").json() == {"deleted": pose_id}
    assert client.delete(f"/api/poses/{pose_id}").status_code == 404
    assert client.get("/api/poses").json() == []


def test_generate_routine_requires_uploaded_file(client):
    res = client.post("/api/routine/generate", params={"audio_file": "missing.mp3"})
    assert res.status_code == 404


def test_generate_routine_end_to_end(client, monkeypatch, audio_info):
    from backend import main

    (client.upload_dir / "track.mp3").write_bytes(b"audio")
    monkeypatch.setattr(main, "analyze_audio", lambda path: audio_info)

    res = client.post("/api/routine/generate", params={
        "audio_file": "track.mp3", "routine_name": "テスト", "trim_start": 10, "trim_end": 40,
    })
    assert res.status_code == 200
    routine = res.json()
    assert routine["name"] == "テスト"
    assert routine["trim_start"] == 10.0
    assert routine["duration"] == pytest.approx(30.0)
    assert routine["pose_count"] > 0

    # 生成したルーティンは保存され、一覧・個別取得・削除ができる
    listed = client.get("/api/routines").json()
    assert [r["id"] for r in listed] == [routine["id"]]

    fetched = client.get(f"/api/routines/{routine['id']}").json()
    assert fetched["trim_start"] == 10.0
    assert fetched["beat_times"] == routine["beat_times"]

    assert client.delete(f"/api/routines/{routine['id']}").status_code == 200
    assert client.get(f"/api/routines/{routine['id']}").status_code == 404


def test_analyze_audio_endpoint_for_pywebview(client, monkeypatch, audio_info):
    from backend import main

    (client.upload_dir / "picked.wav").write_bytes(b"audio")
    monkeypatch.setattr(main, "analyze_audio", lambda path: audio_info)

    res = client.post("/api/audio/analyze", params={"filename": "picked.wav"})
    assert res.status_code == 200
    assert res.json()["file"] == "picked.wav"
    assert res.json()["bpm"] == audio_info["bpm"]


def test_analyze_audio_endpoint_validates_extension(client):
    (client.upload_dir / "picked.txt").write_bytes(b"x")
    res = client.post("/api/audio/analyze", params={"filename": "picked.txt"})
    assert res.status_code == 400


def test_analyze_video_endpoint_for_pywebview(client, monkeypatch, temp_db):
    from backend import main

    (client.upload_dir / "pose.mp4").write_bytes(b"video")
    monkeypatch.setattr(
        main, "_extract_pose_or_422",
        lambda path: {"timestamp": 1.5, "keypoints": {"nose": {"x": 0.5, "y": 0.5, "z": 0.0}}},
    )

    res = client.post("/api/video/analyze", params={
        "filename": "pose.mp4", "pose_name": "most_muscular",
        "category": "competition", "energy_level": 0.9,
    })
    assert res.status_code == 200
    assert res.json()["keypoint_count"] == 1
    assert [p["name"] for p in temp_db.get_poses()] == ["most_muscular"]


def test_upload_model(client):
    import io

    res = client.post("/api/models/upload", files={"file": ("Hero.glb", io.BytesIO(b"glb-bytes"), "model/gltf-binary")})
    assert res.status_code == 200
    assert res.json() == {"file": "Hero.glb"}
    assert (client.models_dir / "Hero.glb").read_bytes() == b"glb-bytes"
    assert client.get("/api/models").json() == {"files": ["Hero.glb"]}


def test_upload_model_rejects_other_formats(client):
    import io

    res = client.post("/api/models/upload", files={"file": ("hero.fbx", io.BytesIO(b"x"), "application/octet-stream")})
    assert res.status_code == 400
    assert list(client.models_dir.iterdir()) == []


def test_upload_model_strips_directory_from_name(client):
    import io

    res = client.post("/api/models/upload", files={"file": ("../../evil.glb", io.BytesIO(b"x"), "model/gltf-binary")})
    assert res.status_code == 200
    assert res.json() == {"file": "evil.glb"}
    assert [f.name for f in client.models_dir.iterdir()] == ["evil.glb"]
