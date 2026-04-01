# Murmur

**Voice-to-text for macOS, right from the menu bar.**

Murmur is a lightweight macOS menu bar app that turns speech into polished text and inserts it at your cursor — in any app. It uses on-device speech recognition for speed and privacy, with an optional AI cleanup pass powered by Claude Haiku for grammar, punctuation, and tone. Built entirely in Swift with zero external dependencies.

## Features

- **Hold Fn to dictate** — press to record, release to transcribe and insert at your cursor
- **Double-tap Fn for toggle mode** — hands-free dictation for longer passages
- **On-device transcription** — Apple Speech framework, no network required, completely private
- **AI cleanup (optional)** — Claude Haiku polishes grammar, punctuation, and formatting
- **Context-aware tone** — detects the active app (email, chat, code editor, terminal) and adjusts output accordingly
- **Command mode** — select text, dictate an editing instruction like *"make this more concise"*
- **Cross-app text insertion** — Accessibility API with automatic clipboard fallback
- **Real-time waveform** — visual feedback while recording
- **Dictation history** — last 10 transcriptions accessible from the menu bar
- **Floating overlay** — shows recording and processing state

## Tech Stack

| | |
|---|---|
| Language | Swift 5.9+ |
| UI | SwiftUI |
| Audio | AVFoundation |
| Speech | Apple Speech framework |
| Text insertion | Accessibility API (AXUIElement) |
| Hotkey | Carbon (Fn key events) |
| Build system | Swift Package Manager |
| Platform | macOS 14 (Sonoma)+ |

## Getting Started

### Build

```bash
# Clone
git clone https://github.com/casey-dunham/Murmur.git
cd Murmur

# Debug build
swift build

# Build .app bundle
scripts/build.sh

# Release build
scripts/build.sh --release
```

### Run

```bash
open Murmur.app
```

### Permissions

Murmur needs two macOS permissions on first launch:

1. **Microphone** — for audio capture (System Settings → Privacy & Security → Microphone)
2. **Accessibility** — for inserting text at the cursor in other apps (System Settings → Privacy & Security → Accessibility)

### AI Enhancement (Optional)

To enable Claude Haiku cleanup, add your Anthropic API key in Murmur's settings. Without it, Murmur still works perfectly using raw on-device transcription.

## License

[MIT](LICENSE)
