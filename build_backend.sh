#!/usr/bin/env bash
# build_backend.sh — Bundle the Python backend into a directory bundle.
# Uses the project venv so no system Python dependencies are needed.
#
# Output: miniflow-engine/dist/miniflow-engine/  (directory, ~80 MB)
# The executable is: dist/miniflow-engine/miniflow-engine
#
# Using --onedir (not --onefile) so the engine launches instantly without
# a slow /tmp extraction step on every run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$SCRIPT_DIR/miniflow-engine"
VENV="$ENGINE_DIR/venv"

# ── Use venv Python ───────────────────────────────────────────────────────────

if [ ! -d "$VENV" ]; then
  echo "✗ venv not found at $VENV"
  echo "  Run: cd miniflow-engine && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
  exit 1
fi

PYTHON="$VENV/bin/python"
PIP="$VENV/bin/pip"

echo "→ Python: $($PYTHON --version)"
echo "→ Installing/upgrading PyInstaller in venv..."
"$PIP" install --quiet --upgrade pyinstaller

PYINSTALLER="$VENV/bin/pyinstaller"

# ── Bundle ────────────────────────────────────────────────────────────────────

echo "→ Bundling miniflow-engine..."
cd "$ENGINE_DIR"

"$PYINSTALLER" \
  --onedir \
  --name miniflow-engine \
  --hidden-import "uvicorn.logging" \
  --hidden-import "uvicorn.loops.auto" \
  --hidden-import "uvicorn.lifespan.on" \
  --hidden-import "uvicorn.protocols.http.auto" \
  --hidden-import "uvicorn.protocols.websockets.auto" \
  --hidden-import "connectors.google" \
  --hidden-import "connectors.slack" \
  --hidden-import "connectors.discord" \
  --hidden-import "connectors.github" \
  --hidden-import "connectors.jira" \
  --hidden-import "connectors.linear" \
  --hidden-import "connectors.notion" \
  --hidden-import "connectors.spotify" \
  --hidden-import "connectors.registry" \
  --collect-all "pyobjc_framework_Quartz" \
  --collect-all "pyobjc_framework_AppKit" \
  --noconfirm \
  main.py

echo ""
echo "✓ Bundle ready: $ENGINE_DIR/dist/miniflow-engine/"
echo "  Executable:   $ENGINE_DIR/dist/miniflow-engine/miniflow-engine"
