"""History — read/write session history JSON."""

import json
import uuid
from datetime import datetime
from pathlib import Path

HISTORY_FILE = Path.home() / "miniflow" / "history.json"


def _read() -> list:
    try:
        if HISTORY_FILE.exists():
            return json.loads(HISTORY_FILE.read_text())
    except Exception:
        pass
    return []


def _write(entries: list):
    HISTORY_FILE.parent.mkdir(exist_ok=True)
    HISTORY_FILE.write_text(json.dumps(entries, indent=2))


def get_history() -> list:
    return _read()


def clear_history():
    _write([])


def append_entry(transcript: str, entry_type: str, actions: list, success: bool):
    entries = _read()
    entries.insert(0, {
        "id": str(uuid.uuid4()),
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "transcript": transcript,
        "entry_type": entry_type,
        "actions": actions,
        "success": success,
    })
    _write(entries[:500])  # keep last 500
