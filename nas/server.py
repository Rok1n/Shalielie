"""Ephemeral authenticated Shalielie photo processing for fnOS Docker (amd64)."""
from __future__ import annotations

import hmac
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import zipfile
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from starlette.background import BackgroundTask

ROOT = Path(__file__).resolve().parent.parent
INDEX = ROOT / "nas" / "static" / "index.html"
PORTER = ROOT / "photographic_style_port.py"
WORKER = ROOT / "nas" / "live_worker.py"
TEMP_ROOT = Path(tempfile.gettempdir()) / "shalielie-nas"
TOKEN = os.environ.get("SHALIELIE_TOKEN", "")
MAX_TOTAL = int(os.environ.get("SHALIELIE_MAX_UPLOAD_MB", "320")) * 1024 * 1024
MAX_PHOTO = 160 * 1024 * 1024
MAX_VIDEO = MAX_TOTAL - MAX_PHOTO
TIMEOUT = int(os.environ.get("SHALIELIE_TIMEOUT", "600"))
GATE = threading.BoundedSemaphore(1)
CHUNK = 1024 * 1024

if not TOKEN or len(TOKEN) < 24:
    raise RuntimeError("Set SHALIELIE_TOKEN to a random secret of at least 24 characters.")
if MAX_TOTAL <= MAX_PHOTO or MAX_TOTAL > 1024 * 1024 * 1024:
    raise RuntimeError("SHALIELIE_MAX_UPLOAD_MB must be between 161 and 1024.")

app = FastAPI(title="Shalielie fnOS", docs_url=None, redoc_url=None, openapi_url=None)


@app.on_event("startup")
def prepare_temp():
    # No photo directory is mounted. Clear orphans after a container restart/crash.
    TEMP_ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    for entry in TEMP_ROOT.iterdir():
        if entry.is_dir() and entry.name.startswith("job-"):
            shutil.rmtree(entry, ignore_errors=True)


@app.middleware("http")
async def authenticate_and_limit(request: Request, call_next):
    if request.url.path.startswith("/api/"):
        header = request.headers.get("authorization", "")
        supplied = header[7:] if header.startswith("Bearer ") else ""
        if not hmac.compare_digest(supplied.encode(), TOKEN.encode()):
            return JSONResponse({"detail": "Invalid access token"}, status_code=401,
                                headers={"Cache-Control": "no-store"})
    if request.method == "POST" and request.url.path == "/api/patch":
        size = request.headers.get("content-length")
        if size is None or not size.isdecimal():
            return JSONResponse({"detail": "Content-Length required"}, status_code=411)
        if int(size) > MAX_TOTAL + 2 * 1024 * 1024:
            return JSONResponse({"detail": "Upload exceeds configured limit"}, status_code=413)
    response = await call_next(request)
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; script-src 'self'; style-src 'self'; "
        "connect-src 'self'; img-src 'self'; frame-ancestors 'none'; base-uri 'none'")
    return response


@app.get("/healthz")
def health():
    return {"ok": True}


@app.get("/")
def index():
    return FileResponse(INDEX, media_type="text/html")


@app.get("/api/status")
def status():
    return {"engine": "Shalielie v0.7.0", "host": "fnOS / Linux amd64",
            "live_photo": True, "max_upload_mb": MAX_TOTAL // (1024 * 1024),
            "retention": "temporary, removed after transfer"}


def kind_of(path: Path) -> str:
    with path.open("rb") as f:
        header = f.read(16)
    if len(header) >= 12 and header[4:8] == b"ftyp":
        if header[8:12] in {b"heic", b"heix", b"heim", b"heis", b"hevc",
                            b"hevx", b"mif1", b"msf1"}:
            return "heic"
        if header[8:12] == b"qt  ":
            return "mov"
    return "other"


def safe_stem(name: str | None) -> str:
    stem = Path(name or "photo").stem
    stem = re.sub(r"[^A-Za-z0-9_-]+", "_", stem).strip("_")
    return stem[:64] or "photo"


def copy_limited(source: UploadFile, target: Path, ceiling: int) -> int:
    written = 0
    with target.open("wb") as output:
        while part := source.file.read(CHUNK):
            written += len(part)
            if written > ceiling:
                raise HTTPException(413, "File is too large")
            output.write(part)
    if not written:
        raise HTTPException(422, "Empty upload")
    return written


def run_command(args: list[str], cwd: Path):
    try:
        result = subprocess.run(args, cwd=str(cwd), stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, errors="replace",
                                timeout=TIMEOUT, check=False,
                                env={**os.environ, "PYTHONIOENCODING": "utf-8"})
    except subprocess.TimeoutExpired:
        raise HTTPException(504, "Photo processing timed out") from None
    if result.returncode:
        detail = (result.stderr or result.stdout).strip().splitlines()
        reason = (detail[-1] if detail else "Photo processing failed")[:450]
        raise HTTPException(422, reason)


@app.post("/api/patch")
def patch(photo: UploadFile = File(...), video: UploadFile | None = File(None)):
    if not GATE.acquire(blocking=False):
        raise HTTPException(429, "Server is busy; finish the current download and retry.")
    tmp = None
    try:
        TEMP_ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
        tmp = tempfile.TemporaryDirectory(prefix="job-", dir=TEMP_ROOT)
        work = Path(tmp.name)
        src_photo, out_photo = work / "source.HEIC", work / "result.HEIC"
        photo_len = copy_limited(photo, src_photo, MAX_PHOTO)
        if kind_of(src_photo) != "heic":
            raise HTTPException(415, "An original HEIC file is required (not JPEG or PNG).")

        src_video, out_video = work / "source.MOV", work / "result.MOV"
        if video is not None:
            copy_limited(video, src_video, min(MAX_VIDEO, MAX_TOTAL - photo_len))
            if kind_of(src_video) != "mov":
                raise HTTPException(415, "Live Photo video must be an original QuickTime MOV.")

        run_command([sys.executable, str(PORTER), "patch",
                     str(src_photo), str(out_photo)], work)
        if not out_photo.is_file() or out_photo.stat().st_size == 0:
            raise HTTPException(422, "Photo porter produced no output.")

        stem = safe_stem(photo.filename) + "_Shalielie"
        if video is None:
            result_path = out_photo
            filename = stem + ".HEIC"
            mime = "image/heic"
        else:
            run_command([sys.executable, str(WORKER), str(src_photo), str(out_photo),
                         str(src_video), str(out_video)], work)
            if not out_video.is_file() or out_video.stat().st_size == 0:
                raise HTTPException(422, "Live Photo porter produced no video.")
            result_path = work / "result.zip"
            with zipfile.ZipFile(result_path, "w", compression=zipfile.ZIP_STORED,
                                 allowZip64=True) as archive:
                archive.write(out_photo, stem + ".HEIC")
                archive.write(out_video, stem + ".MOV")
            filename = stem + ".zip"
            mime = "application/zip"

        def cleanup():
            tmp.cleanup()
            GATE.release()

        return FileResponse(result_path, filename=filename, media_type=mime,
                            background=BackgroundTask(cleanup),
                            headers={"Cache-Control": "no-store"})
    except Exception:
        if tmp is not None:
            tmp.cleanup()
        GATE.release()
        raise
    finally:
        photo.file.close()
        if video is not None:
            video.file.close()
