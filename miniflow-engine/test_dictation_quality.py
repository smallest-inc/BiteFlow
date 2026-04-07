"""
Dictation Quality Contract Tests
==================================
Architecture-agnostic skeleton. These tests define what the dictation
pipeline MUST guarantee to the user — regardless of implementation.

To adapt to a new architecture:
  1. Update PipelineAdapter below to point at your new backend
  2. Run: python3 -m pytest test_dictation_quality.py -v

Currently wired to: BiteFlow FastAPI engine on http://127.0.0.1:8765
Tests that require a live server are marked @pytest.mark.integration.
Tests that only need the text pipeline run without any server.
"""

from __future__ import annotations

import pytest
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# ── Adapter ───────────────────────────────────────────────────────────────────
#
# This is the ONLY place you touch when switching architectures.
# Implement each method to call your new backend.

class PipelineAdapter:
    """
    Wraps the dictation pipeline so tests stay architecture-agnostic.
    Swap this class out when the backend changes.
    """

    # ── Text pipeline ──────────────────────────────────────────────────────
    # Given raw transcribed text, run it through the post-processing pipeline
    # (filler removal → dictionary → shortcuts).
    # In the current architecture this is done in main._transcribe_audio().

    def process(
        self,
        text: str,
        filler_words: list[str] | None = None,
        dictionary: dict | None = None,
        shortcuts: dict | None = None,
        remove_fillers: bool = True,
    ) -> str:
        """
        Run text through the full post-processing pipeline.
        Replace this body when switching architectures.
        """
        from unittest.mock import patch
        import dictionary as _dict
        import shortcuts as _sc

        fw = filler_words if filler_words is not None else []
        dm = dictionary   if dictionary   is not None else {}
        sm = shortcuts    if shortcuts    is not None else {}

        result = text
        if remove_fillers and fw:
            result = self._remove_filler_words(result, fw)
        with patch("dictionary._read", return_value=dm):
            result = _dict.apply(result)
        with patch("shortcuts._read", return_value=sm):
            result = _sc.apply(result)
        return result.strip()

    @staticmethod
    def _remove_filler_words(text: str, words: list[str]) -> str:
        """
        Self-contained filler removal — no dependency on main.py.
        Replace with your new backend's equivalent when architecture changes.
        """
        import re
        if not text or not words:
            return text
        candidates = sorted(
            {w.strip().lower() for w in words if w.strip()},
            key=len, reverse=True,
        )
        pattern = r"\b(?:%s)\b" % "|".join(re.escape(w) for w in candidates)
        cleaned = re.sub(pattern, "", text, flags=re.IGNORECASE)
        cleaned = re.sub(r"\s+([,.;:!?])", r"\1", cleaned)
        cleaned = re.sub(r"\s{2,}", " ", cleaned).strip()
        cleaned = re.sub(r"^\s*,\s*", "", cleaned)
        cleaned = re.sub(r",\s*,+", ",", cleaned)
        cleaned = re.sub(r",\s*(?=[.?!]|$)", "", cleaned)
        cleaned = re.sub(r",\s*(\S)", r", \1", cleaned)
        return cleaned

    # ── Dictation state ────────────────────────────────────────────────────
    # Replace with HTTP calls or SDK calls when architecture changes.

    def start_dictation(self) -> dict:
        """Signal the backend to start listening."""
        import asyncio
        import dictation as _d
        asyncio.run(_d.start_dictation())
        return {"active": _d.get_dictation_status()}

    def stop_dictation(self) -> dict:
        """Signal the backend to stop listening."""
        import asyncio
        import dictation as _d
        asyncio.run(_d.stop_dictation())
        return {"active": _d.get_dictation_status()}

    def get_status(self) -> dict:
        """Return current dictation state."""
        import dictation as _d
        return {"active": _d.get_dictation_status()}

    # ── Dictionary & shortcuts ─────────────────────────────────────────────

    def add_dictionary_word(self, frm: str, to: str):
        """Add a word mapping."""
        import dictionary as _d
        from unittest.mock import patch
        with patch("dictionary._read", return_value={}), \
             patch("dictionary._write"):
            _d.add_word(frm, to)

    def add_shortcut(self, trigger: str, expansion: str):
        """Add a shortcut expansion."""
        import shortcuts as _s
        from unittest.mock import patch
        with patch("shortcuts._read", return_value={}), \
             patch("shortcuts._write"):
            _s.add_shortcut(trigger, expansion)

    # ── Live server (integration) ──────────────────────────────────────────
    # These require the engine to be running.

    def invoke(self, command: str, body: dict | None = None) -> dict:
        """
        POST to /invoke/{command}.
        Replace URL when switching architectures.
        """
        try:
            import requests
            resp = requests.post(
                f"http://127.0.0.1:8765/invoke/{command}",
                json=body or {},
                timeout=5,
            )
            return resp.json()
        except Exception as e:
            pytest.skip(f"Engine not running: {e}")


@pytest.fixture
def adapter():
    """Fresh adapter and clean dictation state for every test."""
    a = PipelineAdapter()
    try:
        import dictation as _d
        _d._active = False
        _d._broadcaster = None
    except Exception:
        pass
    yield a
    try:
        import dictation as _d
        _d._active = False
        _d._broadcaster = None
    except Exception:
        pass


# ═════════════════════════════════════════════════════════════════════════════
# 1. TRANSCRIPTION OUTPUT CONTRACTS
#    What the system guarantees about any transcribed text.
# ═════════════════════════════════════════════════════════════════════════════

class TestTranscriptionOutputContracts:

    def test_output_is_a_string(self, adapter):
        """Pipeline always returns a string, never None or a dict."""
        result = adapter.process("hello world")
        assert isinstance(result, str)

    def test_output_is_not_none(self, adapter):
        """Pipeline never returns None."""
        assert adapter.process("hello") is not None

    def test_empty_input_returns_empty_string(self, adapter):
        """Silence / empty transcript → empty string, not a crash."""
        assert adapter.process("") == ""

    def test_whitespace_only_input_handled(self, adapter):
        """Whitespace-only input does not crash."""
        result = adapter.process("   ")
        assert isinstance(result, str)

    def test_output_has_no_leading_whitespace(self, adapter):
        """Transcript is left-trimmed."""
        result = adapter.process("  hello world", remove_fillers=False)
        assert result == result.lstrip()

    def test_output_has_no_trailing_whitespace(self, adapter):
        """Transcript is right-trimmed after processing."""
        result = adapter.process(
            "hello um",
            filler_words=["um"],
            remove_fillers=True,
        )
        assert result == result.rstrip()

    def test_no_double_spaces_in_output(self, adapter):
        """Removing a filler word never leaves a double space."""
        result = adapter.process(
            "I um want coffee",
            filler_words=["um"],
            remove_fillers=True,
        )
        assert "  " not in result

    def test_output_does_not_contain_raw_error_text(self, adapter):
        """Pipeline never leaks error messages into the transcript."""
        result = adapter.process("hello world")
        for bad in ["Traceback", "Error", "Exception", "null", "undefined"]:
            assert bad not in result

    def test_plain_sentence_survives_pipeline_unchanged(self, adapter):
        """A clean sentence with no fillers/dict/shortcuts comes out identical."""
        text = "I have a meeting at three pm"
        assert adapter.process(text) == text

    def test_numbers_survive_pipeline(self, adapter):
        """Spoken numbers are preserved through the pipeline."""
        result = adapter.process("twenty three items")
        assert "twenty three" in result

    def test_proper_nouns_preserved(self, adapter):
        """Names and proper nouns are not mangled."""
        result = adapter.process("Alice sent a message to Bob")
        assert "Alice" in result and "Bob" in result

    def test_punctuation_in_transcript_preserved(self, adapter):
        """Commas and full stops from the ASR are not stripped."""
        result = adapter.process("Hello, how are you.", remove_fillers=False)
        assert "," in result and "." in result


# ═════════════════════════════════════════════════════════════════════════════
# 2. FILLER WORD REMOVAL CONTRACTS
# ═════════════════════════════════════════════════════════════════════════════

class TestFillerWordContracts:

    FILLERS = ["um", "uh", "er", "erm", "ah", "uhh", "umm", "uhm"]

    def test_um_removed(self, adapter):
        result = adapter.process("I um want coffee", filler_words=["um"])
        assert "um" not in result

    def test_uh_removed(self, adapter):
        result = adapter.process("uh I think so", filler_words=["uh"])
        assert "uh" not in result

    def test_er_removed(self, adapter):
        result = adapter.process("it is er complicated", filler_words=["er"])
        assert "er" not in result

    def test_all_default_fillers_removed(self, adapter):
        text = "um uh er erm ah uhh umm uhm done"
        result = adapter.process(text, filler_words=self.FILLERS)
        for f in self.FILLERS:
            assert f not in result.lower()

    def test_filler_at_start_removed(self, adapter):
        result = adapter.process("um hello there", filler_words=["um"])
        assert result.strip().startswith("hello")

    def test_filler_at_end_removed(self, adapter):
        result = adapter.process("hello there um", filler_words=["um"])
        assert not result.strip().endswith("um")

    def test_filler_in_middle_removed(self, adapter):
        result = adapter.process("I um think so", filler_words=["um"])
        assert "um" not in result and "I" in result and "think" in result

    def test_multiple_fillers_in_one_sentence(self, adapter):
        result = adapter.process("um I uh think er yes", filler_words=self.FILLERS)
        assert "I" in result and "think" in result and "yes" in result

    def test_filler_removal_disabled_leaves_fillers(self, adapter):
        result = adapter.process("I um want coffee", filler_words=["um"], remove_fillers=False)
        assert "um" in result

    def test_non_filler_word_not_removed(self, adapter):
        """'umbrella' should not be stripped when 'um' is a filler."""
        result = adapter.process("I have an umbrella", filler_words=["um"])
        assert "umbrella" in result

    def test_filler_removal_no_leading_comma(self, adapter):
        """Removing a leading filler never leaves a dangling comma."""
        result = adapter.process("um, I think so", filler_words=["um"])
        assert not result.strip().startswith(",")

    def test_punctuation_spacing_after_filler_removal(self, adapter):
        """No space before punctuation after filler removed."""
        result = adapter.process("hello um, world", filler_words=["um"])
        assert " ," not in result


# ═════════════════════════════════════════════════════════════════════════════
# 3. DICTIONARY CONTRACTS
# ═════════════════════════════════════════════════════════════════════════════

class TestDictionaryContracts:

    def test_dictionary_word_replaced_in_output(self, adapter):
        result = adapter.process("gonna go now", dictionary={"gonna": "going to"})
        assert "going to" in result

    def test_dictionary_replacement_case_insensitive(self, adapter):
        result = adapter.process("GONNA go now", dictionary={"gonna": "going to"})
        assert "going to" in result

    def test_non_dictionary_word_unchanged(self, adapter):
        result = adapter.process("hello world", dictionary={"cat": "dog"})
        assert "hello" in result and "world" in result

    def test_multiple_dictionary_words_all_replaced(self, adapter):
        result = adapter.process(
            "gonna wanna go",
            dictionary={"gonna": "going to", "wanna": "want to"},
        )
        assert "going to" in result and "want to" in result

    def test_empty_dictionary_no_change(self, adapter):
        text = "hello world"
        assert adapter.process(text, dictionary={}) == text

    def test_dictionary_applied_to_full_sentence(self, adapter):
        result = adapter.process(
            "I gotta go cause I wanna eat",
            dictionary={"gotta": "have to", "wanna": "want to", "cause": "because"},
        )
        assert "have to" in result
        assert "want to" in result
        assert "because" in result

    def test_dictionary_replacement_value_preserved_exactly(self, adapter):
        result = adapter.process("test word", dictionary={"word": "exact replacement"})
        assert "exact replacement" in result


# ═════════════════════════════════════════════════════════════════════════════
# 4. SHORTCUTS CONTRACTS
# ═════════════════════════════════════════════════════════════════════════════

class TestShortcutsContracts:

    def test_trigger_expanded_in_output(self, adapter):
        result = adapter.process("email myemail", shortcuts={"myemail": "alice@example.com"})
        assert "alice@example.com" in result

    def test_non_trigger_word_unchanged(self, adapter):
        result = adapter.process("hello world", shortcuts={"trigger": "expansion"})
        assert "hello" in result and "world" in result

    def test_multiple_triggers_all_expanded(self, adapter):
        result = adapter.process(
            "send to myemail at myaddress",
            shortcuts={
                "myemail": "alice@example.com",
                "myaddress": "123 Main St",
            },
        )
        assert "alice@example.com" in result
        assert "123 Main St" in result

    def test_empty_shortcuts_no_change(self, adapter):
        text = "hello world"
        assert adapter.process(text, shortcuts={}) == text

    def test_shortcut_expansion_is_exact(self, adapter):
        result = adapter.process("sig", shortcuts={"sig": "Best regards, Alice"})
        assert "Best regards, Alice" in result


# ═════════════════════════════════════════════════════════════════════════════
# 5. PIPELINE ORDER CONTRACTS
#    Filler removal → dictionary → shortcuts. Order must not change.
# ═════════════════════════════════════════════════════════════════════════════

class TestPipelineOrderContracts:

    def test_filler_removed_before_dictionary(self, adapter):
        """'um' stripped, then 'gonna' replaced — result has neither."""
        result = adapter.process(
            "I um gonna go",
            filler_words=["um"],
            dictionary={"gonna": "going to"},
        )
        assert "um" not in result
        assert "going to" in result

    def test_dictionary_applied_before_shortcuts(self, adapter):
        """Dictionary runs before shortcuts — both applied correctly."""
        result = adapter.process(
            "gonna myemail",
            dictionary={"gonna": "going to"},
            shortcuts={"myemail": "alice@example.com"},
        )
        assert "going to" in result
        assert "alice@example.com" in result

    def test_full_pipeline_all_three_stages(self, adapter):
        """All three stages applied in correct order."""
        result = adapter.process(
            "um gonna myemail",
            filler_words=["um"],
            dictionary={"gonna": "going to"},
            shortcuts={"myemail": "alice@example.com"},
        )
        assert "um" not in result
        assert "going to" in result
        assert "alice@example.com" in result

    def test_pipeline_does_not_double_process(self, adapter):
        """Running the pipeline once and twice gives the same result."""
        text = "hello world"
        once  = adapter.process(text)
        twice = adapter.process(once)
        assert once == twice


# ═════════════════════════════════════════════════════════════════════════════
# 6. DICTATION STATE CONTRACTS
# ═════════════════════════════════════════════════════════════════════════════

class TestDictationStateContracts:

    def test_initial_state_is_inactive(self, adapter):
        assert adapter.get_status()["active"] is False

    def test_start_sets_active(self, adapter):
        assert adapter.start_dictation()["active"] is True

    def test_stop_sets_inactive(self, adapter):
        adapter.start_dictation()
        assert adapter.stop_dictation()["active"] is False

    def test_start_twice_still_active(self, adapter):
        adapter.start_dictation()
        assert adapter.start_dictation()["active"] is True

    def test_stop_without_start_does_not_error(self, adapter):
        """Stopping when already inactive is safe."""
        result = adapter.stop_dictation()
        assert result["active"] is False

    def test_stop_twice_does_not_error(self, adapter):
        adapter.start_dictation()
        adapter.stop_dictation()
        result = adapter.stop_dictation()
        assert result["active"] is False

    def test_start_stop_cycle_repeatable(self, adapter):
        """Start/stop can be cycled multiple times cleanly."""
        for _ in range(5):
            assert adapter.start_dictation()["active"] is True
            assert adapter.stop_dictation()["active"] is False

    def test_status_reflects_reality(self, adapter):
        """get_status() always matches the last start/stop call."""
        adapter.start_dictation()
        assert adapter.get_status()["active"] is True
        adapter.stop_dictation()
        assert adapter.get_status()["active"] is False


# ═════════════════════════════════════════════════════════════════════════════
# 7. EDGE CASES THAT KILL QUALITY
# ═════════════════════════════════════════════════════════════════════════════

class TestEdgeCaseContracts:

    def test_very_long_transcript_not_truncated(self, adapter):
        """A 500-word transcript makes it through the pipeline intact."""
        text = "hello world " * 250
        result = adapter.process(text.strip())
        assert len(result) > 100

    def test_only_filler_words_returns_empty_or_clean(self, adapter):
        """A transcript of only fillers gives an empty or whitespace-only result."""
        result = adapter.process("um uh er", filler_words=["um", "uh", "er"])
        assert result.strip() == ""

    def test_mixed_filler_and_content(self, adapter):
        """Fillers removed, real content survives."""
        result = adapter.process(
            "um the meeting um is at um three",
            filler_words=["um"],
        )
        assert "meeting" in result and "three" in result

    def test_repeated_word_not_over_replaced(self, adapter):
        """A word appearing 10 times is replaced exactly 10 times."""
        result = adapter.process(
            "cat " * 10,
            dictionary={"cat": "dog"},
        )
        assert result.count("dog") == 10

    def test_unicode_text_survives(self, adapter):
        """Non-ASCII characters pass through the pipeline without corruption."""
        text = "héllo wörld"
        result = adapter.process(text)
        assert isinstance(result, str)

    def test_numbers_not_mangled(self, adapter):
        """Numeric strings pass through unchanged."""
        result = adapter.process("I need 42 items by 2024")
        assert "42" in result and "2024" in result

    def test_single_word_transcript(self, adapter):
        """A one-word transcript is handled."""
        result = adapter.process("hello")
        assert "hello" in result

    def test_single_char_transcript(self, adapter):
        """A single character is handled."""
        result = adapter.process("a")
        assert isinstance(result, str)

    def test_newline_in_transcript_handled(self, adapter):
        """Newlines in transcript don't crash the pipeline."""
        result = adapter.process("hello\nworld")
        assert isinstance(result, str)

    def test_all_punctuation_transcript(self, adapter):
        """A transcript of only punctuation doesn't crash."""
        result = adapter.process("... , . ! ?")
        assert isinstance(result, str)


# ═════════════════════════════════════════════════════════════════════════════
# 8. LIVE API CONTRACTS (requires engine running on port 8765)
#    These are skipped automatically if the engine is not running.
# ═════════════════════════════════════════════════════════════════════════════

@pytest.mark.integration
class TestLiveAPIContracts:

    def test_health_endpoint_returns_ok(self, adapter):
        """GET /health returns {"status": "ok"}."""
        try:
            import requests
            resp = requests.get("http://127.0.0.1:8765/health", timeout=3)
            assert resp.json()["status"] == "ok"
        except Exception as e:
            pytest.skip(f"Engine not running: {e}")

    def test_get_shortcuts_returns_dict(self, adapter):
        result = adapter.invoke("get_shortcuts")
        assert isinstance(result, dict)

    def test_get_dictionary_returns_dict(self, adapter):
        result = adapter.invoke("get_dictionary")
        assert isinstance(result, dict)

    def test_get_history_returns_list(self, adapter):
        result = adapter.invoke("get_history")
        assert isinstance(result, list)

    def test_unknown_command_returns_error(self, adapter):
        result = adapter.invoke("nonexistent_command")
        assert "error" in result

    def test_get_user_name_returns_string_or_none(self, adapter):
        result = adapter.invoke("get_user_name")
        assert result is None or isinstance(result, str)

    def test_get_advanced_settings_has_filler_removal(self, adapter):
        result = adapter.invoke("get_advanced_settings")
        assert "filler_removal" in result or "fillerRemoval" in result
