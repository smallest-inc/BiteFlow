"""
pytest configuration — skip integration tests during normal runs.

Integration tests require the BiteFlow engine to be running on port 8765.
They are marked with @pytest.mark.integration and are skipped by default
so builds never fail when the engine is offline.

To run integration tests explicitly:
    python3 -m pytest -m integration
"""
import pytest


def pytest_addoption(parser):
    parser.addoption(
        "--integration",
        action="store_true",
        default=False,
        help="Also run tests marked @pytest.mark.integration",
    )


def pytest_configure(config):
    config.addinivalue_line(
        "markers",
        "integration: requires the BiteFlow engine to be running on port 8765",
    )


def pytest_collection_modifyitems(config, items):
    if not config.getoption("--integration"):
        skip = pytest.mark.skip(reason="integration test — run with --integration flag")
        for item in items:
            if item.get_closest_marker("integration"):
                item.add_marker(skip)
