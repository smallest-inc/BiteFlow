"""Dictionary — word replacement mappings."""

import json
import re
from pathlib import Path

DICT_FILE = Path.home() / "miniflow" / "dictionary.json"


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


def get_dictionary() -> dict:
    return _read()


def add_word(from_word: str, to_word: str):
    d = _read()
    d[from_word] = to_word
    _write(d)


def remove_word(from_word: str):
    d = _read()
    d.pop(from_word, None)
    _write(d)


def import_dictionary(entries: dict):
    d = _read()
    d.update(entries)
    _write(d)


def apply(text: str) -> str:
    for frm, to in _read().items():
        text = re.sub(re.escape(frm), to, text, flags=re.IGNORECASE)
    return text
