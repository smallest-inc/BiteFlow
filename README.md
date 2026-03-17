<p align="center">
	<img src="smallestbanner.webp" alt="smallest.ai" />
</p>

# <p align="center"> MiniFlow </p>

<p align="center">
	Voice-to-text dictation and command assistant for macOS.
</p>
<p align="center">
	Hold Fn to speak and MiniFlow types at your cursor using the fastest and most accurate speech-to-text model in the world.
</p>

<p align="center">
	<a href="https://www.apple.com/macos/">
		<img src="https://img.shields.io/badge/platform-macOS-lightgrey" alt="platform" />
	</a>
	<a href="LICENSE">
		<img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="license" />
	</a>
</p>

## Features

- Global Fn hold-to-talk for instant dictation
- Automatic typing at your cursor with no copy/paste steps
- Command mode for rewrite, summary, bullets, grammar fixes, and quick email drafts
- Local-first app with a bundled Python engine
- Clean MVP build (no external integrations)

## Prerequisites

- macOS Ventura 13.0 or later
- Apple Silicon (arm64)
- Smallest AI API key (get one from https://console.smallest.ai)

## Quick start

1. Download the latest DMG and drag MiniFlow.app to Applications.
2. Clear Gatekeeper and launch:

```bash
xattr -cr /Applications/MiniFlow.app && open /Applications/MiniFlow.app
```

3. Grant Microphone and Accessibility permissions when prompted.
4. Open Settings and add your Smallest AI API key from https://console.smallest.ai.

Keys are stored locally in `~/miniflow/miniflow_keys.json`.

## Usage

- Hold Fn to start listening
- Release Fn to stop and process
- Type a command in the command bar to run a text command

Example commands:

- "Summarize this"
- "Rewrite this more professionally"
- "Fix grammar"
- "Draft a quick follow up email"

## Building from source

```bash
# 1. Clone
git clone https://github.com/your-org/miniflow.git
cd miniflow

# 2. Install Python deps
cd miniflow-engine && pip install -r requirements.txt && cd ..

# 3. Build everything (backend + app + DMG)
./build_all.sh
```

Output: `build/MiniFlow-0.2.0.dmg`

## Project structure

```
MiniflowApp/            # Swift/SwiftUI macOS app
	MiniflowApp/          # App source, views, and view models
	Bridge/               # Swift networking helpers (API + event stream)
	Models/               # Action + history models
	Views/                # UI screens and components
miniflow-engine/        # Python FastAPI engine
	connectors/           # Service connectors (disabled in MVP)
	agent.py              # Intent + command execution
	main.py               # API server and request routing
miniflow-auth/          # OAuth helpers (disabled in MVP)
build_*.sh              # Build scripts for backend/app/DMG
```

## Contributing

We love contributions that keep MiniFlow fast, simple, and reliable.

1. Fork the repository.
2. Create a feature branch: `git checkout -b feature/short-description`
3. Commit your changes: `git commit -m "Add short description"`
4. Push the branch: `git push origin feature/short-description`
5. Open a pull request with a short summary and screenshots if UI changes.

### Development guidelines

- Test your changes before submitting.
- Follow the existing coding style.
- Update documentation as needed.

## Troubleshooting

- Fn key not working: enable Accessibility in System Settings.
- No transcription: check Microphone permission and API key.
- Engine failed to start: wait a few seconds after first launch and retry.

Logs:

```bash
tail -f ~/miniflow/miniflow.log
```

## License

MIT. See LICENSE.
