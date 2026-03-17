"""Snippets — trigger → expansion mappings."""

import json
from pathlib import Path

SNIPPETS_FILE = Path.home() / "miniflow" / "snippets.json"


def _read() -> dict:
    try:
        if SNIPPETS_FILE.exists():
            return json.loads(SNIPPETS_FILE.read_text())
    except Exception:
        pass
    return {}


def _write(data: dict):
    SNIPPETS_FILE.parent.mkdir(exist_ok=True)
    SNIPPETS_FILE.write_text(json.dumps(data, indent=2))


def get_snippets() -> dict:
    return _read()


def add_snippet(trigger: str, expansion: str):
    s = _read()
    s[trigger] = expansion
    _write(s)


def remove_snippet(trigger: str):
    s = _read()
    s.pop(trigger, None)
    _write(s)


def apply(text: str) -> str:
    for trigger, expansion in _read().items():
        text = text.replace(trigger, expansion)
    return text
