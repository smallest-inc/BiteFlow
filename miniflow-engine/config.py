"""
Config — reads/writes ~/miniflow/*.json
Same file paths as the old Rust backend — existing user data is preserved.
"""

from __future__ import annotations

import json
import os
import stat
from pathlib import Path
from typing import Any

CONFIG_DIR = Path.home() / "miniflow"
KEYS_FILE = CONFIG_DIR / "miniflow_keys.json"
SETTINGS_FILE = CONFIG_DIR / "miniflow_settings.json"

DEFAULT_FILLER_WORDS = [
    "um",
    "uh",
    "erm",
    "er",
    "ah",
    "uhh",
    "umm",
    "uhm",
]

DEFAULT_SETTINGS = {
    "language": "en",
    "whisper_mode": False,
    "developer_mode": False,
    "filler_removal": True,
    "numeral_mode": False,
    "newline_mode": False,
    "user_name": None,
}


def _ensure_dir():
    CONFIG_DIR.mkdir(exist_ok=True)


def _read_json(path: Path, default: dict) -> dict:
    try:
        if path.exists():
            return json.loads(path.read_text())
    except Exception:
        pass
    return dict(default)


def _write_json(path: Path, data: dict):
    _ensure_dir()
    path.write_text(json.dumps(data, indent=2))
    path.chmod(stat.S_IRUSR | stat.S_IWUSR)  # chmod 600


# ── API Keys ──

def save_api_key(service: str, key: str):
    keys = _read_json(KEYS_FILE, {})
    keys[service] = key
    _write_json(KEYS_FILE, keys)

def get_api_key(service: str) -> str:
    keys = _read_json(KEYS_FILE, {})
    if service not in keys or not keys[service]:
        raise ValueError(f"{service} API key not set")
    return keys[service]

def has_api_keys() -> dict:
    keys = _read_json(KEYS_FILE, {})
    return {"smallest": keys.get("smallest"), "openai": keys.get("openai"), "cerebras": keys.get("cerebras")}

def get_openai_key() -> str:
    return get_api_key("openai")

def get_smallest_key() -> str:
    return get_api_key("smallest")

def get_cerebras_key() -> str:
    return get_api_key("cerebras")


# ── Settings ──

def _read_settings() -> dict:
    return {**DEFAULT_SETTINGS, **_read_json(SETTINGS_FILE, {})}

def _write_settings(settings: dict):
    _write_json(SETTINGS_FILE, settings)

def save_language(language: str):
    s = _read_settings()
    s["language"] = language
    _write_settings(s)

def get_language() -> str:
    return _read_settings()["language"]

def get_advanced_settings() -> dict:
    s = _read_settings()
    return {
        "whisper_mode": s["whisper_mode"],
        "developer_mode": s["developer_mode"],
        "filler_removal": s["filler_removal"],
        "numeral_mode": s.get("numeral_mode", False),
        "newline_mode": s.get("newline_mode", False),
    }

def save_advanced_setting(key: str, value: bool):
    s = _read_settings()
    if key not in ("whisper_mode", "developer_mode", "filler_removal", "numeral_mode", "newline_mode"):
        raise ValueError(f"Unknown setting: {key}")
    s[key] = value
    _write_settings(s)

def save_user_name(name: str):
    s = _read_settings()
    s["user_name"] = name.strip() or None
    _write_settings(s)

def get_user_name() -> str | None:
    return _read_settings().get("user_name")

def get_current_language() -> str:
    return get_language()


# ── Filler words ──

def get_all_filler_words() -> list[str]:
    return DEFAULT_FILLER_WORDS


