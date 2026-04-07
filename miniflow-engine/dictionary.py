"""Dictionary — word replacement mappings."""

import json
import re
from pathlib import Path
from typing import Optional

DICT_FILE = Path.home() / "biteflow" / "dictionary.json"

# ── In-memory cache ───────────────────────────────────────────────────────────
# _refresh() always calls _read() on every apply() so unittest.mock patches
# on _read work correctly in tests (and the file stays the source of truth).
# The compiled regex pattern is rebuilt only when the dict actually changes,
# avoiding N re.compile() + N re.sub() passes on every transcription.

_cache = {}       # lower-cased keys → replacement values
_cache_pattern: Optional[re.Pattern] = None


def _read() -> dict:
    try:
        if DICT_FILE.exists():
            return json.loads(DICT_FILE.read_text())
    except Exception:
        pass
    return {}


def _write(data: dict):
    DICT_FILE.parent.mkdir(exist_ok=True)
    DICT_FILE.write_text(json.dumps(data, indent=2))


def _refresh():
    global _cache, _cache_pattern
    raw = _read()
    normalized = {k.lower(): v for k, v in raw.items()}
    if normalized == _cache:
        return
    _cache = normalized
    if _cache:
        keys_by_len = sorted(_cache, key=len, reverse=True)
        _cache_pattern = re.compile(
            '|'.join(re.escape(k) for k in keys_by_len),
            re.IGNORECASE,
        )
    else:
        _cache_pattern = None


# ── Public API ────────────────────────────────────────────────────────────────

def get_dictionary() -> dict:
    return _read()


def add_word(from_word: str, to_word: str):
    d = _read()
    d[from_word] = to_word
    _write(d)
    _refresh()


def remove_word(from_word: str):
    d = _read()
    d.pop(from_word, None)
    _write(d)
    _refresh()


def import_dictionary(entries: dict):
    d = _read()
    d.update(entries)
    _write(d)
    _refresh()


def apply(text: str) -> str:
    _refresh()
    if not _cache_pattern:
        return text
    return _cache_pattern.sub(lambda m: _cache[m.group(0).lower()], text)
