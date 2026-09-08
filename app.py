"""
app.py — pywebview エントリポイント

FastAPIをバックグラウンドスレッドで起動し、WebViewウィンドウを開く。
ファイル選択はpywebviewのネイティブダイアログAPIで行い、
選択されたファイルを uploads/ (モデルは models/) にコピーしてから
フロントエンドに解析させる。
"""

import os
import shutil
import signal
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path

import uvicorn
import webview

BACKEND_HOST = "127.0.0.1"
BACKEND_PORT = int(os.environ.get("POSE_APP_PORT", "8000"))

ROOT_DIR     = Path(__file__).parent
UPLOAD_DIR   = ROOT_DIR / "uploads"
MODELS_DIR   = ROOT_DIR / "models"
FRONTEND_DIR = ROOT_DIR / "frontend" / "dist"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
MODELS_DIR.mkdir(parents=True, exist_ok=True)

AUDIO_TYPES = ('Audio Files (*.mp3;*.wav;*.flac;*.m4a;*.ogg;*.aac)',)
VIDEO_TYPES = ('Video Files (*.mp4;*.mov;*.avi;*.mkv;*.webm;*.m4v)',)
MODEL_TYPES = ('3D Model Files (*.glb;*.gltf)',)

# pywebviewウィンドウへの参照（Api クラスから参照するため）
_window = None


class Api:
    """JS から window.pywebview.api.xxx() で呼び出せる Python 関数群。

    いずれもファイルを選択してアプリ管理下のフォルダにコピーし、
    そのファイル名を返す。キャンセル時は None、失敗時は {"error": ...} を返す。
    """

    def _pick(self, file_types: tuple[str, ...], dest_dir: Path, keep_name: bool) -> str | dict | None:
        if _window is None:
            return {"error": "ウィンドウが初期化されていません"}
        try:
            result = _window.create_file_dialog(webview.OPEN_DIALOG, file_types=file_types)
            if not result:
                return None
            src = Path(result[0])
            if not src.is_file():
                return {"error": f"ファイルが見つかりません: {src}"}
            # 音楽・動画は一時データなので衝突しないUUID名、モデルは元のファイル名を保つ
            dest = dest_dir / (src.name if keep_name else f"{uuid.uuid4()}{src.suffix.lower()}")
            dest_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)
            return dest.name
        except Exception as e:  # noqa: BLE001 — JS 側にそのままエラーを渡す
            return {"error": str(e)}

    def pick_audio(self):
        """音楽ファイルを選択 → uploads/ にコピー → ファイル名を返す"""
        return self._pick(AUDIO_TYPES, UPLOAD_DIR, keep_name=False)

    def pick_video(self):
        """動画ファイルを選択 → uploads/ にコピー → ファイル名を返す"""
        return self._pick(VIDEO_TYPES, UPLOAD_DIR, keep_name=False)

    def pick_model(self):
        """GLBモデルを選択 → models/ にコピー → ファイル名を返す"""
        return self._pick(MODEL_TYPES, MODELS_DIR, keep_name=True)


def start_backend():
    sys.path.insert(0, str(ROOT_DIR))
    from backend.main import app
    uvicorn.run(app, host=BACKEND_HOST, port=BACKEND_PORT, log_level="warning")


def wait_for_backend(timeout: float = 30.0) -> bool:
    import urllib.request

    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(f"http://{BACKEND_HOST}:{BACKEND_PORT}/api/health", timeout=1):
                return True
        except Exception:
            time.sleep(0.2)
    return False


def free_port(port: int) -> None:
    """既存プロセスがポートを掴んでいれば解放する（lsof が無い環境ではスキップ）。"""
    if not shutil.which("lsof"):
        return
    result = subprocess.run(["lsof", "-ti", f":{port}"], capture_output=True, text=True)
    for pid in result.stdout.strip().split():
        try:
            os.kill(int(pid), signal.SIGKILL)
            print(f"ポート{port}を解放 (PID {pid})")
        except Exception:
            pass


def build_frontend() -> bool:
    """frontend/dist が無ければ npm run build を実行する。"""
    if (FRONTEND_DIR / "index.html").exists():
        return True

    npm = shutil.which("npm")
    if not npm:
        print("ERROR: frontend/dist がなく、npm も見つかりません。")
        print("       Node.js をインストールして `cd frontend && npm install && npm run build` を実行してください。")
        return False

    frontend_dir = ROOT_DIR / "frontend"
    print("フロントエンドをビルド中... (初回のみ数分かかります)")
    if not (frontend_dir / "node_modules").exists():
        subprocess.run([npm, "install"], cwd=frontend_dir, check=True)
    subprocess.run([npm, "run", "build"], cwd=frontend_dir, check=True)
    return (FRONTEND_DIR / "index.html").exists()


def main() -> None:
    global _window

    if not build_frontend():
        sys.exit(1)

    free_port(BACKEND_PORT)

    threading.Thread(target=start_backend, daemon=True).start()

    print("バックエンド起動待機中...")
    if not wait_for_backend():
        print("ERROR: バックエンドの起動に失敗しました")
        sys.exit(1)
    print("バックエンド起動完了")

    _window = webview.create_window(
        title="Bodybuilding Pose App",
        url=f"http://{BACKEND_HOST}:{BACKEND_PORT}/",
        width=1280,
        height=800,
        min_size=(900, 600),
        resizable=True,
        js_api=Api(),
    )
    # POSE_APP_DEBUG=1 で開発者ツールを有効にする
    webview.start(debug=os.environ.get("POSE_APP_DEBUG") == "1")


if __name__ == "__main__":
    main()
