"""Shortcuts — trigger → expansion mappings."""

import json
import re
from pathlib import Path
from typing import Optional

SHORTCUTS_FILE = Path.home() / "biteflow" / "shortcuts.json"

# ── In-memory cache ───────────────────────────────────────────────────────────
# _refresh() always calls _read() on every apply() so unittest.mock patches
# on _read work correctly in tests (and the file stays the source of truth).
# The compiled regex pattern is rebuilt only when the dict actually changes,
# avoiding N str.replace passes on every transcription.
# Note: shortcuts are case-sensitive exact matches (no re.IGNORECASE).

_cache = {}
_cache_pattern: Optional[re.Pattern] = None


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


def _refresh():
    global _cache, _cache_pattern
    raw = _read()
    if raw == _cache:
        return
    _cache = raw
    if _cache:
        keys_by_len = sorted(_cache, key=len, reverse=True)
        _cache_pattern = re.compile(
            '|'.join(re.escape(k) for k in keys_by_len)
        )
    else:
        _cache_pattern = None


# ── Public API ────────────────────────────────────────────────────────────────

def get_shortcuts() -> dict:
    return _read()


def add_shortcut(trigger: str, expansion: str):
    s = _read()
    s[trigger] = expansion
    _write(s)
    _refresh()


def remove_shortcut(trigger: str):
    s = _read()
    s.pop(trigger, None)
    _write(s)
    _refresh()


def apply(text: str) -> str:
    _refresh()
    if not _cache_pattern:
        return text
    return _cache_pattern.sub(lambda m: _cache[m.group(0)], text)
