"""
MiniFlow Engine — FastAPI backend

HTTP:      POST http://localhost:8765/invoke/:command
           GET  http://localhost:8765/health
           GET  http://localhost:8765/callback        ← OAuth token receiver
WebSocket: ws://localhost:8765/ws
"""

from __future__ import annotations

import asyncio
import base64
import json
import logging
import os
import re
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse

import config
import agent
import audio
import dictation
import history
import dictionary
import shortcuts
import styles

import pathlib
_log_path = pathlib.Path.home() / "miniflow" / "miniflow.log"
_log_path.parent.mkdir(exist_ok=True)
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s %(name)s] %(message)s",
    datefmt="%H:%M:%S",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(str(_log_path), encoding="utf-8"),
    ],
)
log = logging.getLogger("main")

# ── WebSocket connection manager ──

class ConnectionManager:
    def __init__(self):
        self.connections: list[WebSocket] = []

    async def connect(self, ws: WebSocket):
        await ws.accept()
        self.connections.append(ws)

    def disconnect(self, ws: WebSocket):
        self.connections.remove(ws)

    async def broadcast(self, event: str, payload: Any):
        msg = json.dumps({"event": event, "payload": payload})
        for ws in list(self.connections):
            try:
                await ws.send_text(msg)
            except Exception:
                self.connections.remove(ws)

manager = ConnectionManager()

# ── App lifespan ──

@asynccontextmanager
async def lifespan(app: FastAPI):
    log.info("MiniFlow engine starting on http://localhost:8765")
    dictation.set_event_broadcaster(manager.broadcast)
    agent.set_event_broadcaster(manager.broadcast)
    yield
    log.info("MiniFlow engine shutting down")

app = FastAPI(lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost", "http://127.0.0.1"],
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Health check ──

@app.get("/health")
async def health():
    return {"status": "ok"}

# ── OAuth callback (legacy, unused) ──

_SUCCESS_HTML = """
<!DOCTYPE html>
<html>
<head><title>MiniFlow — Connected</title>
<style>
  body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
       display:flex;justify-content:center;align-items:center;
       height:100vh;margin:0;background:#0f1923;color:#fff}
  .box{text-align:center}
  h2{font-size:1.4rem;font-weight:600;margin-bottom:.5rem}
  p{color:#8899aa;font-size:.9rem}
</style></head>
<body><div class="box">
  <h2>✓ Connected successfully</h2>
  <p>You can close this window and return to MiniFlow.</p>
</div></body></html>
"""

_FAIL_HTML = """
<!DOCTYPE html>
<html>
<head><title>MiniFlow — Error</title>
<style>
  body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
       display:flex;justify-content:center;align-items:center;
       height:100vh;margin:0;background:#0f1923;color:#fff}
  .box{text-align:center}
  h2{font-size:1.4rem;font-weight:600;margin-bottom:.5rem;color:#ff6b6b}
  p{color:#8899aa;font-size:.9rem}
</style></head>
<body><div class="box">
  <h2>Connection failed</h2>
  <p>{error}</p>
</div></body></html>
"""

@app.get("/callback")
async def oauth_callback(data: str = "", state: str = ""):
    if not data:
        return HTMLResponse(_FAIL_HTML.format(error="No token data received."), status_code=400)
    try:
        # The Vercel proxy encodes the payload as base64url JSON
        # (or AES-256-GCM if ENCRYPTION_KEY is set on Vercel — we support plain only)
        padding = 4 - len(data) % 4
        padded = data + ("=" * (padding % 4))
        raw = base64.urlsafe_b64decode(padded).decode("utf-8")
        payload = json.loads(raw)
        provider = payload.get("provider")
        if not provider:
            raise ValueError("Missing provider in token payload")
        oauth.save_token(provider, payload)
        log.info(f"OAuth token saved for: {provider}")
        await manager.broadcast("oauth-connected", {"provider": provider})
        return HTMLResponse(_SUCCESS_HTML)
    except Exception as e:
        log.error(f"OAuth callback error: {e}")
        return HTMLResponse(_FAIL_HTML.format(error=str(e)), status_code=400)

# ── WebSocket endpoint ──

@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await manager.connect(ws)
    try:
        while True:
            await ws.receive_text()  # keep connection alive
    except WebSocketDisconnect:
        manager.disconnect(ws)

# ── Invoke dispatcher ──

async def _transcribe_audio(b: dict):
    import base64
    bundle_id = b.get("bundleID")
    if bundle_id:
        agent.set_target_app(bundle_id)
    wav_bytes = base64.b64decode(b["audio"])
    transcript = await audio.transcribe(wav_bytes)
    settings = config.get_advanced_settings()
    if settings.get("filler_removal"):
        transcript = _remove_filler_words(transcript, config.get_all_filler_words())
    transcript = dictionary.apply(transcript)
    transcript = shortcuts.apply(transcript)
    return {"transcript": transcript}


def _remove_filler_words(text: str, words: list[str]) -> str:
    if not text or not words:
        return text
    candidates = [w.strip().lower() for w in words if isinstance(w, str) and w.strip()]
    if not candidates:
        return text
    # Longer phrases first so we don't partially match them.
    candidates = sorted(set(candidates), key=len, reverse=True)
    pattern = r"\\b(?:%s)\\b" % "|".join(re.escape(w) for w in candidates)
    cleaned = re.sub(pattern, "", text, flags=re.IGNORECASE)
    cleaned = re.sub(r"\s+([,.;:!?])", r"\1", cleaned)
    cleaned = re.sub(r"\s{2,}", " ", cleaned).strip()
    cleaned = re.sub(r"^\s*,\s*", "", cleaned)
    cleaned = re.sub(r",\s*,+", ",", cleaned)
    cleaned = re.sub(r",\s*(?=[.?!]|$)", "", cleaned)
    cleaned = re.sub(r",\s*(\S)", r", \1", cleaned)
    return cleaned


@app.post("/invoke/{command}")
async def invoke(command: str, body: dict = {}):
    handlers = {
        # Audio
        "transcribe_audio":      lambda b: _transcribe_audio(b),
        # Agent
        "execute_command":       lambda b: agent.execute_command(b["command"]),
        # Config
        "save_api_key":          lambda b: config.save_api_key(b["service"], b["key"]),
        "get_api_key":           lambda b: config.get_api_key(b["service"]),
        "has_api_keys":          lambda b: config.has_api_keys(),
        "save_language":         lambda b: config.save_language(b["language"]),
        "get_language":          lambda b: config.get_language(),
        "get_advanced_settings": lambda b: config.get_advanced_settings(),
        "save_advanced_setting": lambda b: config.save_advanced_setting(b["key"], b["value"]),
        "save_user_name":        lambda b: config.save_user_name(b["name"]),
        "get_user_name":         lambda b: config.get_user_name(),
        # Dictation
        "start_dictation":       lambda b: dictation.start_dictation(),
        "stop_dictation":        lambda b: dictation.stop_dictation(),
        "get_dictation_status":  lambda b: dictation.get_dictation_status(),
        "check_accessibility":   lambda b: dictation.check_accessibility(),
        "open_accessibility_settings": lambda b: dictation.open_accessibility_settings(),
        # History
        "get_history":           lambda b: history.get_history(),
        "clear_history":         lambda b: history.clear_history(),
        # Dictionary
        "add_dictionary_word":   lambda b: dictionary.add_word(b["from"], b["to"]),
        "remove_dictionary_word": lambda b: dictionary.remove_word(b["from"]),
        "get_dictionary":        lambda b: dictionary.get_dictionary(),
        "import_dictionary":     lambda b: dictionary.import_dictionary(b["entries"]),
        # Shortcuts
        "add_shortcut":          lambda b: shortcuts.add_shortcut(b["trigger"], b["expansion"]),
        "remove_shortcut":       lambda b: shortcuts.remove_shortcut(b["trigger"]),
        "get_shortcuts":         lambda b: shortcuts.get_shortcuts(),
        # Styles
        "get_style_preferences": lambda b: styles.get_style_preferences(),
        "save_style_preference": lambda b: styles.save_style_preference(b["category"], b["tone"]),
        # App
        "open_settings":         lambda b: None,
    }

    handler = handlers.get(command)
    if not handler:
        return {"error": f"Unknown command: {command}"}

    try:
        result = handler(body)
        if asyncio.iscoroutine(result):
            result = await result
        return result
    except Exception as e:
        log.error(f"[{command}] {e}")
        return {"error": str(e)}


if __name__ == "__main__":
    import sys
    import uvicorn

    # When frozen (PyInstaller bundle), GUI apps don't inherit shell env vars —
    # SSL_CERT_FILE / REQUESTS_CA_BUNDLE are unset and all HTTPS calls fail.
    # Auto-configure from the certifi bundle that PyInstaller packages.
    if getattr(sys, "frozen", False):
        try:
            import certifi
            cert = certifi.where()
            os.environ.setdefault("SSL_CERT_FILE", cert)
            os.environ.setdefault("REQUESTS_CA_BUNDLE", cert)
        except Exception:
            pass

    uvicorn.run(app, host="127.0.0.1", port=8765, reload=False)
