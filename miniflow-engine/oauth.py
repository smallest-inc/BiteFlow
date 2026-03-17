"""OAuth — provider connect/disconnect, same proxy as old Rust backend."""

from __future__ import annotations

import json
import logging
from pathlib import Path

log = logging.getLogger("oauth")
CONNECTORS_FILE = Path.home() / "miniflow" / "connectors.json"


def _read() -> dict:
    try:
        if CONNECTORS_FILE.exists():
            return json.loads(CONNECTORS_FILE.read_text())
    except Exception:
        pass
    return {}


def _write(data: dict):
    CONNECTORS_FILE.parent.mkdir(exist_ok=True)
    CONNECTORS_FILE.write_text(json.dumps(data, indent=2))


def get_connected_providers() -> list:
    return list(_read().keys())


def is_provider_connected(provider: str) -> bool:
    return provider in _read()


def disconnect_provider(provider: str):
    data = _read()
    data.pop(provider, None)
    _write(data)
    log.info(f"Disconnected: {provider}")


def get_token(provider: str) -> dict | None:
    return _read().get(provider)


def save_token(provider: str, token_data: dict):
    data = _read()
    data[provider] = token_data
    _write(data)


async def start_oauth(provider: str) -> str:
    """
    Returns the OAuth URL to open in the browser.
    The miniflow-auth Vercel proxy handles the OAuth exchange then redirects
    back to http://localhost:8765/callback with the encoded token payload.
    """
    proxy = "https://miniflow-auth.vercel.app"
    return f"{proxy}/api/auth/{provider}?port=8765"
