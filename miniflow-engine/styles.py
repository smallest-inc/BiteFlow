"""Style preferences — tone settings per category."""

import json
from pathlib import Path

STYLES_FILE = Path.home() / "miniflow" / "styles.json"


def _read() -> dict:
    try:
        if STYLES_FILE.exists():
            return json.loads(STYLES_FILE.read_text())
    except Exception:
        pass
    return {}


def _write(data: dict):
    STYLES_FILE.parent.mkdir(exist_ok=True)
    STYLES_FILE.write_text(json.dumps(data, indent=2))


def get_style_preferences() -> dict:
    return _read()


def save_style_preference(category: str, tone: str):
    s = _read()
    s[category] = tone
    _write(s)
