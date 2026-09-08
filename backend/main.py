"""FastAPI アプリケーション本体。全APIエンドポイントを定義する。"""

import logging
import shutil
import uuid
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .audio_analyzer import analyze_audio
from .database import (
    delete_pose,
    delete_routine,
    get_poses,
    get_routine,
    get_routines,
    init_db,
    save_pose,
)
from .routine_generator import generate_routine

logger = logging.getLogger("bodybuilding_pose_app")

ROOT_DIR     = Path(__file__).parent.parent
UPLOAD_DIR   = ROOT_DIR / "uploads"
MODELS_DIR   = ROOT_DIR / "models"
FRONTEND_DIR = ROOT_DIR / "frontend" / "dist"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
MODELS_DIR.mkdir(parents=True, exist_ok=True)

ALLOWED_AUDIO = {".mp3", ".wav", ".flac", ".m4a", ".ogg", ".aac"}
ALLOWED_VIDEO = {".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v"}
ALLOWED_MODEL = {".glb", ".gltf"}
MAX_UPLOAD_BYTES = 512 * 1024 * 1024  # 512MB

app = FastAPI(title="Bodybuilding Pose App API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

init_db()


# ── ヘルパー ─────────────────────────────────────────────────────────

def _safe_upload_path(filename: str) -> Path:
    """uploads/ 配下のファイルパスを安全に解決する（パストラバーサル防止）。"""
    name = Path(filename).name
    if not name or name in {".", ".."}:
        raise HTTPException(400, "Invalid filename")
    path = (UPLOAD_DIR / name).resolve()
    if path.parent != UPLOAD_DIR.resolve():
        raise HTTPException(400, "Invalid filename")
    return path


def _save_upload(file: UploadFile, allowed: set[str], kind: str) -> Path:
    """アップロードされたファイルを検証して uploads/ に保存する。"""
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in allowed:
        raise HTTPException(400, f"Unsupported {kind} format: {suffix or '(none)'}")

    dest = UPLOAD_DIR / f"{uuid.uuid4()}{suffix}"
    written = 0
    try:
        with dest.open("wb") as out:
            while chunk := file.file.read(1024 * 1024):
                written += len(chunk)
                if written > MAX_UPLOAD_BYTES:
                    raise HTTPException(413, "File too large (max 512MB)")
                out.write(chunk)
    except HTTPException:
        dest.unlink(missing_ok=True)
        raise
    except Exception as exc:  # noqa: BLE001
        dest.unlink(missing_ok=True)
        logger.exception("upload failed")
        raise HTTPException(500, f"Failed to save file: {exc}") from exc

    if written == 0:
        dest.unlink(missing_ok=True)
        raise HTTPException(400, "Empty file")
    return dest


def _analyze_or_400(path: Path) -> dict:
    try:
        return analyze_audio(str(path))
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001
        logger.exception("audio analysis failed: %s", path)
        raise HTTPException(422, f"Audio analysis failed: {exc}") from exc


def _extract_pose_or_422(path: Path) -> dict:
    from .pose_extractor import extract_representative_pose

    try:
        pose_data = extract_representative_pose(str(path))
    except Exception as exc:  # noqa: BLE001
        logger.exception("pose extraction failed: %s", path)
        raise HTTPException(422, f"Pose extraction failed: {exc}") from exc
    if not pose_data:
        raise HTTPException(422, "No pose detected in video")
    return pose_data


# ── 基本 ─────────────────────────────────────────────────────────────

@app.get("/api/health")
def health():
    return {"status": "ok"}


@app.get("/api/models")
def list_models():
    """models/ ディレクトリ内の .glb / .gltf ファイル一覧を返す"""
    if not MODELS_DIR.exists():
        return {"files": []}
    files = sorted(
        f.name for f in MODELS_DIR.iterdir()
        if f.is_file() and f.suffix.lower() in {".glb", ".gltf"}
    )
    return {"files": files}


@app.post("/api/models/upload")
async def upload_model(file: UploadFile = File(...)):
    """3Dモデル(.glb/.gltf)を models/ に保存する（ブラウザ用。デスクトップ版は app.py の pick_model）"""
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in ALLOWED_MODEL:
        raise HTTPException(400, f"Unsupported model format: {suffix or '(none)'}")

    name = Path(file.filename or "").name
    dest = (MODELS_DIR / name).resolve()
    if dest.parent != MODELS_DIR.resolve():
        raise HTTPException(400, "Invalid filename")

    written = 0
    try:
        with dest.open("wb") as out:
            while chunk := file.file.read(1024 * 1024):
                written += len(chunk)
                if written > MAX_UPLOAD_BYTES:
                    raise HTTPException(413, "File too large (max 512MB)")
                out.write(chunk)
    except HTTPException:
        dest.unlink(missing_ok=True)
        raise

    if written == 0:
        dest.unlink(missing_ok=True)
        raise HTTPException(400, "Empty file")
    return {"file": dest.name}


# ── 音楽アップロード & 解析 ──────────────────────────────────────────

@app.post("/api/audio/upload")
async def upload_audio(file: UploadFile = File(...)):
    dest = _save_upload(file, ALLOWED_AUDIO, "audio")
    try:
        analysis = _analyze_or_400(dest)
    except HTTPException:
        dest.unlink(missing_ok=True)
        raise
    return {
        "file": dest.name,
        "original_name": file.filename,
        **analysis,
    }


@app.get("/api/audio/{filename}")
def serve_audio(filename: str):
    path = _safe_upload_path(filename)
    if not path.exists() or not path.is_file():
        raise HTTPException(404, "File not found")
    return FileResponse(str(path), filename=path.name)


# ── 動画アップロード & ポーズ抽出 ───────────────────────────────────

@app.post("/api/video/upload")
async def upload_video(
    file: UploadFile = File(...),
    pose_name: str = "unnamed",
    category: str = "general",
    energy_level: float = 0.5,
):
    dest = _save_upload(file, ALLOWED_VIDEO, "video")
    pose_data = _extract_pose_or_422(dest)

    pose_id = save_pose(pose_name, category, energy_level, pose_data["keypoints"])
    return {
        "pose_id": pose_id,
        "name": pose_name,
        "category": category,
        "energy_level": energy_level,
        "timestamp": pose_data.get("timestamp", 0.0),
        "keypoint_count": len(pose_data["keypoints"]),
    }


# ── ポーズライブラリ ─────────────────────────────────────────────────

@app.get("/api/poses")
def list_poses(category: str | None = None):
    return get_poses(category)


@app.delete("/api/poses/{pose_id}")
def remove_pose(pose_id: int):
    if not delete_pose(pose_id):
        raise HTTPException(404, "Pose not found")
    return {"deleted": pose_id}


# ── ルーティン ───────────────────────────────────────────────────────

@app.post("/api/routine/generate")
async def generate_routine_api(
    audio_file: str,
    routine_name: str = "My Routine",
    pose_duration: float | None = None,
    trim_start: float = 0.0,
    trim_end: float | None = None,
):
    path = _safe_upload_path(audio_file)
    if not path.exists():
        raise HTTPException(404, "Audio file not found. Upload first.")

    audio_info = _analyze_or_400(path)
    routine = generate_routine(
        audio_info, path.name, routine_name, pose_duration, trim_start, trim_end
    )
    if routine["pose_count"] == 0:
        raise HTTPException(422, "Could not generate a routine from this audio segment")
    return routine


@app.get("/api/routines")
def list_routines(limit: int = 50):
    return get_routines(limit)


@app.get("/api/routines/{routine_id}")
def read_routine(routine_id: int):
    routine = get_routine(routine_id)
    if routine is None:
        raise HTTPException(404, "Routine not found")
    return routine


@app.delete("/api/routines/{routine_id}")
def remove_routine(routine_id: int):
    if not delete_routine(routine_id):
        raise HTTPException(404, "Routine not found")
    return {"deleted": routine_id}


# ── ファイルパス直接解析（pywebviewがコピー済みのファイルを解析）────

@app.post("/api/audio/analyze")
async def analyze_audio_file(filename: str):
    """uploads/ に置かれたファイルを解析して返す（pywebview用）"""
    path = _safe_upload_path(filename)
    if not path.exists():
        raise HTTPException(404, "File not found")
    if path.suffix.lower() not in ALLOWED_AUDIO:
        raise HTTPException(400, "Unsupported audio format")
    analysis = _analyze_or_400(path)
    return {"file": path.name, "original_name": path.name, **analysis}


@app.post("/api/video/analyze")
async def analyze_video_file(
    filename: str,
    pose_name: str = "unnamed",
    category: str = "general",
    energy_level: float = 0.5,
):
    """uploads/ に置かれた動画ファイルを解析してポーズ登録（pywebview用）"""
    path = _safe_upload_path(filename)
    if not path.exists():
        raise HTTPException(404, "File not found")
    if path.suffix.lower() not in ALLOWED_VIDEO:
        raise HTTPException(400, "Unsupported video format")

    pose_data = _extract_pose_or_422(path)
    pose_id = save_pose(pose_name, category, energy_level, pose_data["keypoints"])
    return {
        "pose_id": pose_id,
        "name": pose_name,
        "category": category,
        "energy_level": energy_level,
        "timestamp": pose_data.get("timestamp", 0.0),
        "keypoint_count": len(pose_data["keypoints"]),
    }


# ── 静的ファイル配信（APIルートより後に定義）─────────────────────────
app.mount("/models", StaticFiles(directory=str(MODELS_DIR)), name="models")

# frontend/dist は `npm run build` 後にのみ存在する。
# 開発時（./dev.sh）はViteが配信するため、無い場合はマウントをスキップする。
if (FRONTEND_DIR / "index.html").exists():
    app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="frontend")
else:
    logger.warning(
        "frontend/dist が見つかりません。フロントエンドは配信されません "
        "（開発時は ./dev.sh、本番は ./start.sh を使用してください）"
    )

    @app.get("/")
    def frontend_not_built():
        return {
            "detail": "フロントエンドがビルドされていません。"
                      "`cd frontend && npm run build` を実行するか、開発時は ./dev.sh を使用してください。",
            "api_docs": "/docs",
        }
