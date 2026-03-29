"""
app.py — pywebview エントリポイント
FastAPIをバックグラウンドスレッドで起動し、WebViewウィンドウを開く。
ファイル選択はpywebviewのネイティブダイアログAPIで行う。
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
BACKEND_PORT = 8000

ROOT_DIR    = Path(__file__).parent
UPLOAD_DIR  = ROOT_DIR / "uploads"
MODELS_DIR  = ROOT_DIR / "models"
UPLOAD_DIR.mkdir(exist_ok=True)
MODELS_DIR.mkdir(exist_ok=True)

# pywebviewウィンドウへの参照（Api クラスから参照するため）
_window = None


class Api:
    """JS から window.pywebview.api.xxx() で呼び出せる Python 関数群"""

    def pick_audio(self):
        """音楽ファイルを選択 → uploads/ にコピー → ファイル名を返す"""
        try:
            result = _window.create_file_dialog(
                webview.OPEN_DIALOG,
                file_types=('Audio Files (*.mp3 *.wav *.flac *.m4a *.ogg *.aac)',),
            )
            if not result:
                return None
            src = Path(result[0])
            dest = UPLOAD_DIR / f"{uuid.uuid4()}{src.suffix.lower()}"
            shutil.copy2(src, dest)
            return dest.name
        except Exception as e:
            return {"error": str(e)}

    def pick_video(self):
        """動画ファイルを選択 → uploads/ にコピー → ファイル名を返す"""
        try:
            result = _window.create_file_dialog(
                webview.OPEN_DIALOG,
                file_types=('Video Files (*.mp4 *.mov *.avi *.mkv)',),
            )
            if not result:
                return None
            src = Path(result[0])
            dest = UPLOAD_DIR / f"{uuid.uuid4()}{src.suffix.lower()}"
            shutil.copy2(src, dest)
            return dest.name
        except Exception as e:
            return {"error": str(e)}

    def pick_model(self):
        """GLBモデルを選択 → models/ にコピー → ファイル名を返す"""
        try:
            result = _window.create_file_dialog(
                webview.OPEN_DIALOG,
                file_types=('3D Model Files (*.glb *.gltf)',),
            )
            if not result:
                return None
            src = Path(result[0])
            dest = MODELS_DIR / src.name
            shutil.copy2(src, dest)
            return src.name
        except Exception as e:
            return {"error": str(e)}


def start_backend():
    sys.path.insert(0, str(ROOT_DIR))
    from backend.main import app
    uvicorn.run(app, host=BACKEND_HOST, port=BACKEND_PORT, log_level="warning")


def wait_for_backend(timeout: float = 10.0):
    import urllib.request
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            urllib.request.urlopen(f"http://{BACKEND_HOST}:{BACKEND_PORT}/api/health")
            return True
        except Exception:
            time.sleep(0.2)
    return False


def free_port(port: int):
    result = subprocess.run(["lsof", "-ti", f":{port}"], capture_output=True, text=True)
    for pid in result.stdout.strip().split():
        try:
            os.kill(int(pid), signal.SIGKILL)
            print(f"ポート{port}を解放 (PID {pid})")
        except Exception:
            pass


if __name__ == "__main__":
    free_port(BACKEND_PORT)

    t = threading.Thread(target=start_backend, daemon=True)
    t.start()

    print("バックエンド起動待機中...")
    if not wait_for_backend():
        print("ERROR: バックエンドの起動に失敗しました")
        sys.exit(1)
    print("バックエンド起動完了")

    api = Api()
    _window = webview.create_window(
        title="Bodybuilding Pose App",
        url=f"http://{BACKEND_HOST}:{BACKEND_PORT}/",
        width=1280,
        height=800,
        min_size=(900, 600),
        resizable=True,
        js_api=api,
    )
    webview.start(debug=True)
