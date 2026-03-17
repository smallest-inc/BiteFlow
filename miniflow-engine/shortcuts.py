"""Shortcuts — trigger → expansion mappings."""

import json
from pathlib import Path

SHORTCUTS_FILE = Path.home() / "miniflow" / "shortcuts.json"


def _read() -> dict:
    try:
        if SHORTCUTS_FILE.exists():
            return json.loads(SHORTCUTS_FILE.read_text())
    except Exception:
        pass
    return {}


def _write(data: dict):
    SHORTCUTS_FILE.parent.mkdir(exist_ok=True)
    SHORTCUTS_FILE.write_text(json.dumps(data, indent=2))


def get_shortcuts() -> dict:
    return _read()


def add_shortcut(trigger: str, expansion: str):
    s = _read()
    s[trigger] = expansion
    _write(s)


def remove_shortcut(trigger: str):
    s = _read()
    s.pop(trigger, None)
    _write(s)


def apply(text: str) -> str:
    for trigger, expansion in _read().items():
        text = text.replace(trigger, expansion)
    return text
