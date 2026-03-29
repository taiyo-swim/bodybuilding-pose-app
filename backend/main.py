import shutil
import uuid
from pathlib import Path

from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

from .database import init_db, get_poses, get_routines, save_pose
from .audio_analyzer import analyze_audio
from .routine_generator import generate_routine

UPLOAD_DIR  = Path(__file__).parent.parent / "uploads"
MODELS_DIR  = Path(__file__).parent.parent / "models"
FRONTEND_DIR = Path(__file__).parent.parent / "frontend" / "dist"
UPLOAD_DIR.mkdir(exist_ok=True)
MODELS_DIR.mkdir(exist_ok=True)

ALLOWED_AUDIO = {".mp3", ".wav", ".flac", ".m4a", ".ogg", ".aac"}
ALLOWED_VIDEO = {".mp4", ".mov", ".avi", ".mkv"}

app = FastAPI(title="Bodybuilding Pose App API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

init_db()


@app.get("/api/health")
def health():
    return {"status": "ok"}


@app.get("/api/models")
def list_models():
    """models/ ディレクトリ内の .glb / .gltf ファイル一覧を返す"""
    files = sorted(
        f.name for f in MODELS_DIR.iterdir()
        if f.suffix.lower() in {".glb", ".gltf"}
    )
    return {"files": files}


# ── 音楽アップロード & 解析 ──────────────────────────────────────────

@app.post("/api/audio/upload")
async def upload_audio(file: UploadFile = File(...)):
    suffix = Path(file.filename).suffix.lower()
    if suffix not in ALLOWED_AUDIO:
        raise HTTPException(400, f"Unsupported audio format: {suffix}")

    dest = UPLOAD_DIR / f"{uuid.uuid4()}{suffix}"
    with dest.open("wb") as f:
        shutil.copyfileobj(file.file, f)

    analysis = analyze_audio(str(dest))
    return {
        "file": dest.name,
        "original_name": file.filename,
        **analysis,
    }


@app.get("/api/audio/{filename}")
def serve_audio(filename: str):
    path = UPLOAD_DIR / filename
    if not path.exists():
        raise HTTPException(404, "File not found")
    return FileResponse(str(path))


# ── 動画アップロード & ポーズ抽出 ───────────────────────────────────

@app.post("/api/video/upload")
async def upload_video(
    file: UploadFile = File(...),
    pose_name: str = "unnamed",
    category: str = "general",
    energy_level: float = 0.5,
):
    suffix = Path(file.filename).suffix.lower()
    if suffix not in ALLOWED_VIDEO:
        raise HTTPException(400, f"Unsupported video format: {suffix}")

    dest = UPLOAD_DIR / f"{uuid.uuid4()}{suffix}"
    with dest.open("wb") as f:
        shutil.copyfileobj(file.file, f)

    from .pose_extractor import extract_representative_pose
    pose_data = extract_representative_pose(str(dest))
    if not pose_data:
        raise HTTPException(422, "No pose detected in video")

    pose_id = save_pose(pose_name, category, energy_level, pose_data["keypoints"])
    return {
        "pose_id": pose_id,
        "name": pose_name,
        "category": category,
        "energy_level": energy_level,
        "timestamp": pose_data["timestamp"],
        "keypoint_count": len(pose_data["keypoints"]),
    }


# ── ポーズライブラリ ─────────────────────────────────────────────────

@app.get("/api/poses")
def list_poses(category: str = None):
    return get_poses(category)


# ── ルーティン生成 ───────────────────────────────────────────────────

@app.post("/api/routine/generate")
async def generate_routine_api(
    audio_file: str,
    routine_name: str = "My Routine",
    pose_duration: float | None = None,
    trim_start: float = 0.0,
    trim_end: float | None = None,
):
    path = UPLOAD_DIR / audio_file
    if not path.exists():
        raise HTTPException(404, "Audio file not found. Upload first.")

    audio_info = analyze_audio(str(path))
    routine = generate_routine(audio_info, audio_file, routine_name, pose_duration, trim_start, trim_end)
    return routine


@app.get("/api/routines")
def list_routines():
    return get_routines()


# ── ファイルパス直接解析（pywebviewがコピー済みのファイルを解析）────
@app.post("/api/audio/analyze")
async def analyze_audio_file(filename: str):
    """uploads/ に置かれたファイルを解析して返す（pywebview用）"""
    path = UPLOAD_DIR / filename
    if not path.exists():
        raise HTTPException(404, "File not found")
    if path.suffix.lower() not in ALLOWED_AUDIO:
        raise HTTPException(400, "Unsupported audio format")
    analysis = analyze_audio(str(path))
    return {"file": filename, **analysis}


@app.post("/api/video/analyze")
async def analyze_video_file(
    filename: str,
    pose_name: str = "unnamed",
    category: str = "general",
    energy_level: float = 0.5,
):
    """uploads/ に置かれた動画ファイルを解析してポーズ登録（pywebview用）"""
    path = UPLOAD_DIR / filename
    if not path.exists():
        raise HTTPException(404, "File not found")
    if path.suffix.lower() not in ALLOWED_VIDEO:
        raise HTTPException(400, "Unsupported video format")

    from .pose_extractor import extract_representative_pose
    pose_data = extract_representative_pose(str(path))
    if not pose_data:
        raise HTTPException(422, "No pose detected in video")

    pose_id = save_pose(pose_name, category, energy_level, pose_data["keypoints"])
    return {
        "pose_id": pose_id,
        "name": pose_name,
        "category": category,
        "energy_level": energy_level,
        "keypoint_count": len(pose_data["keypoints"]),
    }


# ── 静的ファイル配信（APIルートより後に定義）─────────────────────────
app.mount("/models", StaticFiles(directory=str(MODELS_DIR)), name="models")
app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="frontend")
