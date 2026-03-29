"""
Contract tests for the config subsystem.

These tests define the required BEHAVIOUR of config storage — not the
implementation. If the backend changes (SQLite, plist, cloud sync, …) only
the ConfigAdapter class below needs updating; every test stays the same.

Run with: python3 -m pytest test_config.py -v
"""
from __future__ import annotations

import pytest
from pathlib import Path


# ── Adapter ───────────────────────────────────────────────────────────────────
# Only this class changes when the config backend changes.

class ConfigAdapter:
    """Thin facade over the current config.py implementation."""

    def __init__(self, data_dir: Path):
        import config as _cfg
        self._cfg = _cfg
        # Redirect all file I/O to the isolated tmp directory
        self._saved = {
            "CONFIG_DIR": _cfg.CONFIG_DIR,
            "KEYS_FILE":  _cfg.KEYS_FILE,
            "SETTINGS_FILE": _cfg.SETTINGS_FILE,
        }
        _cfg.CONFIG_DIR    = data_dir
        _cfg.KEYS_FILE     = data_dir / "keys.json"
        _cfg.SETTINGS_FILE = data_dir / "settings.json"

    def teardown(self):
        for attr, val in self._saved.items():
            setattr(self._cfg, attr, val)

    # ── API keys ──
    def save_api_key(self, service: str, key: str):
        self._cfg.save_api_key(service, key)

    def get_api_key(self, service: str) -> str:
        return self._cfg.get_api_key(service)

    def has_api_keys(self) -> dict:
        return self._cfg.has_api_keys()

    # ── Language ──
    def save_language(self, lang: str):
        self._cfg.save_language(lang)

    def get_language(self) -> str:
        return self._cfg.get_language()

    # ── Advanced settings ──
    def get_advanced_settings(self) -> dict:
        return self._cfg.get_advanced_settings()

    def save_advanced_setting(self, key: str, value):
        self._cfg.save_advanced_setting(key, value)

    # ── User name ──
    def save_user_name(self, name: str):
        self._cfg.save_user_name(name)

    def get_user_name(self):
        return self._cfg.get_user_name()

    # ── Filler words ──
    def get_filler_words(self) -> list[str]:
        return self._cfg.get_all_filler_words()


@pytest.fixture
def cfg(tmp_path):
    adapter = ConfigAdapter(tmp_path)
    yield adapter
    adapter.teardown()


# ── API key contracts (1–25) ──────────────────────────────────────────────────

class TestApiKeyContracts:
    def test_01_saved_key_can_be_retrieved(self, cfg):
        cfg.save_api_key("openai", "sk-abc")
        assert cfg.get_api_key("openai") == "sk-abc"

    def test_02_missing_key_raises_error(self, cfg):
        with pytest.raises(Exception):
            cfg.get_api_key("openai")

    def test_03_empty_string_key_raises_error(self, cfg):
        cfg.save_api_key("openai", "")
        with pytest.raises(Exception):
            cfg.get_api_key("openai")

    def test_04_saving_same_service_twice_keeps_latest(self, cfg):
        cfg.save_api_key("openai", "first")
        cfg.save_api_key("openai", "second")
        assert cfg.get_api_key("openai") == "second"

    def test_05_two_services_stored_independently(self, cfg):
        cfg.save_api_key("openai", "o-key")
        cfg.save_api_key("smallest", "s-key")
        assert cfg.get_api_key("openai") == "o-key"
        assert cfg.get_api_key("smallest") == "s-key"

    def test_06_saving_one_service_does_not_delete_other(self, cfg):
        cfg.save_api_key("openai", "o-key")
        cfg.save_api_key("smallest", "s-key")
        cfg.save_api_key("openai", "o-key-2")
        assert cfg.get_api_key("smallest") == "s-key"

    def test_07_has_api_keys_both_absent_returns_none_values(self, cfg):
        result = cfg.has_api_keys()
        assert result.get("groq") is None
        assert result.get("smallest") is None

    def test_08_has_api_keys_groq_present(self, cfg):
        cfg.save_api_key("groq", "o-key")
        result = cfg.has_api_keys()
        assert result.get("groq") == "o-key"

    def test_09_has_api_keys_smallest_present(self, cfg):
        cfg.save_api_key("smallest", "s-key")
        result = cfg.has_api_keys()
        assert result.get("smallest") == "s-key"

    def test_10_has_api_keys_returns_dict(self, cfg):
        assert isinstance(cfg.has_api_keys(), dict)

    def test_11_key_with_special_characters_survives_roundtrip(self, cfg):
        key = "sk-abc/123+def==end"
        cfg.save_api_key("openai", key)
        assert cfg.get_api_key("openai") == key

    def test_12_key_with_unicode_survives_roundtrip(self, cfg):
        key = "sk-日本語テスト"
        cfg.save_api_key("openai", key)
        assert cfg.get_api_key("openai") == key

    def test_13_unknown_service_raises_error(self, cfg):
        with pytest.raises(Exception):
            cfg.get_api_key("nonexistent_service")

    def test_14_key_persists_across_multiple_get_calls(self, cfg):
        cfg.save_api_key("openai", "stable")
        assert cfg.get_api_key("openai") == "stable"
        assert cfg.get_api_key("openai") == "stable"

    def test_15_long_api_key_stored_correctly(self, cfg):
        key = "sk-" + "x" * 200
        cfg.save_api_key("openai", key)
        assert cfg.get_api_key("openai") == key

    def test_16_has_api_keys_reflects_saved_keys(self, cfg):
        cfg.save_api_key("groq", "o")
        cfg.save_api_key("smallest", "s")
        result = cfg.has_api_keys()
        assert result["groq"] == "o"
        assert result["smallest"] == "s"

    def test_17_saving_new_key_does_not_affect_has_api_keys_structure(self, cfg):
        cfg.save_api_key("groq", "o")
        result = cfg.has_api_keys()
        assert "groq" in result
        assert "smallest" in result  # key should still appear (as None)

    def test_18_get_api_key_returns_exact_value(self, cfg):
        cfg.save_api_key("openai", "  spaces  ")
        assert cfg.get_api_key("openai") == "  spaces  "

    def test_19_three_sequential_saves_last_wins(self, cfg):
        for v in ["a", "b", "c"]:
            cfg.save_api_key("openai", v)
        assert cfg.get_api_key("openai") == "c"

    def test_20_api_keys_and_settings_do_not_interfere(self, cfg):
        cfg.save_api_key("openai", "o-key")
        cfg.save_language("fr")
        assert cfg.get_api_key("openai") == "o-key"
        assert cfg.get_language() == "fr"

    def test_21_has_api_keys_after_overwrite(self, cfg):
        cfg.save_api_key("groq", "old")
        cfg.save_api_key("groq", "new")
        assert cfg.has_api_keys()["groq"] == "new"

    def test_22_whitespace_only_key_is_stored_as_is(self, cfg):
        # Whitespace-only key is stored verbatim; callers are responsible for validation
        cfg.save_api_key("openai", "   ")
        assert cfg.get_api_key("openai") == "   "

    def test_23_service_name_case_sensitive(self, cfg):
        cfg.save_api_key("OpenAI", "upper")
        with pytest.raises(Exception):
            cfg.get_api_key("openai")

    def test_24_save_api_key_idempotent(self, cfg):
        cfg.save_api_key("openai", "same")
        cfg.save_api_key("openai", "same")
        assert cfg.get_api_key("openai") == "same"

    def test_25_has_api_keys_absent_smallest(self, cfg):
        cfg.save_api_key("openai", "o")
        assert cfg.has_api_keys()["smallest"] is None


# ── Language contracts (26–40) ────────────────────────────────────────────────

class TestLanguageContracts:
    def test_26_default_language_is_en(self, cfg):
        assert cfg.get_language() == "en"

    def test_27_saved_language_can_be_retrieved(self, cfg):
        cfg.save_language("fr")
        assert cfg.get_language() == "fr"

    def test_28_language_roundtrip_multiple_values(self, cfg):
        for lang in ["de", "ja", "zh", "es", "it"]:
            cfg.save_language(lang)
            assert cfg.get_language() == lang

    def test_29_language_overwrite_keeps_latest(self, cfg):
        cfg.save_language("fr")
        cfg.save_language("de")
        assert cfg.get_language() == "de"

    def test_30_language_does_not_affect_advanced_settings(self, cfg):
        defaults = cfg.get_advanced_settings()
        cfg.save_language("fr")
        assert cfg.get_advanced_settings() == defaults

    def test_31_language_does_not_affect_user_name(self, cfg):
        cfg.save_user_name("Alice")
        cfg.save_language("fr")
        assert cfg.get_user_name() == "Alice"

    def test_32_language_uppercase_stored_as_is(self, cfg):
        cfg.save_language("EN-US")
        assert cfg.get_language() == "EN-US"

    def test_33_language_empty_string_stored(self, cfg):
        cfg.save_language("")
        assert cfg.get_language() == ""

    def test_34_language_persists_across_multiple_reads(self, cfg):
        cfg.save_language("ja")
        assert cfg.get_language() == "ja"
        assert cfg.get_language() == "ja"

    def test_35_language_locale_code_stored(self, cfg):
        cfg.save_language("pt-BR")
        assert cfg.get_language() == "pt-BR"

    def test_36_language_does_not_affect_api_keys(self, cfg):
        cfg.save_api_key("openai", "o")
        cfg.save_language("de")
        assert cfg.get_api_key("openai") == "o"

    def test_37_get_language_before_save_returns_default(self, cfg):
        result = cfg.get_language()
        assert isinstance(result, str)
        assert result == "en"

    def test_38_language_long_code(self, cfg):
        cfg.save_language("zh-Hant-TW")
        assert cfg.get_language() == "zh-Hant-TW"

    def test_39_language_unicode(self, cfg):
        cfg.save_language("日本語")
        assert cfg.get_language() == "日本語"

    def test_40_language_is_string(self, cfg):
        assert isinstance(cfg.get_language(), str)


# ── Advanced settings contracts (41–60) ───────────────────────────────────────

class TestAdvancedSettingsContracts:
    def test_41_advanced_settings_returns_dict(self, cfg):
        assert isinstance(cfg.get_advanced_settings(), dict)

    def test_42_advanced_settings_has_whisper_mode(self, cfg):
        assert "whisper_mode" in cfg.get_advanced_settings()

    def test_43_advanced_settings_has_developer_mode(self, cfg):
        assert "developer_mode" in cfg.get_advanced_settings()

    def test_44_advanced_settings_has_filler_removal(self, cfg):
        assert "filler_removal" in cfg.get_advanced_settings()

    def test_45_default_whisper_mode_is_false(self, cfg):
        assert cfg.get_advanced_settings()["whisper_mode"] is False

    def test_46_default_developer_mode_is_false(self, cfg):
        assert cfg.get_advanced_settings()["developer_mode"] is False

    def test_47_default_filler_removal_is_true(self, cfg):
        assert cfg.get_advanced_settings()["filler_removal"] is True

    def test_48_save_whisper_mode_true(self, cfg):
        cfg.save_advanced_setting("whisper_mode", True)
        assert cfg.get_advanced_settings()["whisper_mode"] is True

    def test_49_save_developer_mode_true(self, cfg):
        cfg.save_advanced_setting("developer_mode", True)
        assert cfg.get_advanced_settings()["developer_mode"] is True

    def test_50_save_filler_removal_false(self, cfg):
        cfg.save_advanced_setting("filler_removal", False)
        assert cfg.get_advanced_settings()["filler_removal"] is False

    def test_51_save_one_setting_does_not_change_others(self, cfg):
        cfg.save_advanced_setting("whisper_mode", True)
        s = cfg.get_advanced_settings()
        assert s["developer_mode"] is False
        assert s["filler_removal"] is True

    def test_52_unknown_key_raises_error(self, cfg):
        with pytest.raises(Exception):
            cfg.save_advanced_setting("unknown_key", True)

    def test_53_language_key_raises_error(self, cfg):
        with pytest.raises(Exception):
            cfg.save_advanced_setting("language", "fr")

    def test_54_user_name_key_raises_error(self, cfg):
        with pytest.raises(Exception):
            cfg.save_advanced_setting("user_name", "Alice")

    def test_55_overwrite_setting_keeps_latest(self, cfg):
        cfg.save_advanced_setting("whisper_mode", True)
        cfg.save_advanced_setting("whisper_mode", False)
        assert cfg.get_advanced_settings()["whisper_mode"] is False

    def test_56_settings_do_not_expose_language(self, cfg):
        assert "language" not in cfg.get_advanced_settings()

    def test_57_settings_do_not_expose_user_name(self, cfg):
        assert "user_name" not in cfg.get_advanced_settings()

    def test_58_advanced_settings_has_exactly_five_keys(self, cfg):
        assert len(cfg.get_advanced_settings()) == 5

    def test_59_all_values_are_booleans(self, cfg):
        for v in cfg.get_advanced_settings().values():
            assert isinstance(v, bool)

    def test_60_settings_persist_across_multiple_reads(self, cfg):
        cfg.save_advanced_setting("developer_mode", True)
        assert cfg.get_advanced_settings()["developer_mode"] is True
        assert cfg.get_advanced_settings()["developer_mode"] is True


# ── User name contracts (61–80) ───────────────────────────────────────────────

class TestUserNameContracts:
    def test_61_default_user_name_is_none(self, cfg):
        assert cfg.get_user_name() is None

    def test_62_saved_name_can_be_retrieved(self, cfg):
        cfg.save_user_name("Alice")
        assert cfg.get_user_name() == "Alice"

    def test_63_name_strips_leading_trailing_whitespace(self, cfg):
        cfg.save_user_name("  Bob  ")
        assert cfg.get_user_name() == "Bob"

    def test_64_empty_string_stored_as_none(self, cfg):
        cfg.save_user_name("")
        assert cfg.get_user_name() is None

    def test_65_whitespace_only_stored_as_none(self, cfg):
        cfg.save_user_name("   ")
        assert cfg.get_user_name() is None

    def test_66_overwrite_replaces_old_name(self, cfg):
        cfg.save_user_name("Alice")
        cfg.save_user_name("Bob")
        assert cfg.get_user_name() == "Bob"

    def test_67_name_does_not_affect_language(self, cfg):
        cfg.save_language("de")
        cfg.save_user_name("Alice")
        assert cfg.get_language() == "de"

    def test_68_name_does_not_affect_advanced_settings(self, cfg):
        defaults = cfg.get_advanced_settings()
        cfg.save_user_name("Alice")
        assert cfg.get_advanced_settings() == defaults

    def test_69_unicode_name_stored_correctly(self, cfg):
        cfg.save_user_name("Ève")
        assert cfg.get_user_name() == "Ève"

    def test_70_single_char_name(self, cfg):
        cfg.save_user_name("A")
        assert cfg.get_user_name() == "A"

    def test_71_long_name_stored_correctly(self, cfg):
        name = "A" * 200
        cfg.save_user_name(name)
        assert cfg.get_user_name() == name

    def test_72_name_with_numbers(self, cfg):
        cfg.save_user_name("User42")
        assert cfg.get_user_name() == "User42"

    def test_73_name_persists_across_reads(self, cfg):
        cfg.save_user_name("Carol")
        assert cfg.get_user_name() == "Carol"
        assert cfg.get_user_name() == "Carol"

    def test_74_clear_name_by_saving_empty(self, cfg):
        cfg.save_user_name("Alice")
        cfg.save_user_name("")
        assert cfg.get_user_name() is None

    def test_75_name_with_internal_spaces_preserved(self, cfg):
        cfg.save_user_name("John Smith")
        assert cfg.get_user_name() == "John Smith"

    def test_76_tab_stripped_from_edges(self, cfg):
        cfg.save_user_name("\tAlice\t")
        # strip() removes tabs too
        assert cfg.get_user_name() == "Alice"

    def test_77_name_does_not_affect_api_keys(self, cfg):
        cfg.save_api_key("openai", "o")
        cfg.save_user_name("Alice")
        assert cfg.get_api_key("openai") == "o"

    def test_78_emoji_in_name(self, cfg):
        cfg.save_user_name("Ali 🎙️")
        assert cfg.get_user_name() == "Ali 🎙️"

    def test_79_numeric_only_name(self, cfg):
        cfg.save_user_name("42")
        assert cfg.get_user_name() == "42"

    def test_80_multiple_saves_last_wins(self, cfg):
        for name in ["Alice", "Bob", "Carol", "Dave"]:
            cfg.save_user_name(name)
        assert cfg.get_user_name() == "Dave"


# ── Filler word contracts (81–95) ─────────────────────────────────────────────

class TestFillerWordContracts:
    def test_81_returns_a_list(self, cfg):
        assert isinstance(cfg.get_filler_words(), list)

    def test_82_list_is_nonempty(self, cfg):
        assert len(cfg.get_filler_words()) > 0

    def test_83_all_entries_are_strings(self, cfg):
        for w in cfg.get_filler_words():
            assert isinstance(w, str)

    def test_84_all_entries_are_nonempty(self, cfg):
        for w in cfg.get_filler_words():
            assert w.strip() != ""

    def test_85_all_entries_are_lowercase(self, cfg):
        for w in cfg.get_filler_words():
            assert w == w.lower()

    def test_86_contains_um(self, cfg):
        assert "um" in cfg.get_filler_words()

    def test_87_contains_uh(self, cfg):
        assert "uh" in cfg.get_filler_words()

    def test_88_contains_er(self, cfg):
        assert "er" in cfg.get_filler_words()

    def test_89_contains_ah(self, cfg):
        assert "ah" in cfg.get_filler_words()

    def test_90_contains_erm(self, cfg):
        assert "erm" in cfg.get_filler_words()

    def test_91_returns_same_list_on_repeated_calls(self, cfg):
        assert cfg.get_filler_words() == cfg.get_filler_words()

    def test_92_no_duplicate_entries(self, cfg):
        words = cfg.get_filler_words()
        assert len(words) == len(set(words))

    def test_93_no_entries_contain_spaces(self, cfg):
        # Default filler words are single tokens
        for w in cfg.get_filler_words():
            assert " " not in w

    def test_94_filler_words_independent_of_settings(self, cfg):
        cfg.save_advanced_setting("filler_removal", False)
        # Words list itself should still be returned
        assert len(cfg.get_filler_words()) > 0

    def test_95_filler_words_independent_of_language(self, cfg):
        cfg.save_language("fr")
        assert "um" in cfg.get_filler_words()


# ── Cross-concern isolation contracts (96–100) ────────────────────────────────

class TestIsolationContracts:
    def test_96_all_settings_independent_from_api_keys(self, cfg):
        cfg.save_api_key("openai", "o")
        cfg.save_advanced_setting("whisper_mode", True)
        assert cfg.get_api_key("openai") == "o"
        assert cfg.get_advanced_settings()["whisper_mode"] is True

    def test_97_user_name_language_settings_all_coexist(self, cfg):
        cfg.save_user_name("Alice")
        cfg.save_language("fr")
        cfg.save_advanced_setting("developer_mode", True)
        assert cfg.get_user_name() == "Alice"
        assert cfg.get_language() == "fr"
        assert cfg.get_advanced_settings()["developer_mode"] is True

    def test_98_config_starts_fresh_each_test(self, cfg):
        # No state bleeds from other tests
        assert cfg.get_user_name() is None
        assert cfg.get_language() == "en"

    def test_99_all_defaults_correct_on_fresh_config(self, cfg):
        s = cfg.get_advanced_settings()
        assert s["whisper_mode"] is False
        assert s["developer_mode"] is False
        assert s["filler_removal"] is True
        assert cfg.get_language() == "en"
        assert cfg.get_user_name() is None

    def test_100_rapid_alternating_saves_consistent_state(self, cfg):
        cfg.save_language("fr")
        cfg.save_user_name("Alice")
        cfg.save_advanced_setting("whisper_mode", True)
        cfg.save_language("de")
        cfg.save_user_name("Bob")
        cfg.save_advanced_setting("whisper_mode", False)
        assert cfg.get_language() == "de"
        assert cfg.get_user_name() == "Bob"
        assert cfg.get_advanced_settings()["whisper_mode"] is False
