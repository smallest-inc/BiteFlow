# MiniFlow Engineering (Swift + Smallest)

This repository is intentionally structured around a single runtime path:

- `MiniflowApp/` - native macOS app (Swift/SwiftUI)
- `miniflow-engine/` - local Python engine (FastAPI)
- `miniflow-auth/` - OAuth proxy (Vercel, optional for integrations)

Legacy web/Tauri artifacts have been removed from the root to avoid split build paths.

## System Architecture

```text
MiniflowApp (Swift)  <->  miniflow-engine (FastAPI on localhost:8765)
                                  |
                                  +-> Smallest AI Waves (speech-to-text)
                                  +-> OpenAI (agent/tool orchestration)
                                  +-> OAuth-backed connectors (Slack, GitHub, etc.)
```

## Speech and Command Flow

1. Swift captures microphone audio.
2. Swift posts base64 PCM chunks to engine commands (`start_listening`, `send_audio_chunk`, `stop_listening`).
3. Engine streams audio to Smallest AI Waves over WebSocket.
4. Engine emits transcript events over `ws://127.0.0.1:8765/ws`.
5. Swift receives final transcript and invokes `execute_command`.
6. Engine runs local tools and connector tools, then emits action results.

## API Key Contract

The engine key contract is:

- `openai`
- `smallest`

`has_api_keys` returns:

```json
{
  "openai": "string|null",
  "smallest": "string|null"
}
```

## Build and Packaging

Primary build path:

1. `./build_backend.sh` - bundles Python engine
2. `./build_all.sh` - builds Swift app, embeds engine, creates DMG

DMG-only packaging (for an already built app):

- `APP_PATH=build/MiniFlow.app ./build_dmg.sh`

## Source of Truth

If docs conflict with code, treat these as canonical:

- Runtime and UI behavior: `MiniflowApp/`
- Engine API/events: `miniflow-engine/main.py`
- STT provider behavior: `miniflow-engine/audio.py`
- API key storage contract: `miniflow-engine/config.py`
